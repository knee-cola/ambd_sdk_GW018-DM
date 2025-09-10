#!/bin/bash

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
ICON_BUILD="🔨 "
ICON_DOCKER="🐳 "
ICON_CLEAN="🧹 "
ICON_TOOLBOX="🧰 "

set -e # Exit on error

IMAGE_NAME="gw018-builder-flasher:latest"
CONTAINER_NAME="gw018-builder-flasher"

echo ""
echo -e "${CYAN}${ICON_TOOLBOX}\e[4mGW018 Toolbox Runner\e[0m${NC}"
echo ""

# Function to print usage instructions
print_usage() {
    echo -e "${BLUE}${ICON_INFO}Usage:${NC}"
    echo -e "  ${GREEN}$0 interactive${NC}"
    echo -e "  ${GREEN}$0 minicom${NC}"
    echo -e "  ${GREEN}$0 build${NC} ${YELLOW}[--flash [device]] [--no-flash] [--no-clean]${NC}"
    echo ""
    echo -e "${BLUE}${ICON_INFO}Modes:${NC}"
    echo -e "  ${CYAN}interactive${NC}  ${ICON_DOCKER}Start interactive bash session"
    echo -e "  ${CYAN}build${NC}        ${ICON_BUILD}Run the build script with optional parameters"
    echo -e "  ${CYAN}minicom${NC}      ${ICON_SERIAL}Run minicom script for serial communication"
    echo ""
    echo -e "${BLUE}${ICON_INFO}Build mode options:${NC}"
    echo -e "  ${YELLOW}--flash [device]${NC}  Flash to specified device (e.g. /dev/ttyUSB0)"
    echo -e "  ${YELLOW}--no-flash${NC}        Build only, skip flashing"
    echo -e "  ${YELLOW}--no-clean${NC}        Skip cleaning build artifacts after container exits"
    echo ""
    echo -e "${BLUE}${ICON_INFO}Examples:${NC}"
    echo -e "  ${GREEN}$0 interactive${NC}"
    echo -e "  ${GREEN}$0 build${NC}"
    echo -e "  ${GREEN}$0 build${NC} ${YELLOW}--no-clean${NC}"
    echo -e "  ${GREEN}$0 build${NC} ${YELLOW}--flash /dev/ttyUSB0${NC}"
    echo -e "  ${GREEN}$0 minicom${NC}"
    echo ""
}

# Parse and validate command line arguments
if [[ $# -lt 1 ]]; then
    echo -e "${RED}${ICON_ERROR}Error: At least one parameter required${NC}"
    echo ""
    print_usage
    exit 1
fi

MODE="$1"
shift

# Initialize variables
CLEAN_AFTER=true
BUILD_ARGS=""

# Parse mode-specific arguments
case "$MODE" in
    interactive|minicom)
        # These modes don't accept additional parameters
        if [[ $# -gt 0 ]]; then
            echo -e "${RED}${ICON_ERROR}Error: Mode '$MODE' does not accept additional parameters${NC}"
            echo -e "${BLUE}Usage: $0 $MODE${NC}"
            exit 1
        fi
        ;;
    build)
        # Parse build-specific arguments
        while [[ $# -gt 0 ]]; do
            case $1 in
                --flash)
                    if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                        # Flash device specified
                        BUILD_ARGS="$BUILD_ARGS --flash $2"
                        shift 2
                    else
                        echo -e "${RED}${ICON_ERROR}Error: --flash requires a device parameter (e.g. /dev/ttyUSB0)${NC}"
                        exit 1
                    fi
                    ;;
                --no-flash)
                    BUILD_ARGS="$BUILD_ARGS --no-flash"
                    shift
                    ;;
                --no-clean)
                    CLEAN_AFTER=false
                    shift
                    ;;
                *)
                    echo -e "${RED}${ICON_ERROR}Error: Unknown build option '$1'${NC}"
                    echo -e "${BLUE}Valid build options: --flash [device], --no-flash, --no-clean${NC}"
                    exit 1
                    ;;
            esac
        done
        ;;
    -h|--help)
        print_usage
        exit 0
        ;;
    *)
        echo -e "${RED}${ICON_ERROR}Error: Invalid mode '$MODE'${NC}"
        echo ""
        echo -e "${BLUE}Valid modes: ${GREEN}interactive, build, minicom${NC}"
        echo -e "${BLUE}Run ${GREEN}$0 ${YELLOW}--help${BLUE} for more information${NC}"
        echo ""
        exit 1
        ;;
esac

