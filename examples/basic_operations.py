#!/usr/bin/env python3
"""
Example: Basic Infoblox operations

This example demonstrates basic CRUD operations:
1. Create a network
2. Get network information
3. Allocate IPs
4. Delete a network
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sdn_automation import InfobloxClient
from sdn_automation.utils import setup_logging


def main():
    # Setup logging
    setup_logging(level='DEBUG')
    
    # Initialize client with hardcoded values for demo
    # In production, use config files or environment variables
    client = InfobloxClient(
        host="infoblox.example.com",
        username="admin",
        password="changeme",
        wapi_version="v2.12",
        verify_ssl=False  # Set to True in production
    )
    
    network_cidr = "172.16.0.0/24"
    
    # Create network
    print(f"\n1. Creating network: {network_cidr}")
    result = client.create_network(network_cidr, comment="Demo Network")
    if result:
        print(f"✓ Network created: {result}")
    else:
        print("✗ Failed to create network")
        return 1
    
    # Get network info
    print(f"\n2. Getting network info: {network_cidr}")
    network_info = client.get_network(network_cidr)
    if network_info:
        print(f"✓ Network info: {network_info}")
    else:
        print("✗ Failed to get network info")
    
    # Get next available IPs
    print(f"\n3. Getting next available IPs from: {network_cidr}")
    ips = client.get_next_available_ip(network_cidr, num=5)
    if ips:
        print(f"✓ Available IPs: {', '.join(ips)}")
    else:
        print("✗ Failed to get available IPs")
    
    # Create host record
    if ips:
        print(f"\n4. Creating host record")
        fqdn = "testhost.example.com"
        ip = ips[0]
        result = client.create_host_record(fqdn, ip)
        if result:
            print(f"✓ Host record created: {fqdn} -> {ip}")
        else:
            print("✗ Failed to create host record")
    
    # Note: Deleting the network is commented out for safety
    # Uncomment to test deletion
    # print(f"\n5. Deleting network: {network_cidr}")
    # if network_info:
    #     if client.delete_network(network_info['_ref']):
    #         print(f"✓ Network deleted")
    #     else:
    #         print("✗ Failed to delete network")
    
    print("\nExample completed!")
    return 0


if __name__ == '__main__':
    sys.exit(main())
