package NetMRI::SDN::VeloCloud;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use NetMRI::SDN::Base;
use NetMRI::Util::Date;
use NetMRI::Util::Network qw(netmaskFromPrefix maskStringFromPrefix InetAddr);
use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{vendor_name} = 'VeloCloud';
    $self->{SaveDevices_unique_fieldname} = 'Serial';
    return bless $self, $class;
}

sub getApiClient {
    my $self = shift;
    my $api_helper = $self->SUPER::getApiClient();
    unless (ref($api_helper)) {
        $self->{logger}->error('VeloCloud[' . ($self->{fabric_id} // '') . '] getApiClient: Error getting the API Client');
        return undef;
    }
    return $api_helper;
}

sub loadSdnDevices {
    my $self = shift;

    $self->{logger}->info('VeloCloud[' . ($self->{fabric_id} // '') . '] loadSdnDevices: started');

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveDevices');
    my $query;

    $self->{dn} = '' unless defined $self->{dn};

    if ($self->{dn} eq '') {
        $query = 'select * from ' . $device_plugin->target_table() . ' where SdnControllerId=' . $sql->escape($self->{fabric_id});
    }
    else {
        $query = 'select * from ' . $device_plugin->target_table() . ' where SdnDeviceDN = ' . $sql->escape($self->{dn}) . ' and SdnControllerId=' . $sql->escape($self->{fabric_id});
    }

    my $sdn_devices = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$sdn_devices) {
        $self->{logger}->error('VeloCloud[' . ($self->{fabric_id} // '') . '] loadSdnDevices: No devices for FabricID');
        return;
    }

    $self->{logger}->info('VeloCloud[' . ($self->{fabric_id} // '') . '] loadSdnDevices: ' . scalar(@$sdn_devices) . ' entries');
    $self->{logger}->debug(Dumper($sdn_devices)) if ($self->{logger}->{Debug} && scalar(@$sdn_devices));
    $self->{logger}->info('VeloCloud[' . ($self->{fabric_id} // '') . '] loadSdnDevices: finished');

    return $sdn_devices;
}



sub obtainEverything {
    my $self = shift;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEverything: started");
    my $organizations = $self->obtainOrganizationsAndNetworks();
    return unless $organizations;
    $self->obtainDevices($organizations);
    my $sdn_devices = $self->loadSdnDevices();
    return unless $sdn_devices;
    $self->obtainSystemInfo($sdn_devices);
    $self->obtainPerformance($sdn_devices);
    $self->obtainEnvironment($sdn_devices);
    $self->obtainInterfaces($sdn_devices);
    $self->obtainTopologyAndEndpoints($sdn_devices);
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEverything: finished");
}

sub obtainOrganizationsAndNetworks {
    my $self = shift;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: no API client");
        return;
    }

    my ($enterprises, $err) = $api_helper->v2_list_enterprises();
    unless (defined $enterprises) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: v2_list_enterprises failed: " . ($err // ''));
        return;
    }

    $self->{logger}->debug("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: received " . scalar(@$enterprises) . " enterprises");
    $self->{logger}->debug(Dumper($enterprises)) if $self->{logger}->{Debug};

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@org_rows, @sdn_net_rows);

    foreach my $ent (@$enterprises) {
        next unless ref($ent) eq 'HASH';
        next unless $ent->{'logicalId'} && $ent->{'name'};

        push @org_rows, {
            id        => $ent->{'logicalId'},
            name      => Encode::decode('UTF-8', $ent->{'name'}, Encode::FB_DEFAULT),
            fabric_id => $self->{fabric_id},
            StartTime => $timestamp,
            EndTime   => $timestamp,
        };

        push @sdn_net_rows, {
            sdn_network_key  => $ent->{'logicalId'},
            sdn_network_name => $ent->{'name'},
            fabric_id        => $self->{fabric_id},
            StartTime        => $timestamp,
            EndTime          => $timestamp,
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

sub obtainDevices {
    my ($self, $organizations) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainDevices: started");
    my $devices = $self->getDevices($organizations);
    $self->saveDevices($self->makeDevicesPoolWrapper($devices));
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainDevices: finished");
    return $devices;
}

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

    foreach my $org (@$organizations) {
        my $org_id = $org->{logicalId} || $org->{id};
        next unless $org_id;

        my ($gateways, $err) = $api_helper->v2_list_enterprise_client_devices($org_id);
        if ($err) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] getDevices: v2_list_enterprise_client_devices failed for org $org_id: $err");
            next;
        }
        next unless $gateways && @$gateways;

        foreach my $gw (@$gateways) {
            push @devices, {
                SdnControllerId => $self->{fabric_id},
                IPAddress       => $gw->{'ipAddress'} // '',
                SdnDeviceMac    => $gw->{'macAddress'} // '',
                DeviceStatus    => lc($gw->{'status'} // 'unknown') eq 'connected' ? 'connected' : lc($gw->{'status'} // 'unknown'),
                SdnDeviceDN     => "$org_id/$gw->{'logicalId'}",
                Name            => $gw->{'name'} // '',
                NodeRole        => 'VeloCloud Gateway',
                Vendor          => $gw->{vendor} // $self->{vendor_name},
                Model           => $gw->{'model'}         // '',
                Serial          => $gw->{'serialNumber'}        // '',
                SWVersion       => $gw->{'osVersion'}            // '',
                modTS           => NetMRI::Util::Date::formatDate(time()),
            };
        }
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] getDevices: finished with " . scalar(@devices) . " devices");
    return \@devices;
}

sub obtainSystemInfo {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainSystemInfo: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my $dp        = $self->getPlugin('SaveDeviceProperty');
    my $dp_fields = [qw(DeviceID PropertyName PropertyIndex Source)];
    my @inventory_rows;

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        my $device_id = $dev->{DeviceID};
        $self->{dn} = $dev->{SdnDeviceDN};

        my $system_info = {
            DeviceID        => $device_id,
            Name            => $dev->{Name},
            Vendor          => $dev->{Vendor},
            Model           => $dev->{Model}          // '',
            DeviceMAC       => $dev->{SdnDeviceMac}   // '',
            DeviceStatus    => $dev->{DeviceStatus},
            SWVersion       => $dev->{SWVersion}       // '',
            IPAddress       => $dev->{IPAddress},
            LastTimeStamp   => $timestamp,
            SdnControllerId => $dev->{SdnControllerId},
        };
        $self->saveSystemInfo($system_info);
        $self->updateDataCollectionStatus('System', 'OK', $device_id);

        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysName',    '', 'SNMP'], $self->_remove_utf8($dev->{Name}))    if $dev->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysModel',   '', 'SNMP'], $dev->{Model})    if $dev->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysVendor',  '', 'SNMP'], $dev->{Vendor})   if $dev->{Vendor};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysVersion', '', 'SNMP'], $dev->{SWVersion}) if $dev->{SWVersion};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'DeviceMAC',  '', 'SNMP'], $dev->{SdnDeviceMac}) if $dev->{SdnDeviceMac};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{SdnControllerId}) if $dev->{SdnControllerId};

        push @inventory_rows, {
            DeviceID               => $device_id,
            entPhysicalIndex       => '1',
            entPhysicalClass       => 'chassis',
            entPhysicalDescr       => $dev->{NodeRole}   // '',
            entPhysicalName        => $dev->{Name},
            entPhysicalFirmwareRev => $dev->{SWVersion}  // 'VeloCloud OS',
            entPhysicalSoftwareRev => $dev->{SWVersion}  // '',
            entPhysicalSerialNum   => $dev->{Serial}     // 'N/A',
            entPhysicalMfgName     => $dev->{Vendor}     // '',
            entPhysicalModelName   => $dev->{Model}      // '',
            UnitState              => $dev->{DeviceStatus} // '',
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

sub obtainPerformance {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainPerformance: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainPerformance: no API client");
        return;
    }

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@cpu_rows, @mem_rows);

    my %dn_to_org;
    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{SdnDeviceDN};
        my ($org_part) = split m{/}, $dev->{SdnDeviceDN}, 2;
        $dn_to_org{$dev->{SdnDeviceDN}} = $org_part if $org_part;
    }

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        my $device_id = $dev->{DeviceID};
        my $org_id = $dn_to_org{$dev->{SdnDeviceDN}} // '';

        my (undef, $edge_logical_id) = split m{/}, $dev->{SdnDeviceDN}, 2;
        unless ($edge_logical_id) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainPerformance: cannot parse edge ID from DN=$dev->{SdnDeviceDN}");
            next;
        }

        my ($stats, $err) = $api_helper->v2_get_edge_healthstats($org_id, $edge_logical_id);
        if ($err) {
            $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainPerformance: v2_get_edge_healthstats failed: $err");
            next;
        }

        my $items = ref($stats) eq 'ARRAY' ? $stats : [$stats];
        foreach my $s (@$items) {
            next unless ref($s) eq 'HASH';

            if (defined $s->{'cpuPct'}) {
                push @cpu_rows, {
                    DeviceID  => $device_id,
                    StartTime => $timestamp,
                    EndTime   => $timestamp,
                    CpuIndex  => 1,
                    CpuBusy   => int($s->{'cpuPct'} // 0),
                };
            }

            if (defined $s->{'memoryTotalMB'}) {
                my $total = $s->{'memoryTotalMB'} || 0;
                my $free  = $s->{'memoryFreeMB'} // 0;
                my $used  = $s->{'memoryUsageMB'} // ($total - $free);
                my $util  = $total ? int(($used / $total) * 100) : 0;
                push @mem_rows, {
                    DeviceID       => $device_id,
                    StartTime      => $timestamp,
                    EndTime        => $timestamp,
                    UsedMem        => $used * 1024 * 1024,
                    FreeMem        => $free * 1024 * 1024,
                    Utilization5Min => $util,
                };
            }
        }
    }

    if (@cpu_rows) {
        $self->saveDeviceCpuStats(\@cpu_rows);
        $self->updateDataCollectionStatus('CPU', 'OK');
    }
    if (@mem_rows) {
        $self->saveDeviceMemStats(\@mem_rows);
        $self->updateDataCollectionStatus('Memory', 'OK');
    }

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainPerformance: finished");
}

