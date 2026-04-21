package NetMRI::SDN::VeloCloud;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use Date::Parse;
use NetMRI::SDN::Base;
use NetMRI::Util::Date;
use NetMRI::Util::Network qw(netmaskFromPrefix maskStringFromPrefix InetAddr);
use NetMRI::Util::Wildcard::V4;
use NetAddr::IP;
use Net::IP;
use base 'NetMRI::SDN::Base';

# VeloCloud SD-WAN Orchestrator — SDN Controller module.
#
# Collection flow:
#   1. obtainOrganizationsAndNetworks  → enterprises  → SaveVeloCloudOrganizations, SaveSdnNetworks
#   2. obtainDevices (Base)            → edges        → SaveDevices
#   3. obtainSystemInfo                → edge detail  → SaveInventory, SaveSystemInfo, SaveDeviceProperty
#   4. obtainInterfaces                → edge detail  → SaveSdnFabricInterface, SaveIPAddress
#   5. obtainRoute                     → gateway      → SaveipRouteTable
#   6. obtainBgp                       → gateway      → SavebgpPeerTable

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{vendor_name} = 'VeloCloud';
    $self->{SaveDevices_unique_fieldname} = 'Serial';
    return bless $self, $class;
}

# -----------------------------------------------------------------------
# API Client accessor
# -----------------------------------------------------------------------

sub getApiClient {
    my $self = shift;
    unless (ref($self->{api_helper})) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] getApiClient: API client unavailable: $@");
        return undef;
    }
    return $self->{api_helper};
}

# -----------------------------------------------------------------------
# Database loaders
# -----------------------------------------------------------------------

# Load previously discovered enterprises from the VeloCloudOrganization table.
# VeloCloud enterprises are stored in that table (UUID logicalId format match).
sub loadOrganizations {
    my $self = shift;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] loadOrganizations: started");

    my $sql    = $self->{sql};
    my $plugin = $self->getPlugin('SaveVeloCloudOrganizations');
    my $table  = $plugin->target_table();
    unless ($table) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] loadOrganizations: SaveVeloCloudOrganizations target table is unavailable");
        return;
    }
    my $query  = 'SELECT DISTINCT id AS id, name FROM '
               . $table
               . ' WHERE fabric_id=' . $sql->escape($self->{fabric_id});

    my $orgs = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$orgs) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] loadOrganizations: no enterprises found for FabricID");
        return;
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] loadOrganizations: " . scalar(@$orgs) . " enterprises");
    $self->{logger}->debug(Dumper($orgs)) if $self->{logger}->{Debug};
    return $orgs;
}

# -----------------------------------------------------------------------
# Step 2 — Device Discovery
# -----------------------------------------------------------------------

# Build and persist SDN device rows from discovered organizations.
# Calls VeloCloud gateways endpoint per organization and saves via SaveDevices.

sub obtainDevices {
    my ($self, $organizations) = @_;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainDevices: started");
    my $devices = $self->getDevices($organizations);
    $self->saveDevices($self->makeDevicesPoolWrapper($devices));
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainDevices: finished");
    return $devices;
}

