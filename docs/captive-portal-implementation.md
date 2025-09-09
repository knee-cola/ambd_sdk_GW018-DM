# Prompt for IDE Agent: Add WPA2 SoftAP + Captive Portal Wi-Fi Provisioning to AmebaD GW018-DM Firmware

> **Context**
> Repo: `jasperw1996/ambd_sdk_GW018-DM` (AmebaD RTL8722DM).
> Current behavior: Wi-Fi credentials are entered via UART AT commands, device then acts as a Wi-Fi↔UART TCP bridge to the Tuya ZS3L/EFR32 Zigbee module for Zigbee2MQTT.
> **Goal:** Add an *optional* first-boot (or button-triggered) provisioning flow using a **WPA2 SoftAP + DNS catch-all + minimal HTTP form** (“captive portal”). SSID suffix and per-device random password must be generated at build time, written into a header file (`ap_secrets.h`), and printed on a sticker attached to the device. Do **not** break existing UART AT provisioning or Zigbee bridge behavior.

---

## Requirements (Definition of Done)

* When **no Wi-Fi credentials** exist, or when a **provisioning trigger** is set (e.g., long-press button, or compile-time flag), device:

  1. Starts **AP mode** with SSID `GW018-Setup-XXXX` (XXXX = last 2 bytes of MAC).
  2. Uses **WPA2-PSK AES** security with a **random password** hardcoded in `ap_secrets.h`.
  3. Runs a **DHCP server** for AP clients (use SDK default or enable if disabled).
  4. Runs a **DNS “catch-all”** responder that returns the AP IP for any A record.
  5. Serves a **single HTTP page** at `/` with a form (scan SSIDs + manual override) → POST `/save` with `{ssid,password}`.
  6. On POST, attempts STA connection; on success: save to NVRAM, stop AP/DNS/HTTP, reboot (or clean switch) into normal run.
  7. If join fails N times or after timeout, stay in portal and show error.

* When **credentials exist**, device boots straight to the **existing Zigbee TCP bridge** behavior.

* **UART AT flow remains working** (`ATW0/ATW1/ATWC`) and can override credentials at any time.

* Provide **feature flags** to turn the entire portal ON/OFF at compile time.

* Provide **clear logs** over UART for every state transition (but never print the AP password).

* Provide a **rollback path**: holding the button >5s wipes creds and re-enters portal.

---

## Constraints & Non-Goals

* Do **not** modify Zigbee UART/NCP behavior except for moving its start after provisioning passes.
* Keep memory use modest: each new FreeRTOS task ≤ 2–4 KB stack where possible.
* No external libs; use what’s already in SDK (lwIP sockets, FreeRTOS).
* Keep HTML inline (no filesystem).
* Security: AP must use WPA2-PSK with per-device random password, torn down immediately after success.

---

## High-Level Design

**New components (create files):**

* `project/.../src/provisioning/provisioning_task.c/.h`
  Orchestrates provisioning state machine; exposes `provisioning_run_if_needed()`.
* `project/.../src/provisioning/dns_captive.c/.h`
  Minimal UDP DNS responder: reply to all A queries with AP IP.
* `project/.../src/provisioning/http_portal.c/.h`
  Tiny HTTP server on lwIP: GET `/`, GET `/scan`, POST `/save`.
* `project/.../src/provisioning/wifi_store.c/.h`
  Thin wrapper to read/write Wi-Fi creds to NVRAM/flash using existing SDK KV APIs.
* `project/.../include/provisioning_config.h`
  Compile-time knobs (timeouts, task stacks, etc.).
* `project/.../include/ap_secrets.h` (auto-generated per device, ignored by git).

**Minimal changes (edit):**

* `project/.../src/main.c` (or whichever has `app_main()`):
  Call `provisioning_run_if_needed()` **before** starting the TCP bridge task.
* `platform_opts.h` (or equivalent):
  Add `#define CONFIG_CAPTIVE_PORTAL 1` and other toggles.
* If needed: board `gpio.c` to read a **PROV button** (long-press).

**FreeRTOS tasks:**

* `prov_mgr_task` — supervises state machine (AP up/down, timeouts, button).
* `dns_task` — UDP 53 responder.
* `http_task` — HTTP server (single-threaded, select()/nonblocking).

---

## Build-time step

* Add a script (Python recommended) to generate `ap_secrets.h` with:

  * `#define AP_SSID_SUFFIX "XXXX"` (last two MAC bytes)
  * `#define AP_PASSWORD "randomstring"` (random WPA2 password, ≥10 chars)
* Script also outputs `label.txt` for printing:

  ```
  SSID: GW018-Setup-XXXX
  PASSWORD: randomstring

  1) Connect to this Wi-Fi
  2) Setup page will open automatically
  3) Pick your home Wi-Fi and enter password
  ```
* Keep `ap_secrets.h` out of git (add to `.gitignore`).

---

## Detailed Steps for the Agent

(same as original, except AP bring-up uses WPA2 password from `ap_secrets.h` instead of open AP; ensure password never printed in logs)

---

## HTML for `/` (inline minimal)

(same as original; no changes needed)

---

## Test Plan

1. **Cold boot, no creds**

   * Device launches AP `GW018-Setup-XXXX` (with sticker password).
   * Phone joins using printed password.
   * Captive portal opens; user enters home Wi-Fi SSID + pass.
   * On success: AP stops, device reboots, Zigbee bridge runs.

2. **Wrong Wi-Fi password** → portal shows “Join failed.”

3. **Timeout** → portal stops after 10 min idle.

4. **Button long-press** → wipe creds, restart AP with same SSID/password.

5. **Regression** → UART AT still works.

---

## Deliverables

* Source files: `provisioning_task.c/.h`, `dns_captive.c/.h`, `http_portal.c/.h`, `wifi_store.c/.h`, `provisioning_config.h`, `ap_secrets.h` (generated).
* Modified: `main.c`, `platform_opts.h`, Makefiles.
* Python script for `ap_secrets.h` + sticker.
* README update: “Wi-Fi WPA2 Captive Portal Provisioning.”
* UART log excerpt (without AP password) from successful run.

---

## Nice-to-Haves (Optional)

* Return **200 HTML** for known captive checks (Apple/Android/Windows).
* Add `/version` endpoint echoing git SHA and build date.
* Expose `/reset` to erase creds when connected to AP (with CSRF token).

---

**Proceed to implement.** Use the same Wi-Fi connect path as AT `ATWC`. Never print AP password in logs; rely on the sticker.
