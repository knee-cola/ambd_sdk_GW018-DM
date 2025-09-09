#pragma once
/**
 * DNS Captive Portal for Wi-Fi Provisioning
 * Provides DNS hijacking to redirect all queries to captive portal
 */

#ifndef __DNS_CAPTIVE_H__
#define __DNS_CAPTIVE_H__

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize DNS captive portal server
 * @param ap_ip IP address to redirect all DNS queries to (in network byte order)
 * @return 0 on success, negative on error
 */
int dns_captive_init(uint32_t ap_ip);

/**
 * Start DNS captive portal server
 * Creates FreeRTOS task to handle DNS queries
 * @return 0 on success, negative on error
 */
int dns_captive_start(void);

/**
 * Stop DNS captive portal server
 * @return 0 on success, negative on error
 */
int dns_captive_stop(void);

/**
 * Check if DNS server is running
 * @return true if running
 */
bool dns_captive_is_running(void);

#ifdef __cplusplus
}
#endif

#endif /* __DNS_CAPTIVE_H__ */