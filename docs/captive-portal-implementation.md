# Prompt for IDE Agent: Add WPA2 SoftAP + Captive Portal Wi-Fi Provisioning to AmebaD GW018-DM Firmware

> **Context**
> Repo: `jasperw1996/ambd_sdk_GW018-DM` (AmebaD RTL8722DM).
> Current behavior: Wi-Fi credentials are entered via UART AT commands; after join, device acts as a TCP↔UART bridge to Tuya Zigbee (EFR32MG21) for Zigbee2MQTT.
> **Goal:** Implement an *optional* provisioning flow using a **WPA2-PSK SoftAP + DNS catch-all + minimal HTTP form** (“captive portal”).
> **Important decisions:**
> • AP is **password-protected** (WPA2-PSK AES).
> • **Per-device random password** is generated at **build time**, embedded via `ap_secrets.h`, and printed on a **sticker** with SSID+instructions.
> • Preserve existing UART AT provisioning and Zigbee bridge behavior.

---

## Requirements (Definition of Done)

When **no Wi-Fi credentials** exist, or a **provisioning trigger** is set (long-press button or compile-time flag):

1. Start **SoftAP** with SSID `GW018-Setup-XXXX` (XXXX = last 2 bytes of Wi-Fi MAC, uppercase hex) and security **WPA2-PSK AES** using a **random per-device password** from `ap_secrets.h`.
2. Ensure **DHCP server** is active for AP clients.
3. Run **DNS catch-all** responding to any A query with the AP IP (e.g., `192.168.4.1`).
4. Run a **minimal HTTP server** (port 80):

   * `GET /` → captive page with **SSID list**, manual SSID field, **home Wi-Fi password** field, **Connect** button.
   * `GET /scan` → JSON list of visible SSIDs.
   * `POST /save` → `ssid` + `password`; attempt STA connect.

     * On success: **persist creds**, stop AP/DNS/HTTP, **reboot** (or transition cleanly) into normal mode.
     * On failure: show error and remain in portal.
5. **Timeouts:** tear down portal after **10 minutes** of inactivity.
6. **Captive triggers:** reply **HTTP 200** for OS probes and route to `/`:

   * Android `/generate_204`, Apple `/hotspot-detect.html`, Windows `/ncsi.txt`.
7. **Recovery:** long-press button (>5s) or 3× power-cycle clears creds and restarts the portal.
8. **Fallback:** UART AT (`ATW0/ATW1/ATWC`) still works and overrides stored creds.
9. **Logging:** log state transitions with tags `[PORTAL] [DNS] [HTTP] [WIFI]`; **never** print the AP password.

---

## Constraints & Non-Goals

* Do **not** change Zigbee UART/NCP behavior except delaying its start until provisioning completes.
* **No external libraries**; use lwIP + FreeRTOS + SDK Wi-Fi APIs only.
* Keep HTML inline (no filesystem).
* Memory: each new task ≤ 2–4 KB stack if possible.
* Security: AP must be WPA2-PSK; stop immediately after success.

---

## High-Level Design

**Create (new):**

* `project/.../src/provisioning/provisioning_task.c/.h` – entry orchestration; `provisioning_run_if_needed()`.
* `project/.../src/provisioning/dns_captive.c/.h` – UDP :53 catch-all responder.
* `project/.../src/provisioning/http_portal.c/.h` – minimal HTTP server; routes `/`, `/scan`, `/save`.
* `project/.../src/provisioning/wifi_store.c/.h` – wrapper for reading/writing creds to NVRAM/flash (prefer SDK KV used by AT).
* `project/.../include/provisioning_config.h` – knobs (timeouts, stacks, ports).
* `project/.../include/ap_secrets.h` – **auto-generated per device** (ignored by git).

**Modify:**

* `project/.../src/main.c` (or the file with `app_main()`): call `provisioning_run_if_needed()` **before** starting Zigbee bridge.
* `platform_opts.h`: add `#define CONFIG_CAPTIVE_PORTAL 1` and related toggles.
* Board `gpio.c` (if needed) to read **PROV** button (long-press).

**FreeRTOS tasks:**

* `prov_mgr_task` – state machine (AP up/down, timeouts, button, retries).
* `dns_task` – DNS hijack.
* `http_task` – HTTP server (single-threaded, non-blocking `select()`).

