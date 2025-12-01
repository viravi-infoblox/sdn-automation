#!/usr/bin/env python3
"""
Example: Provision a network and allocate IPs

This example demonstrates how to:
1. Connect to Infoblox
2. Provision a new network
3. Allocate IP addresses for hosts
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sdn_automation import InfobloxClient, NetworkManager
from sdn_automation.utils import setup_logging, load_yaml_config


def main():
    # Setup logging
    setup_logging(level='INFO')
    
    # Load configuration
    config_path = os.path.join(os.path.dirname(__file__), '..', 'config', 'config.example.yml')
    
    try:
        config = load_yaml_config(config_path)
    except FileNotFoundError:
        print(f"Config file not found: {config_path}")
        print("Please create a config file based on config.example.yml")
        return 1
    
    # Initialize Infoblox client
    infoblox_config = config.get('infoblox', {})
    client = InfobloxClient(
        host=infoblox_config.get('host'),
        username=infoblox_config.get('username'),
        password=infoblox_config.get('password'),
        wapi_version=infoblox_config.get('wapi_version', 'v2.12'),
        verify_ssl=infoblox_config.get('verify_ssl', True)
    )
    
    # Initialize Network Manager
    network_mgr = NetworkManager(client)
    
    # Provision a network
    network_cidr = "192.168.100.0/24"
    print(f"\nProvisioning network: {network_cidr}")
    
    if network_mgr.provision_network(network_cidr, comment="Test Network"):
        print(f"✓ Network {network_cidr} provisioned successfully")
    else:
        print(f"✗ Failed to provision network {network_cidr}")
        return 1
    
    # Allocate IPs for multiple hosts
    domain = config.get('automation', {}).get('domain', 'example.com')
    hostnames = ['web01', 'web02', 'db01', 'cache01']
    
    print(f"\nAllocating IPs for hosts in domain {domain}:")
    results = network_mgr.bulk_provision_hosts(network_cidr, hostnames, domain)
    
    for hostname, ip in results.items():
        if ip:
            print(f"✓ {hostname}.{domain} -> {ip}")
        else:
            print(f"✗ {hostname}.{domain} -> Failed to allocate")
    
    print("\nExample completed successfully!")
    return 0


if __name__ == '__main__':
    sys.exit(main())
