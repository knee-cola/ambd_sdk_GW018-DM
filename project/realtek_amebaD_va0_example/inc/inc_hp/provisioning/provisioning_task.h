#pragma once
/**
 * Main Provisioning Task Orchestrator
 * Coordinates captive portal Wi-Fi provisioning process
 */

#ifndef __PROVISIONING_TASK_H__
#define __PROVISIONING_TASK_H__

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Check if provisioning is needed and run captive portal if required
 * This is the main entry point called from main() before starting normal operation
 * @return 0 if provisioning not needed or completed successfully
 *         1 if device should reboot after successful provisioning
 *         negative on error
 */
int provisioning_run_if_needed(void);

/**
 * Force provisioning mode (clear existing credentials and start portal)
 * @return 0 on success, negative on error
 */
int provisioning_force_start(void);

/**
 * Check if provisioning is currently active
 * @return true if provisioning portal is running
 */
bool provisioning_is_active(void);

/**
 * Stop provisioning (emergency stop)
 * @return 0 on success, negative on error
 */
int provisioning_stop(void);

#ifdef __cplusplus
}
#endif

#endif /* __PROVISIONING_TASK_H__ */