# Load SDN devices from API
# Fetches gateways per organization and transforms into device format
sub getDevices {
    my ($self, $organizations) = @_;
    
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] getDevices: started");
    
    unless ($organizations && @$organizations) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] getDevices: no organizations provided");
        return [];
    }
    
    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] getDevices: no API client");
        return [];
    }
    
    my @devices;
    
    # Fetch gateways from each organization
    foreach my $org (@$organizations) {
        my $org_id = $org->{logicalId} || $org->{id};
        next unless $org_id;
        
        my ($gateways, $err);
        if ($api_helper->can('get_enterprise_edges')) {
            ($gateways, $err) = $api_helper->get_enterprise_edges($org_id);
        }
        elsif ($api_helper->can('get_gateways')) {
            # Backward-compatible path for older client implementations.
            ($gateways, $err) = $api_helper->get_gateways($org_id);
        }
        else {
            $self->{logger}->error("VeloCloud[$self->{fabric_id}] getDevices: client does not implement get_enterprise_edges/get_gateways");
            next;
        }
        if ($err) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] getDevices: failed to get gateways for org $org_id: $err");
            next;
        }
        
        next unless $gateways && @$gateways;
        
        foreach my $gateway (@$gateways) {
            push @devices, {
                SdnControllerId => $self->{fabric_id},
                IPAddress       => $gateway->{ipAddress} // '',
                SdnDeviceMac    => '',
                DeviceStatus    => lc($gateway->{edgeState} // 'unknown') eq 'connected' ? 'connected' : lc($gateway->{edgeState} // 'unknown'),
                SdnDeviceDN     => "$org_id/$gateway->{logicalId}",
                Name            => $gateway->{name},
                NodeRole        => 'VeloCloud Gateway',
                Vendor          => $gateway->{vendor} // $self->{vendor_name},
                Model           => $gateway->{model}           // '',
                Serial          => $gateway->{serialNumber}    // '',
                SWVersion       => $gateway->{softwareVersion} // '',
                modTS           => NetMRI::Util::Date::formatDate(time()),
            };
        }

        # Client device collection disabled for now
        # if ($api_helper->can('get_enterprise_client_devices')) {
        #     my ($client_devices, $cd_err) = $api_helper->get_enterprise_client_devices($org_id);
        #     if ($cd_err) {
        #         $self->{logger}->warn("VeloCloud[$self->{fabric_id}] getDevices: failed to get client devices for org $org_id: $cd_err");
        #     }
        #     elsif ($client_devices && @$client_devices) {
        #         foreach my $client (@$client_devices) {
        #             push @devices, {
        #                 SdnControllerId => $self->{fabric_id},
        #                 IPAddress       => $client->{ipAddress}        || '',
        #                 SdnDeviceMac    => $client->{macAddress}       || '',
        #                 DeviceStatus    => $client->{lastActive} ? 'connected' : 'unknown',
        #                 SdnDeviceDN     => "$org_id/$client->{logicalId}",
        #                 Name            => $client->{name}             || '',
        #                 NodeRole        => 'VeloCloud Client Device',
        #                 Vendor          => $client->{vendor}           || $self->{vendor_name},
        #                 Model           => $client->{model}            || '',
        #                 Serial          => $client->{serialNumber}     || '',
        #                 SWVersion       => $client->{operatingSystem}  || '',
        #                 modTS           => NetMRI::Util::Date::formatDate(time()),
        #             };
        #         }
        #     }
        # }
        # else {
        #     $self->{logger}->debug("VeloCloud[$self->{fabric_id}] getDevices: client does not implement get_enterprise_client_devices; skipping for org $org_id");
        # }
    }
    
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] getDevices: finished with " . scalar(@devices) . " devices");
    return \@devices;
}

# Load saved SDN devices for this fabric from the SaveDevices target table.
sub loadSdnDevices {
    my $self = shift;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] loadSdnDevices: started");

    my $sql    = $self->{sql};
    my $plugin = $self->getPlugin('SaveDevices');
    my $query;
    $self->{dn} //= '';

    if ($self->{dn} eq '') {
        $query = 'SELECT * FROM ' . $plugin->target_table()
               . ' WHERE SdnControllerId=' . $sql->escape($self->{fabric_id});
    }
    else {
        $query = 'SELECT * FROM ' . $plugin->target_table()
               . ' WHERE SdnDeviceDN='    . $sql->escape($self->{dn})
               . '   AND SdnControllerId=' . $sql->escape($self->{fabric_id});
    }

    my $devices = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$devices) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] loadSdnDevices: no devices found for FabricID");
        return;
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] loadSdnDevices: " . scalar(@$devices) . " devices");
    $self->{logger}->debug(Dumper($devices)) if $self->{logger}->{Debug};
    return $devices;
}

