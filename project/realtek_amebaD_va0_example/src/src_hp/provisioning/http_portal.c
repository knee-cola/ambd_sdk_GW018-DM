/**
 * HTTP Captive Portal Implementation
 * Provides minimal HTTP server for Wi-Fi provisioning interface
 */

#include "provisioning/http_portal.h"
#include "provisioning/provisioning_config.h"
#include "provisioning/wifi_store.h"
#include "ameba_soc.h"
#include "main.h"
#include "lwip/sockets.h"
#include "lwip/netdb.h"
#include "lwip/inet.h"
#include "wifi_conf.h"
#include "FreeRTOS.h"
#include "task.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#if CONFIG_PORTAL_DEBUG
#define HTTP_LOG(fmt, ...) DiagPrintf("[HTTP] " fmt "\r\n", ##__VA_ARGS__)
#else
#define HTTP_LOG(fmt, ...)
#endif

/* HTML template for captive portal */
static const char captive_portal_html[] = 
"<!doctype html><html><head><meta name=viewport content=\"width=device-width,initial-scale=1\">"
"<title>GW018 Setup</title></head><body>"
"<h2>Connect to Wi-Fi</h2>"
"<label>SSID <select id=\"ssids\"></select></label><br/>"
"<label>Or enter SSID <input id=\"ssid\" placeholder=\"Network name\"></label><br/>"
"<label>Password <input id=\"pass\" type=\"password\"></label><br/>"
"<button onclick=\"save()\">Connect</button>"
"<pre id=\"msg\"></pre>"
"<script>"
"async function scan(){"
"  try{"
"    const r = await fetch('/scan'); const a = await r.json();"
"    const sel = document.getElementById('ssids'); sel.innerHTML='';"
"    (a||[]).forEach(s=>{ const o=document.createElement('option'); o.value=s; o.text=s; sel.appendChild(o); });"
"  }catch(e){}"
"}"
"async function save(){"
"  const sel = document.getElementById('ssids').value;"
"  const sid = document.getElementById('ssid').value || sel;"
"  const pwd = document.getElementById('pass').value;"
"  const body = 'ssid='+encodeURIComponent(sid)+'&password='+encodeURIComponent(pwd);"
"  const r = await fetch('/save',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});"
"  document.getElementById('msg').textContent = await r.text();"
"}"
"scan();"
"</script></body></html>";

/* HTTP response templates */
static const char http_200_header[] = 
"HTTP/1.1 200 OK\r\n"
"Content-Type: text/html\r\n"
"Connection: close\r\n"
"Content-Length: %d\r\n\r\n";

static const char http_json_header[] = 
"HTTP/1.1 200 OK\r\n"
"Content-Type: application/json\r\n"
"Connection: close\r\n"
"Content-Length: %d\r\n\r\n";

static const char http_404_response[] = 
"HTTP/1.1 404 Not Found\r\n"
"Content-Type: text/html\r\n"
"Connection: close\r\n"
"Content-Length: 23\r\n\r\n"
"<h1>404 Not Found</h1>";

static const char http_204_response[] = 
"HTTP/1.1 204 No Content\r\n"
"Connection: close\r\n\r\n";

/* Captive detection endpoints */
static const char *captive_endpoints[] = {
    "/generate_204",        /* Android */
    "/hotspot-detect.html", /* Apple */
    "/ncsi.txt",           /* Windows */
    "/connecttest.txt",    /* Windows 10 */
    NULL
};

static TaskHandle_t g_http_task = NULL;
static int g_http_socket = -1;
static bool g_http_running = false;
static http_portal_success_callback_t g_success_callback = NULL;

