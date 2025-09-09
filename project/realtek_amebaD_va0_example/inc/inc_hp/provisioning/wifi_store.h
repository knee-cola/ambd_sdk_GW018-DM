#pragma once
/**
 * Wi-Fi Credential Storage for Captive Portal
 * Provides interface to store/retrieve Wi-Fi credentials in flash
 * Compatible with existing AT command storage mechanism
 */

#ifndef __WIFI_STORE_H__
#define __WIFI_STORE_H__

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WIFI_STORE_MAX_SSID_LEN 32
#define WIFI_STORE_MAX_PASS_LEN 64

typedef struct {
    char ssid[WIFI_STORE_MAX_SSID_LEN + 1];
    char password[WIFI_STORE_MAX_PASS_LEN + 1];
    uint8_t security_type;  /* RTW_SECURITY_* */
    uint8_t valid;          /* 1 if credentials are valid */
} wifi_credentials_t;

/**
 * Initialize Wi-Fi credential storage
 * @return 0 on success, negative on error
 */
int wifi_store_init(void);

/**
 * Check if valid Wi-Fi credentials exist
 * @return true if credentials exist and are valid
 */
bool wifi_store_have_creds(void);

/**
 * Get stored Wi-Fi credentials
 * @param creds Pointer to credentials structure to fill
 * @return 0 on success, negative on error
 */
int wifi_store_get(wifi_credentials_t *creds);

/**
 * Store Wi-Fi credentials
 * @param creds Pointer to credentials to store
 * @return 0 on success, negative on error
 */
int wifi_store_set(const wifi_credentials_t *creds);

/**
 * Clear stored Wi-Fi credentials
 * @return 0 on success, negative on error
 */
int wifi_store_clear(void);

/**
 * Get provisioning trigger state (button press, power cycles, etc.)
 * @return true if provisioning should be triggered
 */
bool wifi_store_should_provision(void);

/**
 * Clear provisioning trigger state
 * @return 0 on success, negative on error
 */
int wifi_store_clear_provision_trigger(void);

#ifdef __cplusplus
}
#endif

#endif /* __WIFI_STORE_H__ */