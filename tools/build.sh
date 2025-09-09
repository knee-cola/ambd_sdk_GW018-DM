#!/bin/bash

# This script builds and flashes firmware for the GW018-DM device.
# It is intended to be run inside a Docker container with the necessary build environment.

# Color and icon definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Icons
ICON_BUILD="🔨"
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_FLASH="⚡"
ICON_COPY="📁"
ICON_MAC="🏷️"

echo -e "${CYAN}${ICON_BUILD} Building firmware...${NC}"

# Helper function to validate build success
validate_build() {
    local project_name="$1"
    local build_output_file="$2"
    local expected_binaries=("${@:3}")
    
    # Check if build output contains success message
    if ! grep -q "========== Image manipulating end ==========" "$build_output_file"; then
        echo -e "${RED}${ICON_ERROR} ERROR: $project_name build failed - missing success message${NC}"
        echo -e "${YELLOW}${ICON_INFO} Build output saved to: $build_output_file${NC}"
        return 1
    fi
    
    # Check if all expected binary files exist
    for binary in "${expected_binaries[@]}"; do
        if [[ ! -f "$binary" ]]; then
            echo -e "${RED}${ICON_ERROR} ERROR: $project_name build failed - missing binary file: $binary${NC}"
            return 1
        fi
    done
    
    echo -e "${GREEN}${ICON_SUCCESS} $project_name build completed successfully!${NC}"
    return 0
}

echo -e "${BLUE}${ICON_MAC} Please enter the MAC address of the device (format: AA:BB:CC:DD:EE:FF):${NC}"
read -r device_mac

if [[ ! "$device_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    echo -e "${RED}${ICON_ERROR} Error: Invalid MAC address format. Please use AA:BB:CC:DD:EE:FF format.${NC}"
    exit 1
fi

echo -e "${GREEN}${ICON_MAC} Using device MAC address: $device_mac${NC}"

echo -e "${YELLOW}${ICON_INFO} Fixing permissions for project_lp and project_hp directories...${NC}"
chmod -R 777 /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp
chmod -R 777 /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp

echo -e "${PURPLE}${ICON_BUILD} Building LP (Low Power) project...${NC}"
cd /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp
make clean

# Capture build output and check for success
echo -e "${CYAN}${ICON_BUILD} Starting LP build with MAC: $device_mac${NC}"
build_output_lp=$(mktemp)
if ! DEVICE_MAC="$device_mac" make all 2>&1 | tee "$build_output_lp"; then
    echo -e "${RED}${ICON_ERROR} ERROR: LP build failed with non-zero exit code${NC}"
    echo -e "${YELLOW}${ICON_INFO} Build output saved to: $build_output_lp${NC}"
    exit 1
fi

# Validate LP build success
if ! validate_build "LP" "$build_output_lp" "asdk/image/km0_boot_all.bin"; then
    exit 1
fi

echo -e "${BLUE}${ICON_COPY} Copying LP (Low Power) binaries to flash directory...${NC}"
cp asdk/image/km0_boot_all.bin /workspace/flash/

echo -e "${PURPLE}${ICON_BUILD} Building HP (High Performance) project...${NC}"
cd /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/

make clean

# Capture build output and check for success
echo -e "${CYAN}${ICON_BUILD} Starting HP build with MAC: $device_mac${NC}"
build_output_hp=$(mktemp)
if ! DEVICE_MAC="$device_mac" make all 2>&1 | tee "$build_output_hp"; then
    echo -e "${RED}${ICON_ERROR} ERROR: HP build failed with non-zero exit code${NC}"
    echo -e "${YELLOW}${ICON_INFO} Build output saved to: $build_output_hp${NC}"
    exit 1
fi

# Validate HP build success
if ! validate_build "HP" "$build_output_hp" "asdk/image/km4_boot_all.bin" "asdk/image/km0_km4_image2.bin"; then
    exit 1
fi

echo -e "${BLUE}${ICON_COPY} Copying HP (High Performance) binaries to flash directory...${NC}"
cp asdk/image/km4_boot_all.bin /workspace/flash/
cp asdk/image/km0_km4_image2.bin /workspace/flash/

echo -e "${GREEN}${ICON_SUCCESS} Build process completed successfully!${NC}"
echo -e "${GREEN}${ICON_SUCCESS} All firmware binaries have been generated and validated.${NC}"

# Clean up temporary build output files
rm -f "$build_output_lp" "$build_output_hp" 2>/dev/null || true

echo -e "${BLUE}${ICON_FLASH} Do you want to flash the firmware to GW018-DM now? (y/n)${NC}"
read -r response
if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}${ICON_INFO} Exiting without flashing.${NC}"
    exit 0
fi

echo -e "${CYAN}${ICON_FLASH} Flashing firmware to GW018-DM...${NC}"

cd /workspace/flash

# Erase flash before flashing new firmware (may not be needed)
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Enable 921600

# … and let's flash!
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Disable 921600