"""
Infoblox Client Module

This module provides a client for interacting with Infoblox IPAM/DNS systems.
"""

import logging
from typing import Dict, List, Optional, Any
import requests
from requests.auth import HTTPBasicAuth


logger = logging.getLogger(__name__)


class InfobloxClient:
    """Client for Infoblox API interactions."""
    
    def __init__(self, host: str, username: str, password: str, 
                 wapi_version: str = 'v2.12', verify_ssl: bool = True):
        """
        Initialize Infoblox client.
        
        Args:
            host: Infoblox grid master hostname or IP
            username: API username
            password: API password
            wapi_version: WAPI version to use
            verify_ssl: Whether to verify SSL certificates
        """
        self.host = host
        self.username = username
        self.password = password
        self.wapi_version = wapi_version
        self.verify_ssl = verify_ssl
        self.base_url = f"https://{host}/wapi/{wapi_version}"
        self.session = requests.Session()
        self.session.auth = HTTPBasicAuth(username, password)
        self.session.verify = verify_ssl
        
        logger.info(f"Initialized Infoblox client for host: {host}")
    
    def get_network(self, network: str) -> Optional[Dict[str, Any]]:
        """
        Get network information.
        
        Args:
            network: Network CIDR (e.g., '10.0.0.0/24')
            
        Returns:
            Network object or None if not found
        """
        try:
            url = f"{self.base_url}/network"
            params = {'network': network}
            response = self.session.get(url, params=params)
            response.raise_for_status()
            
            data = response.json()
            return data[0] if data else None
        except requests.exceptions.RequestException as e:
            logger.error(f"Error fetching network {network}: {e}")
            return None
    
    def create_network(self, network: str, comment: str = '') -> Optional[Dict[str, Any]]:
        """
        Create a new network.
        
        Args:
            network: Network CIDR (e.g., '10.0.0.0/24')
            comment: Optional comment for the network
            
        Returns:
            Created network reference or None on failure
        """
        try:
            url = f"{self.base_url}/network"
            data = {
                'network': network,
                'comment': comment
            }
            response = self.session.post(url, json=data)
            response.raise_for_status()
            
            logger.info(f"Created network: {network}")
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Error creating network {network}: {e}")
            return None
    
    def delete_network(self, network_ref: str) -> bool:
        """
        Delete a network.
        
        Args:
            network_ref: Network reference string
            
        Returns:
            True if successful, False otherwise
        """
        try:
            url = f"{self.base_url}/{network_ref}"
            response = self.session.delete(url)
            response.raise_for_status()
            
            logger.info(f"Deleted network: {network_ref}")
            return True
        except requests.exceptions.RequestException as e:
            logger.error(f"Error deleting network {network_ref}: {e}")
            return False
    
    def get_next_available_ip(self, network: str, num: int = 1) -> Optional[List[str]]:
        """
        Get next available IP addresses from a network.
        
        Args:
            network: Network CIDR
            num: Number of IPs to retrieve
            
        Returns:
            List of available IP addresses or None on failure
        """
        try:
            # First get the network object
            network_obj = self.get_network(network)
            if not network_obj:
                logger.error(f"Network {network} not found")
                return None
            
            network_ref = network_obj['_ref']
            url = f"{self.base_url}/{network_ref}"
            params = {'_function': 'next_available_ip', 'num': num}
            response = self.session.post(url, params=params)
            response.raise_for_status()
            
            data = response.json()
            return data.get('ips', [])
        except requests.exceptions.RequestException as e:
            logger.error(f"Error getting next available IP for {network}: {e}")
            return None
    
    def create_host_record(self, fqdn: str, ipv4addr: str) -> Optional[Dict[str, Any]]:
        """
        Create a host record.
        
        Args:
            fqdn: Fully qualified domain name
            ipv4addr: IPv4 address
            
        Returns:
            Created host record reference or None on failure
        """
        try:
            url = f"{self.base_url}/record:host"
            data = {
                'name': fqdn,
                'ipv4addrs': [{'ipv4addr': ipv4addr}]
            }
            response = self.session.post(url, json=data)
            response.raise_for_status()
            
            logger.info(f"Created host record: {fqdn} -> {ipv4addr}")
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Error creating host record {fqdn}: {e}")
            return None
    
    def search_by_ip(self, ip: str) -> Optional[List[Dict[str, Any]]]:
        """
        Search for records by IP address.
        
        Args:
            ip: IP address to search for
            
        Returns:
            List of matching records or None on failure
        """
        try:
            url = f"{self.base_url}/search"
            params = {'address': ip}
            response = self.session.get(url, params=params)
            response.raise_for_status()
            
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Error searching for IP {ip}: {e}")
            return None
