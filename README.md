# SDN Automation

A Python-based automation framework for Software-Defined Networking (SDN) with Infoblox integration.

## Overview

This prototype provides a comprehensive solution for automating network provisioning, IP address management (IPAM), and DNS operations using Infoblox. It's designed to simplify and streamline network automation tasks in enterprise environments.

## Features

- **Infoblox Integration**: Full-featured client for Infoblox WAPI
- **Network Management**: High-level abstractions for common network operations
- **IP Address Management**: Automated IP allocation and host record creation
- **Configuration Management**: YAML-based configuration with environment variable support
- **Extensible Architecture**: Modular design for easy extension and customization
- **Comprehensive Testing**: Unit tests for core functionality

## Project Structure

```
sdn-automation/
├── sdn_automation/           # Main package
│   ├── infoblox/            # Infoblox API client
│   │   ├── __init__.py
│   │   └── client.py        # InfobloxClient class
│   ├── network/             # Network management
│   │   ├── __init__.py
│   │   └── manager.py       # NetworkManager class
│   └── utils/               # Utility modules
│       ├── __init__.py
│       ├── config.py        # Configuration loading
│       └── logger.py        # Logging setup
├── config/                  # Configuration files
│   ├── config.example.yml   # Example YAML config
│   └── .env.example         # Example environment variables
├── examples/                # Example scripts
│   ├── basic_operations.py  # Basic CRUD operations
│   ├── provision_network.py # Network provisioning example
│   └── search_ip.py         # IP search example
├── tests/                   # Unit tests
│   ├── test_infoblox_client.py
│   ├── test_network_manager.py
│   └── test_config.py
├── requirements.txt         # Python dependencies
└── README.md               # This file
```

## Installation

### Prerequisites

- Python 3.7 or higher
- Access to an Infoblox Grid Manager
- Valid Infoblox API credentials

### Setup

1. Clone the repository:
```bash
git clone https://github.com/viravi-infoblox/sdn-automation.git
cd sdn-automation
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Configure your environment:

**Option A: Using environment variables**
```bash
cp config/.env.example .env
# Edit .env with your Infoblox credentials
```

**Option B: Using YAML configuration**
```bash
cp config/config.example.yml config/config.yml
# Edit config/config.yml with your settings
```

## Usage

### Basic Example

```python
from sdn_automation import InfobloxClient, NetworkManager

# Initialize client
client = InfobloxClient(
    host="infoblox.example.com",
    username="admin",
    password="password",
    wapi_version="v2.12"
)

# Create network manager
network_mgr = NetworkManager(client)

# Provision a network
network_mgr.provision_network("10.0.0.0/24", comment="Test Network")

# Allocate IP for a host
ip = network_mgr.allocate_ip("10.0.0.0/24", "webserver01", "example.com")
print(f"Allocated IP: {ip}")
```

### Running Examples

The `examples/` directory contains several ready-to-use scripts:

```bash
# Basic operations
python examples/basic_operations.py

# Provision a network and allocate IPs
python examples/provision_network.py

# Search for IP information
python examples/search_ip.py
```

### Configuration

#### YAML Configuration

Create a `config/config.yml` file:

```yaml
infoblox:
  host: "infoblox.example.com"
  username: "admin"
  password: "changeme"
  wapi_version: "v2.12"
  verify_ssl: true

automation:
  domain: "example.com"
  default_network: "10.0.0.0/24"
```

#### Environment Variables

```bash
export INFOBLOX_HOST="infoblox.example.com"
export INFOBLOX_USERNAME="admin"
export INFOBLOX_PASSWORD="changeme"
export INFOBLOX_WAPI_VERSION="v2.12"
export VERIFY_SSL="true"
```

## API Reference

### InfobloxClient

The `InfobloxClient` class provides low-level access to the Infoblox WAPI.

**Methods:**
- `get_network(network)` - Retrieve network information
- `create_network(network, comment)` - Create a new network
- `delete_network(network_ref)` - Delete a network
- `get_next_available_ip(network, num)` - Get available IP addresses
- `create_host_record(fqdn, ipv4addr)` - Create a host record
- `search_by_ip(ip)` - Search for records by IP address

### NetworkManager

The `NetworkManager` class provides high-level network automation operations.

**Methods:**
- `provision_network(network, comment)` - Provision a new network
- `allocate_ip(network, hostname, domain)` - Allocate IP and create host record
- `get_network_info(network)` - Get network information
- `find_ip_owner(ip)` - Find records associated with an IP
- `bulk_provision_hosts(network, hostnames, domain)` - Provision multiple hosts

## Testing

Run the test suite:

```bash
# Run all tests
python -m unittest discover tests

# Run specific test file
python -m unittest tests.test_infoblox_client

# Run with verbose output
python -m unittest discover tests -v
```

## Development

### Adding New Features

1. Create your feature in the appropriate module under `sdn_automation/`
2. Add unit tests in the `tests/` directory
3. Update documentation in this README
4. Create an example script in `examples/` if applicable

### Code Style

- Follow PEP 8 guidelines
- Use type hints where appropriate
- Document all public functions and classes
- Write unit tests for new functionality

## Security Considerations

- **Never commit credentials**: Use environment variables or secure configuration management
- **SSL Verification**: Always enable SSL verification in production (`verify_ssl=True`)
- **Credential Storage**: Use secure secret management systems (e.g., HashiCorp Vault, AWS Secrets Manager)
- **Access Control**: Follow the principle of least privilege for API credentials

## Troubleshooting

### Common Issues

**SSL Certificate Errors**
```python
# For development/testing only, disable SSL verification
client = InfobloxClient(..., verify_ssl=False)
```

**Connection Timeouts**
- Verify network connectivity to Infoblox Grid Manager
- Check firewall rules for HTTPS (port 443)
- Ensure WAPI version matches your Infoblox version

**Authentication Failures**
- Verify credentials are correct
- Check user permissions in Infoblox
- Ensure API access is enabled for the user

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## License

This project is part of the Infoblox SDN Automation initiative.

## Support

For issues and questions:
- Open an issue on GitHub
- Contact the SDN Automation team

## Roadmap

- [ ] Support for additional Infoblox objects (zones, views, etc.)
- [ ] Integration with network orchestration platforms
- [ ] REST API wrapper for web service integration
- [ ] CLI tool for command-line operations
- [ ] Ansible playbook integration
- [ ] Enhanced error handling and retry logic
- [ ] Performance optimization for bulk operations
- [ ] Integration with monitoring systems

## Version History

- **0.1.0** (Current) - Initial prototype release
  - Infoblox client implementation
  - Network management functionality
  - Basic examples and documentation
