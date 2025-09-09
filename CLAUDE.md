# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AmebaD SDK project for the Tuya GW018-DM Zigbee gateway, designed to cut the gateway from the cloud and use it as a Zigbee adapter in Home Assistant via Zigbee2MQTT. The firmware targets the RTL8721CSM chip (WBRG1 module) and provides TCP socket communication on port 80 for Zigbee2MQTT integration.

## Architecture

The RTL8721CSM uses a dual-core ARM architecture:
- **KM0 (Low Power)**: Handles bootloader and power management - built in `project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp/`
- **KM4 (High Performance)**: Main application logic - built in `project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/`

## Build Commands

### Standard Build Process
```bash
# Build Low Power core
cd project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp/
make clean && make all

# Build High Performance core  
cd ../project_hp/
make clean && make all
```

### Docker Build (Recommended)
```bash
cd tools/
docker build -t gw018-dm-flasher .
./build.sh
```

### Build Artifacts
Generated binaries are located in `asdk/image/` directories:
- `project_lp/asdk/image/km0_boot_all.bin`
- `project_hp/asdk/image/km4_boot_all.bin` 
- `project_hp/asdk/image/km0_km4_image2.bin`

## Configuration System

Features are controlled via `CONFIG_EXAMPLE_*` macros in `project/realtek_amebaD_va0_example/inc/inc_hp/platform_opts.h`. Key enabled features:
- `CONFIG_EXAMPLE_SOCKET_TCP_TRX=1` - TCP socket server for Zigbee2MQTT
- `CONFIG_EXAMPLE_OTA_HTTP=1` - Over-the-air updates
- `CONFIG_EXAMPLE_WLAN_FAST_CONNECT=1` - WiFi auto-connection

## Flashing Firmware

### Using ImageTool CLI
```bash
# Erase flash
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Enable 921600

# Flash firmware  
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Disable 921600
```

Required files: `km0_boot_all.bin`, `km4_boot_all.bin`, `km0_km4_image2.bin`

### UART Communication
Connect via `minicom -b 115200 -D /dev/ttyUSB0`. WiFi configuration:
```
ATW0=wifi_ssid
ATW1=wifi_password  
ATWC
reboot
```

## Development Workflow

1. Make code changes
2. Build both cores: `make clean && make all` in project_lp and project_hp
3. Flash firmware using ImageTool
4. Test WiFi connectivity and Zigbee2MQTT integration
5. Verify OTA updates work if modified

## Code Conventions

- C/C++ with embedded constraints
- Snake_case naming for functions/variables
- Feature toggles via CONFIG_EXAMPLE_* macros
- Examples in `component/common/example/`
- Manual memory management required

## Testing

Device should:
- Connect to WiFi automatically on boot
- Start TCP server on port 80
- Show "Example: socket tx/rx 1" in boot logs
- Work with Zigbee2MQTT configuration:
  ```yaml
  serial:
    adapter: ezsp
    baudrate: 115200
    port: tcp://<gateway-ip>:80
    rtscts: true
  ```

## Over-The-Air Updates

Serve firmware from `project_hp/asdk/image/` via HTTP server, then press device reset button for 3-4 seconds to trigger OTA update.