sub obtainEnvironment {
    my ($self, $sdn_devices) = @_;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEnvironment: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;
    my $environment_rows = [];
    my $hr_storage_rows = [];

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainEnvironment: Error getting the API Client");
        return;
    }

    # Collect environmental and storage state for loaded devices.
    # Candidate API helpers for this dataset:
    # - $self->api_v2_get_edge_healthstats(%args); # GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges/{edgeLogicalId}/healthStats [DeviceCpuStats, DeviceMemStats, Environmental] path_params=[enterpriseLogicalId, edgeLogicalId]
    # Persist transformed rows using:
    # - saveEnvironmental
    # - savehrStorageTable

    foreach my $sdn_device (@$sdn_devices) {
        next unless ref($sdn_device) eq 'HASH';

        # Use device fields such as SdnDeviceDN, SdnDeviceMac, DeviceID, or IPAddress to build API arguments.
        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['enterpriseLogicalId', 'edgeLogicalId']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_v2_get_edge_healthstats(%api_args);
    }

    $self->saveEnvironmental($environment_rows) if ref($environment_rows) eq 'ARRAY' && @$environment_rows;
    $self->savehrStorageTable($hr_storage_rows) if ref($hr_storage_rows) eq 'ARRAY' && @$hr_storage_rows;
    $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainEnvironment: generated skeleton requires vendor-specific transforms");
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEnvironment: finished");
    return;
}

