#!/bin/bash

# This script provides serial communication with the GW018-DM device.
# It is intended to be run inside a Docker container with minicom installed.

# Color and icon definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Icons
ICON_SUCCESS="✅ "
ICON_ERROR="❌ "
ICON_WARNING="⚠️  "
ICON_INFO="ℹ️  "
ICON_SERIAL="📡 "

echo ""
echo -e "${CYAN}${ICON_SERIAL}\e[4mGW018-DM Serial Communication\e[0m${NC}"
echo ""

# Check if running inside container by verifying expected directory structure
if [[ "$PWD" != "/workspace" ]]; then
    echo -e "${RED}${ICON_ERROR}ERROR: this script should not be used directly (outside a Docker container)!${NC}"
    echo ""
    echo -e "${BLUE}${ICON_INFO}To use it run:${YELLOW} ./run.sh minicom${NC}"
    echo -e ""
    exit 1
fi

# Detect available serial devices
echo -e "${BLUE}${ICON_INFO}Detecting serial devices...${NC}"
SERIAL_DEVICES=()
DEVICE_COUNT=0

# Check for ttyUSB devices
for device in /dev/ttyUSB*; do
    if [ -c "$device" ] 2>/dev/null; then
        SERIAL_DEVICES+=("$device")
        echo -e "${GREEN}${ICON_SUCCESS}Found serial device: $device${NC}"
        ((DEVICE_COUNT++))
    fi
done

# Check for ttyACM devices
for device in /dev/ttyACM*; do
    if [ -c "$device" ] 2>/dev/null; then
        SERIAL_DEVICES+=("$device")
        echo -e "${GREEN}${ICON_SUCCESS}Found serial device: $device${NC}"
        ((DEVICE_COUNT++))
    fi
done

if [ $DEVICE_COUNT -eq 0 ]; then
    echo -e "${RED}${ICON_ERROR}No serial devices found (/dev/ttyUSB*, /dev/ttyACM*)${NC}"
    echo -e "${YELLOW}${ICON_WARNING}Device may not be connected or accessible${NC}"
    exit 1
fi

# Select serial device to use
SELECTED_DEVICE=""
if [ $DEVICE_COUNT -eq 1 ]; then
    SELECTED_DEVICE="${SERIAL_DEVICES[0]}"
    echo -e "${GREEN}${ICON_SUCCESS}Using serial device: $SELECTED_DEVICE${NC}"
else
    echo -e "${BLUE}${ICON_INFO}Multiple serial devices found. Please select one:${NC}"
    for i in "${!SERIAL_DEVICES[@]}"; do
        echo -e "${CYAN}  $((i+1))) ${SERIAL_DEVICES[i]}${NC}"
    done
    
    while true; do
        echo -e "${BLUE}Enter selection (1-$DEVICE_COUNT): ${NC}"
        read -r selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $DEVICE_COUNT ]; then
            SELECTED_DEVICE="${SERIAL_DEVICES[$((selection-1))]}"
            echo -e "${GREEN}${ICON_SUCCESS}Selected device: $SELECTED_DEVICE${NC}"
            break
        else
            echo -e "${RED}${ICON_ERROR}Invalid selection. Please enter a number between 1 and $DEVICE_COUNT.${NC}"
        fi
    done
fi

echo ""
echo -e "${YELLOW}${ICON_INFO}Starting minicom with the following settings:${NC}"
echo -e "  Device: $SELECTED_DEVICE"
echo -e "  Baud rate: 115200"
echo -e "  Data bits: 8"
echo -e "  Stop bits: 1"
echo -e "  Parity: None"
echo ""
echo -e "${CYAN}${ICON_INFO}Press Ctrl+A, X to exit minicom${NC}"
echo ""

# Start minicom with appropriate settings
minicom -b 115200 -D "$SELECTED_DEVICE"