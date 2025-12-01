# 🚀 Generated Code Usage Guide

**Quick reference for using the generated NetMRI SDN modules**

---

## 📁 Generated Files

```
POC/generated/
├── Client/
│   └── Cisco_Generated.pm    # API Client - 183 lines
└── Server/
    └── Cisco_Generated.pm    # Business Logic - 214 lines
```

---

## 🔌 Client Module Usage

### Location
`/Users/viravi/Desktop/SDN_Files/POC/generated/Client/Cisco_Generated.pm`

### Purpose
HTTP client for Cisco Meraki Dashboard API with:
- API key authentication
- Pagination support
- Rate limiting (3 req/sec)
- Error handling

### Initialization

```perl
use NetMRI::HTTP::Client::Cisco;

my $client = NetMRI::HTTP::Client::Cisco->new(
    api_key   => 'your-meraki-api-key',
    fabric_id => 123,
    address   => 'api.meraki.com',  # optional
);
```

### Available Methods

#### 1. Get Organizations
```perl
my ($organizations, $error) = $client->get_organizations();

# Returns array of organizations:
# [
#   { id => "123456", name => "My Org", url => "..." },
#   ...
# ]
```

#### 2. Get Networks
```perl
my ($networks, $error) = $client->get_organization_networks(
    $org_id,
    { perPage => 1000 }  # optional params
);

# Returns array of networks:
# [
#   { id => "L_123", name => "Main Office", timeZone => "America/Los_Angeles" },
#   ...
# ]
```

#### 3. Get Devices
```perl
my ($devices, $error) = $client->get_organization_devices(
    $org_id,
    { perPage => 1000 }
);

# Returns array of devices:
# [
#   {
#     serial => "Q2AB-C3DE-F4GH",
#     mac => "00:11:22:33:44:55",
#     model => "MS220-8P",
#     name => "Office Switch",
#     networkId => "L_123",
#     firmware => "switch-11-31",
#     lanIp => "192.168.1.1",
#     ...
#   },
#   ...
# ]
```

#### 4. Get Device Details
```perl
my ($device, $error) = $client->get_device($serial);
```

#### 5. Get Device Statuses
```perl
my ($statuses, $error) = $client->get_organization_devices_statuses($org_id);

# Returns array of device statuses:
# [
#   {
#     serial => "Q2AB-C3DE-F4GH",
#     status => "online",
#     lanIp => "192.168.1.1",
#     ...
#   },
#   ...
# ]
```

#### 6. Get Switch Ports
```perl
my ($ports, $error) = $client->get_device_switch_ports($serial);

# Returns array of switch ports:
# [
#   {
#     portId => "1",
#     name => "Uplink Port",
#     enabled => true,
#     type => "trunk",
#     vlan => 10,
#     allowedVlans => "1,10,20,30",
#     status => "Connected",
#     speed => "1 Gbps",
#     ...
#   },
#   ...
# ]
```

#### 7. Get LLDP/CDP Info
```perl
my ($lldp_cdp, $error) = $client->get_device_lldp_cdp(
    $serial,
    { timespan => 7200 }  # 2 hours in seconds
);

# Returns LLDP/CDP neighbor info:
# {
#   sourceMac => "00:11:22:33:44:55",
#   ports => {
#     "1" => {
#       cdp => { deviceId => "switch.example.com", portId => "Gi1/0/1", ... },
#       lldp => { systemName => "core-switch-01", portId => "Gi1/0/1", ... }
#     },
#     ...
#   }
# }
```

#### 8. Get Static Routes
```perl
my ($routes, $error) = $client->get_network_appliance_static_routes($network_id);

# Returns array of static routes:
# [
#   {
#     id => "1234567890",
#     name => "Corporate Network",
#     subnet => "192.168.100.0/24",
#     gatewayIp => "192.168.1.1"
#   },
#   ...
# ]
```

#### 9. Get Wireless SSIDs
```perl
my ($ssids, $error) = $client->get_network_wireless_ssids($network_id);

# Returns array of SSIDs:
# [
#   {
#     number => 0,
#     name => "Corporate WiFi",
#     enabled => true,
#     authMode => "psk",
#     encryptionMode => "wpa",
#     ...
#   },
#   ...
# ]
```

### Error Handling

```perl
my ($data, $error) = $client->get_organizations();

if ($error) {
    print "API Error: $error\n";
    # Handle error
} else {
    # Process $data
}
```

### Pagination

The client automatically handles pagination for list endpoints:
- Follows "next" links in response headers
- Configurable iteration limit (default: 100)
- Automatically aggregates results

---

## 🏢 Server Module Usage

### Location
`/Users/viravi/Desktop/SDN_Files/POC/generated/Server/Cisco_Generated.pm`

### Purpose
Business logic for NetMRI SDN data collection with:
- AUTOLOAD plugin integration
- Data transformation
- Field mapping
- Multiple obtain methods

### Initialization