---

## Build-Time Automation (Agent must create this)

**The agent must implement a build helper that auto-generates `ap_secrets.h` and a printable label for each device.**

**Requirements for the helper:**

1. **Inputs:**

   * Wi-Fi **MAC address** of the device. Obtain via one of:
     a) Environment variable `DEVICE_MAC=AA:BB:CC:DD:EE:FF`,
     b) Tiny host tool (or one-shot firmware) that prints MAC,
     c) Accept manual input if neither available.
2. **Outputs:**

   * `ap_secrets.h` with:

     ```c
     #pragma once
     #define AP_SSID_PREFIX "GW018-Setup-"
     #define AP_SSID_SUFFIX "XXXX"     // last two MAC bytes, uppercase hex
     #define AP_PASSWORD    "RandomAlnum10+"
     ```
   * A human-readable **label file** (e.g., `label.txt`) containing:

     ```
     SSID: GW018-Setup-XXXX
     PASSWORD: <random>
     1) Connect to the Wi-Fi above
     2) Setup page opens automatically (or visit http://192.168.4.1/)
     3) Choose your home Wi-Fi and enter its password
     ```
   * A **CSV log** (`provision_log.csv`) with timestamp, MAC, SSID, password.
   * (Optional) a **Wi-Fi QR** string and/or PNG (`wifi_qr.png`).
3. **Random password policy:**

   * 10–16 chars, `[A–Za–z0–9]`, WPA2-PSK compliant (≥8 ASCII).
4. **Idempotency:**

   * If `ap_secrets.h` exists and `FORCE_REGEN=0`, do nothing.
   * `FORCE_REGEN=1` regenerates secrets.
5. **Integration:**

   * Update the project **Makefile** (or build script) to **invoke the helper** before compile **iff** `ap_secrets.h` is missing or `FORCE_REGEN=1`.
   * Add `ap_secrets.h` and generated artifacts to **`.gitignore`**.
6. **Security:**

   * Never commit secrets; only log to the local CSV.
   * Do not print AP password in runtime logs.

---

## Detailed Steps for the Agent

1. **Locate entry point & Zigbee start:** find `app_main()` and the startup of the TCP↔UART bridge; defer that until after provisioning.

2. **Add config (`provisioning_config.h`):**

```c
#pragma once
#define CONFIG_CAPTIVE_PORTAL        1
#define CONFIG_PORTAL_AP_SSID_PREFIX "GW018-Setup-"
#define CONFIG_PORTAL_HTTP_PORT      80
#define CONFIG_PORTAL_DNS_PORT       53
#define CONFIG_PORTAL_IDLE_TIMEOUT_S 600
#define CONFIG_PORTAL_MAX_JOIN_TRIES 3
#define CONFIG_PROV_BUTTON_GPIO      <gpio or -1>
#define CONFIG_PROV_BUTTON_HOLD_MS   5000
#define CONFIG_TASK_STACK_DNS        2048
#define CONFIG_TASK_STACK_HTTP       4096
#define CONFIG_TASK_STACK_PROV       3072
```

3. **Credential storage (`wifi_store`):**
   Implement `wifi_store_have_creds()`, `wifi_store_get()`, `wifi_store_set()`. Prefer the **same KV** used by AT Wi-Fi commands; otherwise implement a tiny flash KV (document sector, alignment, wear).

4. **SoftAP helper:**
   Compute SSID as `AP_SSID_PREFIX + AP_SSID_SUFFIX`; bring up WPA2-PSK AES AP with `AP_PASSWORD` from `ap_secrets.h`. Set AP IP (`192.168.4.1/24`) and ensure DHCP server is enabled.

5. **DNS catch-all (`dns_captive`):**
   UDP :53; minimal header parse; answer first A-record question with AP IP; ignore EDNS/TCP.

6. **HTTP portal (`http_portal`):**

* Listen :80.
* `GET /` → embedded HTML (see snippet below).
* `GET /scan` → use SDK Wi-Fi scan API; return `["SSID1","SSID2",...]`.
* `POST /save` (form-urlencoded) → `ssid`, `password`:

  * Call the **same connect path** as AT `ATWC`.
  * On success: `wifi_store_set()`, respond “Connected. Rebooting…”, delay, reboot.
  * On failure: message + stay in portal.
