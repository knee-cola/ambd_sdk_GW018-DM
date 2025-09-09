/**
 * Main Provisioning Task Implementation
 * Orchestrates the entire captive portal Wi-Fi provisioning process
 */

#include "provisioning_task.h"
#include "provisioning_config.h"
#include "wifi_store.h"
#include "dns_captive.h"
#include "http_portal.h"
#include "ameba_soc.h"
#include "main.h"
#include "wifi_conf.h"
#include "lwip/inet.h"
#include "FreeRTOS.h"
#include "task.h"
#include <string.h>

/* Include generated secrets */
#if CONFIG_CAPTIVE_PORTAL
#include "provisioning/ap_secrets.h"
#endif

#if CONFIG_PORTAL_DEBUG
#define PROV_LOG(fmt, ...) DiagPrintf("[PORTAL] " fmt "\r\n", ##__VA_ARGS__)
#else
#define PROV_LOG(fmt, ...)
#endif

typedef enum {
    PROV_STATE_IDLE,
    PROV_STATE_STARTING,
    PROV_STATE_AP_SETUP,
    PROV_STATE_SERVICES_STARTING,
    PROV_STATE_WAITING,
    PROV_STATE_SUCCESS,
    PROV_STATE_TIMEOUT,
    PROV_STATE_ERROR,
    PROV_STATE_STOPPING
} prov_state_t;

static TaskHandle_t g_prov_task = NULL;
static prov_state_t g_prov_state = PROV_STATE_IDLE;
static bool g_prov_should_reboot = false;
static bool g_prov_force_stop = false;

static void provisioning_success_callback(const wifi_credentials_t *creds)
{
    PROV_LOG("Provisioning successful for SSID: %.20s", creds->ssid);
    g_prov_state = PROV_STATE_SUCCESS;
    g_prov_should_reboot = true;
}

static int setup_softap(void)
{
    rtw_ap_info_t ap_info = {0};
    
    /* Configure SoftAP parameters */
    strncpy((char *)ap_info.ssid, AP_SSID_PREFIX AP_SSID_SUFFIX, sizeof(ap_info.ssid) - 1);
    strncpy((char *)ap_info.password, AP_PASSWORD, sizeof(ap_info.password) - 1);
    ap_info.security_type = CONFIG_PORTAL_AP_AUTH_MODE;
    ap_info.channel = CONFIG_PORTAL_AP_CHANNEL;
    ap_info.hidden_ssid = 0;
    
    PROV_LOG("Starting SoftAP: %s", ap_info.ssid);
    
    /* Start SoftAP */
    int ret = wifi_start_ap((char *)ap_info.ssid,
                           ap_info.security_type,
                           (char *)ap_info.password,
                           strlen((char *)ap_info.ssid),
                           strlen((char *)ap_info.password),
                           ap_info.channel);
    
    if (ret != RTW_SUCCESS) {
        PROV_LOG("Failed to start SoftAP: %d", ret);
        return -1;
    }
    
    /* Wait for AP to be ready */
    vTaskDelay(pdMS_TO_TICKS(2000));
    
    /* Set AP IP address */
    extern struct netif xnetif[NET_IF_NUM];
    struct netif *ap_netif = &xnetif[1]; /* AP interface */
    if (ap_netif) {
        ip4_addr_t ip, netmask, gateway;
        
        inet_aton(CONFIG_PORTAL_AP_IP, &ip);
        inet_aton(CONFIG_PORTAL_AP_NETMASK, &netmask);
        gateway = ip; /* Gateway same as AP IP */
        
        netif_set_addr(ap_netif, &ip, &netmask, &gateway);
        netif_set_up(ap_netif);
        
        PROV_LOG("AP IP configured: %s", CONFIG_PORTAL_AP_IP);
    }
    
    /* Enable DHCP server */
    dhcps_init(ap_netif);
    
    return 0;
}

