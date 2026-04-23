package NetMRI::SDN::Mist;

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
    $self->{vendor_name} = 'Juniper Mist';
    $self->{SaveDevices_unique_fieldname} = 'Serial';
    return bless $self, $class;
}

sub getApiClient {
    my $self = shift;
    my $api_helper = $self->SUPER::getApiClient();
    unless (ref($api_helper)) {
        $self->{logger}->error('Mist[' . ($self->{fabric_id} // '') . '] getApiClient: Error getting the API Client');
        return undef;
    }
    return $api_helper;
}

sub loadSdnDevices {
    my $self = shift;

    $self->{logger}->info('Mist[' . ($self->{fabric_id} // '') . '] loadSdnDevices: started');

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
        $self->{logger}->error('Mist[' . ($self->{fabric_id} // '') . '] loadSdnDevices: No devices for FabricID');
        return;
    }

    $self->{logger}->info('Mist[' . ($self->{fabric_id} // '') . '] loadSdnDevices: ' . scalar(@$sdn_devices) . ' entries');
    $self->{logger}->debug(Dumper($sdn_devices)) if ($self->{logger}->{Debug} && scalar(@$sdn_devices));
    $self->{logger}->info('Mist[' . ($self->{fabric_id} // '') . '] loadSdnDevices: finished');

    return $sdn_devices;
}



sub obtainEverything {
    my $self = shift;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEverything: started");
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
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEverything: finished");
}

sub obtainOrganizationsAndNetworks {
    my $self = shift;
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: no API client");
        return;
    }

    my ($enterprises, $err) = $api_helper->listinstallersites();
    unless (defined $enterprises) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: listinstallersites failed: " . ($err // ''));
        return;
    }

    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: received " . scalar(@$enterprises) . " enterprises");
    $self->{logger}->debug(Dumper($enterprises)) if $self->{logger}->{Debug};

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@org_rows, @sdn_net_rows);

    foreach my $ent (@$enterprises) {
        next unless ref($ent) eq 'HASH';
        next unless $ent->{'id'} && $ent->{'name'};

        push @org_rows, {
            id        => $ent->{'id'},
            name      => Encode::decode('UTF-8', $ent->{'name'}, Encode::FB_DEFAULT),
            fabric_id => $self->{fabric_id},
            StartTime => $timestamp,
            EndTime   => $timestamp,
        };

        push @sdn_net_rows, {
            sdn_network_key  => $ent->{'id'},
            sdn_network_name => $ent->{'name'},
            fabric_id        => $self->{fabric_id},
            StartTime        => $timestamp,
            EndTime          => $timestamp,
        };
    }

    if (@org_rows) {
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: saving " . scalar(@org_rows) . " organizations");
        $self->saveMistOrganizations(\@org_rows);
    }

    if (@sdn_net_rows) {
        $self->saveSdnNetworks(\@sdn_net_rows);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: finished");
    return $enterprises;
}

sub obtainDevices {
    my ($self, $organizations) = @_;
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainDevices: started");
    my $devices = $self->getDevices($organizations);
    $self->saveDevices($self->makeDevicesPoolWrapper($devices));
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainDevices: finished");
    return $devices;
}

sub getDevices {
    my ($self, $organizations) = @_;
    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getDevices: no API client");
        return [];
    }

    my ($gateways, $err) = $api_helper->getsitewirelessclientstats();
    unless (defined $gateways) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getDevices: getsitewirelessclientstats failed: " . ($err // ''));
        return [];
    }

    my @devices;
    foreach my $gw (@$gateways) {
            push @devices, {
                SdnControllerId => $self->{fabric_id},
                IPAddress       => $gw->{'ipAddress'} // '',
                SdnDeviceMac    => $gw->{''} // '',
                DeviceStatus    => lc($gw->{'status'} // 'unknown') eq 'connected' ? 'connected' : lc($gw->{'status'} // 'unknown'),
                SdnDeviceDN     => "$org_id/$gw->{'id'}",
                Name            => $gw->{'name'} // '',
                NodeRole        => 'Mist Gateway',
                Vendor          => $gw->{vendor} // $self->{vendor_name},
                Model           => $gw->{''}         // '',
                Serial          => $gw->{''}        // '',
                SWVersion       => $gw->{''}            // '',
                modTS           => NetMRI::Util::Date::formatDate(time()),
            };
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: finished with " . scalar(@devices) . " devices");
    return \@devices;
}

sub obtainSystemInfo {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainSystemInfo: started");
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
            entPhysicalFirmwareRev => $dev->{SWVersion}  // 'Mist OS',
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
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainSystemInfo: saving " . scalar(@inventory_rows) . " inventory rows");
        $self->saveInventory(\@inventory_rows);
        $self->updateDataCollectionStatus('Inventory', 'OK');
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainSystemInfo: finished");
}

sub obtainPerformance {
    my ($self, $sdn_devices) = @_;
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainPerformance: no API client");
        return;
    }

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@cpu_rows, @mem_rows);


    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{DeviceID};
        my $device_id = $dev->{DeviceID};

        my ($stats, $err) = $api_helper->countorgsworgwports();
        if ($err) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] obtainPerformance: countorgsworgwports failed: $err");
            next;
        }

        my $items = ref($stats) eq 'ARRAY' ? $stats : [$stats];
        foreach my $s (@$items) {
            next unless ref($s) eq 'HASH';

            if (defined $s->{''}) {
                push @cpu_rows, {
                    DeviceID  => $device_id,
                    StartTime => $timestamp,
                    EndTime   => $timestamp,
                    CpuIndex  => 1,
                    CpuBusy   => int($s->{''} // 0),
                };
            }

            if (defined $s->{''}) {
                my $total = $s->{''} || 0;
                my $free  = $s->{''} // 0;
                my $used  = $s->{''} // ($total - $free);
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

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance: finished");
}

sub obtainEnvironment {
    my ($self, $sdn_devices) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;
    my $environment_rows = [];
    my $hr_storage_rows = [];

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainEnvironment: Error getting the API Client");
        return;
    }

    # Collect environmental and storage state for loaded devices.
    # Candidate API helpers for this dataset:
    # - $self->api_getsiteallclientsstatsbydevice(%args); # GET /api/v1/sites/{site_id}/stats/devices/{device_id}/clients [DeviceContext, DeviceCpuStats, Environmental, Inventory, VlanObject, ifPerf] path_params=[site_id, device_id]
    # - $self->api_listorgstatsdevices(%args); # GET /api/v1/orgs/{org_id}/stats/devices [Devices, SystemInfo, DeviceCpuStats, DeviceMemStats, Environmental, Inventory, ifConfig, ifPerf] path_params=[org_id]
    # Persist transformed rows using:
    # - saveEnvironmental
    # - savehrStorageTable

    foreach my $sdn_device (@$sdn_devices) {
        next unless ref($sdn_device) eq 'HASH';

        # Use device fields such as SdnDeviceDN, SdnDeviceMac, DeviceID, or IPAddress to build API arguments.
        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['site_id', 'device_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_getsiteallclientsstatsbydevice(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_listorgstatsdevices(%api_args);
    }

    $self->saveEnvironmental($environment_rows) if ref($environment_rows) eq 'ARRAY' && @$environment_rows;
    $self->savehrStorageTable($hr_storage_rows) if ref($hr_storage_rows) eq 'ARRAY' && @$hr_storage_rows;
    $self->{logger}->warn("Mist[$self->{fabric_id}] obtainEnvironment: generated skeleton requires vendor-specific transforms");
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: finished");
    return;
}

sub obtainInterfaces {
    my ($self, $sdn_devices) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: started");
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
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainInterfaces: Error getting the API Client");
        return;
    }

    # Collect interface, switchport, and VLAN datasets for loaded devices.
    # Candidate API helpers for this dataset:
    # - $self->api_countorgsworgwports(%args); # GET /api/v1/orgs/{org_id}/stats/ports/count [CDP, Firewall, Forwarding, LLDP, SwitchPortObject, VlanTrunkPortTable, VrfHasInterface, dot1dBasePortTable, ifConfig] path_params=[org_id]
    # - $self->api_getorgnetworktemplate(%args); # GET /api/v1/orgs/{org_id}/networktemplates/{networktemplate_id} [MistOrganizations, RoutingPerfObject, SdnFabricInterface, SdnNetworks, VrfHasRTCommunity, VrfRoute] path_params=[org_id, networktemplate_id]
    # - $self->api_downloadorgnacportalsamlmetadata(%args); # GET /api/v1/orgs/{org_id}/nacportals/{nacportal_id}/saml_metadata.xml [ifStatus] path_params=[org_id, nacportal_id]
    # - $self->api_getsiteallclientsstatsbydevice(%args); # GET /api/v1/sites/{site_id}/stats/devices/{device_id}/clients [DeviceContext, DeviceCpuStats, Environmental, Inventory, VlanObject, ifPerf] path_params=[site_id, device_id]
    # - $self->api_listorgstatsdevices(%args); # GET /api/v1/orgs/{org_id}/stats/devices [Devices, SystemInfo, DeviceCpuStats, DeviceMemStats, Environmental, Inventory, ifConfig, ifPerf] path_params=[org_id]
    # - $self->api_searchorgsworgwports(%args); # GET /api/v1/orgs/{org_id}/stats/ports/search [ifConfig, ifStatus, ifPerf, SdnFabricInterface, SwitchPortObject, LLDP, CDP] path_params=[org_id]
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
        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_countorgsworgwports(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id', 'networktemplate_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_getorgnetworktemplate(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id', 'nacportal_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_downloadorgnacportalsamlmetadata(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['site_id', 'device_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_getsiteallclientsstatsbydevice(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_listorgstatsdevices(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_searchorgsworgwports(%api_args);
    }

    $self->saveifConfig($if_config_rows) if ref($if_config_rows) eq 'ARRAY' && @$if_config_rows;
    $self->saveifStatus($if_status_rows) if ref($if_status_rows) eq 'ARRAY' && @$if_status_rows;
    $self->saveifPerf($if_perf_rows) if ref($if_perf_rows) eq 'ARRAY' && @$if_perf_rows;
    $self->saveSwitchPortObject($switch_port_rows) if ref($switch_port_rows) eq 'ARRAY' && @$switch_port_rows;
    $self->saveSdnFabricInterface($sdn_fabric_interface_rows) if ref($sdn_fabric_interface_rows) eq 'ARRAY' && @$sdn_fabric_interface_rows;
    $self->saveVlanObject($vlan_rows) if ref($vlan_rows) eq 'ARRAY' && @$vlan_rows;
    $self->saveVlanTrunkPortTable($vlan_trunk_rows) if ref($vlan_trunk_rows) eq 'ARRAY' && @$vlan_trunk_rows;
    $self->savedot1dBasePortTable($dot1d_base_port_rows) if ref($dot1d_base_port_rows) eq 'ARRAY' && @$dot1d_base_port_rows;
    $self->{logger}->warn("Mist[$self->{fabric_id}] obtainInterfaces: generated skeleton requires vendor-specific transforms");
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: finished");
    return;
}

sub obtainTopologyAndEndpoints {
    my ($self, $sdn_devices) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainTopologyAndEndpoints: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;
    my $lldp_rows = [];
    my $cdp_rows = [];
    my $sdn_endpoint_rows = [];
    my $mist_sdn_endpoint_rows = [];
    my $bsn_ap_rows = [];
    my $bsn_mobile_station_rows = [];

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainTopologyAndEndpoints: Error getting the API Client");
        return;
    }

    # Collect topology, AP, and endpoint visibility datasets.
    # Candidate API helpers for this dataset:
    # - $self->api_getsitewirelessclientstats(%args); # GET /api/v1/sites/{site_id}/stats/clients/{client_mac} [MistSdnEndpoint, SdnEndpoint, bsnAPTable, bsnMobileStationTable] path_params=[site_id, client_mac]
    # - $self->api_countorgsworgwports(%args); # GET /api/v1/orgs/{org_id}/stats/ports/count [CDP, Firewall, Forwarding, LLDP, SwitchPortObject, VlanTrunkPortTable, VrfHasInterface, dot1dBasePortTable, ifConfig] path_params=[org_id]
    # - $self->api_searchorgsworgwports(%args); # GET /api/v1/orgs/{org_id}/stats/ports/search [ifConfig, ifStatus, ifPerf, SdnFabricInterface, SwitchPortObject, LLDP, CDP] path_params=[org_id]
    # - $self->api_searchorgdevices(%args); # GET /api/v1/orgs/{org_id}/devices/search [LLDP, CDP] path_params=[org_id]
    # - $self->api_getsiteclientsstats(%args); # GET /api/v1/sites/{site_id}/stats/clients [MistSdnEndpoint, SdnEndpoint, bsnMobileStationTable] path_params=[site_id]
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
        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['site_id', 'client_mac']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_getsitewirelessclientstats(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_countorgsworgwports(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_searchorgsworgwports(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['org_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_searchorgdevices(%api_args);

        my %api_args = $self->_generated_api_args_from_device($sdn_device, ['site_id']);
        next unless %api_args;
        # my ($res, $msg) = $self->api_getsiteclientsstats(%api_args);
    }

    $self->saveLLDP($lldp_rows) if ref($lldp_rows) eq 'ARRAY' && @$lldp_rows;
    $self->saveCDP($cdp_rows) if ref($cdp_rows) eq 'ARRAY' && @$cdp_rows;
    $self->saveSdnEndpoint($sdn_endpoint_rows) if ref($sdn_endpoint_rows) eq 'ARRAY' && @$sdn_endpoint_rows;
    $self->saveMistSdnEndpoint($mist_sdn_endpoint_rows) if ref($mist_sdn_endpoint_rows) eq 'ARRAY' && @$mist_sdn_endpoint_rows;
    $self->savebsnAPTable($bsn_ap_rows) if ref($bsn_ap_rows) eq 'ARRAY' && @$bsn_ap_rows;
    $self->savebsnMobileStationTable($bsn_mobile_station_rows) if ref($bsn_mobile_station_rows) eq 'ARRAY' && @$bsn_mobile_station_rows;
    $self->{logger}->warn("Mist[$self->{fabric_id}] obtainTopologyAndEndpoints: generated skeleton requires vendor-specific transforms");
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainTopologyAndEndpoints: finished");
    return;
}

sub api_listinstallersites {
    my ($self, %args) = @_;
    return $self->getApiClient()->listinstallersites(%args);
}

sub api_getsitewirelessclientstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->getsitewirelessclientstats(%args);
}

sub api_countorgsworgwports {
    my ($self, %args) = @_;
    return $self->getApiClient()->countorgsworgwports(%args);
}

sub api_getorgnetworktemplate {
    my ($self, %args) = @_;
    return $self->getApiClient()->getorgnetworktemplate(%args);
}

sub api_listorgavailabledeviceversions {
    my ($self, %args) = @_;
    return $self->getApiClient()->listorgavailabledeviceversions(%args);
}

sub api_getorgsettings {
    my ($self, %args) = @_;
    return $self->getApiClient()->getorgsettings(%args);
}

sub api_countorgwirelessclientssessions {
    my ($self, %args) = @_;
    return $self->getApiClient()->countorgwirelessclientssessions(%args);
}

sub api_getorginventory {
    my ($self, %args) = @_;
    return $self->getApiClient()->getorginventory(%args);
}

sub api_downloadorgnacportalsamlmetadata {
    my ($self, %args) = @_;
    return $self->getApiClient()->downloadorgnacportalsamlmetadata(%args);
}

sub api_getsiteallclientsstatsbydevice {
    my ($self, %args) = @_;
    return $self->getApiClient()->getsiteallclientsstatsbydevice(%args);
}

sub api_getsitestats {
    my ($self, %args) = @_;
    return $self->getApiClient()->getsitestats(%args);
}

sub api_listsiteunconnectedclientstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->listsiteunconnectedclientstats(%args);
}

sub api_showsitedeviceforwardingtable {
    my ($self, %args) = @_;
    return $self->getApiClient()->showsitedeviceforwardingtable(%args);
}

sub api_getapiv1self {
    my ($self, %args) = @_;
    return $self->getApiClient()->getapiv1self(%args);
}

sub api_listorgstatsdevices {
    my ($self, %args) = @_;
    return $self->getApiClient()->listorgstatsdevices(%args);
}

sub api_listorgstatsmxedges {
    my ($self, %args) = @_;
    return $self->getApiClient()->listorgstatsmxedges(%args);
}

sub api_searchorgsworgwports {
    my ($self, %args) = @_;
    return $self->getApiClient()->searchorgsworgwports(%args);
}

sub api_searchorgdevices {
    my ($self, %args) = @_;
    return $self->getApiClient()->searchorgdevices(%args);
}

sub api_getsiteclientsstats {
    my ($self, %args) = @_;
    return $self->getApiClient()->getsiteclientsstats(%args);
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
    my $err_text = 'Mist ' . $datapoint . ' failed';
    $err_text .= ' for device ' . $self->{dn} if defined $self->{dn} && length $self->{dn};
    $err_text .= ": " . Dumper($resp) if defined $resp;
    $self->{logger}->warn($err_text) if $self->{logger};

    if ($dataset && $self->can('updateDataCollectionStatus')) {
        $self->updateDataCollectionStatus($dataset, 'Error');
    }
}

1;
