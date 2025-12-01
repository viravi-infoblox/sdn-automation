"""
Unit tests for configuration utilities
"""

import unittest
import tempfile
import os
from sdn_automation.utils.config import load_yaml_config, get_env_config, merge_configs


class TestConfigUtils(unittest.TestCase):
    """Test cases for configuration utilities."""
    
    def test_load_yaml_config_success(self):
        """Test loading valid YAML configuration."""
        # Create temporary YAML file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as f:
            f.write("""
infoblox:
  host: test.example.com
  username: testuser
networks:
  - 10.0.0.0/24
            """)
            temp_path = f.name
        
        try:
            # Test
            config = load_yaml_config(temp_path)
            
            # Assertions
            self.assertIn('infoblox', config)
            self.assertEqual(config['infoblox']['host'], 'test.example.com')
            self.assertEqual(config['infoblox']['username'], 'testuser')
            self.assertIn('networks', config)
        finally:
            os.unlink(temp_path)
    
    def test_load_yaml_config_file_not_found(self):
        """Test loading non-existent configuration file."""
        with self.assertRaises(FileNotFoundError):
            load_yaml_config('/nonexistent/path/config.yml')
    
    def test_get_env_config(self):
        """Test getting configuration from environment variables."""
        # Set environment variables
        os.environ['INFOBLOX_HOST'] = 'test.example.com'
        os.environ['INFOBLOX_USERNAME'] = 'testuser'
        os.environ['INFOBLOX_PASSWORD'] = 'testpass'
        
        try:
            # Test
            config = get_env_config()
            
            # Assertions
            self.assertEqual(config['infoblox_host'], 'test.example.com')
            self.assertEqual(config['infoblox_username'], 'testuser')
            self.assertEqual(config['infoblox_password'], 'testpass')
        finally:
            # Clean up
            del os.environ['INFOBLOX_HOST']
            del os.environ['INFOBLOX_USERNAME']
            del os.environ['INFOBLOX_PASSWORD']
    
    def test_merge_configs(self):
        """Test merging multiple configurations."""
        config1 = {'a': 1, 'b': 2}
        config2 = {'b': 3, 'c': 4}
        config3 = {'c': 5, 'd': 6}
        
        # Test
        merged = merge_configs(config1, config2, config3)
        
        # Assertions
        self.assertEqual(merged['a'], 1)
        self.assertEqual(merged['b'], 3)  # Overridden by config2
        self.assertEqual(merged['c'], 5)  # Overridden by config3
        self.assertEqual(merged['d'], 6)


if __name__ == '__main__':
    unittest.main()
