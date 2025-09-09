#!/usr/bin/env python3
"""
Build helper for AmebaD GW018-DM Captive Portal
Generates ap_secrets.h with per-device random passwords and creates printable labels.
"""

import os
import sys
import random
import string
import datetime
import csv
import argparse
from pathlib import Path

def generate_random_password(length=12):
    """Generate WPA2-PSK compliant random password (8-63 ASCII chars)"""
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def get_mac_from_env():
    """Get MAC address from DEVICE_MAC environment variable"""
    mac = os.environ.get('DEVICE_MAC', '')
    if mac and len(mac.replace(':', '').replace('-', '')) == 12:
        # Normalize to AA:BB:CC:DD:EE:FF format
        clean_mac = mac.replace(':', '').replace('-', '').upper()
        return ':'.join([clean_mac[i:i+2] for i in range(0, 12, 2)])
    return None

def get_mac_suffix(mac_addr):
    """Extract last 2 bytes of MAC for SSID suffix"""
    if mac_addr:
        parts = mac_addr.split(':')
        if len(parts) == 6:
            return parts[-2] + parts[-1]
    return None

def create_ap_secrets_h(project_dir, mac_addr, password):
    """Create ap_secrets.h header file"""
    mac_suffix = get_mac_suffix(mac_addr) or "0000"
    
    content = f'''#pragma once
/*
 * Auto-generated per-device secrets for captive portal
 * DO NOT COMMIT THIS FILE TO VERSION CONTROL
 * Generated: {datetime.datetime.now().isoformat()}
 * Device MAC: {mac_addr or "Unknown"}
 */

#define AP_SSID_PREFIX "GW018-Setup-"
#define AP_SSID_SUFFIX "{mac_suffix}"
#define AP_PASSWORD    "{password}"
'''
    
    secrets_file = Path(project_dir) / "inc" / "inc_hp" / "provisioning" / "ap_secrets.h"
    secrets_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(secrets_file, 'w') as f:
        f.write(content)
    
    return secrets_file

def create_label_file(project_dir, mac_addr, password):
    """Create human-readable label file"""
    mac_suffix = get_mac_suffix(mac_addr) or "0000"
    ssid = f"GW018-Setup-{mac_suffix}"
    
    content = f'''GW018-DM Zigbee Gateway Setup
============================

SSID: {ssid}
PASSWORD: {password}

Setup Instructions:
1) Connect to the Wi-Fi network above
2) Setup page opens automatically (or visit http://192.168.4.1/)
3) Choose your home Wi-Fi and enter its password
4) Device will reboot and connect to your home network

Recovery:
- Long-press button for >5 seconds to reset Wi-Fi settings
- Or power cycle 3 times quickly to reset

Device MAC: {mac_addr or "Unknown"}
Generated: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
'''
    
    label_file = Path(project_dir) / "label.txt"
    with open(label_file, 'w') as f:
        f.write(content)
    
    return label_file

def update_provision_log(project_dir, mac_addr, password):
    """Update CSV log with provision data"""
    mac_suffix = get_mac_suffix(mac_addr) or "0000"
    ssid = f"GW018-Setup-{mac_suffix}"
    
    log_file = Path(project_dir) / "provision_log.csv"
    
    # Check if file exists and has headers
    file_exists = log_file.exists()
    
    with open(log_file, 'a', newline='') as csvfile:
        fieldnames = ['timestamp', 'mac_address', 'ssid', 'password']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        if not file_exists:
            writer.writeheader()
        
        writer.writerow({
            'timestamp': datetime.datetime.now().isoformat(),
            'mac_address': mac_addr or "Unknown",
            'ssid': ssid,
            'password': password
        })
    
    return log_file

def generate_wifi_qr(ssid, password):
    """Generate Wi-Fi QR code string (optional feature)"""
    # QR format: WIFI:S:<SSID>;T:WPA;P:<PASSWORD>;H:false;
    qr_string = f"WIFI:S:{ssid};T:WPA;P:{password};H:false;"
    return qr_string

def main():
    parser = argparse.ArgumentParser(description='Generate AP secrets for GW018-DM captive portal')
    parser.add_argument('--project-dir', 
                       default='project/realtek_amebaD_va0_example',
                       help='Project directory path')
    parser.add_argument('--force-regen', 
                       action='store_true',
                       help='Force regeneration even if ap_secrets.h exists')
    parser.add_argument('--mac', 
                       help='Device MAC address (overrides DEVICE_MAC env var)')
    parser.add_argument('--password-length', 
                       type=int, 
                       default=12,
                       help='Password length (8-63 chars)')
    
    args = parser.parse_args()
    
    if args.password_length < 8 or args.password_length > 63:
        print("ERROR: Password length must be between 8 and 63 characters")
        sys.exit(1)
    
    project_dir = Path(args.project_dir)
    if not project_dir.exists():
        print(f"ERROR: Project directory {project_dir} does not exist")
        sys.exit(1)
    
    secrets_file = project_dir / "inc" / "inc_hp" / "provisioning" / "ap_secrets.h"
    
    # Check if regeneration is needed
    if secrets_file.exists() and not args.force_regen and not os.environ.get('FORCE_REGEN') == '1':
        print(f"ap_secrets.h already exists at {secrets_file}")
        print("Use --force-regen or set FORCE_REGEN=1 to regenerate")
        return
    
    # Get MAC address
    mac_addr = args.mac or get_mac_from_env()
    if not mac_addr:
        print("Warning: No MAC address provided via --mac or DEVICE_MAC environment variable")
        print("Will use default suffix '0000' for SSID")
        mac_addr = None
    
    # Generate password
    password = generate_random_password(args.password_length)
    
    try:
        # Create files
        secrets_file = create_ap_secrets_h(project_dir, mac_addr, password)
        label_file = create_label_file(project_dir, mac_addr, password)
        log_file = update_provision_log(project_dir, mac_addr, password)
        
        # Generate QR string
        mac_suffix = get_mac_suffix(mac_addr) or "0000"
        ssid = f"GW018-Setup-{mac_suffix}"
        qr_string = generate_wifi_qr(ssid, password)
        
        qr_file = project_dir / "wifi_qr.txt"
        with open(qr_file, 'w') as f:
            f.write(f"Wi-Fi QR Code String:\n{qr_string}\n")
        
        print("✓ Generated AP secrets successfully:")
        print(f"  - Header: {secrets_file}")
        print(f"  - Label:  {label_file}")
        print(f"  - Log:    {log_file}")
        print(f"  - QR:     {qr_file}")
        print(f"  - SSID:   {ssid}")
        print("  - Password: [hidden - see label.txt]")
        
    except Exception as e:
        print(f"ERROR: Failed to generate secrets: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()