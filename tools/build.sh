#!/bin/bash

# This script builds and flashes firmware for the GW018-DM device.
# It is intended to be run inside a Docker container with the necessary build environment.

echo "Building firmware..."

# Helper function to validate build success
validate_build() {
    local project_name="$1"
    local build_output_file="$2"
    local expected_binaries=("${@:3}")
    
    # Check if build output contains success message
    if ! grep -q "========== Image manipulating end ==========" "$build_output_file"; then
        echo "ERROR: $project_name build failed - missing success message"
        echo "Build output saved to: $build_output_file"
        return 1
    fi
    
    # Check if all expected binary files exist
    for binary in "${expected_binaries[@]}"; do
        if [[ ! -f "$binary" ]]; then
            echo "ERROR: $project_name build failed - missing binary file: $binary"
            return 1
        fi
    done
    
    echo "$project_name build completed successfully!"
    return 0
}

echo "Please enter the MAC address of the device (format: AA:BB:CC:DD:EE:FF):"
read -r device_mac

if [[ ! "$device_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    echo "Error: Invalid MAC address format. Please use AA:BB:CC:DD:EE:FF format."
    exit 1
fi

echo "Using device MAC address: $device_mac"

echo "Fixing permissions for project_lp and project_hp directories..."
chmod -R 777 /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp
chmod -R 777 /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp

echo "Building LP (Low Power) project..."
cd /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp
make clean

# Capture build output and check for success
echo "Starting LP build with MAC: $device_mac"
build_output_lp=$(mktemp)
if ! DEVICE_MAC="$device_mac" make all 2>&1 | tee "$build_output_lp"; then
    echo "ERROR: LP build failed with non-zero exit code"
    echo "Build output saved to: $build_output_lp"
    exit 1
fi

# Validate LP build success
if ! validate_build "LP" "$build_output_lp" "asdk/image/km0_boot_all.bin"; then
    exit 1
fi

echo "Copying LP (Low Power) binaries to flash directory..."
cp asdk/image/km0_boot_all.bin /workspace/flash/

echo "Building HP (High Performance) project..."
cd /workspace/ambd_sdk_GW018-DM/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/

make clean

# Capture build output and check for success
echo "Starting HP build with MAC: $device_mac"
build_output_hp=$(mktemp)
if ! DEVICE_MAC="$device_mac" make all 2>&1 | tee "$build_output_hp"; then
    echo "ERROR: HP build failed with non-zero exit code"
    echo "Build output saved to: $build_output_hp"
    exit 1
fi

# Validate HP build success
if ! validate_build "HP" "$build_output_hp" "asdk/image/km4_boot_all.bin" "asdk/image/km0_km4_image2.bin"; then
    exit 1
fi

echo "Copying HP (High Performance) binaries to flash directory..."
cp asdk/image/km4_boot_all.bin /workspace/flash/
cp asdk/image/km0_km4_image2.bin /workspace/flash/

echo "Build process completed successfully!"
echo "All firmware binaries have been generated and validated."

# Clean up temporary build output files
rm -f "$build_output_lp" "$build_output_hp" 2>/dev/null || true

echo "Do you want to flash the firmware to GW018-DM now? (y/n)"
read -r response
if [[ "$response" != "y" ]]; then
    echo "Exiting without flashing."
    exit 0
fi

echo "Flashing firmware to GW018-DM..."

cd /workspace/flash

# Erase flash before flashing new firmware (may not be needed)
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Enable 921600

# … and let's flash!
./upload_image_tool_linux "$PWD" /dev/ttyUSB0 ameba_rtl8721csm Enable Disable 921600