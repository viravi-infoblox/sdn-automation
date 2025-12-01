#!/usr/bin/env python3
"""
Plugin Mapper for SDN Agent POC
Maps classified endpoints to appropriate NetMRI SDN plugins
"""

import json
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from enum import Enum


class PluginType(Enum):
    """NetMRI plugin types"""
    SAVE_DEVICES = "SaveDevices"
    SAVE_SYSTEM_INFO = "SaveSystemInfo"
    SAVE_SDN_FABRIC_INTERFACE = "SaveSdnFabricInterface"
    SAVE_SDN_INTERFACE = "SaveSdnInterface"
    SAVE_SDN_LLDP = "SaveSdnLldp"
    SAVE_SDN_CDP = "SaveSdnCdp"
    SAVE_SDN_SWITCH_PORT = "SaveSdnSwitchPort"
    SAVE_SDN_SWITCH_PORT_CONFIG = "SaveSdnSwitchPortConfig"
    SAVE_SDN_ROUTE = "SaveSdnRoute"
    SAVE_SDN_WIRELESS_SSID = "SaveSdnWirelessSsid"
    SAVE_SDN_WIRELESS_AP = "SaveSdnWirelessAp"
    SAVE_SDN_VLAN = "SaveSdnVlan"
    SAVE_SDN_ENDPOINT = "SaveSdnEndpoint"
    SAVE_SDN_NETWORK = "SaveSdnNetwork"
    UNKNOWN = "Unknown"


@dataclass
class FieldMapping:
    """Mapping from API field to NetMRI field"""
    api_field: str
    netmri_field: str
    required: bool
    transform: Optional[str] = None  # Transformation function name


@dataclass
class PluginMapping:
    """Complete plugin mapping for an endpoint"""
    operation_id: str
    path: str
    method: str
    plugin: PluginType
    plugin_method: str  # e.g., "saveDevices", "saveSystemInfo"
    confidence: float
    field_mappings: List[FieldMapping]
    coverage: float  # Percentage of required fields covered
    notes: List[str] = field(default_factory=list)


