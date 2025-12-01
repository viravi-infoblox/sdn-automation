"""
Unit tests for Network Manager
"""

import unittest
from unittest.mock import Mock, patch
from sdn_automation.network.manager import NetworkManager
from sdn_automation.infoblox.client import InfobloxClient


class TestNetworkManager(unittest.TestCase):
    """Test cases for NetworkManager class."""
    
    def setUp(self):
        """Set up test fixtures."""
        # Create a mock InfobloxClient
        self.mock_client = Mock(spec=InfobloxClient)
        self.manager = NetworkManager(self.mock_client)
    
    def test_initialization(self):
        """Test manager initialization."""
        self.assertIsNotNone(self.manager.infoblox)
    
    def test_provision_network_success(self):
        """Test successful network provisioning."""
        # Setup mocks
        self.mock_client.get_network.return_value = None
        self.mock_client.create_network.return_value = {'_ref': 'network/abc123'}
        
        # Test
        result = self.manager.provision_network('10.0.0.0/24', 'Test Network')
        
        # Assertions
        self.assertTrue(result)
        self.mock_client.get_network.assert_called_once_with('10.0.0.0/24')
        self.mock_client.create_network.assert_called_once_with('10.0.0.0/24', 'Test Network')
    
    def test_provision_network_already_exists(self):
        """Test provisioning when network already exists."""
        # Setup mocks
        self.mock_client.get_network.return_value = {'_ref': 'network/abc123', 'network': '10.0.0.0/24'}
        
        # Test
        result = self.manager.provision_network('10.0.0.0/24', 'Test Network')
        
        # Assertions
        self.assertFalse(result)
        self.mock_client.create_network.assert_not_called()
    
    def test_allocate_ip_success(self):
        """Test successful IP allocation."""
        # Setup mocks
        self.mock_client.get_next_available_ip.return_value = ['10.0.0.10']
        self.mock_client.create_host_record.return_value = {'_ref': 'record:host/abc123'}
        
        # Test
        result = self.manager.allocate_ip('10.0.0.0/24', 'testhost', 'example.com')
        
        # Assertions
        self.assertEqual(result, '10.0.0.10')
        self.mock_client.get_next_available_ip.assert_called_once_with('10.0.0.0/24', num=1)
        self.mock_client.create_host_record.assert_called_once_with('testhost.example.com', '10.0.0.10')
    
    def test_allocate_ip_no_available_ips(self):
        """Test IP allocation when no IPs available."""
        # Setup mocks
        self.mock_client.get_next_available_ip.return_value = None
        
        # Test
        result = self.manager.allocate_ip('10.0.0.0/24', 'testhost', 'example.com')
        
        # Assertions
        self.assertIsNone(result)
        self.mock_client.create_host_record.assert_not_called()
    
    def test_bulk_provision_hosts(self):
        """Test bulk host provisioning."""
        # Setup mocks
        self.mock_client.get_next_available_ip.side_effect = [
            ['10.0.0.10'],
            ['10.0.0.11'],
            ['10.0.0.12']
        ]
        self.mock_client.create_host_record.return_value = {'_ref': 'record:host/abc123'}
        
        # Test
        hostnames = ['web01', 'web02', 'db01']
        results = self.manager.bulk_provision_hosts('10.0.0.0/24', hostnames, 'example.com')
        
        # Assertions
        self.assertEqual(len(results), 3)
        self.assertEqual(results['web01'], '10.0.0.10')
        self.assertEqual(results['web02'], '10.0.0.11')
        self.assertEqual(results['db01'], '10.0.0.12')
    
    def test_get_network_info(self):
        """Test getting network information."""
        # Setup mocks
        expected_info = {'_ref': 'network/abc123', 'network': '10.0.0.0/24'}
        self.mock_client.get_network.return_value = expected_info
        
        # Test
        result = self.manager.get_network_info('10.0.0.0/24')
        
        # Assertions
        self.assertEqual(result, expected_info)
    
    def test_find_ip_owner(self):
        """Test finding IP owner."""
        # Setup mocks
        expected_records = [
            {'_ref': 'record:host/abc123', 'name': 'testhost.example.com', 'ipv4addr': '10.0.0.10'}
        ]
        self.mock_client.search_by_ip.return_value = expected_records
        
        # Test
        result = self.manager.find_ip_owner('10.0.0.10')
        
        # Assertions
        self.assertEqual(result, expected_records)


if __name__ == '__main__':
    unittest.main()
