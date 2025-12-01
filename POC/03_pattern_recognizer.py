#!/usr/bin/env python3
"""
Pattern Recognizer for SDN Agent POC
Classifies API endpoints by data category and NetMRI plugin patterns
"""

import json
from pathlib import Path
from typing import Dict, List, Set
from dataclasses import dataclass, field
from enum import Enum


class DataCategory(Enum):
    """NetMRI data collection categories"""
    DEVICE_DISCOVERY = "device_discovery"
    SYSTEM_INFO = "system_info"
    INTERFACES = "interfaces"
    TOPOLOGY_LLDP_CDP = "topology_lldp_cdp"
    SWITCH_PORTS = "switch_ports"
    ROUTING = "routing"
    WIRELESS = "wireless"
    VLANS = "vlans"
    ENDPOINTS = "endpoints"
    UNKNOWN = "unknown"


@dataclass
class FieldPattern:
    """Pattern for field matching"""
    category: DataCategory
    required_fields: Set[str]
    optional_fields: Set[str]
    url_patterns: List[str]
    keywords: Set[str]
    weight: float = 1.0


@dataclass
class ClassifiedEndpoint:
    """Endpoint with classification metadata"""
    operation_id: str
    path: str
    method: str
    category: DataCategory
    confidence: float
    matched_fields: Set[str]
    missing_fields: Set[str]
    schema_name: str
    is_array: bool
    all_fields: Set[str]
    tags: List[str]


