"""
Configuration Loader Utility

This module provides utilities for loading configuration from files.
"""

import yaml
import os
from typing import Dict, Any
import logging


logger = logging.getLogger(__name__)


def load_yaml_config(config_path: str) -> Dict[str, Any]:
    """
    Load configuration from a YAML file.
    
    Args:
        config_path: Path to the YAML configuration file
        
    Returns:
        Configuration dictionary
        
    Raises:
        FileNotFoundError: If config file doesn't exist
        yaml.YAMLError: If config file is invalid YAML
    """
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")
    
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        logger.info(f"Loaded configuration from {config_path}")
        return config or {}
    except yaml.YAMLError as e:
        logger.error(f"Error parsing YAML configuration: {e}")
        raise


def get_env_config() -> Dict[str, str]:
    """
    Get configuration from environment variables.
    
    Returns:
        Dictionary of environment configuration
    """
    config = {
        'infoblox_host': os.getenv('INFOBLOX_HOST', ''),
        'infoblox_username': os.getenv('INFOBLOX_USERNAME', ''),
        'infoblox_password': os.getenv('INFOBLOX_PASSWORD', ''),
        'infoblox_wapi_version': os.getenv('INFOBLOX_WAPI_VERSION', 'v2.12'),
        'verify_ssl': os.getenv('VERIFY_SSL', 'true').lower() == 'true'
    }
    
    return config


def merge_configs(*configs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Merge multiple configuration dictionaries.
    Later configs override earlier ones.
    
    Args:
        *configs: Configuration dictionaries to merge
        
    Returns:
        Merged configuration dictionary
    """
    merged = {}
    for config in configs:
        merged.update(config)
    
    return merged
