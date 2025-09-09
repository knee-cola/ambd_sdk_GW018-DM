/**
 * DNS Captive Portal Implementation
 * Hijacks all DNS queries and redirects them to the captive portal IP
 */

#include "provisioning/dns_captive.h"
#include "provisioning/provisioning_config.h"
#include "ameba_soc.h"
#include "main.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"
#include "lwip/inet.h"
#include "FreeRTOS.h"
#include "task.h"
#include <string.h>

#if CONFIG_PORTAL_DEBUG
#define DNS_LOG(fmt, ...) DiagPrintf("[DNS] " fmt "\r\n", ##__VA_ARGS__)
#else
#define DNS_LOG(fmt, ...)
#endif

/* DNS header structure */
typedef struct {
    uint16_t id;
    uint16_t flags;
    uint16_t questions;
    uint16_t answers;
    uint16_t authority;
    uint16_t additional;
} __attribute__((packed)) dns_header_t;

/* DNS flags */
#define DNS_FLAG_RESPONSE   0x8000
#define DNS_FLAG_OPCODE     0x7800
#define DNS_FLAG_AA         0x0400
#define DNS_FLAG_TC         0x0200
#define DNS_FLAG_RD         0x0100
#define DNS_FLAG_RA         0x0080
#define DNS_FLAG_RCODE      0x000F

/* DNS query types */
#define DNS_TYPE_A          1
#define DNS_TYPE_AAAA       28
#define DNS_CLASS_IN        1

static TaskHandle_t g_dns_task = NULL;
static int g_dns_socket = -1;
static uint32_t g_redirect_ip = 0;
static bool g_dns_running = false;

static uint16_t dns_ntohs(uint16_t val)
{
    return ((val & 0xFF) << 8) | ((val >> 8) & 0xFF);
}

static uint16_t dns_htons(uint16_t val)
{
    return ((val & 0xFF) << 8) | ((val >> 8) & 0xFF);
}

static int parse_dns_name(const uint8_t *data, int len, int *offset)
{
    int pos = *offset;
    int jumped = 0;
    int name_len = 0;
    
    while (pos < len) {
        uint8_t label_len = data[pos];
        
        /* Check for compression */
        if ((label_len & 0xC0) == 0xC0) {
            if (!jumped) {
                *offset = pos + 2;
            }
            pos = ((label_len & 0x3F) << 8) | data[pos + 1];
            jumped = 1;
            continue;
        }
        
        if (label_len == 0) {
            if (!jumped) {
                *offset = pos + 1;
            }
            break;
        }
        
        if (pos + label_len + 1 >= len) {
            return -1;
        }
        
        pos += label_len + 1;
        name_len += label_len + 1;
        
        if (name_len > 255) {
            return -1;
        }
    }
    
    return name_len;
}

static int create_dns_response(const uint8_t *query, int query_len, 
                              uint8_t *response, int max_resp_len)
{
    if (query_len < sizeof(dns_header_t) + 5) {
        return -1;
    }
    
    const dns_header_t *req_hdr = (const dns_header_t *)query;
    dns_header_t *resp_hdr = (dns_header_t *)response;
    
    /* Copy query as base for response */
    if (query_len > max_resp_len) {
        return -1;
    }
    memcpy(response, query, query_len);
    
    /* Set response flags */
    resp_hdr->flags = dns_htons(DNS_FLAG_RESPONSE | DNS_FLAG_RD | DNS_FLAG_RA);
    resp_hdr->answers = dns_htons(1);
    
    int pos = sizeof(dns_header_t);
    
    /* Skip question section */
    int name_len = parse_dns_name(query, query_len, &pos);
    if (name_len < 0) {
        DNS_LOG("Failed to parse DNS question name");
        return -1;
    }
    
    if (pos + 4 > query_len) {
        return -1;
    }
    
    uint16_t qtype = dns_ntohs(*(uint16_t *)(query + pos));
    pos += 4; /* Skip QTYPE and QCLASS */
    
    /* Only respond to A record queries */
    if (qtype != DNS_TYPE_A) {
        DNS_LOG("Non-A record query, type: %d", qtype);
        return query_len; /* Return original query without answer */
    }
    
    /* Add answer record */
    int resp_pos = pos;
    
    /* Name (pointer to question) */
    response[resp_pos++] = 0xC0;
    response[resp_pos++] = 0x0C;
    
    /* Type (A) */
    *(uint16_t *)(response + resp_pos) = dns_htons(DNS_TYPE_A);
    resp_pos += 2;
    
    /* Class (IN) */
    *(uint16_t *)(response + resp_pos) = dns_htons(DNS_CLASS_IN);
    resp_pos += 2;
    
    /* TTL */
    *(uint32_t *)(response + resp_pos) = htonl(CONFIG_DNS_RESPONSE_TTL);
    resp_pos += 4;
    
    /* Data length (4 bytes for IPv4) */
    *(uint16_t *)(response + resp_pos) = dns_htons(4);
    resp_pos += 2;
    
    /* IP address */
    *(uint32_t *)(response + resp_pos) = g_redirect_ip;
    resp_pos += 4;
    
    return resp_pos;
}

