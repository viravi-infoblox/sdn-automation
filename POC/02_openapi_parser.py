#!/usr/bin/env python3
"""
OpenAPI Parser for SDN Agent POC
Parses Meraki OpenAPI specification and extracts endpoint metadata
"""

import yaml
import json
from typing import Dict, List, Any
from pathlib import Path
from dataclasses import dataclass, asdict, field


@dataclass
class Parameter:
    """API parameter model"""
    name: str
    location: str  # path, query, header
    required: bool
    param_type: str
    description: str = ""
    default: Any = None


@dataclass
class ResponseSchema:
    """Response schema model"""
    name: str
    type: str  # object, array, string, etc.
    properties: Dict[str, Any] = field(default_factory=dict)
    is_array: bool = False
    items_ref: str = ""  # For array types
    required_fields: List[str] = field(default_factory=list)


@dataclass
class Endpoint:
    """API endpoint model"""
    path: str
    method: str
    operation_id: str
    summary: str
    description: str
    tags: List[str]
    parameters: List[Parameter]
    response_schema: ResponseSchema
    security_schemes: List[str]


@dataclass
class ParsedAPI:
    """Complete API specification"""
    title: str
    version: str
    base_url: str
    auth_type: str
    auth_header: str
    endpoints: List[Endpoint]
    schemas: Dict[str, ResponseSchema]


