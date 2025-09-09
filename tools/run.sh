#!/bin/bash
set -e

IMAGE_NAME="gw018-builder-flasher:latest"
CONTAINER_NAME="gw018-builder-flasher"

# Function to clean build artifacts safely using selective git clean
cleanup_build_artifacts() {
    echo "Cleaning build artifacts from build-only directories..."
    cd "$PWD/../"
    
    # Function to clean a directory with permission handling
    clean_directory() {
        local dir="$1"
        local description="$2"
        if [ -d "$dir" ]; then
            echo "  $description..."
            # First try to fix permissions, then clean
            find "$dir" -type f -exec chmod u+w {} \; 2>/dev/null || true
            git clean -fdx "$dir/" 2>/dev/null || {
                echo "    Warning: Some files in $dir may require manual removal"
            }
        fi
    }

    # Clean firmware binary directories (safe - only contain generated binaries)
    clean_directory "project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp/asdk/image" "Cleaning LP image directory"
    clean_directory "project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/asdk/image" "Cleaning HP image directory"
    clean_directory "project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/asdk/build" "Cleaning HP build directory"
    
    # Clean make object directories (safe - only contain .o, .d, .s, .su files)
    clean_directory "project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/asdk/make" "Cleaning HP make artifacts"
    clean_directory "project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp/asdk/make" "Cleaning LP make artifacts"
    
    # Clean component build artifacts (safe - only contain build files)
    clean_directory "component" "Cleaning component build artifacts"
    
    echo "Build artifacts cleaned safely (source code preserved)"
}

# Show help message
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Run GW018-DM firmware development container with auto-detected serial devices"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --clean       Clean build artifacts (run separately to clean up)"
    echo ""
    echo "This script will:"
    echo "  - Build Docker image if it doesn't exist"
    echo "  - Auto-detect serial devices (/dev/ttyUSB*, /dev/ttyACM*)"
    echo "  - Mount project directory and pass devices to container"
    echo "  - Optionally clean build artifacts (preserves source code)"
    exit 0
fi

# Handle cleanup option - immediate cleanup if requested
if [[ "$1" == "--clean" ]]; then
    echo "Cleaning build artifacts..."
    cleanup_build_artifacts
    echo "Cleanup complete."
    exit 0
fi

# Validate we're in the tools directory
if [[ ! -f "Dockerfile" ]]; then
    echo "Error: Must run from tools/ directory (Dockerfile not found)"
    exit 1
fi

# Remove existing container if it exists
if docker ps -a --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
    echo "Removing existing container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1
fi

# Check if Docker image exists
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE_NAME$"; then
    echo "Docker image $IMAGE_NAME not found. Building it..."
    docker build -t gw018-builder-flasher .
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build Docker image"
        exit 1
    fi
    echo "Docker image built successfully"
fi

# Find all serial devices and build device options
DEVICE_OPTS=""
DEVICE_COUNT=0

# Check for ttyUSB devices
for device in /dev/ttyUSB*; do
    if [ -c "$device" ] 2>/dev/null; then
        DEVICE_OPTS="$DEVICE_OPTS --device $device"
        echo "Found serial device: $device"
        ((DEVICE_COUNT++))
    fi
done

# Check for ttyACM devices
for device in /dev/ttyACM*; do
    if [ -c "$device" ] 2>/dev/null; then
        DEVICE_OPTS="$DEVICE_OPTS --device $device"
        echo "Found serial device: $device"
        ((DEVICE_COUNT++))
    fi
done

if [ $DEVICE_COUNT -eq 0 ]; then
    echo "Warning: No serial devices found (/dev/ttyUSB*, /dev/ttyACM*)"
    echo "         Device may not be connected or accessible"
else
    echo "Total serial devices found: $DEVICE_COUNT"
fi

echo "Starting container..."
docker run --rm --name "$CONTAINER_NAME" \
  --volume "$PWD/../:/workspace/ambd_sdk_GW018-DM" \
  $DEVICE_OPTS \
  -ti --entrypoint /bin/bash \
  "$IMAGE_NAME"

# After container exits, offer to clean build artifacts
echo ""
echo "Container session ended."
echo "Would you like to clean build artifacts? (y/n)"
read -r response
if [[ "$response" == "y" || "$response" == "Y" ]]; then
    echo "Cleaning build artifacts..."
    cleanup_build_artifacts
    echo "Cleanup complete."
else
    echo "Skipping cleanup. Run '$0 --clean' later to clean build artifacts."
fi
  