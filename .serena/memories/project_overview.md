# Project Overview - AmebaD SDK for GW018-DM Gateway

## Purpose
This project is an AmebaD SDK adjusted for the Tuya GW018-DM gateway. The main purpose is to cut the GW018-DM gateway from the cloud and use it as a Zigbee Adapter in Home Assistant (e.g., via Zigbee2MQTT). 

The firmware is based on https://github.com/parasite85/rtl_firmware but with adjustments for AmebaD (WBRG1 module, RTL8721CSM) instead of Ameba1 (WRG1 module, RTL8711AM).

## Hardware Target
- Device: Tuya GW018-DM Zigbee gateway
- Main chip: RTL8721CSM (AmebaD/WBRG1 module) 
- Zigbee chip: ZS3L module
- Connection: UART interface for flashing and communication

## Key Features
- WiFi connectivity with automatic connection
- TCP socket server on port 80 for Zigbee2MQTT communication
- OTA (Over-The-Air) firmware updates via HTTP
- Support for both WBRG1 module updates and ZS3L module updates
- Serial EZSP adapter functionality for Home Assistant/Zigbee2MQTT

## Project Status
**Work in Progress! Use at your own risk! Consider making a backup before flashing.**