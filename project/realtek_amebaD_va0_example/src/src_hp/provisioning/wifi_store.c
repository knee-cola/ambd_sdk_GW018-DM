/**
 * Wi-Fi Credential Storage Implementation
 * Uses the same flash storage mechanism as AT commands for compatibility
 */

#include "provisioning/wifi_store.h"
#include "provisioning/provisioning_config.h"
#include "ameba_soc.h"
#include "main.h"
#include "flash_api.h"
#include "device_lock.h"
#include <string.h>

#if CONFIG_PORTAL_DEBUG
#define WIFI_STORE_LOG(fmt, ...) DiagPrintf("[WIFI_STORE] " fmt "\r\n", ##__VA_ARGS__)
#else
#define WIFI_STORE_LOG(fmt, ...)
#endif

/* Flash storage sectors - use same as AT commands */
#define WIFI_STORE_SECTOR       AP_SETTING_SECTOR
#define WIFI_STORE_MAGIC        0x57494649  /* "WIFI" */
#define WIFI_STORE_VERSION      0x01

/* Power cycle detection for recovery */
#define POWER_CYCLE_MAGIC       0x50435943  /* "PCYC" */
#define POWER_CYCLE_SECTOR      (AP_SETTING_SECTOR + 0x1000)

typedef struct {
    uint32_t magic;
    uint32_t version;
    wifi_credentials_t creds;
    uint32_t checksum;
} wifi_store_data_t;

typedef struct {
    uint32_t magic;
    uint32_t count;
    uint32_t timestamp;
    uint32_t checksum;
} power_cycle_data_t;

static bool g_store_initialized = false;

static uint32_t calculate_checksum(const void *data, size_t len)
{
    const uint8_t *ptr = (const uint8_t *)data;
    uint32_t checksum = 0;
    
    for (size_t i = 0; i < len; i++) {
        checksum += ptr[i];
    }
    return checksum;
}

static int flash_read_data(uint32_t address, void *data, size_t len)
{
    flash_t flash;
    device_mutex_lock(RT_DEV_LOCK_FLASH);
    int ret = flash_stream_read(&flash, address, len, (uint8_t *)data);
    device_mutex_unlock(RT_DEV_LOCK_FLASH);
    return ret;
}

static int flash_write_data(uint32_t address, const void *data, size_t len)
{
    flash_t flash;
    device_mutex_lock(RT_DEV_LOCK_FLASH);
    
    /* Erase sector first */
    flash_erase_sector(&flash, address);
    
    /* Write data */
    int ret = flash_stream_write(&flash, address, len, (uint8_t *)data);
    device_mutex_unlock(RT_DEV_LOCK_FLASH);
    return ret;
}

int wifi_store_init(void)
{
    if (g_store_initialized) {
        return 0;
    }
    
    WIFI_STORE_LOG("Initializing Wi-Fi credential storage");
    g_store_initialized = true;
    return 0;
}

bool wifi_store_have_creds(void)
{
    wifi_store_data_t store_data;
    
    if (!g_store_initialized) {
        wifi_store_init();
    }
    
    if (flash_read_data(WIFI_STORE_SECTOR, &store_data, sizeof(store_data)) != 0) {
        WIFI_STORE_LOG("Failed to read credential storage");
        return false;
    }
    
    /* Check magic and version */
    if (store_data.magic != WIFI_STORE_MAGIC || store_data.version != WIFI_STORE_VERSION) {
        WIFI_STORE_LOG("Invalid storage magic/version: 0x%08x/0x%08x", 
                       store_data.magic, store_data.version);
        return false;
    }
    
    /* Verify checksum */
    uint32_t calc_checksum = calculate_checksum(&store_data, 
                                               sizeof(store_data) - sizeof(store_data.checksum));
    if (calc_checksum != store_data.checksum) {
        WIFI_STORE_LOG("Checksum mismatch: calc=0x%08x stored=0x%08x", 
                       calc_checksum, store_data.checksum);
        return false;
    }
    
    /* Check if credentials are marked as valid */
    if (!store_data.creds.valid) {
        WIFI_STORE_LOG("Stored credentials marked as invalid");
        return false;
    }
    
    /* Basic sanity check */
    if (strlen(store_data.creds.ssid) == 0) {
        WIFI_STORE_LOG("Empty SSID in stored credentials");
        return false;
    }
    
    WIFI_STORE_LOG("Valid credentials found for SSID: %.20s", store_data.creds.ssid);
    return true;
}