# -----------------------------------------------------------------------
# Top-level orchestration
# -----------------------------------------------------------------------

sub obtainEverything {
    my $self = shift;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEverything: started");

    my $organizations = $self->obtainOrganizationsAndNetworks();
    return unless $organizations;
    
    $self->obtainDevices($organizations);

    my $sdn_devices = $self->loadSdnDevices();
    return unless $sdn_devices;
    
    $self->obtainSystemInfo($sdn_devices);
    #$self->obtainInterfaces($sdn_devices);
    #$self->obtainRoute($sdn_devices);
    #$self->obtainBgp($sdn_devices);

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEverything: finished");
}

# -----------------------------------------------------------------------
# Step 1 — Enterprises / Organizations
# -----------------------------------------------------------------------

# Calls GET /api/sdwan/v2/enterprises/ and persists:
#   - each enterprise as a VeloCloudOrganization row (UUID logicalId format)
#   - a corresponding SdnNetwork row for virtual-network mapping
sub obtainOrganizationsAndNetworks {
    my $self = shift;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: no API client");
        return;
    }

    my ($enterprises, $err) = $api_helper->get_enterprises();
    unless (defined $enterprises) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: get_enterprises failed: " . ($err // ''));
        return;
    }

    $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: received " . scalar(@$enterprises) . " enterprises");
    $self->{logger}->debug(Dumper($enterprises)) if $self->{logger}->{Debug};

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@org_rows, @sdn_net_rows);

    foreach my $ent (@$enterprises) {
        next unless ref($ent) eq 'HASH';
        next unless $ent->{logicalId} && $ent->{name};

        push @org_rows, {
            id        => $ent->{logicalId},
            name      => Encode::decode('UTF-8', $ent->{name}, Encode::FB_DEFAULT),
            fabric_id => $self->{fabric_id},
            StartTime => $timestamp,
            EndTime   => $timestamp,
        };

        push @sdn_net_rows, {
            sdn_network_key    => $ent->{logicalId},
            sdn_network_name   => $ent->{name},
            fabric_id          => $self->{fabric_id},
            StartTime          => $timestamp,
            EndTime            => $timestamp,
        };
    }

    if (@org_rows) {
        $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: saving " . scalar(@org_rows) . " organizations");
        $self->saveVeloCloudOrganizations(\@org_rows);
    }

    if (@sdn_net_rows) {
        $self->saveSdnNetworks(\@sdn_net_rows);
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: finished");
    return $enterprises;
}

# -----------------------------------------------------------------------
# Step 3 — System Info, Inventory, Device Properties
# -----------------------------------------------------------------------

