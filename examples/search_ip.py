#!/usr/bin/env python3
"""
Example: Search for IP address information

This example demonstrates how to:
1. Connect to Infoblox
2. Search for IP address ownership
3. Display DNS and network information
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sdn_automation import InfobloxClient, NetworkManager
from sdn_automation.utils import setup_logging, get_env_config


def main():
    # Setup logging
    setup_logging(level='INFO')
    
    # Get configuration from environment
    env_config = get_env_config()
    
    if not env_config.get('infoblox_host'):
        print("Error: INFOBLOX_HOST environment variable not set")
        print("Please set environment variables or create a .env file")
        return 1
    
    # Initialize Infoblox client
    client = InfobloxClient(
        host=env_config['infoblox_host'],
        username=env_config['infoblox_username'],
        password=env_config['infoblox_password'],
        wapi_version=env_config['infoblox_wapi_version'],
        verify_ssl=env_config['verify_ssl']
    )
    
    # Initialize Network Manager
    network_mgr = NetworkManager(client)
    
    # Search for an IP address
    ip_address = "192.168.100.10"
    print(f"\nSearching for IP: {ip_address}")
    
    results = network_mgr.find_ip_owner(ip_address)
    
    if results:
        print(f"\nFound {len(results)} record(s):")
        for record in results:
            print(f"  Type: {record.get('_ref', '').split(':')[0]}")
            print(f"  Name: {record.get('name', 'N/A')}")
            print(f"  IP: {record.get('ipv4addr', record.get('address', 'N/A'))}")
            print()
    else:
        print(f"No records found for IP: {ip_address}")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
