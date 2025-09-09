#pragma once
/**
 * HTTP Captive Portal for Wi-Fi Provisioning
 * Provides minimal HTTP server for captive portal interface
 */

#ifndef __HTTP_PORTAL_H__
#define __HTTP_PORTAL_H__

#include <stdint.h>
#include <stdbool.h>
#include "wifi_store.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Callback for when credentials are successfully saved and connected */
typedef void (*http_portal_success_callback_t)(const wifi_credentials_t *creds);

/**
 * Initialize HTTP portal server
 * @param success_cb Callback to call when Wi-Fi connection succeeds
 * @return 0 on success, negative on error
 */
int http_portal_init(http_portal_success_callback_t success_cb);

/**
 * Start HTTP portal server
 * Creates FreeRTOS task to handle HTTP requests
 * @return 0 on success, negative on error
 */
int http_portal_start(void);

/**
 * Stop HTTP portal server
 * @return 0 on success, negative on error
 */
int http_portal_stop(void);

/**
 * Check if HTTP server is running
 * @return true if running
 */
bool http_portal_is_running(void);

#ifdef __cplusplus
}
#endif

#endif /* __HTTP_PORTAL_H__ */