int wifi_store_get(wifi_credentials_t *creds)
{
    wifi_store_data_t store_data;
    
    if (!creds) {
        return -1;
    }
    
    if (!g_store_initialized) {
        wifi_store_init();
    }
    
    if (flash_read_data(WIFI_STORE_SECTOR, &store_data, sizeof(store_data)) != 0) {
        WIFI_STORE_LOG("Failed to read credentials");
        return -1;
    }
    
    /* Verify data integrity */
    if (store_data.magic != WIFI_STORE_MAGIC || 
        store_data.version != WIFI_STORE_VERSION ||
        !store_data.creds.valid) {
        WIFI_STORE_LOG("Invalid or corrupted credential data");
        return -1;
    }
    
    uint32_t calc_checksum = calculate_checksum(&store_data, 
                                               sizeof(store_data) - sizeof(store_data.checksum));
    if (calc_checksum != store_data.checksum) {
        WIFI_STORE_LOG("Credential checksum verification failed");
        return -1;
    }
    
    /* Copy credentials */
    memcpy(creds, &store_data.creds, sizeof(wifi_credentials_t));
    
    WIFI_STORE_LOG("Retrieved credentials for SSID: %.20s", creds->ssid);
    return 0;
}

int wifi_store_set(const wifi_credentials_t *creds)
{
    wifi_store_data_t store_data;
    
    if (!creds) {
        return -1;
    }
    
    if (!g_store_initialized) {
        wifi_store_init();
    }
    
    /* Validate input */
    if (strlen(creds->ssid) == 0 || strlen(creds->ssid) > WIFI_STORE_MAX_SSID_LEN) {
        WIFI_STORE_LOG("Invalid SSID length: %d", strlen(creds->ssid));
        return -1;
    }
    
    if (strlen(creds->password) > WIFI_STORE_MAX_PASS_LEN) {
        WIFI_STORE_LOG("Password too long: %d", strlen(creds->password));
        return -1;
    }
    
    /* Prepare storage data */
    memset(&store_data, 0, sizeof(store_data));
    store_data.magic = WIFI_STORE_MAGIC;
    store_data.version = WIFI_STORE_VERSION;
    memcpy(&store_data.creds, creds, sizeof(wifi_credentials_t));
    store_data.creds.valid = 1;
    
    /* Calculate checksum */
    store_data.checksum = calculate_checksum(&store_data, 
                                           sizeof(store_data) - sizeof(store_data.checksum));
    
    /* Write to flash */
    if (flash_write_data(WIFI_STORE_SECTOR, &store_data, sizeof(store_data)) != 0) {
        WIFI_STORE_LOG("Failed to write credentials to flash");
        return -1;
    }
    
    WIFI_STORE_LOG("Stored credentials for SSID: %.20s", creds->ssid);
    return 0;
}

int wifi_store_clear(void)
{
    wifi_store_data_t store_data;
    
    if (!g_store_initialized) {
        wifi_store_init();
    }
    
    /* Create empty/invalid data structure */
    memset(&store_data, 0, sizeof(store_data));
    store_data.magic = WIFI_STORE_MAGIC;
    store_data.version = WIFI_STORE_VERSION;
    store_data.creds.valid = 0;  /* Mark as invalid */
    
    store_data.checksum = calculate_checksum(&store_data, 
                                           sizeof(store_data) - sizeof(store_data.checksum));
    
    if (flash_write_data(WIFI_STORE_SECTOR, &store_data, sizeof(store_data)) != 0) {
        WIFI_STORE_LOG("Failed to clear credentials");
        return -1;
    }
    
    WIFI_STORE_LOG("Credentials cleared");
    return 0;
}

