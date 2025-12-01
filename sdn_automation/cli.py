#!/usr/bin/env python3
"""
Command-line interface for SDN Automation

This module provides a basic CLI interface for common operations.
"""

import argparse
import sys
from sdn_automation import InfobloxClient, NetworkManager
from sdn_automation.utils import setup_logging, get_env_config, load_yaml_config, merge_configs


def create_client_from_config(config_file=None):
    """Create an Infoblox client from configuration."""
    env_config = get_env_config()
    
    if config_file:
        file_config = load_yaml_config(config_file)
        infoblox_config = file_config.get('infoblox', {})
    else:
        infoblox_config = {}
    
    # Merge configs - env vars take precedence
    config = {
        'host': env_config.get('infoblox_host') or infoblox_config.get('host'),
        'username': env_config.get('infoblox_username') or infoblox_config.get('username'),
        'password': env_config.get('infoblox_password') or infoblox_config.get('password'),
        'wapi_version': env_config.get('infoblox_wapi_version') or infoblox_config.get('wapi_version', 'v2.12'),
        'verify_ssl': env_config.get('verify_ssl', True)
    }
    
    if not config['host']:
        raise ValueError("Infoblox host not configured. Set INFOBLOX_HOST or provide config file.")
    
    return InfobloxClient(**config)


def cmd_provision_network(args):
    """Provision a new network."""
    client = create_client_from_config(args.config)
    manager = NetworkManager(client)
    
    result = manager.provision_network(args.network, args.comment or '')
    if result:
        print(f"✓ Network {args.network} provisioned successfully")
        return 0
    else:
        print(f"✗ Failed to provision network {args.network}")
        return 1


def cmd_allocate_ip(args):
    """Allocate an IP address."""
    client = create_client_from_config(args.config)
    manager = NetworkManager(client)
    
    ip = manager.allocate_ip(args.network, args.hostname, args.domain)
    if ip:
        print(f"✓ Allocated IP {ip} for {args.hostname}.{args.domain}")
        return 0
    else:
        print(f"✗ Failed to allocate IP for {args.hostname}.{args.domain}")
        return 1


def cmd_search_ip(args):
    """Search for IP information."""
    client = create_client_from_config(args.config)
    manager = NetworkManager(client)
    
    results = manager.find_ip_owner(args.ip)
    if results:
        print(f"Found {len(results)} record(s) for {args.ip}:")
        for record in results:
            print(f"  - {record.get('_ref', 'Unknown')}")
        return 0
    else:
        print(f"No records found for {args.ip}")
        return 1


def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description='SDN Automation CLI',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--config', '-c',
        help='Path to configuration file',
        default=None
    )
    
    parser.add_argument(
        '--log-level',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
        default='INFO',
        help='Logging level'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to run')
    
    # Provision network command
    provision_parser = subparsers.add_parser('provision', help='Provision a network')
    provision_parser.add_argument('network', help='Network CIDR (e.g., 10.0.0.0/24)')
    provision_parser.add_argument('--comment', help='Optional comment for the network')
    provision_parser.set_defaults(func=cmd_provision_network)
    
    # Allocate IP command
    allocate_parser = subparsers.add_parser('allocate', help='Allocate an IP address')
    allocate_parser.add_argument('network', help='Network CIDR')
    allocate_parser.add_argument('hostname', help='Hostname')
    allocate_parser.add_argument('domain', help='Domain name')
    allocate_parser.set_defaults(func=cmd_allocate_ip)
    
    # Search IP command
    search_parser = subparsers.add_parser('search', help='Search for IP information')
    search_parser.add_argument('ip', help='IP address to search')
    search_parser.set_defaults(func=cmd_search_ip)
    
    args = parser.parse_args()
    
    # Setup logging
    setup_logging(level=args.log_level)
    
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        return args.func(args)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
