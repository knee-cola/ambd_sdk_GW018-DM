#!/bin/bash

# This script builds and flashes firmware for the GW018-DM device.
# It is intended to be run inside a Docker container with the necessary build environment.
# Usage: ./build.sh [--flash /dev/ttyUSB0] [--no-flash]

# Parse command line arguments
FLASH_DEVICE=""
NO_FLASH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --flash)
            FLASH_DEVICE="$2"
            shift 2
            ;;
        --no-flash)
            NO_FLASH=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./build.sh [--flash /dev/ttyUSB0] [--no-flash]"
            exit 1
            ;;
    esac
done

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
ICON_WARNING="⚠️ "
ICON_INFO="ℹ️ "
ICON_FLASH="⚡"
ICON_COPY="📁"

# Verify flash device if --flash flag is used
if [[ -n "$FLASH_DEVICE" ]]; then
    if [[ ! -c "$FLASH_DEVICE" ]]; then
        echo -e "${RED}${ICON_ERROR} Error: Serial device $FLASH_DEVICE does not exist or is not accessible${NC}"
        exit 1
    fi
    echo -e "${GREEN}${ICON_SUCCESS} Using serial device: $FLASH_DEVICE${NC}"
fi

# Check if running inside container by verifying expected directory structure
if [[ "$PWD" != "/workspace" ]]; then
    echo -e "${RED}${ICON_ERROR} This script must be run inside a Docker container!${NC}"
    echo ""
    echo -e "${BLUE}${ICON_INFO} To build the firmware, please follow these steps:${NC}"
    echo -e "${CYAN}  1. ${NC}Run the container: ${YELLOW}./run.sh${NC}"
    echo -e "${CYAN}  2. ${NC}Inside the container, run: ${YELLOW}./build.sh${NC}"
    echo ""
    echo -e "${YELLOW}${ICON_WARNING} The build script requires the containerized build environment${NC}"
    echo -e "${YELLOW}   with all necessary tools and dependencies.${NC}"
    exit 1
fi
echo -e "${CYAN}${ICON_BUILD} Building firmware...${NC}"

# Project paths
PROJECT_LP_DIR="/workspace/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp"
PROJECT_HP_DIR="/workspace/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp"

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


echo -e "${YELLOW}${ICON_INFO} Setting permissions for Docker build environment...${NC}"
chmod -R 777 "$PROJECT_LP_DIR"
chmod -R 777 "$PROJECT_HP_DIR"

echo -e "${PURPLE}${ICON_BUILD} Building LP (Low Power) project...${NC}"
cd "$PROJECT_LP_DIR"
make clean

# Capture build output and check for success
echo -e "${CYAN}${ICON_BUILD} Starting LP build...${NC}"
build_output_lp=$(mktemp)
if ! make all 2>&1 | tee "$build_output_lp"; then
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
cd "$PROJECT_HP_DIR"

make clean

# Capture build output and check for success
echo -e "${CYAN}${ICON_BUILD} Starting HP build...${NC}"
build_output_hp=$(mktemp)
if ! make all 2>&1 | tee "$build_output_hp"; then
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

# Exit early if --no-flash flag is set
if [[ "$NO_FLASH" == true ]]; then
    echo -e "${YELLOW}${ICON_INFO} Build completed. Skipping flashing as requested.${NC}"
    exit 0
fi

# Select serial device to use
SELECTED_DEVICE=""

if [[ -n "$FLASH_DEVICE" ]]; then
    # Use pre-selected device from --flash flag
    SELECTED_DEVICE="$FLASH_DEVICE"
else
    # Ask for confirmation first
    echo -e "${BLUE}${ICON_FLASH} Do you want to flash the firmware to GW018-DM now? (y/n)${NC}"
    read -r response
    if [[ "$response" != "y" ]]; then
        echo -e "${YELLOW}${ICON_INFO} Exiting without flashing.${NC}"
        exit 0
    fi

    # Detect available serial devices
    echo -e "${CYAN}${ICON_INFO} Detecting serial devices...${NC}"
    SERIAL_DEVICES=()
    DEVICE_COUNT=0

    # Check for ttyUSB devices
    for device in /dev/ttyUSB*; do
        if [ -c "$device" ] 2>/dev/null; then
            SERIAL_DEVICES+=("$device")
            echo -e "${GREEN}${ICON_SUCCESS} Found serial device: $device${NC}"
            ((DEVICE_COUNT++))
        fi
    done

    # Check for ttyACM devices
    for device in /dev/ttyACM*; do
        if [ -c "$device" ] 2>/dev/null; then
            SERIAL_DEVICES+=("$device")
            echo -e "${GREEN}${ICON_SUCCESS} Found serial device: $device${NC}"
            ((DEVICE_COUNT++))
        fi
    done

    if [ $DEVICE_COUNT -eq 0 ]; then
        echo -e "${YELLOW}${ICON_WARNING} No serial devices found (/dev/ttyUSB*, /dev/ttyACM*)${NC}"
        echo -e "${YELLOW}${ICON_INFO} Device may not be connected or accessible${NC}"
        echo -e "${YELLOW}${ICON_INFO} Skipping firmware flashing.${NC}"
        exit 0
    fi

    # Select serial device to use
    if [ $DEVICE_COUNT -eq 1 ]; then
        SELECTED_DEVICE="${SERIAL_DEVICES[0]}"
        echo -e "${GREEN}${ICON_SUCCESS} Using serial device: $SELECTED_DEVICE${NC}"
    else
        echo -e "${BLUE}${ICON_INFO} Multiple serial devices found. Please select one:${NC}"
        for i in "${!SERIAL_DEVICES[@]}"; do
            echo -e "${CYAN}  $((i+1))) ${SERIAL_DEVICES[i]}${NC}"
        done
        
        while true; do
            echo -e "${BLUE}Enter selection (1-$DEVICE_COUNT): ${NC}"
            read -r selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $DEVICE_COUNT ]; then
                SELECTED_DEVICE="${SERIAL_DEVICES[$((selection-1))]}"
                echo -e "${GREEN}${ICON_SUCCESS} Selected device: $SELECTED_DEVICE${NC}"
                break
            else
                echo -e "${RED}${ICON_ERROR} Invalid selection. Please enter a number between 1 and $DEVICE_COUNT.${NC}"
            fi
        done
    fi
fi

echo -e "${CYAN}${ICON_FLASH} Flashing firmware to GW018-DM using $SELECTED_DEVICE...${NC}"

cd /workspace/flash

# Erase flash before flashing new firmware (may not be needed)
echo -e "${YELLOW}${ICON_INFO} Erasing flash...${NC}"
./upload_image_tool_linux "$PWD" "$SELECTED_DEVICE" ameba_rtl8721csm Enable Enable 921600

# … and let's flash!
echo -e "${CYAN}${ICON_FLASH} Writing firmware...${NC}"
./upload_image_tool_linux "$PWD" "$SELECTED_DEVICE" ameba_rtl8721csm Enable Disable 921600