# For each loaded SDN device, persist inventory chassis row and device properties.
# Edge detail is re-fetched from the enterprise/edges already stored in device record.
sub obtainSystemInfo {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainSystemInfo: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainSystemInfo: no API client");
        return;
    }

    my $timestamp = NetMRI::Util::Date::formatDate(time());

    my (@inventory_rows);
    my $dp         = $self->getPlugin('SaveDeviceProperty');
    my $dp_fields  = [qw(DeviceID PropertyName PropertyIndex Source)];

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        my $device_id = $dev->{DeviceID};
        $self->{dn} = $dev->{SdnDeviceDN};
        my $detail = $self->_load_cached_device_detail($dev) || $dev;

        # Persist basic system identity via SaveSystemInfo
        my $system_info = {
            DeviceID       => $device_id,
            Name           => $detail->{Name},
            Vendor         => $detail->{Vendor},
            Model          => $detail->{Model}    // '',
            DeviceMAC      => $detail->{SdnDeviceMac} // '',
            DeviceStatus   => $detail->{DeviceStatus},
            SWVersion      => $detail->{SWVersion}    // '',
            IPAddress      => $detail->{IPAddress},
            LastTimeStamp  => $timestamp,
            SdnControllerId => $dev->{SdnControllerId},
        };
        $self->saveSystemInfo($system_info);
        $self->updateDataCollectionStatus('System', 'OK', $device_id);

        # Device properties (shown in NetMRI device detail panel)
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysName',    '', 'SNMP'], $self->_remove_utf8($detail->{Name}))    if $detail->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysModel',   '', 'SNMP'], $detail->{Model})    if $detail->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysVendor',  '', 'SNMP'], $detail->{Vendor})   if $detail->{Vendor};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysVersion', '', 'SNMP'], $detail->{SWVersion}) if $detail->{SWVersion};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'DeviceMAC',  '', 'SNMP'], $detail->{SdnDeviceMac}) if $detail->{SdnDeviceMac};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{SdnControllerId}) if $dev->{SdnControllerId};

        # Inventory chassis row
        push @inventory_rows, {
            DeviceID               => $device_id,
            entPhysicalIndex       => '1',
            entPhysicalClass       => 'chassis',
            entPhysicalDescr       => $detail->{NodeRole} // '',
            entPhysicalName        => $detail->{Name},
            entPhysicalFirmwareRev => $detail->{SWVersion} // 'VeloCloud OS',
            entPhysicalSoftwareRev => $detail->{SWVersion} // '',
            entPhysicalSerialNum   => $detail->{Serial} // 'N/A',
            entPhysicalMfgName     => $detail->{Vendor} // '',
            entPhysicalModelName   => $detail->{Model} // '',
            entPhysicalAlias       => $detail->{logicalId} // '',
            entPhysicalAssetID     => $detail->{deviceId} // '',
            UnitState              => $detail->{DeviceStatus} // '',
            StartTime              => $timestamp,
            EndTime                => $timestamp,
        };
    }

    if (@inventory_rows) {
        $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainSystemInfo: saving " . scalar(@inventory_rows) . " inventory rows");
        $self->saveInventory(\@inventory_rows);
        $self->updateDataCollectionStatus('Inventory', 'OK');
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainSystemInfo: finished");
}

# -----------------------------------------------------------------------
# Step 4 — Interfaces
# -----------------------------------------------------------------------

