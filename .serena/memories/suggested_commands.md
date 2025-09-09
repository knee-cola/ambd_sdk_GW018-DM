# Essential Commands for GW018-DM Development

## Building Firmware

### Manual Build Process
```bash
# Build Low Power (KM0) core
cd project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp/
make clean
make all

# Build High Performance (KM4) core  
cd ../project_hp/
make clean
make all
```

### Docker-based Build (Recommended)
```bash
# Build Docker image
cd tools/
docker build -t gw018-dm-flasher .

# Run build script in container
./build.sh
```

## Flashing Firmware

### Using ImageTool CLI (Linux)
```bash
# Download flashing tool
wget -O upload_image_tool_linux https://github.com/ambiot/ambd_arduino/raw/dev/Arduino_package/ameba_d_tools_linux/upload_image_tool_linux
chmod +x upload_image_tool_linux

# Erase flash (optional)
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Enable 921600

# Flash firmware
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Disable 921600
```

### Required Binary Files
- `km0_boot_all.bin` (from project_lp/asdk/image/)
- `km4_boot_all.bin` (from project_hp/asdk/image/)
- `km0_km4_image2.bin` (from project_hp/asdk/image/)

## UART Communication
```bash
# Install minicom
sudo dnf install minicom

# Connect to device  
minicom -b 115200 -D /dev/ttyUSB0

# Enter command mode (power device first, then connect UART)
# Press and hold ESC to get shell prompt

# WiFi configuration commands
ATW0=myWifiName
ATW1=myWifiPassword  
ATWC
reboot
```

## Over-The-Air Updates
```bash
# Serve firmware files via HTTP
cd project_hp/asdk/image/
python3 -m http.server 8080

# Trigger OTA update (press reset button for 3-4 seconds)
```

## Development Tools
```bash
# Clean build artifacts
make clean

# Configuration menu  
make menuconfig

# Debug via GDB
make debug

# Flash via GDB
make flash
```