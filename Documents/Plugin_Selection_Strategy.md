# Plugin Selection Strategy for SDN Discovery Agent

## How the Agent Determines Which Plugins to Use

### Current Plugin Selection Mechanism

#### 1. **AUTOLOAD Magic Method Pattern**
The existing SDN framework uses Perl's `AUTOLOAD` feature to dynamically create `save*` methods:

```perl
# From Base.pm
sub AUTOLOAD {
  my ($self) = @_;
  if ($AUTOLOAD =~ /.*::save(.*)/ && exists($self->{autoload_save_methods}->{$1})) {
    my $object_name = $1;
    *$AUTOLOAD = sub {
      my ($self, $data) = @_;
      $self->getPlugin('Save' . $object_name)->run($data);
    };
    goto &$AUTOLOAD;
  }
}
```

**How it works:**
1. Code calls `$self->saveDevices($data)`
2. Method doesn't exist, AUTOLOAD intercepts
3. Extracts "Devices" from "saveDevices"
4. Dynamically creates method that calls `getPlugin('SaveDevices')`
5. Plugin name = "Save" + object name

#### 2. **Pre-registered Plugin Names**
Available plugins are declared in `Base.pm`:

```perl
$self->{autoload_save_methods}->{$_} = 1 foreach (qw(
    Devices              # SaveDevices.pm
    SystemInfo           # SaveSystemInfo.pm
    SdnFabricInterface   # SaveSdnFabricInterface.pm
    SwitchPortObject     # SaveSwitchPortObject.pm
    IPAddress            # SaveIPAddress.pm
    CDP                  # SaveCDP.pm
    LLDP                 # SaveLLDP.pm
    SdnEndpoint          # SaveSdnEndpoint.pm
    Forwarding           # SaveForwarding.pm
    VlanObject           # SaveVlanObject.pm
    Wireless             # SaveWireless.pm
    # ... 40+ more plugins
));
```

#### 3. **Plugin Loading Pattern**

```perl
sub getPlugin {
  my ($self, $pluginName) = @_;
  unless (defined($self->{plugins}->{$pluginName})) {
    my $module_name = 'NetMRI::SDN::Plugins::'.$pluginName;
    my $cmd = 'require '. $module_name . '; 
               $self->{plugins}->{$pluginName} = ' . $module_name . '->new($self);';
    eval $cmd;
  }
  return $self->{plugins}->{$pluginName};
}
```

**Plugin Selection Flow:**
```
obtainSystemInfo() 
  → saveSystemInfo($data) 
    → AUTOLOAD intercepts 
      → getPlugin('SaveSystemInfo') 
        → loads NetMRI::SDN::Plugins::SaveSystemInfo
          → Plugin->run($data)
```

---

## Agent's Plugin Selection Strategy

### Phase 1: Data Type Classification

The agent analyzes OpenAPI responses and classifies data into NetMRI plugin categories:

```yaml
plugin_mapping_rules:
  device_discovery:
    openapi_indicators:
      - response contains: ["devices", "nodes", "inventory"]
      - fields present: ["id", "name", "model", "serial", "ip"]
    maps_to_plugin: "SaveDevices"
    
  system_information:
    openapi_indicators:
      - response contains: ["version", "uptime", "model", "serial"]
      - endpoint pattern: "/devices/{id}", "/system/info"
    maps_to_plugin: "SaveSystemInfo"
    
  interfaces:
    openapi_indicators:
      - response contains: ["interfaces", "ports", "links"]
      - fields present: ["name", "mac", "status", "speed"]
    maps_to_plugin: "SaveSdnFabricInterface"
    
  neighbors:
    openapi_indicators:
      - response contains: ["lldp", "cdp", "neighbors"]
      - fields present: ["remoteDevice", "remotePort"]
    maps_to_plugins: ["SaveCDP", "SaveLLDP"]
    
  switching:
    openapi_indicators:
      - response contains: ["switchport", "vlan", "trunk"]
      - fields present: ["portNumber", "vlan", "mode"]
    maps_to_plugins: ["SaveSwitchPortObject", "SaveVlanObject"]
```

### Phase 2: Response Schema Analysis

**Algorithm:**
```python
def determine_plugins_from_response(api_response_schema):
    plugins = []
    
    # Analyze top-level response structure
    if is_array_of_objects(api_response_schema):
        # Likely a list endpoint (devices, networks, etc.)
        field_analysis = analyze_fields(api_response_schema.items)
        
        if has_device_fields(field_analysis):
            plugins.append('SaveDevices')
        
        if has_interface_fields(field_analysis):
            plugins.append('SaveSdnFabricInterface')
    
    # Check for nested structures
    if has_nested_object(api_response_schema, 'topology'):
        plugins.extend(['SaveCDP', 'SaveLLDP'])
    
    if has_nested_object(api_response_schema, 'vlans'):
        plugins.append('SaveVlanObject')
    
    return plugins

def has_device_fields(fields):
    device_indicators = ['id', 'deviceId', 'serial', 'model', 
                         'ipAddress', 'name', 'vendor']
    return count_matching_fields(fields, device_indicators) >= 4

def has_interface_fields(fields):
    interface_indicators = ['interfaceName', 'portId', 'macAddress', 
                           'status', 'speed', 'mtu']
    return count_matching_fields(fields, interface_indicators) >= 3
```

