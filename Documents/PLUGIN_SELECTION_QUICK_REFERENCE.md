# Plugin Selection - Quick Reference

## How the Agent Knows Which Plugin to Use

### TL;DR
The agent analyzes OpenAPI response schemas and automatically maps them to NetMRI plugins using pattern recognition and field matching.

---

## The Plugin Selection Process

```
OpenAPI Response → Pattern Analysis → Plugin Mapping → Code Generation
```

### Step 1: Analyze API Response Schema
```json
GET /devices/{id}/interfaces
Response: {
  "interfaces": [
    {
      "name": "eth0",
      "macAddress": "00:11:22:33:44:55",
      "status": "up",
      "speed": "1000"
    }
  ]
}
```

### Step 2: Pattern Recognition
- **Detects**: Array of interface objects
- **Key Fields**: name, macAddress, status, speed
- **Category**: Interface Data

### Step 3: Plugin Mapping
- **Matched Plugin**: `SaveSdnFabricInterface`
- **Confidence**: 90% (field coverage)

### Step 4: Generated Code
```perl
sub obtainInterfaces {
    my $self = shift;
    my ($data, $err) = $self->{api_helper}->get_interfaces($device_id);
    
    $self->saveSdnFabricInterface($transformed_data);
    #                    ▲
    #                    └── Auto-routes to SaveSdnFabricInterface plugin
}
```

---

## Plugin Mapping Rules

| API Response Contains | Plugin Selected |
|----------------------|-----------------|
| `id, name, model, serial` | `SaveDevices` |
| `version, uptime, model` | `SaveSystemInfo` |
| `interfaces, ports, name, mac` | `SaveSdnFabricInterface` |
| `lldp, neighbors, remoteDevice` | `SaveLLDP` |
| `cdp, neighbors, remotePort` | `SaveCDP` |
| `vlans, vlanId, name` | `SaveVlanObject` |
| `switchport, port, vlan` | `SaveSwitchPortObject` |
| `ssid, wireless, radio` | `SaveWireless` |
| `clients, endpoints, mac` | `SaveSdnEndpoint` |
| `routes, nextHop, prefix` | `SaveipRouteTable` |

---

## Decision Criteria Weights

1. **Field Pattern Match** (40%) - Primary indicator
2. **Response Schema Complexity** (25%) - Plugin capability match
3. **Endpoint URL Pattern** (20%) - Context-based selection
4. **Device Type/Role** (15%) - Conditional plugins

---

## Example: Complete Flow

### Input: New Vendor OpenAPI Spec
```yaml
paths:
  /devices:
    get:
      responses:
        200:
          schema:
            type: array
            items:
              properties:
                id: string
                name: string
                model: string
                ipAddress: string
```

### Agent Processing:
1. ✅ Parses OpenAPI spec
2. ✅ Identifies `/devices` endpoint
3. ✅ Analyzes response schema
4. ✅ Detects device fields (id, name, model, ipAddress)
5. ✅ Maps to `SaveDevices` plugin (100% field match)
6. ✅ Generates `getDevices()` method
7. ✅ Generates `obtainDevices()` method
8. ✅ Registers plugin in `autoload_save_methods`

### Generated Code:
```perl
# Auto-generated
sub new {
    my $self = ...;
    $self->{autoload_save_methods}->{Devices} = 1;  # ← Plugin registered
}

sub getDevices {
    my ($devices, $err) = $self->{api_helper}->get_devices();
    return transform_to_netmri_format($devices);
}

sub obtainDevices {
    $self->saveDevices($self->getDevices());  # ← Auto-routes to SaveDevices
}
```

---

## Plugin Validation

The agent validates plugin selection by checking:

✅ **Field Coverage**: ≥80% of plugin's required fields available in API response  
✅ **Data Type Compatibility**: API field types match plugin expectations  
✅ **Transformation Feasibility**: Can convert API format to NetMRI format  

### Example Validation:
```
Plugin: SaveDevices
Required Fields: [SdnDeviceDN, Name, Model, IPAddress]
API Response Fields: [id, name, model, ipAddress]

Field Mapping:
  id → SdnDeviceDN ✓
  name → Name ✓
  model → Model ✓
  ipAddress → IPAddress ✓

Coverage: 100% ✓ PASS
```

---

## AUTOLOAD Magic

The NetMRI SDN framework uses Perl's `AUTOLOAD` to dynamically route plugin calls:

```perl
$self->saveDevices($data);
         ▼
    (method doesn't exist)
         ▼
    AUTOLOAD intercepts
         ▼
    Extract "Devices" from "saveDevices"
         ▼
    Call getPlugin('SaveDevices')
         ▼
    Load NetMRI::SDN::Plugins::SaveDevices
         ▼
    Execute $plugin->run($data)
```

**No manual routing needed!** The agent just generates the correct `save*` method calls.

---

## Configuration Override

Manual override supported for edge cases:

```yaml
# vendor_config.yaml
plugin_overrides:
  custom_endpoint:
    api_path: "/devices/{id}/special"
    force_plugin: "SaveCustomData"
    transformation: "custom_transform_function"
```

---

## Summary

**Q: How does the agent know which plugin to use?**

**A: Through intelligent analysis:**
1. Parses OpenAPI response schemas
2. Matches field patterns to plugin requirements
3. Validates field coverage (≥80% threshold)
4. Generates plugin registration code
5. Creates obtain* methods with correct save* calls
6. AUTOLOAD mechanism auto-routes to correct plugin

**Result**: Fully automated, zero manual configuration needed for standard patterns!

---

*See full documentation in: `Plugin_Selection_Strategy.md`*
