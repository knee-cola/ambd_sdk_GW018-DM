# Build System Structure

## Project Layout
```
ambd_sdk_GW018-DM/
├── component/          # SDK components and examples
│   ├── common/         # Common examples and utilities
│   ├── os/             # Operating system components  
│   └── soc/            # System-on-chip specific code
├── project/            # Main project directory
│   └── realtek_amebaD_va0_example/
│       ├── GCC-RELEASE/
│       │   ├── project_lp/    # Low Power (KM0) build
│       │   └── project_hp/    # High Performance (KM4) build
│       ├── inc/        # Header files and configuration
│       └── src/        # Source code
└── tools/              # Docker and build scripts
```

## Dual-Core Architecture
The RTL8721CSM has two ARM cores:
- **KM0 (project_lp)**: Low power core, handles bootloader and power management
- **KM4 (project_hp)**: High performance core, handles main application logic

## Build Targets
Each core project supports these Make targets:
- `all`: Build complete firmware images
- `clean`: Clean build artifacts
- `setup`: Setup build environment
- `flash`: Flash via GDB
- `debug`: Debug via GDB  
- `menuconfig`: Configuration menu
- `xip`: Execute-in-place build

## Configuration
- Main config: `platform_opts.h` - enables/disables features via CONFIG_EXAMPLE_* flags
- Key enabled features:
  - CONFIG_EXAMPLE_SOCKET_TCP_TRX=1 (TCP socket server)
  - CONFIG_EXAMPLE_OTA_HTTP=1 (OTA updates)
  - CONFIG_EXAMPLE_WLAN_FAST_CONNECT=1 (WiFi auto-connect)