bool wifi_store_should_provision(void)
{
    power_cycle_data_t pc_data;
    uint32_t current_time;
    
    if (!g_store_initialized) {
        wifi_store_init();
    }
    
    /* Read power cycle data */
    if (flash_read_data(POWER_CYCLE_SECTOR, &pc_data, sizeof(pc_data)) != 0) {
        /* First time or read error - assume no trigger */
        return false;
    }
    
    /* Validate power cycle data */
    if (pc_data.magic != POWER_CYCLE_MAGIC) {
        return false;
    }
    
    uint32_t calc_checksum = calculate_checksum(&pc_data, 
                                               sizeof(pc_data) - sizeof(pc_data.checksum));
    if (calc_checksum != pc_data.checksum) {
        return false;
    }
    
    /* Get current time (approximation using tick count) */
    current_time = xTaskGetTickCount() / configTICK_RATE_HZ;
    
    /* Check if within power cycle window and count threshold exceeded */
    if ((current_time - pc_data.timestamp) <= CONFIG_PORTAL_POWER_CYCLE_WINDOW_S &&
        pc_data.count >= CONFIG_PORTAL_POWER_CYCLE_COUNT) {
        WIFI_STORE_LOG("Provision trigger: %d power cycles in %d seconds", 
                       pc_data.count, current_time - pc_data.timestamp);
        return true;
    }
    
    return false;
}

int wifi_store_clear_provision_trigger(void)
{
    power_cycle_data_t pc_data;
    
    if (!g_store_initialized) {
        wifi_store_init();
    }
    
    /* Clear power cycle counter */
    memset(&pc_data, 0, sizeof(pc_data));
    pc_data.magic = POWER_CYCLE_MAGIC;
    pc_data.count = 0;
    pc_data.timestamp = xTaskGetTickCount() / configTICK_RATE_HZ;
    pc_data.checksum = calculate_checksum(&pc_data, 
                                        sizeof(pc_data) - sizeof(pc_data.checksum));
    
    if (flash_write_data(POWER_CYCLE_SECTOR, &pc_data, sizeof(pc_data)) != 0) {
        WIFI_STORE_LOG("Failed to clear provision trigger");
        return -1;
    }
    
    WIFI_STORE_LOG("Provision trigger cleared");
    return 0;
}

/* Function to be called early in boot to track power cycles */
void wifi_store_track_power_cycle(void)
{
    power_cycle_data_t pc_data;
    uint32_t current_time = xTaskGetTickCount() / configTICK_RATE_HZ;
    
    /* Read existing data */
    if (flash_read_data(POWER_CYCLE_SECTOR, &pc_data, sizeof(pc_data)) != 0) {
        /* Initialize new power cycle tracking */
        memset(&pc_data, 0, sizeof(pc_data));
        pc_data.magic = POWER_CYCLE_MAGIC;
        pc_data.count = 1;
        pc_data.timestamp = current_time;
    } else if (pc_data.magic == POWER_CYCLE_MAGIC) {
        /* Check if within window */
        if ((current_time - pc_data.timestamp) <= CONFIG_PORTAL_POWER_CYCLE_WINDOW_S) {
            pc_data.count++;
        } else {
            /* Reset counter if outside window */
            pc_data.count = 1;
            pc_data.timestamp = current_time;
        }
    } else {
        /* Initialize if magic is invalid */
        memset(&pc_data, 0, sizeof(pc_data));
        pc_data.magic = POWER_CYCLE_MAGIC;
        pc_data.count = 1;
        pc_data.timestamp = current_time;
    }
    
    /* Update checksum and write back */
    pc_data.checksum = calculate_checksum(&pc_data, 
                                        sizeof(pc_data) - sizeof(pc_data.checksum));
    flash_write_data(POWER_CYCLE_SECTOR, &pc_data, sizeof(pc_data));
    
    WIFI_STORE_LOG("Power cycle tracked: count=%d, time=%d", pc_data.count, current_time);
}