static int url_decode(char *dst, const char *src, int dst_len)
{
    int src_len = strlen(src);
    int di = 0;
    
    for (int si = 0; si < src_len && di < dst_len - 1; si++) {
        if (src[si] == '%' && si + 2 < src_len) {
            int hex_val;
            if (sscanf(src + si + 1, "%2x", &hex_val) == 1) {
                dst[di++] = (char)hex_val;
                si += 2;
            } else {
                dst[di++] = src[si];
            }
        } else if (src[si] == '+') {
            dst[di++] = ' ';
        } else {
            dst[di++] = src[si];
        }
    }
    dst[di] = '\0';
    return di;
}

static int parse_form_data(const char *data, char *ssid, int ssid_len, 
                          char *password, int pass_len)
{
    char *ssid_start = strstr(data, "ssid=");
    char *pass_start = strstr(data, "password=");
    
    if (!ssid_start) {
        return -1;
    }
    
    ssid_start += 5; /* Skip "ssid=" */
    char *ssid_end = strchr(ssid_start, '&');
    if (!ssid_end) {
        ssid_end = ssid_start + strlen(ssid_start);
    }
    
    int ssid_raw_len = ssid_end - ssid_start;
    if (ssid_raw_len >= ssid_len) {
        ssid_raw_len = ssid_len - 1;
    }
    
    char temp_ssid[CONFIG_PORTAL_MAX_SSID_LEN + 1];
    strncpy(temp_ssid, ssid_start, ssid_raw_len);
    temp_ssid[ssid_raw_len] = '\0';
    url_decode(ssid, temp_ssid, ssid_len);
    
    if (pass_start) {
        pass_start += 9; /* Skip "password=" */
        char *pass_end = strchr(pass_start, '&');
        if (!pass_end) {
            pass_end = pass_start + strlen(pass_start);
        }
        
        int pass_raw_len = pass_end - pass_start;
        if (pass_raw_len >= pass_len) {
            pass_raw_len = pass_len - 1;
        }
        
        char temp_pass[CONFIG_PORTAL_MAX_PASS_LEN + 1];
        strncpy(temp_pass, pass_start, pass_raw_len);
        temp_pass[pass_raw_len] = '\0';
        url_decode(password, temp_pass, pass_len);
    } else {
        password[0] = '\0';
    }
    
    return 0;
}

/* Scan completion handler for HTTP portal */
static rtw_scan_result_t g_scan_results[CONFIG_WIFI_SCAN_MAX_RESULTS];
static int g_scan_count = 0;
static rtw_bool_t g_scan_complete = RTW_FALSE;

static rtw_result_t scan_result_handler(rtw_scan_handler_result_t* malloced_scan_result)
{
    if (malloced_scan_result->scan_complete != RTW_TRUE) {
        if (g_scan_count < CONFIG_WIFI_SCAN_MAX_RESULTS) {
            memcpy(&g_scan_results[g_scan_count], &malloced_scan_result->ap_details, 
                   sizeof(rtw_scan_result_t));
            g_scan_count++;
        }
    } else {
        g_scan_complete = RTW_TRUE;
    }
    return RTW_SUCCESS;
}

static int wifi_scan_and_format_json(char *json_buf, int buf_len)
{
    g_scan_count = 0;
    g_scan_complete = RTW_FALSE;
    
    /* Start Wi-Fi scan */
    if (wifi_scan_networks(scan_result_handler, NULL) != RTW_SUCCESS) {
        HTTP_LOG("Wi-Fi scan failed");
        snprintf(json_buf, buf_len, "[]");
        return strlen(json_buf);
    }
    
    /* Wait for scan completion */
    int timeout = CONFIG_PORTAL_SCAN_TIMEOUT_S * 10;
    while (!g_scan_complete && timeout > 0) {
        vTaskDelay(pdMS_TO_TICKS(100));
        timeout--;
    }
    
    if (!g_scan_complete) {
        HTTP_LOG("Wi-Fi scan timeout");
        snprintf(json_buf, buf_len, "[]");
        return strlen(json_buf);
    }
    
    /* Format as JSON array */
    int pos = 0;
    pos += snprintf(json_buf + pos, buf_len - pos, "[");
    
    for (int i = 0; i < g_scan_count && pos < buf_len - 20; i++) {
        if (i > 0) {
            pos += snprintf(json_buf + pos, buf_len - pos, ",");
        }
        pos += snprintf(json_buf + pos, buf_len - pos, "\"%s\"", 
                       g_scan_results[i].SSID.val);
    }
    
    pos += snprintf(json_buf + pos, buf_len - pos, "]");
    
    HTTP_LOG("Wi-Fi scan found %d networks", g_scan_count);
    return pos;
}