sub obtainInterfaces {
    my ($self, $sdn_devices) = @_;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainInterfaces: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;
    my $if_config_rows = [];
    my $if_status_rows = [];
    my $if_perf_rows = [];
    my $switch_port_rows = [];
    my $sdn_fabric_interface_rows = [];
    my $vlan_rows = [];
    my $vlan_trunk_rows = [];
    my $dot1d_base_port_rows = [];

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainInterfaces: Error getting the API Client");
        return;
    }

    # Collect interface, switchport, and VLAN datasets for loaded devices.
    # Candidate API helpers for this dataset:
    # - $self->api_v2_list_enterprises(%args); # GET /api/sdwan/v2/enterprises/ [VeloCloudOrganizations, SdnNetworks, SdnFabricInterface, SwitchPortObject, ifConfig] path_params=[none]
    # - $self->api_v2_get_edge_flowstats(%args); # GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges/{edgeLogicalId}/flowStats [Forwarding, IPAddress, Inventory, Performance, SystemInfo, VrfARP, atObject, ifPerf] path_params=[enterpriseLogicalId, edgeLogicalId]
    # Persist transformed rows using:
    # - saveifConfig
    # - saveifStatus
    # - saveifPerf
    # - saveSwitchPortObject
    # - saveSdnFabricInterface
    # - saveVlanObject
    # - saveVlanTrunkPortTable
    # - savedot1dBasePortTable

    foreach my $sdn_device (@$sdn_devices) {
        next unless ref($sdn_device) eq 'HASH';

        # Use device fields such as SdnDeviceDN, SdnDeviceMac, DeviceID, or IPAddress to build API arguments.
        # my ($res, $msg) = $self->api_v2_list_enterprises();

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['enterpriseLogicalId', 'edgeLogicalId']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_v2_get_edge_flowstats(%api_args);
    }

    $self->saveifConfig($if_config_rows) if ref($if_config_rows) eq 'ARRAY' && @$if_config_rows;
    $self->saveifStatus($if_status_rows) if ref($if_status_rows) eq 'ARRAY' && @$if_status_rows;
    $self->saveifPerf($if_perf_rows) if ref($if_perf_rows) eq 'ARRAY' && @$if_perf_rows;
    $self->saveSwitchPortObject($switch_port_rows) if ref($switch_port_rows) eq 'ARRAY' && @$switch_port_rows;
    $self->saveSdnFabricInterface($sdn_fabric_interface_rows) if ref($sdn_fabric_interface_rows) eq 'ARRAY' && @$sdn_fabric_interface_rows;
    $self->saveVlanObject($vlan_rows) if ref($vlan_rows) eq 'ARRAY' && @$vlan_rows;
    $self->saveVlanTrunkPortTable($vlan_trunk_rows) if ref($vlan_trunk_rows) eq 'ARRAY' && @$vlan_trunk_rows;
    $self->savedot1dBasePortTable($dot1d_base_port_rows) if ref($dot1d_base_port_rows) eq 'ARRAY' && @$dot1d_base_port_rows;
    $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainInterfaces: generated skeleton requires vendor-specific transforms");
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainInterfaces: finished");
    return;
}