# For each Edge device, persist interface config + IP address rows.
# Interface data comes from the edge object stored in the edges API response.
# Gateway-level interface detail is obtained from get_gateway_details().
sub obtainInterfaces {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainInterfaces: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainInterfaces: no API client");
        return;
    }

    my $timestamp  = NetMRI::Util::Date::formatDate(time());
    my $intf_plugin = $self->getPlugin('SaveSdnFabricInterface');

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        next unless $dev->{NodeRole} eq 'VeloCloud Edge';   # only edges have gateway interface data

        my $device_id    = $dev->{DeviceID};
        my $sdn_device_id = $dev->{SdnDeviceID};
        $self->{dn}      = $dev->{SdnDeviceDN};

        # DN format: {enterpriseLogicalId}/{edgeLogicalId}
        my (undef, $edge_logical_id) = split m{/}, $dev->{SdnDeviceDN}, 2;
        unless ($edge_logical_id) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainInterfaces: cannot determine gatewayLogicalId from DN=$dev->{SdnDeviceDN}");
            next;
        }

        my ($gw, $err) = $api_helper->get_gateway_details($edge_logical_id);
        unless (defined $gw) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainInterfaces: get_gateway_details failed for $edge_logical_id: " . ($err // ''));
            next;
        }

        $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainInterfaces: received gateway detail for $edge_logical_id");
        $self->{logger}->debug(Dumper($gw)) if $self->{logger}->{Debug};

        my $interfaces = $gw->{interfaces};
        unless (ref($interfaces) eq 'ARRAY' && @$interfaces) {
            $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainInterfaces: no interfaces for $edge_logical_id");
            next;
        }

        my (@intf_rows, @ip_rows);
        my $if_index = 1;

        foreach my $intf (@$interfaces) {
            next unless ref($intf) eq 'HASH' && $intf->{name};

            my $oper_status  = lc($intf->{operationalStatus} // $intf->{status} // 'unknown');
            my $admin_status = lc($intf->{adminStatus} // ($intf->{adminUp} ? 'up' : 'down'));
            my $speed_bps    = _parse_bandwidth_bps($intf->{bandwidthUp} // $intf->{speed} // 0);

            push @intf_rows, {
                SdnDeviceID => $sdn_device_id,
                Name        => $intf->{name},
                Descr       => $intf->{description} // $intf->{name},
                MAC         => $intf->{macAddress}   // '',
                Mtu         => $intf->{mtu}           // 1500,
                adminStatus => $admin_status,
                operStatus  => $oper_status,
                operSpeed   => $speed_bps || undef,
                Type        => 'ethernet-csmacd',
                Timestamp   => $timestamp,
            };

            # IP address row for this interface
            if ($intf->{ipAddress}) {
                my $ip_dotted    = $intf->{ipAddress};
                my $mask_dotted  = $intf->{subnetMask} // _prefix_to_mask($intf->{cidr});
                my $ip_num       = InetAddr($ip_dotted);
                my $mask_num     = InetAddr($mask_dotted) if $mask_dotted;
                my $subnet_num;
                if ($ip_num && $mask_num) {
                    eval {
                        require Math::BigInt;
                        $subnet_num = Math::BigInt->new("$ip_num")->band(Math::BigInt->new("$mask_num"));
                    };
                    $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainInterfaces: subnet calc error for $ip_dotted: $@") if $@;
                }

                push @ip_rows, {
                    DeviceID         => $device_id,
                    Timestamp        => $timestamp,
                    IPAddress        => $ip_num,
                    IPAddressDotted  => $ip_dotted,
                    ifIndex          => $if_index,
                    NetMask          => $mask_num // 0,
                    SubnetIPNumeric  => $subnet_num // 0,
                };
            }

            $if_index++;
        }

        if (@intf_rows) {
            $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainInterfaces: saving " . scalar(@intf_rows) . " interfaces for $edge_logical_id");
            $self->saveSdnFabricInterface(\@intf_rows);
            $self->updateDataCollectionStatus('Interface', 'OK', $device_id);
        }

        if (@ip_rows) {
            $self->saveIPAddress(\@ip_rows);
        }
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainInterfaces: finished");
}

# -----------------------------------------------------------------------
# Step 5 — IP Routing Table
# -----------------------------------------------------------------------

sub obtainRoute {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainRoute: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainRoute: no API client");
        return;
    }

    my $timestamp  = NetMRI::Util::Date::formatDate(time());
    my $intf_plugin = $self->getPlugin('SaveSdnFabricInterface');

    my @route_rows;

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        next unless $dev->{NodeRole} eq 'VeloCloud Edge';

        my $device_id = $dev->{DeviceID};
        $self->{dn}   = $dev->{SdnDeviceDN};

        my (undef, $edge_logical_id) = split m{/}, $dev->{SdnDeviceDN}, 2;
        unless ($edge_logical_id) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainRoute: cannot parse gateway ID from DN=$dev->{SdnDeviceDN}");
            next;
        }

        my ($gw, $err) = $api_helper->get_gateway_details($edge_logical_id);
        unless (defined $gw) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainRoute: get_gateway_details failed for $edge_logical_id: " . ($err // ''));
            $self->handle_error($err, 'obtainRoute', 'Route');
            next;
        }

        my $ip_routes = $gw->{ipRoutes};
        unless (ref($ip_routes) eq 'ARRAY' && @$ip_routes) {
            $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainRoute: no ipRoutes for $edge_logical_id");
            next;
        }

        $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainRoute: " . scalar(@$ip_routes) . " routes for $edge_logical_id");
        $self->{logger}->debug(Dumper($ip_routes)) if $self->{logger}->{Debug};

        my $row_id = 1;
        foreach my $rt (@$ip_routes) {
            next unless ref($rt) eq 'HASH';

            # destination may be CIDR "10.0.0.0/24" or separate fields
            my ($dest_str, $prefix_len) = _parse_cidr($rt->{destination});
            next unless defined $dest_str;

            my $mask_str  = maskStringFromPrefix("$dest_str/$prefix_len");
            my $mask_num  = netmaskFromPrefix('ipv4', $prefix_len);
            my $dest_num  = InetAddr($dest_str) // 0;
            my $nh_str    = $rt->{nextHop} // '';
            my $nh_num    = ($nh_str ? InetAddr($nh_str) : 0) // 0;
            my $if_name   = $rt->{interface} // $rt->{ifName} // '';
            my $if_index  = ($if_name ? $self->getInterfaceIndex($if_name) : 0) || 0;
            my $protocol  = lc($rt->{protocol} // 'other');
            my $route_type = ($protocol eq 'static' || $protocol eq 'connected') ? 'local' : 'remote';

            push @route_rows, {
                RowID             => $row_id++,
                DeviceID          => $device_id,
                StartTime         => $timestamp,
                EndTime           => $timestamp,
                ipRouteDestStr    => $dest_str,
                ipRouteDestNum    => $dest_num,
                ipRouteMaskStr    => $mask_str // '',
                ipRouteMaskNum    => $mask_num // 0,
                ipRouteNextHopStr => $nh_str,
                ipRouteNextHopNum => $nh_num,
                ifDescr           => $if_name,
                ipRouteIfIndex    => $if_index,
                ipRouteProto      => $protocol,
                ipRouteType       => $route_type,
                ipRouteMetric1    => $rt->{metric}  // -1,
                ipRouteMetric2    => -1,
            };
        }
    }

    if (@route_rows) {
        $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainRoute: saving " . scalar(@route_rows) . " route rows");
        $self->saveipRouteTable(\@route_rows);
        $self->updateDataCollectionStatus('Route', 'OK');
    }
    else {
        $self->updateDataCollectionStatus('Route', 'N/A');
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainRoute: finished");
}