static int attempt_wifi_connection(const char *ssid, const char *password)
{
    rtw_security_t security_type;
    
    /* Determine security type based on password */
    if (strlen(password) == 0) {
        security_type = RTW_SECURITY_OPEN;
    } else {
        security_type = RTW_SECURITY_WPA2_AES_PSK;
    }
    
    HTTP_LOG("Attempting to connect to SSID: %.20s", ssid);
    
    /* Disconnect if already connected */
    wifi_disconnect();
    vTaskDelay(pdMS_TO_TICKS(1000));
    
    /* Connect to network */
    int ret = wifi_connect((char *)ssid, 
                          security_type,
                          (char *)password, 
                          strlen(ssid),
                          strlen(password),
                          -1, NULL);
    
    if (ret == RTW_SUCCESS) {
        /* Wait for connection and IP assignment */
        int timeout = CONFIG_PORTAL_JOIN_TIMEOUT_S;
        while (timeout > 0 && wifi_is_connected_to_ap() != RTW_SUCCESS) {
            vTaskDelay(pdMS_TO_TICKS(1000));
            timeout--;
        }
        
        if (wifi_is_connected_to_ap() == RTW_SUCCESS) {
            HTTP_LOG("Successfully connected to Wi-Fi");
            return 0;
        } else {
            HTTP_LOG("Connected but no IP assigned");
            return -1;
        }
    } else {
        HTTP_LOG("Wi-Fi connection failed: %d", ret);
        return -1;
    }
}