* Ensure proper HTTP CRLF and connection close per request.

7. **Provisioning manager (`provisioning_task`):**
   State machine: if no creds or button held → start AP/DNS/HTTP, wait until success/timeout. On exit: stop services; reboot if success.

8. **Integrate into boot:**
   Early in `app_main()`:

```c
provisioning_run_if_needed();           // may reboot internally on success
attempt_sta_connect_if_needed();        // reuse AT path if needed
start_zigbee_tcp_bridge();              // existing behavior
```

9. **Build system changes:**

* Add a pre-build rule/step that runs the **helper** to generate `ap_secrets.h`.
* If `DEVICE_MAC` not provided, prompt or gracefully fail with instructions.

10. **Logging & hygiene:**

* Consistent tags; mask secrets; handle errors; ensure tasks delete themselves cleanly.

---

## HTML for `/` (inline minimal)

```html
<!doctype html><html><head><meta name=viewport content="width=device-width,initial-scale=1">
<title>GW018 Setup</title></head><body>
<h2>Connect to Wi-Fi</h2>
<label>SSID <select id="ssids"></select></label><br/>
<label>Or enter SSID <input id="ssid" placeholder="Network name"></label><br/>
<label>Password <input id="pass" type="password"></label><br/>
<button onclick="save()">Connect</button>
<pre id="msg"></pre>
<script>
async function scan(){
  try{
    const r = await fetch('/scan'); const a = await r.json();
    const sel = document.getElementById('ssids'); sel.innerHTML='';
    (a||[]).forEach(s=>{ const o=document.createElement('option'); o.value=s; o.text=s; sel.appendChild(o); });
  }catch(e){}
}
async function save(){
  const sel = document.getElementById('ssids').value;
  const sid = document.getElementById('ssid').value || sel;
  const pwd = document.getElementById('pass').value;
  const body = 'ssid='+encodeURIComponent(sid)+'&password='+encodeURIComponent(pwd);
  const r = await fetch('/save',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
  document.getElementById('msg').textContent = await r.text();
}
scan();
</script></body></html>
```

---

## Test Plan

1. **Fresh device (no creds):** AP `GW018-Setup-XXXX` (WPA2 with sticker password) appears; connect; captive portal shows; submit correct home Wi-Fi; AP stops; device reboots; bridge runs; Z2M connects.
2. **Wrong home Wi-Fi password:** portal shows “Join failed.”
3. **Timeout:** no interaction for 10 min → portal stops/reboots; logs reason.
4. **Recovery:** long-press button clears creds and restarts AP with **same** SSID/password (from `ap_secrets.h`).
5. **Regression:** UART AT `ATW0/ATW1/ATWC` still works; with creds present, device skips portal.
6. **Resource checks:** no stack overflow; tasks exit; no memory leaks.

---

## Deliverables

* New source: `provisioning_task.c/.h`, `dns_captive.c/.h`, `http_portal.c/.h`, `wifi_store.c/.h`, `provisioning_config.h`.
* **Build helper** that generates `ap_secrets.h`, `label.txt`, and updates `provision_log.csv` (and optional QR).
* Modified: `main.c` (or equivalent), `platform_opts.h`, Makefiles to invoke the helper.
* `.gitignore` updates to exclude generated secrets/artifacts.
* README section: **“Provisioning via WPA2 AP captive portal”** including label screenshot and recovery instructions.
* UART log excerpt from a successful run (no secrets).

---

## Notes & Unknowns (resolve during implementation)

* Use the **same STA connect routine** invoked by AT `ATWC` to avoid duplicating logic.
* Prefer SDK’s **existing DHCP-AP** behavior; enable/configure if not automatic.
* Confirm **MAC read** API or provide a documented fallback input path.
* Choose a stable **GPIO** for the PROV button and document pull-ups/downs.

---

**Proceed to implement.** The agent must:

1. Implement the portal (AP/DNS/HTTP) per above,
2. Create and integrate the **build helper** that generates `ap_secrets.h` + label,
3. Update Makefiles/README/tests,
4. Keep UART provisioning and Zigbee bridge intact.