### Phase 3: Plugin Compatibility Matrix

**Generated Plugin Mapping:**

| Data Category | OpenAPI Response Pattern | Plugin(s) | Priority |
|---------------|-------------------------|-----------|----------|
| **Device List** | `GET /devices` → Array[Device] | `SaveDevices` | Required |
| **System Info** | `GET /devices/{id}` → Device Details | `SaveSystemInfo` | Required |
| **Interfaces** | `GET /devices/{id}/interfaces` | `SaveSdnFabricInterface` | Required |
| **CDP/LLDP** | `GET /devices/{id}/neighbors` | `SaveCDP`, `SaveLLDP` | Optional |
| **Switch Ports** | `GET /devices/{id}/ports` | `SaveSwitchPortObject` | Conditional* |
| **VLANs** | `GET /devices/{id}/vlans` | `SaveVlanObject` | Conditional* |
| **Wireless** | `GET /devices/{id}/wireless` | `SaveWireless` | Conditional* |
| **Routing** | `GET /devices/{id}/routes` | `SaveipRouteTable` | Optional |
| **ARP** | `GET /devices/{id}/arp` | `SaveatObject` | Optional |
| **Endpoints** | `GET /devices/{id}/clients` | `SaveSdnEndpoint` | Optional |

*Conditional = Based on device type/role

### Phase 4: Auto-Generated Plugin Registration

The agent will generate code that registers plugins in the vendor's Server module:

```perl
# Auto-generated in SDN_Server/NewVendor.pm
package NetMRI::SDN::NewVendor;

use strict;
use NetMRI::SDN::Base;
use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{vendor_name} = 'NewVendor';
    
    # Agent auto-detects which plugins are needed based on OpenAPI spec
    $self->_register_vendor_plugins();
    
    return bless $self, $class;
}

sub _register_vendor_plugins {
    my $self = shift;
    
    # Standard plugins (always used)
    my @standard_plugins = qw(
        Devices
        SystemInfo
        DeviceProperty
        SdnFabricInterface
    );
    
    # Conditional plugins based on API capabilities
    my @conditional_plugins = ();
    
    # If OpenAPI has /devices/{id}/neighbors endpoint
    push @conditional_plugins, qw(CDP LLDP) if $self->_has_neighbor_api();
    
    # If OpenAPI has /devices/{id}/vlans endpoint
    push @conditional_plugins, qw(VlanObject SwitchPortObject) if $self->_has_vlan_api();
    
    # If OpenAPI has /devices/{id}/wireless endpoint
    push @conditional_plugins, 'Wireless' if $self->_has_wireless_api();
    
    # Register all plugins
    foreach my $plugin (@standard_plugins, @conditional_plugins) {
        $self->{autoload_save_methods}->{$plugin} = 1;
    }
}
```

### Phase 5: Dynamic Plugin Selection Logic

**Generated Code Pattern:**

```perl
# Auto-generated obtain methods with intelligent plugin selection
sub obtainEverything {
    my $self = shift;
    my $dev_role = $self->getDeviceRole();
    
    # Always collect basic info
    $self->obtainSystemInfo();           # → SaveSystemInfo
    $self->obtainSdnFabricInterface();   # → SaveSdnFabricInterface
    
    # Conditional collection based on device role
    if ($dev_role =~ /Switch|Router/) {
        $self->obtainCdpLldp();          # → SaveCDP, SaveLLDP
        $self->obtainSwitchPort();       # → SaveSwitchPortObject
        $self->obtainVlan();             # → SaveVlanObject
    }
    
    if ($dev_role =~ /Wireless|AP/) {
        $self->obtainWireless();         # → SaveWireless
        $self->obtainEndpoints();        # → SaveSdnEndpoint
    }
    
    if ($dev_role =~ /Router|Firewall/) {
        $self->obtainRoute();            # → SaveipRouteTable
        $self->obtainArp();              # → SaveatObject
    }
}

sub obtainSystemInfo {
    my $self = shift;
    my ($device_info, $error) = $self->{api_helper}->get_device_details($device_id);
    
    # Transform to NetMRI format
    my $data = {
        LastTimeStamp => NetMRI::Util::Date::formatDate(time()),
        Name => $device_info->{name},
        Model => $device_info->{model},
        SWVersion => $device_info->{version},
        UpTime => $device_info->{uptime},
    };
    
    # Plugin automatically selected via AUTOLOAD
    $self->saveSystemInfo($data);  # → getPlugin('SaveSystemInfo')->run($data)
}
```

---

## Agent Decision Tree

