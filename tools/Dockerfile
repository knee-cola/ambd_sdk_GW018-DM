# Dockerfile for GW018-DM Gateway Flashing Tools
# Based on requirements from https://github.com/jasperw1996/ambd_sdk_GW018-DM

FROM fedora:latest

# Install system dependencies required for building and flashing
RUN dnf update -y && \
    dnf install -y \
        git \
        make \
        gcc \
        gcc-c++ \
        glibc-devel.i686 \
        ncurses-compat-libs.i686 \
        python3 \
        python3-pip \
        minicom \
        wget \
        curl \
        unzip \
        nano \
        vim \
        which \
        file \
        usbutils \
        && \
    dnf clean all

# Create working directory and flash tools directory
WORKDIR /workspace
RUN mkdir -p /workspace/flash

# Download the official flashing tool for GW018-DM
RUN wget -O /workspace/flash/upload_image_tool_linux https://github.com/ambiot/ambd_arduino/raw/dev/Arduino_package/ameba_d_tools_linux/upload_image_tool_linux && \
    wget -O /workspace/flash/imgtool_flashloader_amebad.bin https://github.com/Ameba-AIoT/ameba-arduino-d/raw/refs/heads/dev/Arduino_package/ameba_d_tools_linux/tools/linux/image_tool/imgtool_flashloader_amebad.bin && \
    chmod +x /workspace/flash/upload_image_tool_linux

# Set the working directory to /workspace for mounted volume
WORKDIR /workspace

# Labels for documentation
LABEL maintainer="Docker image for GW018-DM gateway firmware flashing"
LABEL description="Contains all tools needed to build and flash custom firmware for GW018-DM Zigbee gateway"
LABEL version="1.0"
LABEL source="https://github.com/jasperw1996/ambd_sdk_GW018-DM"