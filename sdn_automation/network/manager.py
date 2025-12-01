"""
Network Manager Module

This module provides high-level network management functionality.
"""

import logging
from typing import Dict, List, Optional, Any
from ..infoblox.client import InfobloxClient


logger = logging.getLogger(__name__)


class NetworkManager:
    """Manager for network automation tasks."""
    
    def __init__(self, infoblox_client: InfobloxClient):
        """
        Initialize Network Manager.
        
        Args:
            infoblox_client: Initialized InfobloxClient instance
        """
        self.infoblox = infoblox_client
        logger.info("Initialized Network Manager")
    
    def provision_network(self, network: str, comment: str = '') -> bool:
        """
        Provision a new network.
        
        Args:
            network: Network CIDR (e.g., '10.0.0.0/24')
            comment: Optional comment for the network
            
        Returns:
            True if successful, False otherwise
        """
        logger.info(f"Provisioning network: {network}")
        
        # Check if network already exists
        existing = self.infoblox.get_network(network)
        if existing:
            logger.warning(f"Network {network} already exists")
            return False
        
        # Create the network
        result = self.infoblox.create_network(network, comment)
        if result:
            logger.info(f"Successfully provisioned network: {network}")
            return True
        else:
            logger.error(f"Failed to provision network: {network}")
            return False
    
    def allocate_ip(self, network: str, hostname: str, domain: str) -> Optional[str]:
        """
        Allocate an IP address from a network and create a host record.
        
        Args:
            network: Network CIDR to allocate from
            hostname: Hostname for the record
            domain: Domain name
            
        Returns:
            Allocated IP address or None on failure
        """
        logger.info(f"Allocating IP for {hostname}.{domain} from {network}")
        
        # Get next available IP
        ips = self.infoblox.get_next_available_ip(network, num=1)
        if not ips:
            logger.error(f"No available IPs in network {network}")
            return None
        
        ip = ips[0]
        fqdn = f"{hostname}.{domain}"
        
        # Create host record
        result = self.infoblox.create_host_record(fqdn, ip)
        if result:
            logger.info(f"Successfully allocated IP {ip} for {fqdn}")
            return ip
        else:
            logger.error(f"Failed to create host record for {fqdn}")
            return None
    
    def get_network_info(self, network: str) -> Optional[Dict[str, Any]]:
        """
        Get information about a network.
        
        Args:
            network: Network CIDR
            
        Returns:
            Network information dictionary or None if not found
        """
        return self.infoblox.get_network(network)
    
    def find_ip_owner(self, ip: str) -> Optional[List[Dict[str, Any]]]:
        """
        Find records associated with an IP address.
        
        Args:
            ip: IP address to search for
            
        Returns:
            List of records associated with the IP or None on failure
        """
        logger.info(f"Finding owner of IP: {ip}")
        return self.infoblox.search_by_ip(ip)
    
    def bulk_provision_hosts(self, network: str, hostnames: List[str], 
                            domain: str) -> Dict[str, Optional[str]]:
        """
        Provision multiple hosts in a network.
        
        Args:
            network: Network CIDR to allocate from
            hostnames: List of hostnames to provision
            domain: Domain name
            
        Returns:
            Dictionary mapping hostname to allocated IP (or None on failure)
        """
        logger.info(f"Bulk provisioning {len(hostnames)} hosts in {network}")
        
        results = {}
        for hostname in hostnames:
            ip = self.allocate_ip(network, hostname, domain)
            results[hostname] = ip
        
        success_count = sum(1 for ip in results.values() if ip is not None)
        logger.info(f"Successfully provisioned {success_count}/{len(hostnames)} hosts")
        
        return results