static void dns_task(void *param)
{
    uint8_t buffer[512];
    uint8_t response[512];
    struct sockaddr_in client_addr;
    socklen_t client_len;
    int recv_len, resp_len;
    
    DNS_LOG("DNS captive task started");
    
    while (g_dns_running) {
        client_len = sizeof(client_addr);
        recv_len = recvfrom(g_dns_socket, buffer, sizeof(buffer), 0,
                           (struct sockaddr *)&client_addr, &client_len);
        
        if (recv_len <= 0) {
            if (g_dns_running) {
                DNS_LOG("DNS receive error: %d", recv_len);
                vTaskDelay(pdMS_TO_TICKS(100));
            }
            continue;
        }
        
        if (recv_len < sizeof(dns_header_t)) {
            DNS_LOG("DNS packet too short: %d bytes", recv_len);
            continue;
        }
        
        /* Create response */
        resp_len = create_dns_response(buffer, recv_len, response, sizeof(response));
        if (resp_len > 0) {
            int sent = sendto(g_dns_socket, response, resp_len, 0,
                            (struct sockaddr *)&client_addr, client_len);
            if (sent != resp_len) {
                DNS_LOG("DNS send failed: %d/%d", sent, resp_len);
            } else {
                struct in_addr redirect_addr;
                redirect_addr.s_addr = g_redirect_ip;
                DNS_LOG("DNS query answered, redirected to %s", inet_ntoa(redirect_addr));
            }
        }
    }
    
    DNS_LOG("DNS captive task exiting");
    if (g_dns_socket >= 0) {
        closesocket(g_dns_socket);
        g_dns_socket = -1;
    }
    
    g_dns_task = NULL;
    vTaskDelete(NULL);
}

int dns_captive_init(uint32_t ap_ip)
{
    if (g_dns_running) {
        DNS_LOG("DNS captive already initialized");
        return 0;
    }
    
    g_redirect_ip = ap_ip;
    DNS_LOG("DNS captive initialized, redirect IP: 0x%08x", ap_ip);
    return 0;
}

int dns_captive_start(void)
{
    struct sockaddr_in server_addr;
    int opt = 1;
    
    if (g_dns_running) {
        DNS_LOG("DNS captive already running");
        return 0;
    }
    
    /* Create UDP socket */
    g_dns_socket = socket(AF_INET, SOCK_DGRAM, 0);
    if (g_dns_socket < 0) {
        DNS_LOG("Failed to create DNS socket: %d", g_dns_socket);
        return -1;
    }
    
    /* Set socket options */
    if (setsockopt(g_dns_socket, SOL_SOCKET, SO_REUSEADDR, 
                  &opt, sizeof(opt)) < 0) {
        DNS_LOG("Failed to set SO_REUSEADDR");
        closesocket(g_dns_socket);
        g_dns_socket = -1;
        return -1;
    }
    
    /* Bind to DNS port */
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(CONFIG_PORTAL_DNS_PORT);
    
    if (bind(g_dns_socket, (struct sockaddr *)&server_addr, 
            sizeof(server_addr)) < 0) {
        DNS_LOG("Failed to bind DNS socket to port %d", CONFIG_PORTAL_DNS_PORT);
        closesocket(g_dns_socket);
        g_dns_socket = -1;
        return -1;
    }
    
    /* Create DNS task */
    g_dns_running = true;
    if (xTaskCreate(dns_task, "dns_captive", CONFIG_TASK_STACK_DNS / sizeof(StackType_t),
                   NULL, CONFIG_TASK_PRIORITY_DNS, &g_dns_task) != pdPASS) {
        DNS_LOG("Failed to create DNS task");
        g_dns_running = false;
        closesocket(g_dns_socket);
        g_dns_socket = -1;
        return -1;
    }
    
    DNS_LOG("DNS captive server started on port %d", CONFIG_PORTAL_DNS_PORT);
    return 0;
}

int dns_captive_stop(void)
{
    if (!g_dns_running) {
        return 0;
    }
    
    DNS_LOG("Stopping DNS captive server");
    g_dns_running = false;
    
    /* Close socket to wake up task */
    if (g_dns_socket >= 0) {
        closesocket(g_dns_socket);
        g_dns_socket = -1;
    }
    
    /* Wait for task to exit */
    int timeout = 100; /* 1 second timeout */
    while (g_dns_task && timeout > 0) {
        vTaskDelay(pdMS_TO_TICKS(10));
        timeout--;
    }
    
    if (g_dns_task) {
        DNS_LOG("Force deleting DNS task");
        vTaskDelete(g_dns_task);
        g_dns_task = NULL;
    }
    
    DNS_LOG("DNS captive server stopped");
    return 0;
}

bool dns_captive_is_running(void)
{
    return g_dns_running && (g_dns_task != NULL);
}