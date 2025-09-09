echo "Building firmware..."

echo "Please enter the MAC address of the device (format: AA:BB:CC:DD:EE:FF):"
read -r device_mac

if [[ ! "$device_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    echo "Error: Invalid MAC address format. Please use AA:BB:CC:DD:EE:FF format."
    exit 1
fi

echo "Using device MAC address: $device_mac"

echo "Building LP (Low Power) project..."
cd /workspace/project/realtek_amebaD_va0_example/GCC-RELEASE/project_lp
make clean
DEVICE_MAC="$device_mac" make all

echo "Copying LP (Low Power) binaries to flash directory..."
cp asdk/image/km0_boot_all.bin /workspace/flash/
cp asdk/image/km0_km4_image2.bin /workspace/flash/

echo "Building HP (High Performance) project..."
cd /workspace/project/realtek_amebaD_va0_example/GCC-RELEASE/project_hp/

make clean
DEVICE_MAC="$device_mac" make all

echo "Copying HP (High Performance) binaries to flash directory..."
cp asdk/image/km4_boot_all.bin /workspace/flash/

echo "Build process completed."
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