class OpenAPIParser:
    """Parse OpenAPI 3.0 specifications"""
    
    def __init__(self, spec_file: str):
        self.spec_file = Path(spec_file)
        self.spec = None
        self.parsed_api = None
        
    def load_spec(self) -> Dict:
        """Load OpenAPI YAML file"""
        with open(self.spec_file, 'r') as f:
            self.spec = yaml.safe_load(f)
        return self.spec
    
    def parse(self) -> ParsedAPI:
        """Parse the OpenAPI specification"""
        if not self.spec:
            self.load_spec()
        
        # Extract API metadata
        info = self.spec.get('info', {})
        servers = self.spec.get('servers', [])
        base_url = servers[0]['url'] if servers else ""
        
        # Extract authentication
        security_schemes = self.spec.get('components', {}).get('securitySchemes', {})
        auth_type, auth_header = self._parse_auth(security_schemes)
        
        # Parse schemas
        schemas = self._parse_schemas()
        
        # Parse endpoints
        endpoints = self._parse_endpoints(schemas)
        
        self.parsed_api = ParsedAPI(
            title=info.get('title', ''),
            version=info.get('version', '1.0.0'),
            base_url=base_url,
            auth_type=auth_type,
            auth_header=auth_header,
            endpoints=endpoints,
            schemas=schemas
        )
        
        return self.parsed_api
    
    def _parse_auth(self, security_schemes: Dict) -> tuple:
        """Extract authentication type and header name"""
        for scheme_name, scheme_data in security_schemes.items():
            if scheme_data.get('type') == 'apiKey':
                return ('api_key', scheme_data.get('name', 'X-API-Key'))
            elif scheme_data.get('type') == 'http':
                return ('bearer', 'Authorization')
        return ('none', '')
    
    def _parse_schemas(self) -> Dict[str, ResponseSchema]:
        """Parse component schemas"""
        schemas = {}
        component_schemas = self.spec.get('components', {}).get('schemas', {})
        
        for schema_name, schema_def in component_schemas.items():
            schemas[schema_name] = ResponseSchema(
                name=schema_name,
                type=schema_def.get('type', 'object'),
                properties=schema_def.get('properties', {}),
                required_fields=schema_def.get('required', [])
            )
        
        return schemas
    
    def _parse_endpoints(self, schemas: Dict[str, ResponseSchema]) -> List[Endpoint]:
        """Parse API endpoints/paths"""
        endpoints = []
        paths = self.spec.get('paths', {})
        
        for path, path_item in paths.items():
            for method, operation in path_item.items():
                if method.lower() not in ['get', 'post', 'put', 'patch', 'delete']:
                    continue
                
                # Parse parameters
                parameters = self._parse_parameters(operation.get('parameters', []))
                
                # Parse response schema
                response_schema = self._parse_response_schema(
                    operation.get('responses', {}),
                    schemas
                )
                
                endpoint = Endpoint(
                    path=path,
                    method=method.upper(),
                    operation_id=operation.get('operationId', ''),
                    summary=operation.get('summary', ''),
                    description=operation.get('description', ''),
                    tags=operation.get('tags', []),
                    parameters=parameters,
                    response_schema=response_schema,
                    security_schemes=operation.get('security', [])
                )
                
                endpoints.append(endpoint)
        
        return endpoints
    
    def _parse_parameters(self, params: List[Dict]) -> List[Parameter]:
        """Parse endpoint parameters"""
        parsed_params = []
        
        for param in params:
            schema = param.get('schema', {})
            parsed_params.append(Parameter(
                name=param.get('name', ''),
                location=param.get('in', 'query'),
                required=param.get('required', False),
                param_type=schema.get('type', 'string'),
                description=param.get('description', ''),
                default=schema.get('default')
            ))
        
        return parsed_params
    
    def _parse_response_schema(self, responses: Dict, schemas: Dict) -> ResponseSchema:
        """Parse response schema from 200 response"""
        success_response = responses.get('200', {})
        content = success_response.get('content', {})
        json_content = content.get('application/json', {})
        schema = json_content.get('schema', {})
        
        # Handle $ref
        if '$ref' in schema:
            ref_name = schema['$ref'].split('/')[-1]
            if ref_name in schemas:
                return schemas[ref_name]
        
        # Handle array responses
        if schema.get('type') == 'array':
            items = schema.get('items', {})
            if '$ref' in items:
                ref_name = items['$ref'].split('/')[-1]
                response = ResponseSchema(
                    name=ref_name,
                    type='object',
                    is_array=True,
                    items_ref=ref_name
                )
                if ref_name in schemas:
                    response.properties = schemas[ref_name].properties
                    response.required_fields = schemas[ref_name].required_fields
                return response
        
        # Handle direct object response
        return ResponseSchema(
            name='inline_response',
            type=schema.get('type', 'object'),
            properties=schema.get('properties', {}),
            required_fields=schema.get('required', [])
        )
    
    def save_json(self, output_file: str):
        """Save parsed API to JSON file"""
        if not self.parsed_api:
            raise ValueError("No parsed API data. Call parse() first.")
        
        output = {
            'title': self.parsed_api.title,
            'version': self.parsed_api.version,
            'base_url': self.parsed_api.base_url,
            'auth_type': self.parsed_api.auth_type,
            'auth_header': self.parsed_api.auth_header,
            'endpoints': [asdict(ep) for ep in self.parsed_api.endpoints],
            'schemas': {name: asdict(schema) for name, schema in self.parsed_api.schemas.items()}
        }
        
        with open(output_file, 'w') as f:
            json.dump(output, f, indent=2)
        
        print(f"✓ Saved parsed API to {output_file}")
    
    def print_summary(self):
        """Print parsing summary"""
        if not self.parsed_api:
            raise ValueError("No parsed API data. Call parse() first.")
        
        print("\n" + "="*70)
        print(f"OpenAPI Parser - {self.parsed_api.title}")
        print("="*70)
        print(f"Version: {self.parsed_api.version}")
        print(f"Base URL: {self.parsed_api.base_url}")
        print(f"Auth Type: {self.parsed_api.auth_type} ({self.parsed_api.auth_header})")
        print(f"\nTotal Endpoints: {len(self.parsed_api.endpoints)}")
        print(f"Total Schemas: {len(self.parsed_api.schemas)}")
        
        print("\n" + "-"*70)
        print("Endpoints:")
        print("-"*70)
        
        for ep in self.parsed_api.endpoints:
            response_type = f"{ep.response_schema.items_ref}[]" if ep.response_schema.is_array else ep.response_schema.name
            print(f"{ep.method:6} {ep.path:50} → {response_type}")
        
        print("\n" + "-"*70)
        print("Schemas:")
        print("-"*70)
        
        for schema_name, schema in self.parsed_api.schemas.items():
            field_count = len(schema.properties)
            required_count = len(schema.required_fields)
            print(f"{schema_name:20} - {field_count} fields ({required_count} required)")


def main():
    """Main execution"""
    script_dir = Path(__file__).parent
    input_file = script_dir / "01_meraki_openapi_sample.yaml"
    output_file = script_dir / "parsed_api.json"
    
    print("\n🚀 SDN Agent POC - OpenAPI Parser")
    print("="*70)
    print(f"Input: {input_file}")
    print(f"Output: {output_file}")
    
    parser = OpenAPIParser(str(input_file))
    
    try:
        # Parse the API
        parser.parse()
        
        # Print summary
        parser.print_summary()
        
        # Save to JSON
        parser.save_json(str(output_file))
        
        print("\n✅ OpenAPI parsing completed successfully!\n")
        
    except Exception as e:
        print(f"\n❌ Error: {e}\n")
        raise


if __name__ == "__main__":
    main()