# -----------------------------------------------------------------------
# Step 6 — BGP Peer Table
# -----------------------------------------------------------------------

sub obtainBgp {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainBgp: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainBgp: no API client");
        return;
    }

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my @bgp_rows;

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        next unless $dev->{NodeRole} eq 'VeloCloud Edge';

        my $device_id = $dev->{DeviceID};
        $self->{dn}   = $dev->{SdnDeviceDN};

        my (undef, $edge_logical_id) = split m{/}, $dev->{SdnDeviceDN}, 2;
        unless ($edge_logical_id) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainBgp: cannot parse gateway ID from DN=$dev->{SdnDeviceDN}");
            next;
        }

        my ($gw, $err) = $api_helper->get_gateway_details($edge_logical_id);
        unless (defined $gw) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainBgp: get_gateway_details failed for $edge_logical_id: " . ($err // ''));
            next;
        }

        my $bgp_peers = $gw->{bgpPeers};
        unless (ref($bgp_peers) eq 'ARRAY' && @$bgp_peers) {
            $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainBgp: no BGP peers for $edge_logical_id");
            next;
        }

        $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainBgp: " . scalar(@$bgp_peers) . " BGP peers for $edge_logical_id");
        $self->{logger}->debug(Dumper($bgp_peers)) if $self->{logger}->{Debug};

        foreach my $peer (@$bgp_peers) {
            next unless ref($peer) eq 'HASH';
            next unless $peer->{peerIp} && $peer->{asn};

            # Map VeloCloud peer state to BGP FSM state string
            my $state = _map_bgp_state($peer->{state});

            push @bgp_rows, {
                DeviceID                  => $device_id,
                StartTime                 => $timestamp,
                EndTime                   => $timestamp,
                bgpPeerRemoteAddr         => $peer->{peerIp},
                bgpPeerRemoteAs           => $peer->{asn},
                bgpPeerRemotePort         => $peer->{remotePort}   // 179,
                bgpPeerLocalAddr          => $peer->{localIp}      // '',
                bgpPeerLocalPort          => $peer->{localPort}     // 179,
                bgpPeerState              => $state,
                bgpPeerFsmEstablishedTime => $peer->{uptime} // 0,
                bgpPeerEntryStatus        => $state eq 'established' ? 'active' : 'notInService',
            };
        }
    }

    if (@bgp_rows) {
        $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainBgp: saving " . scalar(@bgp_rows) . " BGP peer rows");
        $self->savebgpPeerTable(\@bgp_rows);
        $self->updateDataCollectionStatus('BGP', 'OK');
    }
    else {
        $self->updateDataCollectionStatus('BGP', 'N/A');
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainBgp: finished");
}