sub obtainTopologyAndEndpoints {
    my ($self, $sdn_devices) = @_;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainTopologyAndEndpoints: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;
    my $lldp_rows = [];
    my $cdp_rows = [];
    my $sdn_endpoint_rows = [];
    my $mist_sdn_endpoint_rows = [];
    my $bsn_ap_rows = [];
    my $bsn_mobile_station_rows = [];

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$self->{fabric_id}] obtainTopologyAndEndpoints: Error getting the API Client");
        return;
    }

    # Collect topology, AP, and endpoint visibility datasets.
    # Candidate API helpers for this dataset:
    # - $self->api_v2_get_edge_non_sdwan_tunnel_status(%args); # GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges/{edgeLogicalId}/nonSdWanTunnelStatus [Devices, bsnAPTable] path_params=[enterpriseLogicalId, edgeLogicalId]
    # - $self->api_v2_list_enterprise_client_devices(%args); # GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/clientDevices [SdnEndpoint, bsnMobileStationTable] path_params=[enterpriseLogicalId]
    # - $self->api_v2_get_enterprise_bgp_sessions(%args); # GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/bgpSessions [LLDP, bgpPeerTable] path_params=[enterpriseLogicalId]
    # Persist transformed rows using:
    # - saveLLDP
    # - saveCDP
    # - saveSdnEndpoint
    # - saveMistSdnEndpoint
    # - savebsnAPTable
    # - savebsnMobileStationTable

    foreach my $sdn_device (@$sdn_devices) {
        next unless ref($sdn_device) eq 'HASH';

        # Use device fields such as SdnDeviceDN, SdnDeviceMac, DeviceID, or IPAddress to build API arguments.
        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['enterpriseLogicalId', 'edgeLogicalId']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_v2_get_edge_non_sdwan_tunnel_status(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['enterpriseLogicalId']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_v2_list_enterprise_client_devices(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['enterpriseLogicalId']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_v2_get_enterprise_bgp_sessions(%api_args);
    }

    $self->saveLLDP($lldp_rows) if ref($lldp_rows) eq 'ARRAY' && @$lldp_rows;
    $self->saveCDP($cdp_rows) if ref($cdp_rows) eq 'ARRAY' && @$cdp_rows;
    $self->saveSdnEndpoint($sdn_endpoint_rows) if ref($sdn_endpoint_rows) eq 'ARRAY' && @$sdn_endpoint_rows;
    $self->saveMistSdnEndpoint($mist_sdn_endpoint_rows) if ref($mist_sdn_endpoint_rows) eq 'ARRAY' && @$mist_sdn_endpoint_rows;
    $self->savebsnAPTable($bsn_ap_rows) if ref($bsn_ap_rows) eq 'ARRAY' && @$bsn_ap_rows;
    $self->savebsnMobileStationTable($bsn_mobile_station_rows) if ref($bsn_mobile_station_rows) eq 'ARRAY' && @$bsn_mobile_station_rows;
    $self->{logger}->warn("VeloCloud[$self->{fabric_id}] obtainTopologyAndEndpoints: generated skeleton requires vendor-specific transforms");
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainTopologyAndEndpoints: finished");
    return;
}

sub api_v2_list_enterprises {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_list_enterprises(%args);
}

sub api_v2_get_edge_flowstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_edge_flowstats(%args);
}

