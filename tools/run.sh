#!/bin/bash

IMAGE_NAME="gw018-builder-flasher:latest"

# Check if Docker image exists
if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^$IMAGE_NAME$"; then
    echo "Docker image $IMAGE_NAME not found. Building it..."
    docker build -t gw018-builder-flasher .
    if [ $? -ne 0 ]; then
        echo "Failed to build Docker image"
        exit 1
    fi
    echo "Docker image built successfully"
fi

docker run --rm --name gw018-builder-flasher \
  --volume $PWD../:/workspace/ambd_sdk_GW018-DM \
  -ti --entrypoint /bin/bash \
  $IMAGE_NAME
