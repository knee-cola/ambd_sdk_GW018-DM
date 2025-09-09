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

# Project paths
PROJECT_LP_DIR="/workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp"
PROJECT_HP_DIR="/workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp"

# Permission backup files
PERMISSIONS_LP_FILE=""
PERMISSIONS_HP_FILE=""

# Function to backup directory permissions
backup_permissions() {
    local dir="$1"
    local backup_file="$2"
    
    echo -e "${CYAN}${ICON_INFO} Backing up permissions for $(basename "$dir")...${NC}"
    
    # Create temporary file for permission backup
    backup_file=$(mktemp)
    
    # Save current permissions using find and stat
    find "$dir" -type f -exec stat -c "%n %a" {} \; > "$backup_file" 2>/dev/null || {
        echo -e "${YELLOW}${ICON_WARNING} Warning: Could not backup all file permissions in $dir${NC}"
    }
    find "$dir" -type d -exec stat -c "%n %a" {} \; >> "$backup_file" 2>/dev/null || {
        echo -e "${YELLOW}${ICON_WARNING} Warning: Could not backup all directory permissions in $dir${NC}"
    }
    
    echo "$backup_file"
}

# Function to restore directory permissions
restore_permissions() {
    local backup_file="$1"
    local description="$2"
    
    if [[ -f "$backup_file" ]]; then
        echo -e "${CYAN}${ICON_INFO} Restoring $description permissions...${NC}"
        
        while IFS=' ' read -r file_path perm; do
            if [[ -e "$file_path" ]]; then
                chmod "$perm" "$file_path" 2>/dev/null || {
                    echo -e "${YELLOW}${ICON_WARNING} Warning: Could not restore permissions for $file_path${NC}"
                }
            fi
        done < "$backup_file"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null || true
    fi
}

# Function to cleanup and restore permissions on exit
cleanup_and_restore() {
    local exit_code=$?
    
    # Only show cleanup message if not a normal exit
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${YELLOW}${ICON_INFO} Build failed - cleaning up and restoring permissions...${NC}"
    else
        echo -e "${CYAN}${ICON_INFO} Restoring original permissions...${NC}"
    fi
    
    # Restore LP permissions
    if [[ -n "$PERMISSIONS_LP_FILE" ]]; then
        restore_permissions "$PERMISSIONS_LP_FILE" "LP project"
    fi
    
    # Restore HP permissions
    if [[ -n "$PERMISSIONS_HP_FILE" ]]; then
        restore_permissions "$PERMISSIONS_HP_FILE" "HP project"
    fi
    
    # Clean up temporary build output files
    rm -f "$build_output_lp" "$build_output_hp" 2>/dev/null || true
    
    # Only exit with error code if this was an error exit
    if [[ $exit_code -ne 0 ]]; then
        exit $exit_code
    fi
}

# Set up trap to ensure cleanup happens on any exit
trap cleanup_and_restore EXIT

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

# Backup original permissions before changing them
echo -e "${YELLOW}${ICON_INFO} Backing up and setting permissions for build directories...${NC}"
PERMISSIONS_LP_FILE=$(backup_permissions "$PROJECT_LP_DIR")
PERMISSIONS_HP_FILE=$(backup_permissions "$PROJECT_HP_DIR")

# Set permissions for Docker build environment
echo -e "${CYAN}${ICON_INFO} Setting build permissions (777)...${NC}"
chmod -R 777 "$PROJECT_LP_DIR"
chmod -R 777 "$PROJECT_HP_DIR"

echo -e "${PURPLE}${ICON_BUILD} Building LP (Low Power) project...${NC}"
cd "$PROJECT_LP_DIR"
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
cd "$PROJECT_HP_DIR"

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
SELECTED_DEVICE=""
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

echo -e "${BLUE}${ICON_FLASH} Do you want to flash the firmware to GW018-DM now? (y/n)${NC}"
read -r response
if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}${ICON_INFO} Exiting without flashing.${NC}"
    exit 0
fi

echo -e "${CYAN}${ICON_FLASH} Flashing firmware to GW018-DM using $SELECTED_DEVICE...${NC}"

cd /workspace/flash

# Erase flash before flashing new firmware (may not be needed)
echo -e "${YELLOW}${ICON_INFO} Erasing flash...${NC}"
./upload_image_tool_linux "$PWD" "$SELECTED_DEVICE" ameba_rtl8721csm Enable Enable 921600

# … and let's flash!
echo -e "${CYAN}${ICON_FLASH} Writing firmware...${NC}"
./upload_image_tool_linux "$PWD" "$SELECTED_DEVICE" ameba_rtl8721csm Enable Disable 921600