static int start_portal_services(void)
{
    uint32_t ap_ip;
    
    /* Convert AP IP to network byte order for DNS server */
    inet_aton(CONFIG_PORTAL_AP_IP, (struct in_addr *)&ap_ip);
    
    /* Initialize and start DNS captive server */
    if (dns_captive_init(ap_ip) != 0) {
        PROV_LOG("Failed to initialize DNS captive server");
        return -1;
    }
    
    if (dns_captive_start() != 0) {
        PROV_LOG("Failed to start DNS captive server");
        return -1;
    }
    
    /* Initialize and start HTTP portal */
    if (http_portal_init(provisioning_success_callback) != 0) {
        PROV_LOG("Failed to initialize HTTP portal");
        dns_captive_stop();
        return -1;
    }
    
    if (http_portal_start() != 0) {
        PROV_LOG("Failed to start HTTP portal");
        dns_captive_stop();
        return -1;
    }
    
    PROV_LOG("Portal services started successfully");
    return 0;
}

static void stop_portal_services(void)
{
    PROV_LOG("Stopping portal services");
    
    http_portal_stop();
    dns_captive_stop();
    
    /* Stop SoftAP */
    wifi_off();
    vTaskDelay(pdMS_TO_TICKS(1000));
}

static void provisioning_main_task(void *param)
{
    uint32_t start_time = xTaskGetTickCount();
    uint32_t timeout_ticks = pdMS_TO_TICKS(CONFIG_PORTAL_IDLE_TIMEOUT_S * 1000);
    
    PROV_LOG("Provisioning task started");
    g_prov_state = PROV_STATE_STARTING;
    
    /* Initialize Wi-Fi storage */
    if (wifi_store_init() != 0) {
        PROV_LOG("Failed to initialize Wi-Fi storage");
        g_prov_state = PROV_STATE_ERROR;
        goto exit;
    }
    
    /* Set up SoftAP */
    g_prov_state = PROV_STATE_AP_SETUP;
    if (setup_softap() != 0) {
        PROV_LOG("Failed to set up SoftAP");
        g_prov_state = PROV_STATE_ERROR;
        goto exit;
    }
    
    /* Start portal services */
    g_prov_state = PROV_STATE_SERVICES_STARTING;
    if (start_portal_services() != 0) {
        PROV_LOG("Failed to start portal services");
        g_prov_state = PROV_STATE_ERROR;
        goto exit;
    }
    
    /* Main provisioning loop */
    g_prov_state = PROV_STATE_WAITING;
    PROV_LOG("Captive portal ready, waiting for user interaction...");
    
    while (g_prov_state == PROV_STATE_WAITING && !g_prov_force_stop) {
        /* Check for timeout */
        uint32_t elapsed = xTaskGetTickCount() - start_time;
        if (elapsed > timeout_ticks) {
            PROV_LOG("Provisioning timeout after %d seconds", CONFIG_PORTAL_IDLE_TIMEOUT_S);
            g_prov_state = PROV_STATE_TIMEOUT;
            break;
        }
        
        /* Check service health */
        if (!dns_captive_is_running() || !http_portal_is_running()) {
            PROV_LOG("Portal services died unexpectedly");
            g_prov_state = PROV_STATE_ERROR;
            break;
        }
        
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    
exit:
    PROV_LOG("Provisioning task finishing, state: %d", g_prov_state);
    
    /* Clean up */
    g_prov_state = PROV_STATE_STOPPING;
    stop_portal_services();
    
    /* Clear provision trigger */
    wifi_store_clear_provision_trigger();
    
    if (g_prov_state == PROV_STATE_SUCCESS) {
        PROV_LOG("Provisioning completed successfully");
    } else if (g_prov_state == PROV_STATE_TIMEOUT) {
        PROV_LOG("Provisioning timed out");
    } else if (g_prov_state == PROV_STATE_ERROR) {
        PROV_LOG("Provisioning failed with error");
    } else {
        PROV_LOG("Provisioning stopped");
    }
    
    g_prov_state = PROV_STATE_IDLE;
    g_prov_task = NULL;
    vTaskDelete(NULL);
}

int provisioning_run_if_needed(void)
{
    /* Check if already running */
    if (g_prov_state != PROV_STATE_IDLE || g_prov_task != NULL) {
        PROV_LOG("Provisioning already running or in progress");
        return 0;
    }
    
    /* Initialize storage system */
    if (wifi_store_init() != 0) {
        PROV_LOG("Failed to initialize Wi-Fi storage");
        return -1;
    }
    
    /* Track power cycle for recovery detection */
    wifi_store_track_power_cycle();
    
    /* Check if provisioning should be triggered */
    bool should_provision = false;
    
    /* Check for existing credentials */
    if (!wifi_store_have_creds()) {
        PROV_LOG("No valid Wi-Fi credentials found");
        should_provision = true;
    }
    
    /* Check for provision triggers (power cycles, button, etc.) */
    if (wifi_store_should_provision()) {
        PROV_LOG("Provision trigger detected");
        should_provision = true;
        
        /* Clear existing credentials when triggered */
        wifi_store_clear();
    }
    
    /* TODO: Add button press detection when GPIO is configured */
    
    if (!should_provision) {
        PROV_LOG("Provisioning not needed");
        return 0;
    }
    
    PROV_LOG("Starting captive portal provisioning");
    
    /* Create provisioning task */
    if (xTaskCreate(provisioning_main_task, "provisioning", 
                   CONFIG_TASK_STACK_PROV / sizeof(StackType_t),
                   NULL, CONFIG_TASK_PRIORITY_PROV, &g_prov_task) != pdPASS) {
        PROV_LOG("Failed to create provisioning task");
        return -1;
    }
    
    /* Wait for provisioning to complete */
    while (g_prov_state != PROV_STATE_IDLE && 
           g_prov_state != PROV_STATE_SUCCESS &&
           g_prov_state != PROV_STATE_TIMEOUT &&
           g_prov_state != PROV_STATE_ERROR) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    
    /* Handle result */
    if (g_prov_state == PROV_STATE_SUCCESS && g_prov_should_reboot) {
        PROV_LOG("Provisioning successful, system will reboot in 3 seconds");
        vTaskDelay(pdMS_TO_TICKS(3000));
        sys_reset();
        return 1; /* Should not reach here */
    } else if (g_prov_state == PROV_STATE_TIMEOUT) {
        PROV_LOG("Provisioning timed out, continuing with normal operation");
        return 0;
    } else if (g_prov_state == PROV_STATE_ERROR) {
        PROV_LOG("Provisioning failed, continuing with normal operation");
        return -1;
    }
    
    return 0;
}

int provisioning_force_start(void)
{
    PROV_LOG("Forcing provisioning start");
    
    /* Clear existing credentials */
    if (wifi_store_init() == 0) {
        wifi_store_clear();
    }
    
    /* Run provisioning */
    return provisioning_run_if_needed();
}

bool provisioning_is_active(void)
{
    return (g_prov_state != PROV_STATE_IDLE);
}

int provisioning_stop(void)
{
    if (g_prov_state == PROV_STATE_IDLE) {
        return 0;
    }
    
    PROV_LOG("Stopping provisioning");
    g_prov_force_stop = true;
    
    /* Wait for task to stop */
    int timeout = 50; /* 5 seconds */
    while (g_prov_task && timeout > 0) {
        vTaskDelay(pdMS_TO_TICKS(100));
        timeout--;
    }
    
    if (g_prov_task) {
        PROV_LOG("Force deleting provisioning task");
        vTaskDelete(g_prov_task);
        g_prov_task = NULL;
    }
    
    g_prov_state = PROV_STATE_IDLE;
    g_prov_force_stop = false;
    
    return 0;
}