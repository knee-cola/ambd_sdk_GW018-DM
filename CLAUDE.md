# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AmebaD SDK (RTL8721CSM) firmware project for the Tuya GW018-DM Zigbee gateway, modified to disconnect from the cloud and function as a local Zigbee adapter for Home Assistant/Zigbee2MQTT. The firmware creates a TCP-to-UART bridge allowing communication with the onboard Zigbee chip (EFR32MG21) via network connection.

## Build Commands

### Primary Build Process
The project has dual-core architecture (KM0 and KM4):

1. **Build KM0 (Low Power Core):**
   ```bash
   cd project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp/
   make all
   ```

2. **Build KM4 (High Performance Core):**
   ```bash
   cd project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/
   make all
   ```

### Build Outputs
- Built images are located in `asdk/image/` subdirectories of each project
- Key files: `km0_boot_all.bin`, `km4_boot_all.bin`, `km0_km4_image2.bin`

### Clean Commands
```bash
make clean      # Clean current project
make clean_all  # Deep clean all build artifacts
```

### Permission Fix (if needed)
```bash
chmod -R 777 ./
```

## Architecture

### Core Structure
- **Dual-core ARM Cortex-M architecture**: KM0 (power management) + KM4 (application)
- **KM0 (project_lp)**: Low-power core handling power management, wake-up events, RTC
- **KM4 (project_hp)**: High-performance core running main application, Wi-Fi, networking

### Key Directories
- `project/realtek_amebaD_va0_example/`: Main project directory
- `component/common/`: Shared components (drivers, APIs, examples)
- `component/soc/realtek/amebad/`: SoC-specific hardware abstraction

### Main Entry Points
- **KM0**: `project/realtek_amebaD_va0_example/src/src_lp/main.c`
- **KM4**: `project/realtek_amebaD_va0_example/src/src_hp/main.c`

### Configuration Files
- `project/realtek_amebaD_va0_example/inc/inc_hp/platform_opts.h`: Main feature toggles
- `component/common/example/example_entry.c`: Example application router

## Current Functionality

### Wi-Fi Provisioning
- UART AT commands for Wi-Fi setup: `ATW0=SSID`, `ATW1=PASSWORD`, `ATWC`
- Automatic reconnection to saved credentials

### Zigbee Bridge Operation
- TCP server on port 80 exposing UART interface to Zigbee chip
- Compatible with Zigbee2MQTT using `tcp://gateway-ip:80` as serial port
- UART configuration: 115200 baud, RTS/CTS enabled

### Hardware Interfaces
- **UART Pins**: TX(_PA_18), RX(_PA_19), RTS(_PA_16), CTS(_PA_17)
- **LEDs**: Red(_PA_25), Blue(_PB_22)
- **Debug UART**: Available for AT commands and firmware interaction

## Flashing/Programming

### Using ImageTool (Linux CLI)
```bash
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Disable 921600
```

### UART Command Mode
Access via holding ESC during power-up with UART connected at 115200 baud.

## Development Notes

### Feature Configuration
- Features are controlled via `#define` directives in `platform_opts.h`
- Example applications can be enabled/disabled through `CONFIG_EXAMPLE_*` flags
- Current focus is on TCP-UART bridge functionality for Zigbee communication

### Memory Layout
- Flash sectors allocated for different purposes (UART settings, AP settings, fast reconnect data)
- Power management optimized for low-power operation

### Wi-Fi Provisioning Methods

#### 1. UART AT Commands (Legacy)
- `ATW0=SSID` - Set SSID
- `ATW1=PASSWORD` - Set password  
- `ATWC` - Connect to Wi-Fi

#### 2. Captive Portal (New - Implemented)
When no Wi-Fi credentials exist or provisioning is triggered:
- Device creates WPA2-PSK protected SoftAP: `GW018-Setup-XXXX`
- SSID suffix (XXXX) = last 2 bytes of Wi-Fi MAC address
- Password is randomly generated per device at build time
- DNS catch-all redirects all queries to captive portal at `192.168.4.1`
- HTTP server provides Wi-Fi setup interface

**Recovery Methods:**
- 3× power cycles within 30 seconds triggers provisioning mode
- Long button press (5+ seconds) - *when GPIO configured*

**Build Integration:**
- `tools/generate_ap_secrets.py` creates per-device secrets
- Run with `DEVICE_MAC=AA:BB:CC:DD:EE:FF` environment variable
- Generates `ap_secrets.h`, `label.txt`, and provision log

### Current Branch Status
- Working on: `implementing-captive-portal` branch  
- Main development branch: `dev`
- **Captive portal Wi-Fi provisioning feature is now implemented**