# Function to clean build artifacts safely using selective git clean
cleanup_build_artifacts() {
    echo -e "${CYAN}${ICON_INFO}Cleaning build artifacts from build-only directories...${NC}"
    cd "$PWD/../"
    
    sudo git clean -fdx project/realtek_amebaD_va0_example/GCC-RELEASE/
    sudo git restore project/realtek_amebaD_va0_example/GCC-RELEASE/
    sudo git clean -fdx project/realtek_amebaD_va0_example/inc/inc_hp/build_info.h
    sudo git clean -fdx project/realtek_amebaD_va0_example/inc/inc_lp/build_info.h
    sudo git clean -fdx component/common/
    
    echo -e "${GREEN}${ICON_SUCCESS}Build artifacts cleaned safely (source code preserved)${NC}"
}


# Validate we're in the tools directory
if [[ ! -f "Dockerfile" ]]; then
    echo -e "${RED}${ICON_ERROR}Error: Must run from tools/ directory (Dockerfile not found)${NC}"
    exit 1
fi

# Remove existing container if it exists
if docker ps -a --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
    echo -e "${YELLOW}${ICON_INFO}Removing existing container: $CONTAINER_NAME${NC}"
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1
fi

# Check if Docker image exists
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE_NAME$"; then
    echo -e "${BLUE}${ICON_DOCKER}Docker image $IMAGE_NAME not found. Building it...${NC}"
    docker build -t gw018-builder-flasher .
    if [ $? -ne 0 ]; then
        echo -e "${RED}${ICON_ERROR}Failed to build Docker image${NC}"
        exit 1
    fi
    echo -e "${GREEN}${ICON_SUCCESS}Docker image built successfully${NC}"
fi

# Find all serial devices and build device options
DEVICE_OPTS=""
DEVICE_COUNT=0

# Check for ttyUSB devices
for device in /dev/ttyUSB*; do
    if [ -c "$device" ] 2>/dev/null; then
        DEVICE_OPTS="$DEVICE_OPTS --device $device"
        echo -e "${GREEN}${ICON_SUCCESS}Found serial device: $device${NC}"
        ((DEVICE_COUNT++))
    fi
done

# Check for ttyACM devices
for device in /dev/ttyACM*; do
    if [ -c "$device" ] 2>/dev/null; then
        DEVICE_OPTS="$DEVICE_OPTS --device $device"
        echo -e "${GREEN}${ICON_SUCCESS}Found serial device: $device${NC}"
        ((DEVICE_COUNT++))
    fi
done

# Determine container command based on mode
case "$MODE" in
    interactive)
        echo -e "${CYAN}${ICON_DOCKER}Starting container in interactive mode...${NC}"
        CONTAINER_CMD="/bin/bash"
        INTERACTIVE_FLAG="-ti"
        ;;
    build)
        echo -e "${CYAN}${ICON_DOCKER}Starting container and running build script with args: $BUILD_ARGS${NC}"
        CONTAINER_CMD="/bin/bash"
        INTERACTIVE_FLAG="-ti"
        ;;
    minicom)
        echo -e "${CYAN}${ICON_DOCKER}Starting container and running minicom script...${NC}"
        CONTAINER_CMD="/workspace/minicom.sh"
        INTERACTIVE_FLAG="-ti"
        ;;
esac

if [[ "$MODE" == "build" ]]; then
    # For build mode, run the build script with arguments
    docker run --rm --name "$CONTAINER_NAME" \
      --volume "$PWD/../project:/workspace/project" \
      --volume "$PWD/../component:/workspace/component" \
      --volume "$PWD/../tools/build.sh:/workspace/build.sh" \
      --volume "$PWD/../tools/minicom.sh:/workspace/minicom.sh" \
      $DEVICE_OPTS \
      $INTERACTIVE_FLAG --entrypoint "/bin/bash" \
      "$IMAGE_NAME" -c "/workspace/build.sh $BUILD_ARGS"
else
    # For interactive and minicom modes
    docker run --rm --name "$CONTAINER_NAME" \
      --volume "$PWD/../project:/workspace/project" \
      --volume "$PWD/../component:/workspace/component" \
      --volume "$PWD/../tools/build.sh:/workspace/build.sh" \
      --volume "$PWD/../tools/minicom.sh:/workspace/minicom.sh" \
      $DEVICE_OPTS \
      $INTERACTIVE_FLAG --entrypoint "$CONTAINER_CMD" \
      "$IMAGE_NAME"
fi

# After container exits, handle cleanup based on --no-clean flag (only for build mode)
echo ""
echo -e "${BLUE}${ICON_INFO}Container session ended.${NC}"

if [[ "$MODE" == "build" ]]; then
    if [[ "$CLEAN_AFTER" == true ]]; then
        echo -e "${YELLOW}${ICON_CLEAN}Cleaning build artifacts: this requires sudo privileges${NC}"
        cleanup_build_artifacts
        echo -e "${GREEN}${ICON_SUCCESS}Cleanup complete.${NC}"
    else
        echo -e "${YELLOW}${ICON_INFO}Skipping cleanup as requested with --no-clean flag.${NC}"
    fi
fi
  