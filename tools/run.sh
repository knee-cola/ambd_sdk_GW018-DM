#!/bin/bash
set -e

IMAGE_NAME="gw018-builder-flasher:latest"
CONTAINER_NAME="gw018-builder-flasher"

# Show help message
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Run GW018-DM firmware development container with auto-detected serial devices"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "This script will:"
    echo "  - Build Docker image if it doesn't exist"
    echo "  - Auto-detect serial devices (/dev/ttyUSB*, /dev/ttyACM*)"
    echo "  - Mount project directory and pass devices to container"
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