```
┌─────────────────────────────────────┐
│ Parse OpenAPI Specification        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Analyze All API Endpoints          │
│ - Extract response schemas         │
│ - Identify field patterns          │
│ - Categorize by data type          │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Match to NetMRI Data Categories    │
│ - Device Discovery                 │
│ - System Information               │
│ - Interfaces                       │
│ - Topology (CDP/LLDP)             │
│ - VLANs/Switching                 │
│ - Wireless                         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Map Categories to Plugins          │
│ Device Discovery → SaveDevices     │
│ System Info → SaveSystemInfo       │
│ Interfaces → SaveSdnFabricInterface│
│ etc.                               │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Generate Plugin Registration Code  │
│ - Standard plugins (always used)   │
│ - Conditional plugins (role-based) │
│ - Update autoload_save_methods     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Generate obtain* Methods           │
│ - obtainSystemInfo()               │
│ - obtainSdnFabricInterface()       │
│ - obtainCdpLldp()                  │
│ Each calls appropriate save method │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ Generate Data Transformation Logic │
│ API Response → NetMRI Data Model   │
│ Then: $self->saveFoo($data)        │
│ AUTOLOAD → getPlugin('SaveFoo')    │
└─────────────────────────────────────┘
```

---

## Plugin Selection Configuration

The agent will support manual overrides via configuration:

```yaml
# vendor_config.yaml
vendor: NewVendor
plugin_mappings:
  
  # Required plugins (always used)
  required:
    - SaveDevices
    - SaveSystemInfo
    - SaveSdnFabricInterface
    
  # Conditional plugins based on device capabilities
  conditional:
    switching:
      condition: "device_role =~ /Switch/"
      plugins:
        - SaveSwitchPortObject
        - SaveVlanObject
        - SaveVlanTrunkPortTable
        
    wireless:
      condition: "device_role =~ /Wireless|AP/"
      plugins:
        - SaveWireless
        - SaveSdnEndpoint
        
    routing:
      condition: "device_role =~ /Router/"
      plugins:
        - SaveipRouteTable
        - SaveatObject
        - SaveForwarding
        
  # Custom plugin mappings (override defaults)
  custom:
    neighbor_discovery:
      api_endpoint: "/devices/{id}/neighbors"
      plugins:
        - SaveCDP
        - SaveLLDP
      transform_function: "transform_neighbors_data"
```

---

## Example: Generated Plugin Code

### For Cisco Meraki (Existing)
```perl
# Current implementation uses these plugins:
$self->saveDevices($devices);              # SaveDevices
$self->saveSystemInfo($system_data);       # SaveSystemInfo
$self->saveSdnFabricInterface($interfaces);# SaveSdnFabricInterface
$self->saveCDP($cdp_data);                 # SaveCDP
$self->saveLLDP($lldp_data);               # SaveLLDP
$self->saveSwitchPortObject($ports);       # SaveSwitchPortObject
$self->saveWireless($wireless_data);       # SaveWireless
$self->saveSdnEndpoint($endpoints);        # SaveSdnEndpoint
```

### For New Vendor (Agent-Generated)
```perl
# Agent analyzes OpenAPI and generates:
sub obtainEverything {
    my $self = shift;
    
    # Core data collection (plugins auto-selected)
    $self->obtainSystemInfo();           # Uses SaveSystemInfo
    $self->obtainInterfaces();           # Uses SaveSdnFabricInterface
    
    # Conditional based on detected APIs
    $self->obtainTopology() if $self->_has_topology_api();  # SaveCDP, SaveLLDP
    $self->obtainVlans() if $self->_has_vlan_api();         # SaveVlanObject
}
```

---

## Validation & Testing

The agent will validate plugin selection by:

1. **Schema Validation**: Ensure API response matches plugin's expected fields
2. **Field Coverage**: Check that required plugin fields can be populated
3. **Data Type Checking**: Verify data transformations are valid
4. **Mock Data Testing**: Generate test cases with sample API responses

```python
def validate_plugin_selection(api_endpoint, selected_plugin):
    # Get API response schema
    response_schema = parse_openapi_response(api_endpoint)
    
    # Get plugin requirements
    plugin_required_fields = load_plugin_schema(selected_plugin)
    
    # Check coverage
    coverage = calculate_field_coverage(response_schema, plugin_required_fields)
    
    if coverage < 0.8:  # 80% field coverage minimum
        return ValidationError(
            f"Plugin {selected_plugin} requires fields not in API response"
        )
    
    return ValidationSuccess(coverage)
```

---

## Summary

**The agent determines plugin selection through:**

1. ✅ **OpenAPI Analysis**: Parse response schemas to identify data types
2. ✅ **Pattern Matching**: Match API responses to NetMRI data categories
3. ✅ **Plugin Mapping**: Map categories to specific SaveXXX plugins
4. ✅ **Code Generation**: Generate plugin registration and usage code
5. ✅ **Validation**: Ensure API data can populate plugin fields
6. ✅ **Configuration**: Support manual overrides for edge cases

**Result**: Fully automated plugin selection that follows existing NetMRI patterns while being intelligent enough to adapt to vendor-specific API structures.
