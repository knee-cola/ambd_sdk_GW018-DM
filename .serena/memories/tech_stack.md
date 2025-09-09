# Technology Stack

## Core Technologies
- **Platform**: AmebaD SDK (Realtek RTL8721CSM)
- **Language**: C/C++ 
- **Build System**: Make with GCC toolchain
- **Architecture**: Dual-core ARM (KM0 low power + KM4 high performance)

## Development Environment
- **OS**: Linux (tested on Fedora)
- **Required Packages**: 
  - make
  - gcc/gcc-c++
  - glibc-devel.i686
  - ncurses-compat-libs.i686
  - minicom (for UART communication)
- **Containerization**: Docker support with complete build environment

## Flashing Tools
- **ImageTool CLI**: Linux executable from AmebaD Arduino SDK
- **ImageTool GUI**: Windows-based GUI tool (.NET Framework 3.5 required)
- **UART Communication**: Minicom, 115200/921600 baud rate
- **Flash Memory**: External flash on RTL8721CSM chip

## Protocols & Communication
- **WiFi**: 802.11 with WPA/WPA2
- **Zigbee**: EZSP protocol over TCP socket
- **Update Methods**: HTTP OTA updates, UART firmware flashing
- **Serial Protocol**: AT commands for WiFi configuration