static void handle_client_request(int client_sock)
{
    char buffer[CONFIG_HTTP_BUFFER_SIZE];
    char response[CONFIG_HTTP_BUFFER_SIZE * 2];
    int recv_len, resp_len;
    
    /* Receive HTTP request */
    recv_len = recv(client_sock, buffer, sizeof(buffer) - 1, 0);
    if (recv_len <= 0) {
        return;
    }
    buffer[recv_len] = '\0';
    
    /* Parse request line */
    char method[16], path[256];
    if (sscanf(buffer, "%15s %255s", method, path) != 2) {
        send(client_sock, http_404_response, strlen(http_404_response), 0);
        return;
    }
    
    HTTP_LOG("HTTP %s %s", method, path);
    
    /* Check for captive portal detection endpoints */
    for (int i = 0; captive_endpoints[i]; i++) {
        if (strcmp(path, captive_endpoints[i]) == 0) {
            send(client_sock, http_204_response, strlen(http_204_response), 0);
            return;
        }
    }
    
    if (strcmp(method, "GET") == 0) {
        if (strcmp(path, "/") == 0 || strcmp(path, "/index.html") == 0) {
            /* Serve captive portal page */
            resp_len = snprintf(response, sizeof(response), http_200_header, 
                              strlen(captive_portal_html));
            send(client_sock, response, resp_len, 0);
            send(client_sock, captive_portal_html, strlen(captive_portal_html), 0);
            
        } else if (strcmp(path, "/scan") == 0) {
            /* Wi-Fi scan endpoint */
            char json_data[1024];
            int json_len = wifi_scan_and_format_json(json_data, sizeof(json_data));
            
            resp_len = snprintf(response, sizeof(response), http_json_header, json_len);
            send(client_sock, response, resp_len, 0);
            send(client_sock, json_data, json_len, 0);
            
        } else {
            /* 404 for other GET requests */
            send(client_sock, http_404_response, strlen(http_404_response), 0);
        }
        
    } else if (strcmp(method, "POST") == 0 && strcmp(path, "/save") == 0) {
        /* Handle Wi-Fi credential submission */
        char *body = strstr(buffer, "\r\n\r\n");
        if (!body) {
            send(client_sock, http_404_response, strlen(http_404_response), 0);
            return;
        }
        body += 4;
        
        char ssid[CONFIG_PORTAL_MAX_SSID_LEN + 1];
        char password[CONFIG_PORTAL_MAX_PASS_LEN + 1];
        
        if (parse_form_data(body, ssid, sizeof(ssid), password, sizeof(password)) != 0) {
            const char *error_msg = "Invalid form data";
            resp_len = snprintf(response, sizeof(response), http_200_header, 
                              strlen(error_msg));
            send(client_sock, response, resp_len, 0);
            send(client_sock, error_msg, strlen(error_msg), 0);
            return;
        }
        
        if (strlen(ssid) == 0) {
            const char *error_msg = "SSID is required";
            resp_len = snprintf(response, sizeof(response), http_200_header, 
                              strlen(error_msg));
            send(client_sock, response, resp_len, 0);
            send(client_sock, error_msg, strlen(error_msg), 0);
            return;
        }
        
        HTTP_LOG("Received credentials for SSID: %.20s", ssid);
        
        /* Attempt Wi-Fi connection */
        if (attempt_wifi_connection(ssid, password) == 0) {
            /* Success - save credentials and notify */
            wifi_credentials_t creds = {0};
            strncpy(creds.ssid, ssid, sizeof(creds.ssid) - 1);
            strncpy(creds.password, password, sizeof(creds.password) - 1);
            creds.security_type = (strlen(password) > 0) ? RTW_SECURITY_WPA2_AES_PSK : RTW_SECURITY_OPEN;
            creds.valid = 1;
            
            wifi_store_set(&creds);
            
            const char *success_msg = "Connected successfully! Rebooting...";
            resp_len = snprintf(response, sizeof(response), http_200_header, 
                              strlen(success_msg));
            send(client_sock, response, resp_len, 0);
            send(client_sock, success_msg, strlen(success_msg), 0);
            
            /* Call success callback after a short delay */
            vTaskDelay(pdMS_TO_TICKS(1000));
            if (g_success_callback) {
                g_success_callback(&creds);
            }
            
        } else {
            /* Connection failed */
            const char *error_msg = "Failed to connect to Wi-Fi. Please check credentials.";
            resp_len = snprintf(response, sizeof(response), http_200_header, 
                              strlen(error_msg));
            send(client_sock, response, resp_len, 0);
            send(client_sock, error_msg, strlen(error_msg), 0);
        }
        
    } else {
        /* Unsupported method */
        send(client_sock, http_404_response, strlen(http_404_response), 0);
    }
}