sub api_v2_get_edge_non_sdwan_tunnel_status {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_edge_non_sdwan_tunnel_status(%args);
}

sub api_v2_get_edge_qos {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_edge_qos(%args);
}

sub api_v2_get_edge_linkqualitystats {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_edge_linkqualitystats(%args);
}

sub api_v2_list_enterprise_client_devices {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_list_enterprise_client_devices(%args);
}

sub api_v2_get_edge_healthstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_edge_healthstats(%args);
}

sub api_v2_get_enterprise_bgp_sessions {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_enterprise_bgp_sessions(%args);
}

sub api_v2_get_edge_firewallidpsstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_edge_firewallidpsstats(%args);
}

sub api_v2_get_enterprise_flowstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_enterprise_flowstats(%args);
}


sub _remove_utf8 {
    my ($self, $str) = @_;
    return '' unless defined $str;
    $str = Encode::encode('ASCII', $str, Encode::FB_DEFAULT);
    $str =~ s/[^[:print:]]//g;
    return $str;
}

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

sub _prefix_to_mask {
    my $cidr = shift // '';
    my (undef, $len) = _parse_cidr($cidr);
    return undef unless defined $len;
    return maskStringFromPrefix("0.0.0.0/$len");
}

sub _parse_bandwidth_bps {
    my $mbps = shift // 0;
    return $mbps * 1_000_000 if $mbps =~ /^\d+(\.\d+)?$/;
    return 0;
}

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


sub handle_error {
    my ($self, $resp, $datapoint, $dataset) = @_;
    my $err_text = 'VeloCloud ' . $datapoint . ' failed';
    $err_text .= ' for device ' . $self->{dn} if defined $self->{dn} && length $self->{dn};
    $err_text .= ": " . Dumper($resp) if defined $resp;
    $self->{logger}->warn($err_text) if $self->{logger};

    if ($dataset && $self->can('updateDataCollectionStatus')) {
        $self->updateDataCollectionStatus($dataset, 'Error');
    }
}

1;