class PatternRecognizer:
    """Recognize NetMRI data patterns in OpenAPI endpoints"""
    
    def __init__(self, parsed_api_file: str):
        self.parsed_api_file = Path(parsed_api_file)
        self.api_data = None
        self.patterns = self._initialize_patterns()
        self.classified_endpoints = []
        
    def _initialize_patterns(self) -> Dict[DataCategory, FieldPattern]:
        """Initialize field patterns for each data category"""
        return {
            DataCategory.DEVICE_DISCOVERY: FieldPattern(
                category=DataCategory.DEVICE_DISCOVERY,
                required_fields={'serial', 'model'},
                optional_fields={'name', 'mac', 'networkId', 'lanIp', 'wan1Ip', 'publicIp', 'firmware'},
                url_patterns=['/devices', '/inventory', '/equipment'],
                keywords={'device', 'devices', 'inventory', 'equipment'},
                weight=1.0
            ),
            
            DataCategory.SYSTEM_INFO: FieldPattern(
                category=DataCategory.SYSTEM_INFO,
                required_fields={'serial', 'firmware'},
                optional_fields={'model', 'name', 'status', 'lanIp', 'uptime', 'lastReportedAt'},
                url_patterns=['/status', '/devices', '/system'],
                keywords={'status', 'device', 'system', 'info'},
                weight=0.9
            ),
            
            DataCategory.INTERFACES: FieldPattern(
                category=DataCategory.INTERFACES,
                required_fields={'portId', 'status'},
                optional_fields={'name', 'enabled', 'speed', 'duplex', 'vlan', 'mac', 'type'},
                url_patterns=['/ports', '/interfaces', '/switch/ports'],
                keywords={'port', 'ports', 'interface', 'interfaces'},
                weight=1.0
            ),
            
            DataCategory.TOPOLOGY_LLDP_CDP: FieldPattern(
                category=DataCategory.TOPOLOGY_LLDP_CDP,
                required_fields={'deviceId', 'portId'},
                optional_fields={'systemName', 'address', 'managementAddress', 'sourceMac', 'ports'},
                url_patterns=['/lldp', '/cdp', '/neighbors', '/topology'],
                keywords={'lldp', 'cdp', 'neighbor', 'topology', 'discovery'},
                weight=1.0
            ),
            
            DataCategory.SWITCH_PORTS: FieldPattern(
                category=DataCategory.SWITCH_PORTS,
                required_fields={'portId'},
                optional_fields={'vlan', 'allowedVlans', 'type', 'enabled', 'poeEnabled', 'status'},
                url_patterns=['/switch/ports', '/switchports'],
                keywords={'switch', 'port', 'switchport', 'vlan'},
                weight=1.0
            ),
            
            DataCategory.ROUTING: FieldPattern(
                category=DataCategory.ROUTING,
                required_fields={'subnet', 'gatewayIp'},
                optional_fields={'name', 'enabled', 'fixedIpAssignments'},
                url_patterns=['/routes', '/routing', '/staticRoutes'],
                keywords={'route', 'routes', 'routing', 'gateway', 'static'},
                weight=1.0
            ),
            
            DataCategory.WIRELESS: FieldPattern(
                category=DataCategory.WIRELESS,
                required_fields={'name', 'enabled'},
                optional_fields={'number', 'ssid', 'authMode', 'encryptionMode', 'splashPage'},
                url_patterns=['/wireless', '/ssid', '/wifi', '/radio'],
                keywords={'wireless', 'wifi', 'ssid', 'radio', 'access'},
                weight=1.0
            ),
            
            DataCategory.VLANS: FieldPattern(
                category=DataCategory.VLANS,
                required_fields={'id', 'name'},
                optional_fields={'subnet', 'applianceIp', 'groupPolicyId'},
                url_patterns=['/vlans', '/vlan'],
                keywords={'vlan', 'vlans', 'network'},
                weight=1.0
            ),
            
            DataCategory.ENDPOINTS: FieldPattern(
                category=DataCategory.ENDPOINTS,
                required_fields={'mac'},
                optional_fields={'ip', 'manufacturer', 'os', 'description', 'deviceTypePrediction'},
                url_patterns=['/clients', '/endpoints', '/users'],
                keywords={'client', 'endpoint', 'user', 'station'},
                weight=0.9
            )
        }
    
    def load_api_data(self):
        """Load parsed API data"""
        with open(self.parsed_api_file, 'r') as f:
            self.api_data = json.load(f)
        return self.api_data
    
    def classify_endpoint(self, endpoint: Dict) -> ClassifiedEndpoint:
        """Classify a single endpoint"""
        response_schema = endpoint['response_schema']
        
        # Get all fields from response schema
        all_fields = set(response_schema.get('properties', {}).keys())
        
        # Extract field names for matching
        field_names = {f.lower() for f in all_fields}
        
        best_match = None
        best_score = 0.0
        
        # Try each pattern
        for pattern in self.patterns.values():
            score = self._calculate_match_score(
                field_names=field_names,
                path=endpoint['path'],
                tags=endpoint['tags'],
                pattern=pattern
            )
            
            if score > best_score:
                best_score = score
                best_match = pattern
        
        # Determine matched and missing fields
        if best_match:
            matched = all_fields & (best_match.required_fields | best_match.optional_fields)
            missing = best_match.required_fields - {f.lower() for f in all_fields}
            category = best_match.category
        else:
            matched = set()
            missing = set()
            category = DataCategory.UNKNOWN
        
        # Calculate confidence (0.0 to 1.0)
        confidence = min(best_score, 1.0)
        
        return ClassifiedEndpoint(
            operation_id=endpoint['operation_id'],
            path=endpoint['path'],
            method=endpoint['method'],
            category=category,
            confidence=confidence,
            matched_fields=matched,
            missing_fields=missing,
            schema_name=response_schema.get('name', 'unknown'),
            is_array=response_schema.get('is_array', False),
            all_fields=all_fields,
            tags=endpoint['tags']
        )
    
    def _calculate_match_score(self, field_names: Set[str], path: str, 
                                tags: List[str], pattern: FieldPattern) -> float:
        """Calculate matching score for a pattern"""
        score = 0.0
        
        # Field matching (40% weight)
        required_matches = len(pattern.required_fields & field_names)
        required_total = len(pattern.required_fields)
        if required_total > 0:
            field_score = (required_matches / required_total) * 0.4
            score += field_score
        
        # Optional field matching (25% weight)
        optional_matches = len(pattern.optional_fields & field_names)
        optional_total = len(pattern.optional_fields)
        if optional_total > 0:
            optional_score = (optional_matches / optional_total) * 0.25
            score += optional_score
        
        # URL pattern matching (20% weight)
        path_lower = path.lower()
        for url_pattern in pattern.url_patterns:
            if url_pattern.lower() in path_lower:
                score += 0.2
                break
        
        # Keyword matching in tags (15% weight)
        tags_lower = {t.lower() for t in tags}
        keyword_matches = len(pattern.keywords & tags_lower)
        if len(pattern.keywords) > 0:
            keyword_score = (keyword_matches / len(pattern.keywords)) * 0.15
            score += keyword_score
        
        return score * pattern.weight
    
    def classify_all(self) -> List[ClassifiedEndpoint]:
        """Classify all endpoints"""
        if not self.api_data:
            self.load_api_data()
        
        self.classified_endpoints = []
        
        for endpoint in self.api_data['endpoints']:
            classified = self.classify_endpoint(endpoint)
            self.classified_endpoints.append(classified)
        
        return self.classified_endpoints
    
    def save_results(self, output_file: str):
        """Save classification results to JSON"""
        if not self.classified_endpoints:
            raise ValueError("No classified endpoints. Call classify_all() first.")
        
        output = {
            'total_endpoints': len(self.classified_endpoints),
            'endpoints': [
                {
                    'operation_id': ep.operation_id,
                    'path': ep.path,
                    'method': ep.method,
                    'category': ep.category.value,
                    'confidence': round(ep.confidence, 3),
                    'schema_name': ep.schema_name,
                    'is_array': ep.is_array,
                    'matched_fields': sorted(list(ep.matched_fields)),
                    'missing_fields': sorted(list(ep.missing_fields)),
                    'all_fields': sorted(list(ep.all_fields)),
                    'tags': ep.tags
                }
                for ep in self.classified_endpoints
            ]
        }
        
        with open(output_file, 'w') as f:
            json.dump(output, f, indent=2)
        
        print(f"✓ Saved classification results to {output_file}")
    
    def print_summary(self):
        """Print classification summary"""
        if not self.classified_endpoints:
            raise ValueError("No classified endpoints. Call classify_all() first.")
        
        print("\n" + "="*70)
        print("Pattern Recognition Results")
        print("="*70)
        
        # Count by category
        category_counts = {}
        for ep in self.classified_endpoints:
            category = ep.category.value
            category_counts[category] = category_counts.get(category, 0) + 1
        
        print("\nEndpoints by Category:")
        print("-"*70)
        for category, count in sorted(category_counts.items()):
            print(f"{category:30} : {count:2} endpoint(s)")
        
        print("\n" + "-"*70)
        print("Detailed Classification:")
        print("-"*70)
        
        for ep in self.classified_endpoints:
            confidence_marker = "✓" if ep.confidence >= 0.8 else "⚠" if ep.confidence >= 0.5 else "✗"
            print(f"\n{confidence_marker} {ep.operation_id}")
            print(f"   Path: {ep.method} {ep.path}")
            print(f"   Category: {ep.category.value}")
            print(f"   Confidence: {ep.confidence:.2%}")
            print(f"   Schema: {ep.schema_name}{'[]' if ep.is_array else ''}")
            if ep.matched_fields:
                print(f"   Matched Fields ({len(ep.matched_fields)}): {', '.join(sorted(ep.matched_fields)[:5])}")
            if ep.missing_fields:
                print(f"   Missing Required: {', '.join(sorted(ep.missing_fields))}")


def main():
    """Main execution"""
    script_dir = Path(__file__).parent
    input_file = script_dir / "parsed_api.json"
    output_file = script_dir / "classified_endpoints.json"
    
    print("\n🔍 SDN Agent POC - Pattern Recognizer")
    print("="*70)
    print(f"Input: {input_file}")
    print(f"Output: {output_file}")
    
    recognizer = PatternRecognizer(str(input_file))
    
    try:
        # Classify all endpoints
        recognizer.classify_all()
        
        # Print summary
        recognizer.print_summary()
        
        # Save results
        recognizer.save_results(str(output_file))
        
        print("\n✅ Pattern recognition completed successfully!\n")
        
    except Exception as e:
        print(f"\n❌ Error: {e}\n")
        raise


if __name__ == "__main__":
    main()