```perl
use NetMRI::SDN::Cisco;

my $server = NetMRI::SDN::Cisco->new(
    # NetMRI SDN::Base parameters
    fabric_id => 123,
    device_dn => "org123/net456/SERIAL789",
    ...
);
```

### Data Collection Methods

#### 1. Collect All Data
```perl
$server->obtainEverything();

# Calls all obtain methods:
# - obtainSystemInfo()
# - obtainSdnFabricInterface()
# - obtainCdpLldp()
# - obtainSwitchPort()
# - obtainRoute()
# - obtainWireless()
```

#### 2. Get Devices (for Discovery)
```perl
my $devices = $server->getDevices();

# Returns arrayref of device hashes:
# [
#   {
#     SdnControllerId => 123,
#     SdnDeviceDN => "org123/net456/SERIAL789",
#     Name => "Office Switch",
#     Serial => "SERIAL789",
#     Model => "MS220-8P",
#     Vendor => "Cisco",
#     SWVersion => "switch-11-31",
#     IPAddress => "192.168.1.1",
#     MACAddress => "00:11:22:33:44:55",
#     modTS => "2025-12-01 14:30:00"
#   },
#   ...
# ]
```

#### 3. Obtain System Info
```perl
$server->obtainSystemInfo();

# Internally calls:
# $self->saveSystemInfo(\%system_info);
# 
# Data collected:
# - SdnDeviceDN
# - Status (online/offline)
# - SWVersion
# - Model
# - Serial
```

#### 4. Obtain Interfaces
```perl
$server->obtainSdnFabricInterface();

# Internally calls:
# $self->saveSdnFabricInterface(\@interfaces);
#
# Data per interface:
# - ifIndex (port ID)
# - ifName
# - ifOperStatus (Connected/Disconnected)
# - ifAdminStatus (up/down)
# - ifSpeed
# - ifDuplex
# - VlanIndex
```

#### 5. Obtain LLDP/CDP Topology
```perl
$server->obtainCdpLldp();

# Internally calls:
# $self->saveSdnLldp(\@neighbors);
#
# Data per neighbor:
# - SdnDeviceDN
# - ifIndex (local port)
# - NeighborDeviceID
# - NeighborPortID
# - NeighborIPAddress
# - Protocol (LLDP/CDP)
```

#### 6. Obtain Switch Port Config
```perl
$server->obtainSwitchPort();

# Internally calls:
# $self->saveSdnSwitchPortConfig(\@switch_ports);
#
# Data per port:
# - ifIndex
# - VlanIndex
# - PortMode (access/trunk)
# - AllowedVlans
# - POEEnabled (1/0)
# - ifAdminStatus
```

#### 7. Obtain Static Routes
```perl
$server->obtainRoute();

# Internally calls:
# $self->saveSdnRoute(\@routes);
#
# Data per route:
# - RouteCIDR (192.168.0.0/24)
# - RouteNextHop (gateway IP)
# - RouteName
# - RouteEnabled (1/0)
```

#### 8. Obtain Wireless SSIDs
```perl
$server->obtainWireless();

# Internally calls:
# $self->saveSdnWirelessSsid(\@ssids);
#
# Data per SSID:
# - SSID (name)
# - SSIDEnabled (1/0)
# - SSIDNumber
# - AuthMode
# - EncryptionMode
```

### Plugin Integration (AUTOLOAD)

The server module uses NetMRI's AUTOLOAD mechanism:

```perl
# These calls automatically route to appropriate plugins:
$self->saveDevices(\@devices);              # → SaveDevices.pm
$self->saveSystemInfo(\%info);              # → SaveSystemInfo.pm
$self->saveSdnFabricInterface(\@interfaces);# → SaveSdnFabricInterface.pm
$self->saveSdnLldp(\@neighbors);            # → SaveSdnLldp.pm
$self->saveSdnSwitchPortConfig(\@ports);    # → SaveSdnSwitchPortConfig.pm
$self->saveSdnRoute(\@routes);              # → SaveSdnRoute.pm
$self->saveSdnWirelessSsid(\@ssids);        # → SaveSdnWirelessSsid.pm
```

---

## 🔗 Integration Example

### Complete Workflow

```perl
use NetMRI::HTTP::Client::Cisco;
use NetMRI::SDN::Cisco;

# 1. Initialize API client
my $client = NetMRI::HTTP::Client::Cisco->new(
    api_key   => $api_key,
    fabric_id => $fabric_id
);

# 2. Initialize SDN server
my $server = NetMRI::SDN::Cisco->new(
    fabric_id => $fabric_id,
    device_dn => $device_dn,
    api_client => $client
);

# 3. Discover and save devices
my $devices = $server->getDevices();
# Devices automatically saved to NetMRI database

# 4. Collect detailed data for specific device
$server->obtainEverything();
# All data types collected and saved
```

---

## 📝 Field Mappings Reference

### Device Discovery (SaveDevices)

