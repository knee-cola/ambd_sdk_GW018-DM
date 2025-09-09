#pragma once
/**
 * Configuration constants for Captive Portal Wi-Fi Provisioning
 * AmebaD GW018-DM Zigbee Gateway
 */

#ifndef __PROVISIONING_CONFIG_H__
#define __PROVISIONING_CONFIG_H__

/* Feature enable/disable */
#define CONFIG_CAPTIVE_PORTAL        1

/* Network configuration */
#define CONFIG_PORTAL_AP_SSID_PREFIX "GW018-Setup-"
#define CONFIG_PORTAL_HTTP_PORT      80
#define CONFIG_PORTAL_DNS_PORT       53
#define CONFIG_PORTAL_AP_IP          "192.168.4.1"
#define CONFIG_PORTAL_AP_NETMASK     "255.255.255.0"
#define CONFIG_PORTAL_AP_CHANNEL     6
#define CONFIG_PORTAL_DHCP_START     "192.168.4.2"
#define CONFIG_PORTAL_DHCP_END       "192.168.4.100"

/* Timing configuration */
#define CONFIG_PORTAL_IDLE_TIMEOUT_S 600    /* 10 minutes */
#define CONFIG_PORTAL_MAX_JOIN_TRIES 3
#define CONFIG_PORTAL_JOIN_TIMEOUT_S 30
#define CONFIG_PORTAL_SCAN_TIMEOUT_S 10
#define CONFIG_PORTAL_HTTP_TIMEOUT_S 30

/* GPIO configuration */
#define CONFIG_PROV_BUTTON_GPIO      (-1)   /* Disable button for now, use -1 */
#define CONFIG_PROV_BUTTON_HOLD_MS   5000   /* 5 second hold */

/* Task stack sizes (bytes) */
#define CONFIG_TASK_STACK_DNS        2048
#define CONFIG_TASK_STACK_HTTP       4096
#define CONFIG_TASK_STACK_PROV       3072

/* Task priorities */
#define CONFIG_TASK_PRIORITY_DNS     2
#define CONFIG_TASK_PRIORITY_HTTP    2
#define CONFIG_TASK_PRIORITY_PROV    3

/* HTTP server configuration */
#define CONFIG_HTTP_MAX_CONNECTIONS  4
#define CONFIG_HTTP_BUFFER_SIZE      1024
#define CONFIG_HTTP_HEADER_TIMEOUT   10000  /* ms */

/* Wi-Fi scan configuration */
#define CONFIG_WIFI_SCAN_MAX_RESULTS 20
#define CONFIG_WIFI_SCAN_PASSIVE     0

/* Debug configuration */
#define CONFIG_PORTAL_DEBUG          1
#define CONFIG_PORTAL_LOG_SECRETS    0      /* Never log passwords */

/* DNS configuration */
#define CONFIG_DNS_MAX_QUERIES       16
#define CONFIG_DNS_RESPONSE_TTL      300

/* Memory management */
#define CONFIG_PORTAL_MAX_SSID_LEN   32
#define CONFIG_PORTAL_MAX_PASS_LEN   64

/* Security settings */
#define CONFIG_PORTAL_AP_AUTH_MODE   RTW_SECURITY_WPA2_AES_PSK
#define CONFIG_PORTAL_STOP_ON_SUCCESS 1

/* Retry and recovery settings */
#define CONFIG_PORTAL_POWER_CYCLE_COUNT 3
#define CONFIG_PORTAL_POWER_CYCLE_WINDOW_S 30

#endif /* __PROVISIONING_CONFIG_H__ */