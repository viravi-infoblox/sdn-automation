# Quick Start Guide

This guide helps you get started with SDN Automation quickly.

## Installation

```bash
# Clone the repository
git clone https://github.com/viravi-infoblox/sdn-automation.git
cd sdn-automation

# Install dependencies
pip install -r requirements.txt
```

## Configuration

### Option 1: Environment Variables

```bash
export INFOBLOX_HOST="your-infoblox-host.example.com"
export INFOBLOX_USERNAME="admin"
export INFOBLOX_PASSWORD="your-password"
export INFOBLOX_WAPI_VERSION="v2.12"
```

### Option 2: Configuration File

```bash
cp config/config.example.yml config/config.yml
# Edit config/config.yml with your settings
```

## Basic Usage

### Using the Python API

```python
from sdn_automation import InfobloxClient, NetworkManager

# Initialize
client = InfobloxClient(
    host="infoblox.example.com",
    username="admin",
    password="password"
)
network_mgr = NetworkManager(client)

# Provision a network
network_mgr.provision_network("10.0.0.0/24", comment="Test Network")

# Allocate an IP
ip = network_mgr.allocate_ip("10.0.0.0/24", "server01", "example.com")
print(f"Allocated: {ip}")
```

### Using the CLI

```bash
# Provision a network
python -m sdn_automation.cli provision 10.0.0.0/24 --comment "Test Network"

# Allocate an IP
python -m sdn_automation.cli allocate 10.0.0.0/24 webserver01 example.com

# Search for an IP
python -m sdn_automation.cli search 10.0.0.10
```

### Running Examples

```bash
# Basic operations
python examples/basic_operations.py

# Network provisioning
python examples/provision_network.py

# IP search
python examples/search_ip.py
```

## Running Tests

```bash
# Run all tests
python -m unittest discover tests -v

# Run specific test
python -m unittest tests.test_infoblox_client -v
```

## Common Tasks

### Provision Multiple Hosts

```python
from sdn_automation import InfobloxClient, NetworkManager

client = InfobloxClient(host="...", username="...", password="...")
network_mgr = NetworkManager(client)

hostnames = ['web01', 'web02', 'db01', 'cache01']
results = network_mgr.bulk_provision_hosts(
    "10.0.0.0/24", 
    hostnames, 
    "example.com"
)

for hostname, ip in results.items():
    print(f"{hostname}: {ip}")
```

### Search for IP Information

```python
from sdn_automation import InfobloxClient, NetworkManager

client = InfobloxClient(host="...", username="...", password="...")
network_mgr = NetworkManager(client)

records = network_mgr.find_ip_owner("10.0.0.10")
for record in records:
    print(f"Found: {record}")
```

## Next Steps

- Read the full [README.md](README.md) for detailed documentation
- Check out [examples/](examples/) for more use cases
- See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute
- Review [tests/](tests/) for testing examples

## Troubleshooting

### SSL Certificate Error

For testing only:
```python
client = InfobloxClient(..., verify_ssl=False)
```

### Authentication Error

- Verify credentials are correct
- Check user has API access enabled
- Ensure WAPI version matches your Infoblox version

### Network Not Found

Ensure the network exists in Infoblox before trying to allocate IPs.

## Support

For issues: https://github.com/viravi-infoblox/sdn-automation/issues