| API Field | NetMRI Field | Required | Notes |
|-----------|--------------|----------|-------|
| serial | Serial | Yes | Device serial number |
| model | Model | Yes | Device model |
| name | Name | Yes | Device hostname |
| lanIp, wan1Ip, wan2Ip, publicIp | IPAddress | Yes | First available IP |
| firmware | SWVersion | No | Software version |
| mac | MACAddress | No | MAC address |
| orgId + networkId + serial | SdnDeviceDN | Yes | Composite DN |

### Interfaces (SaveSdnFabricInterface)

| API Field | NetMRI Field | Required | Notes |
|-----------|--------------|----------|-------|
| portId | ifIndex | Yes | Port number |
| name | ifName | Yes | Port name |
| status | ifOperStatus | Yes | Connected/Disconnected |
| enabled | ifAdminStatus | No | up/down |
| speed | ifSpeed | No | "1 Gbps" |
| duplex | ifDuplex | No | full/half |
| type | ifType | No | access/trunk |
| vlan | VlanIndex | No | VLAN ID |

### LLDP/CDP (SaveSdnLldp)

| API Field | NetMRI Field | Required | Notes |
|-----------|--------------|----------|-------|
| deviceId, systemName | NeighborDeviceID | Yes | Neighbor name |
| portId | NeighborPortID | Yes | Remote port |
| address, managementAddress | NeighborIPAddress | No | Neighbor IP |

### Switch Ports (SaveSdnSwitchPortConfig)

| API Field | NetMRI Field | Required | Notes |
|-----------|--------------|----------|-------|
| portId | ifIndex | Yes | Port number |
| vlan | VlanIndex | Yes | Native VLAN |
| type | PortMode | No | access/trunk |
| allowedVlans | AllowedVlans | No | "1,10,20" |
| poeEnabled | POEEnabled | No | 1/0 |
| enabled | ifAdminStatus | No | up/down |

### Static Routes (SaveSdnRoute)

| API Field | NetMRI Field | Required | Notes |
|-----------|--------------|----------|-------|
| subnet | RouteCIDR | Yes | 192.168.0.0/24 |
| gatewayIp | RouteNextHop | Yes | Gateway IP |
| name | RouteName | No | Route description |
| enabled | RouteEnabled | No | 1/0 |

### Wireless SSIDs (SaveSdnWirelessSsid)

| API Field | NetMRI Field | Required | Notes |
|-----------|--------------|----------|-------|
| name | SSID | Yes | SSID name |
| enabled | SSIDEnabled | Yes | 1/0 |
| number | SSIDNumber | No | 0-14 |
| authMode | AuthMode | No | psk, open, etc |
| encryptionMode | EncryptionMode | No | wpa, wpa2, etc |

---

## 🔧 Customization Points

### 1. Device Role Mapping
Currently vendor is hardcoded as "Cisco". To add device role mapping:

```perl
# In Server module, add:
my %model_to_role_map = (
    MS => 'Meraki Switching',
    MR => 'Meraki Wireless',
    MX => 'Meraki Security',
);

my $model_prefix = substr($dev->{model}, 0, 2);
$device{NodeRole} = $model_to_role_map{$model_prefix} || 'Meraki Device';
```

### 2. Virtual Network Handling
Add virtual network mapping logic:

```perl
# Map Meraki networks to NetMRI virtual networks
my $vnid = $self->get_virtual_network_id($org_id, $network_id);
```

### 3. Offline Device Filtering
Add status checking:

```perl
# Skip offline devices if configured
my $collect_offline = $self->should_collect_offline_devices();
next if (!$collect_offline && $status eq 'offline');
```

---

## ✅ Testing

### Unit Test Example

```perl
use Test::More tests => 3;
use NetMRI::HTTP::Client::Cisco;

my $client = NetMRI::HTTP::Client::Cisco->new(
    api_key => 'test_key',
    fabric_id => 999
);

ok($client, "Client initialized");
ok($client->{fabric_id} == 999, "Fabric ID set correctly");
ok($client->{requests_per_second} == 3, "Rate limit configured");
```

### Integration Test Example

```perl
# Test device discovery
my $server = NetMRI::SDN::Cisco->new(...);
my $devices = $server->getDevices();

ok(ref($devices) eq 'ARRAY', "Returns array of devices");
ok(scalar(@$devices) > 0, "Found devices");
ok($devices->[0]->{Serial}, "Device has serial number");
ok($devices->[0]->{IPAddress}, "Device has IP address");
```

---

## 📚 Additional Resources

- **Plugin Details**: See `../Documents/Plugin_Selection_Strategy.md`
- **Architecture**: See `../Documents/SDN_Agent_Design_Document.md`
- **Existing Implementation**: See `../SDN_Client/Client/Meraki.pm` and `../SDN_Server/Meraki.pm`

---

**Generated**: December 1, 2025  
**Code Version**: Generated by SDN Agent POC v1.0  
**Status**: Ready for integration testing
