"""
SDN Automation Package

A Python package for automating Software-Defined Networking tasks
with Infoblox integration.
"""

__version__ = '0.1.0'
__author__ = 'SDN Automation Team'

from .infoblox.client import InfobloxClient
from .network.manager import NetworkManager

__all__ = ['InfobloxClient', 'NetworkManager']