class PluginMapper:
    """Map endpoints to NetMRI plugins"""
    
    def __init__(self, classified_file: str):
        self.classified_file = Path(classified_file)
        self.classified_data = None
        self.plugin_mappings = []
        self.plugin_definitions = self._initialize_plugin_definitions()
        
    def _initialize_plugin_definitions(self) -> Dict:
        """Initialize NetMRI plugin field requirements"""
        return {
            'device_discovery': {
                'plugin': PluginType.SAVE_DEVICES,
                'method': 'saveDevices',
                'required_fields': {
                    'SdnDeviceDN': ['serial', 'networkId', 'orgId'],  # Composite
                    'Serial': ['serial'],
                    'Model': ['model'],
                    'Vendor': [],  # Constant: "Cisco Meraki"
                    'Name': ['name'],
                    'IPAddress': ['lanIp', 'wan1Ip', 'wan2Ip', 'publicIp'],
                },
                'optional_fields': {
                    'NodeRole': ['model'],  # Derived from model prefix
                    'SWVersion': ['firmware'],
                    'modTS': ['claimedAt'],
                    'MACAddress': ['mac'],
                }
            },
            'system_info': {
                'plugin': PluginType.SAVE_SYSTEM_INFO,
                'method': 'saveSystemInfo',
                'required_fields': {
                    'SdnDeviceDN': ['serial'],
                    'Status': ['status'],
                },
                'optional_fields': {
                    'Uptime': ['uptime'],
                    'LastReportedAt': ['lastReportedAt'],
                    'PublicIP': ['publicIp'],
                    'LanIP': ['lanIp'],
                }
            },
            'interfaces': {
                'plugin': PluginType.SAVE_SDN_FABRIC_INTERFACE,
                'method': 'saveSdnFabricInterface',
                'required_fields': {
                    'ifIndex': ['portId'],
                    'ifName': ['name', 'portId'],
                    'ifOperStatus': ['status'],
                },
                'optional_fields': {
                    'ifAdminStatus': ['enabled'],
                    'ifSpeed': ['speed'],
                    'ifDuplex': ['duplex'],
                    'ifType': ['type'],
                    'ifMAC': ['mac'],
                    'VlanIndex': ['vlan'],
                }
            },
            'topology_lldp_cdp': {
                'plugin': PluginType.SAVE_SDN_LLDP,
                'method': 'saveSdnLldp',
                'required_fields': {
                    'ifIndex': ['portId'],
                    'NeighborDeviceID': ['deviceId', 'systemName'],
                    'NeighborPortID': ['portId'],
                },
                'optional_fields': {
                    'NeighborIPAddress': ['address', 'managementAddress'],
                    'NeighborCapabilities': ['capabilities'],
                }
            },
            'switch_ports': {
                'plugin': PluginType.SAVE_SDN_SWITCH_PORT_CONFIG,
                'method': 'saveSdnSwitchPortConfig',
                'required_fields': {
                    'ifIndex': ['portId'],
                    'VlanIndex': ['vlan'],
                },
                'optional_fields': {
                    'PortMode': ['type'],
                    'AllowedVlans': ['allowedVlans'],
                    'POEEnabled': ['poeEnabled'],
                    'ifAdminStatus': ['enabled'],
                }
            },
            'routing': {
                'plugin': PluginType.SAVE_SDN_ROUTE,
                'method': 'saveSdnRoute',
                'required_fields': {
                    'RouteCIDR': ['subnet'],
                    'RouteNextHop': ['gatewayIp'],
                },
                'optional_fields': {
                    'RouteName': ['name'],
                    'RouteEnabled': ['enabled'],
                }
            },
            'wireless': {
                'plugin': PluginType.SAVE_SDN_WIRELESS_SSID,
                'method': 'saveSdnWirelessSsid',
                'required_fields': {
                    'SSID': ['name'],
                    'SSIDEnabled': ['enabled'],
                },
                'optional_fields': {
                    'SSIDNumber': ['number'],
                    'AuthMode': ['authMode'],
                    'EncryptionMode': ['encryptionMode'],
                    'SplashPage': ['splashPage'],
                }
            },
            'vlans': {
                'plugin': PluginType.SAVE_SDN_VLAN,
                'method': 'saveSdnVlan',
                'required_fields': {
                    'VlanID': ['id'],
                    'VlanName': ['name'],
                },
                'optional_fields': {
                    'VlanSubnet': ['subnet'],
                    'VlanGateway': ['applianceIp'],
                }
            },
            'endpoints': {
                'plugin': PluginType.SAVE_SDN_ENDPOINT,
                'method': 'saveSdnEndpoint',
                'required_fields': {
                    'EndpointMAC': ['mac'],
                },
                'optional_fields': {
                    'EndpointIP': ['ip'],
                    'EndpointManufacturer': ['manufacturer'],
                    'EndpointOS': ['os'],
                    'EndpointType': ['deviceTypePrediction'],
                }
            }
        }
    
    def load_classified_data(self):
        """Load classified endpoints"""
        with open(self.classified_file, 'r') as f:
            self.classified_data = json.load(f)
        return self.classified_data
    
    def map_endpoint(self, endpoint: Dict) -> PluginMapping:
        """Map a single endpoint to a plugin"""
        category = endpoint['category']
        all_fields = set(f.lower() for f in endpoint['all_fields'])
        
        # Get plugin definition for this category
        plugin_def = self.plugin_definitions.get(category)
        
        if not plugin_def:
            return PluginMapping(
                operation_id=endpoint['operation_id'],
                path=endpoint['path'],
                method=endpoint['method'],
                plugin=PluginType.UNKNOWN,
                plugin_method='unknown',
                confidence=0.0,
                field_mappings=[],
                coverage=0.0,
                notes=[f"No plugin defined for category: {category}"]
            )
        
        # Calculate field coverage
        field_mappings = []
        required_coverage = 0
        total_required = len(plugin_def['required_fields'])
        
        # Map required fields
        for netmri_field, api_field_options in plugin_def['required_fields'].items():
            mapped = False
            for api_field in api_field_options:
                if api_field.lower() in all_fields:
                    field_mappings.append(FieldMapping(
                        api_field=api_field,
                        netmri_field=netmri_field,
                        required=True
                    ))
                    required_coverage += 1
                    mapped = True
                    break
            
            if not mapped and api_field_options:
                # Field not found in API response
                field_mappings.append(FieldMapping(
                    api_field=f"MISSING: {api_field_options[0]}",
                    netmri_field=netmri_field,
                    required=True
                ))
        
        # Map optional fields
        for netmri_field, api_field_options in plugin_def['optional_fields'].items():
            for api_field in api_field_options:
                if api_field.lower() in all_fields:
                    field_mappings.append(FieldMapping(
                        api_field=api_field,
                        netmri_field=netmri_field,
                        required=False
                    ))
                    break
        
        # Calculate coverage percentage
        coverage = (required_coverage / total_required * 100) if total_required > 0 else 100
        
        # Determine confidence based on coverage and pattern confidence
        pattern_confidence = endpoint['confidence']
        coverage_factor = coverage / 100
        confidence = (pattern_confidence * 0.6 + coverage_factor * 0.4)
        
        # Generate notes
        notes = []
        if coverage < 80:
            notes.append(f"⚠ Low field coverage: {coverage:.0f}% (recommended: ≥80%)")
        if coverage < 100:
            missing = [fm.api_field for fm in field_mappings if fm.required and fm.api_field.startswith('MISSING')]
            if missing:
                notes.append(f"Missing required fields: {', '.join(missing)}")
        
        return PluginMapping(
            operation_id=endpoint['operation_id'],
            path=endpoint['path'],
            method=endpoint['method'],
            plugin=plugin_def['plugin'],
            plugin_method=plugin_def['method'],
            confidence=confidence,
            field_mappings=field_mappings,
            coverage=coverage,
            notes=notes
        )
    
    def map_all(self) -> List[PluginMapping]:
        """Map all endpoints"""
        if not self.classified_data:
            self.load_classified_data()
        
        self.plugin_mappings = []
        
        for endpoint in self.classified_data['endpoints']:
            mapping = self.map_endpoint(endpoint)
            self.plugin_mappings.append(mapping)
        
        return self.plugin_mappings
    
    def save_results(self, output_file: str):
        """Save plugin mappings to JSON"""
        if not self.plugin_mappings:
            raise ValueError("No plugin mappings. Call map_all() first.")
        
        output = {
            'total_endpoints': len(self.plugin_mappings),
            'mappings': [
                {
                    'operation_id': pm.operation_id,
                    'path': pm.path,
                    'method': pm.method,
                    'plugin': pm.plugin.value,
                    'plugin_method': pm.plugin_method,
                    'confidence': round(pm.confidence, 3),
                    'coverage': round(pm.coverage, 1),
                    'field_mappings': [
                        {
                            'api_field': fm.api_field,
                            'netmri_field': fm.netmri_field,
                            'required': fm.required,
                            'transform': fm.transform
                        }
                        for fm in pm.field_mappings
                    ],
                    'notes': pm.notes
                }
                for pm in self.plugin_mappings
            ]
        }
        
        with open(output_file, 'w') as f:
            json.dump(output, f, indent=2)
        
        print(f"✓ Saved plugin mappings to {output_file}")
    
    def print_summary(self):
        """Print mapping summary"""
        if not self.plugin_mappings:
            raise ValueError("No plugin mappings. Call map_all() first.")
        
        print("\n" + "="*70)
        print("Plugin Mapping Results")
        print("="*70)
        
        # Count by plugin
        plugin_counts = {}
        for pm in self.plugin_mappings:
            plugin = pm.plugin.value
            plugin_counts[plugin] = plugin_counts.get(plugin, 0) + 1
        
        print("\nEndpoints by Plugin:")
        print("-"*70)
        for plugin, count in sorted(plugin_counts.items()):
            print(f"{plugin:35} : {count:2} endpoint(s)")
        
        print("\n" + "-"*70)
        print("Detailed Mappings:")
        print("-"*70)
        
        for pm in self.plugin_mappings:
            confidence_marker = "✓" if pm.confidence >= 0.8 else "⚠" if pm.confidence >= 0.5 else "✗"
            coverage_marker = "✓" if pm.coverage >= 80 else "⚠" if pm.coverage >= 50 else "✗"
            
            print(f"\n{confidence_marker} {pm.operation_id}")
            print(f"   Path: {pm.method} {pm.path}")
            print(f"   Plugin: {pm.plugin.value} → ${pm.plugin_method}()")
            print(f"   Confidence: {pm.confidence:.2%} | Coverage: {coverage_marker} {pm.coverage:.0f}%")
            
            # Show field mappings
            required_mappings = [fm for fm in pm.field_mappings if fm.required]
            optional_mappings = [fm for fm in pm.field_mappings if not fm.required]
            
            if required_mappings:
                print(f"   Required Fields ({len(required_mappings)}):")
                for fm in required_mappings[:5]:
                    status = "✗" if fm.api_field.startswith("MISSING") else "✓"
                    print(f"      {status} {fm.api_field:20} → {fm.netmri_field}")
            
            if optional_mappings:
                print(f"   Optional Fields ({len(optional_mappings)}):")
                for fm in optional_mappings[:3]:
                    print(f"      ✓ {fm.api_field:20} → {fm.netmri_field}")
            
            if pm.notes:
                print(f"   Notes:")
                for note in pm.notes:
                    print(f"      {note}")


def main():
    """Main execution"""
    script_dir = Path(__file__).parent
    input_file = script_dir / "classified_endpoints.json"
    output_file = script_dir / "plugin_mappings.json"
    
    print("\n🔌 SDN Agent POC - Plugin Mapper")
    print("="*70)
    print(f"Input: {input_file}")
    print(f"Output: {output_file}")
    
    mapper = PluginMapper(str(input_file))
    
    try:
        # Map all endpoints
        mapper.map_all()
        
        # Print summary
        mapper.print_summary()
        
        # Save results
        mapper.save_results(str(output_file))
        
        print("\n✅ Plugin mapping completed successfully!\n")
        
    except Exception as e:
        print(f"\n❌ Error: {e}\n")
        raise


if __name__ == "__main__":
    main()