# -----------------------------------------------------------------------
# Private utility methods
# -----------------------------------------------------------------------

sub _load_cached_device_detail {
    my ($self, $dev) = @_;
    return unless ref($dev) eq 'HASH' && $dev->{SdnDeviceDN};
    return $self->{device_detail_cache}->{ $dev->{SdnDeviceDN} };
}

sub _pick_device_identifier {
    my ($self, $device) = @_;
    return unless ref($device) eq 'HASH';

    foreach my $field (qw(
        ipAddress
        managementIp
        primaryIpAddress
        deviceIp
        systemIp
        hostIp
        wanIp
        lanIp
        publicIp
        privateIpAddress
    )) {
        next unless defined $device->{$field};
        return $device->{$field} if $device->{$field} ne '';
    }

    foreach my $field (qw(logicalId id)) {
        next unless defined $device->{$field};
        return $device->{$field} if $device->{$field} ne '';
    }

    return;
}

# Parse a CIDR string like "10.0.0.0/24" or just "10.0.0.0" (default /32).
# Returns ($dest_addr_str, $prefix_len) or (undef, undef) on failure.
sub _parse_cidr {
    my $cidr = shift // '';
    if ($cidr =~ m{^([\d.]+)/(\d+)$}) {
        return ($1, $2);
    }
    elsif ($cidr =~ m{^([\d.]+)$}) {
        return ($1, 32);
    }
    return (undef, undef);
}

# Convert a CIDR prefix length to a dotted-decimal mask string.
sub _prefix_to_mask {
    my $cidr = shift // '';
    my (undef, $len) = _parse_cidr($cidr);
    return undef unless defined $len;
    return maskStringFromPrefix("0.0.0.0/$len");
}

# Convert bandwidth in Mbps (VeloCloud units) to bps (NetMRI storage units).
sub _parse_bandwidth_bps {
    my $mbps = shift // 0;
    return $mbps * 1_000_000 if $mbps =~ /^\d+(\.\d+)?$/;
    return 0;
}

# Map VeloCloud BGP peer state strings to RFC 4271 FSM state names.
sub _map_bgp_state {
    my $raw = lc(shift // '');
    my %map = (
        established => 'established',
        connect     => 'connect',
        active      => 'active',
        opensent    => 'openSent',
        openconfirm => 'openConfirm',
        idle        => 'idle',
    );
    return $map{$raw} // 'idle';
}

# Strip non-ASCII / problematic UTF-8 characters from name strings
# to avoid display issues in NetMRI (SDN-72).
sub _remove_utf8 {
    my ($self, $str) = @_;
    return '' unless defined $str;
    $str = Encode::encode('ASCII', $str, Encode::FB_DEFAULT);
    $str =~ s/[^[:print:]]//g;
    return $str;
}

1;