static void http_task(void *param)
{
    struct sockaddr_in client_addr;
    socklen_t client_len;
    int client_sock;
    fd_set read_fds;
    struct timeval timeout;
    
    HTTP_LOG("HTTP portal task started");
    
    while (g_http_running) {
        /* Use select with timeout for graceful shutdown */
        FD_ZERO(&read_fds);
        FD_SET(g_http_socket, &read_fds);
        timeout.tv_sec = 1;
        timeout.tv_usec = 0;
        
        int ready = select(g_http_socket + 1, &read_fds, NULL, NULL, &timeout);
        
        if (ready < 0) {
            if (g_http_running) {
                HTTP_LOG("HTTP select error: %d", ready);
                vTaskDelay(pdMS_TO_TICKS(100));
            }
            continue;
        } else if (ready == 0) {
            /* Timeout - continue loop */
            continue;
        }
        
        /* Accept client connection */
        client_len = sizeof(client_addr);
        client_sock = accept(g_http_socket, (struct sockaddr *)&client_addr, &client_len);
        
        if (client_sock < 0) {
            if (g_http_running) {
                HTTP_LOG("HTTP accept error: %d", client_sock);
            }
            continue;
        }
        
        HTTP_LOG("HTTP client connected from %s:%d", 
                inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
        
        /* Handle request */
        handle_client_request(client_sock);
        
        /* Close client connection */
        closesocket(client_sock);
    }
    
    HTTP_LOG("HTTP portal task exiting");
    if (g_http_socket >= 0) {
        closesocket(g_http_socket);
        g_http_socket = -1;
    }
    
    g_http_task = NULL;
    vTaskDelete(NULL);
}

int http_portal_init(http_portal_success_callback_t success_cb)
{
    if (g_http_running) {
        HTTP_LOG("HTTP portal already initialized");
        return 0;
    }
    
    g_success_callback = success_cb;
    HTTP_LOG("HTTP portal initialized");
    return 0;
}

int http_portal_start(void)
{
    struct sockaddr_in server_addr;
    int opt = 1;
    
    if (g_http_running) {
        HTTP_LOG("HTTP portal already running");
        return 0;
    }
    
    /* Create TCP socket */
    g_http_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (g_http_socket < 0) {
        HTTP_LOG("Failed to create HTTP socket: %d", g_http_socket);
        return -1;
    }
    
    /* Set socket options */
    if (setsockopt(g_http_socket, SOL_SOCKET, SO_REUSEADDR, 
                  &opt, sizeof(opt)) < 0) {
        HTTP_LOG("Failed to set SO_REUSEADDR");
        closesocket(g_http_socket);
        g_http_socket = -1;
        return -1;
    }
    
    /* Bind to HTTP port */
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(CONFIG_PORTAL_HTTP_PORT);
    
    if (bind(g_http_socket, (struct sockaddr *)&server_addr, 
            sizeof(server_addr)) < 0) {
        HTTP_LOG("Failed to bind HTTP socket to port %d", CONFIG_PORTAL_HTTP_PORT);
        closesocket(g_http_socket);
        g_http_socket = -1;
        return -1;
    }
    
    /* Listen for connections */
    if (listen(g_http_socket, CONFIG_HTTP_MAX_CONNECTIONS) < 0) {
        HTTP_LOG("Failed to listen on HTTP socket");
        closesocket(g_http_socket);
        g_http_socket = -1;
        return -1;
    }
    
    /* Create HTTP task */
    g_http_running = true;
    if (xTaskCreate(http_task, "http_portal", CONFIG_TASK_STACK_HTTP / sizeof(StackType_t),
                   NULL, CONFIG_TASK_PRIORITY_HTTP, &g_http_task) != pdPASS) {
        HTTP_LOG("Failed to create HTTP task");
        g_http_running = false;
        closesocket(g_http_socket);
        g_http_socket = -1;
        return -1;
    }
    
    HTTP_LOG("HTTP portal server started on port %d", CONFIG_PORTAL_HTTP_PORT);
    return 0;
}

int http_portal_stop(void)
{
    if (!g_http_running) {
        return 0;
    }
    
    HTTP_LOG("Stopping HTTP portal server");
    g_http_running = false;
    
    /* Close socket to wake up task */
    if (g_http_socket >= 0) {
        closesocket(g_http_socket);
        g_http_socket = -1;
    }
    
    /* Wait for task to exit */
    int timeout = 100; /* 1 second timeout */
    while (g_http_task && timeout > 0) {
        vTaskDelay(pdMS_TO_TICKS(10));
        timeout--;
    }
    
    if (g_http_task) {
        HTTP_LOG("Force deleting HTTP task");
        vTaskDelete(g_http_task);
        g_http_task = NULL;
    }
    
    HTTP_LOG("HTTP portal server stopped");
    return 0;
}

bool http_portal_is_running(void)
{
    return g_http_running && (g_http_task != NULL);
}