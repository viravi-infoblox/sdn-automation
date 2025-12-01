"""
Unit tests for Infoblox Client
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
from sdn_automation.infoblox.client import InfobloxClient


class TestInfobloxClient(unittest.TestCase):
    """Test cases for InfobloxClient class."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.client = InfobloxClient(
            host="test.example.com",
            username="testuser",
            password="testpass",
            wapi_version="v2.12",
            verify_ssl=False
        )
    
    def test_initialization(self):
        """Test client initialization."""
        self.assertEqual(self.client.host, "test.example.com")
        self.assertEqual(self.client.username, "testuser")
        self.assertEqual(self.client.wapi_version, "v2.12")
        self.assertEqual(self.client.base_url, "https://test.example.com/wapi/v2.12")
    
    @patch('sdn_automation.infoblox.client.requests.Session')
    def test_get_network_success(self, mock_session):
        """Test successful network retrieval."""
        # Setup mock
        mock_response = Mock()
        mock_response.json.return_value = [{'_ref': 'network/ZG5zLm5ldHdvcmskMTAuMC4wLjAvMjQvMA:10.0.0.0/24/default', 'network': '10.0.0.0/24'}]
        mock_response.raise_for_status = Mock()
        
        self.client.session.get = Mock(return_value=mock_response)
        
        # Test
        result = self.client.get_network('10.0.0.0/24')
        
        # Assertions
        self.assertIsNotNone(result)
        self.assertEqual(result['network'], '10.0.0.0/24')
    
    @patch('sdn_automation.infoblox.client.requests.Session')
    def test_get_network_not_found(self, mock_session):
        """Test network not found."""
        # Setup mock
        mock_response = Mock()
        mock_response.json.return_value = []
        mock_response.raise_for_status = Mock()
        
        self.client.session.get = Mock(return_value=mock_response)
        
        # Test
        result = self.client.get_network('10.0.0.0/24')
        
        # Assertions
        self.assertIsNone(result)
    
    @patch('sdn_automation.infoblox.client.requests.Session')
    def test_create_network_success(self, mock_session):
        """Test successful network creation."""
        # Setup mock
        mock_response = Mock()
        mock_response.json.return_value = 'network/ZG5zLm5ldHdvcmskMTAuMC4wLjAvMjQvMA:10.0.0.0/24/default'
        mock_response.raise_for_status = Mock()
        
        self.client.session.post = Mock(return_value=mock_response)
        
        # Test
        result = self.client.create_network('10.0.0.0/24', 'Test Network')
        
        # Assertions
        self.assertIsNotNone(result)
    
    @patch('sdn_automation.infoblox.client.requests.Session')
    def test_delete_network_success(self, mock_session):
        """Test successful network deletion."""
        # Setup mock
        mock_response = Mock()
        mock_response.raise_for_status = Mock()
        
        self.client.session.delete = Mock(return_value=mock_response)
        
        # Test
        result = self.client.delete_network('network/ZG5zLm5ldHdvcmskMTAuMC4wLjAvMjQvMA:10.0.0.0/24/default')
        
        # Assertions
        self.assertTrue(result)
    
    @patch('sdn_automation.infoblox.client.requests.Session')
    def test_create_host_record_success(self, mock_session):
        """Test successful host record creation."""
        # Setup mock
        mock_response = Mock()
        mock_response.json.return_value = 'record:host/ZG5zLmhvc3QkLl9kZWZhdWx0LmNvbS5leGFtcGxlLnRlc3Rob3N0:testhost.example.com/default'
        mock_response.raise_for_status = Mock()
        
        self.client.session.post = Mock(return_value=mock_response)
        
        # Test
        result = self.client.create_host_record('testhost.example.com', '10.0.0.10')
        
        # Assertions
        self.assertIsNotNone(result)


class TestInfobloxClientErrorHandling(unittest.TestCase):
    """Test error handling in InfobloxClient."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.client = InfobloxClient(
            host="test.example.com",
            username="testuser",
            password="testpass"
        )
    
    def test_get_network_request_exception(self):
        """Test network retrieval with request exception."""
        # Setup mock to raise exception
        import requests
        self.client.session.get = Mock(side_effect=requests.exceptions.RequestException("Connection error"))
        
        # Test
        result = self.client.get_network('10.0.0.0/24')
        
        # Assertions
        self.assertIsNone(result)


if __name__ == '__main__':
    unittest.main()
