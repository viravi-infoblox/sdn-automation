package NetMRI::SDN::VeloCloud;

use strict;
use warnings;

use NetMRI::HTTP::Client::VeloCloud;
use Data::Dumper;
use HTTP::Date qw(str2time);
use NetMRI::Util::Date;
use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    my %args = @_;
    my $self = $class->SUPER::new(%args);

    $self->{vendor_name} = $args{vendor_name} || 'VeloCloud';
    $self->{api_helper_class} ||= 'NetMRI::HTTP::Client::VeloCloud';

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

sub _generated_organizations {
    my $self = shift;
    my $ctx = $self->{generated_collection_context};
    return [] unless ref($ctx) eq 'HASH';
    return $ctx->{organizations} if ref($ctx->{organizations}) eq 'ARRAY';
    return [];
}

sub _generated_networks {
    my $self = shift;
    my $ctx = $self->{generated_collection_context};
    return [] unless ref($ctx) eq 'HASH';
    return $ctx->{networks} if ref($ctx->{networks}) eq 'ARRAY';
    return [];
}

sub _generated_extract_dn_context {
    my ($self, $dn) = @_;
    my @parts = split m{/}, ($dn || '');
    return {
        org_id => $parts[0] || '',
        site_id => $parts[1] || '',
        device_id => $parts[2] || '',
    };
}

sub _generated_api_args_from_organization {
    my ($self, $organization, $placeholders) = @_;
    return () unless ref($organization) eq 'HASH';
    $placeholders = [] unless ref($placeholders) eq 'ARRAY';

    my %candidates = (
        org_id => $organization->{org_id} || $organization->{organization_id} || $organization->{id} || '',
    );

    my %args;
    foreach my $placeholder (@$placeholders) {
        my $value = $candidates{$placeholder};
        return () unless defined $value && length $value;
        $args{$placeholder} = $value;
    }
    return %args;
}

sub _generated_api_args_from_network {
    my ($self, $network, $placeholders) = @_;
    return () unless ref($network) eq 'HASH';
    $placeholders = [] unless ref($placeholders) eq 'ARRAY';

    my %candidates = (
        org_id => $network->{org_id} || $network->{organization_id} || '',
        site_id => $network->{site_id} || $network->{id} || '',
    );

    my %args;
    foreach my $placeholder (@$placeholders) {
        my $value = $candidates{$placeholder};
        return () unless defined $value && length $value;
        $args{$placeholder} = $value;
    }
    return %args;
}

sub _generated_api_args_from_device {
    my ($self, $sdn_device, $placeholders) = @_;
    return () unless ref($sdn_device) eq 'HASH';
    $placeholders = [] unless ref($placeholders) eq 'ARRAY';

    my $dn_ctx = $self->_generated_extract_dn_context($sdn_device->{SdnDeviceDN} || $sdn_device->{dn} || '');
    my %candidates = (
        org_id => $sdn_device->{org_id} || $dn_ctx->{org_id} || '',
        site_id => $sdn_device->{site_id} || $dn_ctx->{site_id} || '',
        device_id => $sdn_device->{device_id} || $sdn_device->{SdnDeviceID} || $dn_ctx->{device_id} || '',
        client_mac => $sdn_device->{client_mac} || $sdn_device->{SdnDeviceMac} || $sdn_device->{mac} || '',
    );

    my %args;
    foreach my $placeholder (@$placeholders) {
        my $value = $candidates{$placeholder};
        return () unless defined $value && length $value;
        $args{$placeholder} = $value;
    }
    return %args;
}


sub obtainEverything {
    my $self = shift;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEverything: started");
    my $collection_context = $self->obtainOrganizationsAndNetworks();
    $self->{generated_collection_context} = $collection_context if ref($collection_context) eq 'HASH';
    $self->obtainDevices();
    my $sdn_devices = $self->loadSdnDevices();
    return unless $sdn_devices;
    $self->obtainSystemInfo($sdn_devices);
    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainEverything: finished");
}

sub obtainOrganizationsAndNetworks {
    my $self = shift;

    $self->{logger}->info("VeloCloud[$self->{fabric_id}] obtainOrganizationsAndNetworks: started");
    my $fabric_id = $self->{fabric_id};
    my @organization_rows;
    my @sdn_network_rows;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$fabric_id] obtainOrganizationsAndNetworks: Error getting the API Client");
        return { organizations => [], networks => [] };
    }

    # -----------------------------------------------------------------------
    # 1. Get enterprises (= organizations)
    #    GET /api/sdwan/v2/enterprises/
    #    Key fields: logicalId, id (numeric), name
    # -----------------------------------------------------------------------
    my ($ent_res, $ent_err) = $self->api_v2_get_enterprises();
    if ($ent_err) {
        $self->{logger}->error("VeloCloud[$fabric_id] obtainOrganizationsAndNetworks: "
            . "enterprises fetch failed: $ent_err");
        return { organizations => [], networks => [] };
    }

    my $enterprises = ref($ent_res) eq 'HASH' ? ($ent_res->{data} || []) : $ent_res;
    $enterprises = [] unless ref($enterprises) eq 'ARRAY';

    foreach my $ent (@$enterprises) {
        next unless ref($ent) eq 'HASH';

        my $ent_logical_id = $ent->{logicalId} || next;
        my $ent_name       = $ent->{name}       || '';

        # Organization row for SaveVeloCloudOrganizations (id, name, fabric_id).
        push @organization_rows, {
            id                => $ent_logical_id,
            name              => $ent_name,
            fabric_id         => $fabric_id,
            enterprise_int_id => $ent->{id},    # numeric ID for v1 portal calls
        };

        # -------------------------------------------------------------------
        # 2. Get edges for this enterprise to extract unique sites (= networks)
        #    GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges/
        #    Each edge carries: site._href → .../sites/{siteLogicalId}
        # -------------------------------------------------------------------
        my ($edge_res, $edge_err) = $self->api_v2_get_enterprise_edges(
            enterpriseLogicalId => $ent_logical_id,
        );
        if ($edge_err) {
            $self->{logger}->warn("VeloCloud[$fabric_id] obtainOrganizationsAndNetworks: "
                . "edges fetch failed for enterprise $ent_logical_id: $edge_err");
            next;
        }

        my $edges = ref($edge_res) eq 'HASH' ? ($edge_res->{data} || []) : $edge_res;
        $edges = [] unless ref($edges) eq 'ARRAY';

        # De-duplicate sites by site _href (each edge references one site).
        my %seen_sites;
        foreach my $edge (@$edges) {
            next unless ref($edge) eq 'HASH';
            my $site_href = ref($edge->{site}) eq 'HASH' ? $edge->{site}{_href} : '';
            next unless $site_href;

            # Extract siteLogicalId from _href: .../sites/{siteLogicalId}
            my ($site_id) = $site_href =~ m{/sites/([^/]+)};
            next unless defined $site_id && length $site_id;
            next if $seen_sites{$site_id}++;

            # Build a site display name from the edge's description or name.
            # All edges at the same site share the site_href, so first one wins.
            my $site_name = $edge->{description} || $edge->{name} || $site_id;

            push @sdn_network_rows, {
                sdn_network_key  => "$ent_logical_id/$site_id",
                sdn_network_name => "$ent_name/$site_name",
                fabric_id        => $fabric_id,
            };
        }

        $self->{logger}->info("VeloCloud[$fabric_id] obtainOrganizationsAndNetworks: "
            . "enterprise '$ent_name' — " . scalar(@$edges) . " edges, "
            . scalar(keys %seen_sites) . " unique sites");
    }

    $self->saveVeloCloudOrganizations(\@organization_rows) if @organization_rows;
    $self->saveSdnNetworks(\@sdn_network_rows) if @sdn_network_rows;

    $self->{logger}->info("VeloCloud[$fabric_id] obtainOrganizationsAndNetworks: "
        . scalar(@organization_rows) . " orgs, " . scalar(@sdn_network_rows) . " networks saved");
    $self->{logger}->info("VeloCloud[$fabric_id] obtainOrganizationsAndNetworks: finished");
    return { organizations => \@organization_rows, networks => \@sdn_network_rows };
}

sub getDevices {
    my $self = shift;

    my $fabric_id = $self->{fabric_id};
    $self->{logger}->info("VeloCloud[$fabric_id] getDevices: started");
    my @devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("VeloCloud[$fabric_id] getDevices: Error getting the API Client");
        return [];
    }

    # Check if offline devices should be collected.
    my $settings_rec = $self->{sql}->record(
        "select collect_offline_devices from " . $self->{config_db}
        . ".sdn_controller_settings where id = " . $self->{sql}->escape($fabric_id),
        RefWanted => 1, AllowNoRows => 1,
    );
    my $collect_offline = $settings_rec->{collect_offline_devices} || 0;

    my $organizations = $self->_generated_organizations();

    foreach my $org (@$organizations) {
        next unless ref($org) eq 'HASH';
        my $ent_logical_id = $org->{id}        || next;
        my $ent_int_id     = $org->{enterprise_int_id};
        my $ent_name       = $org->{name}       || '';

        # ------------------------------------------------------------------
        # v2: Get all edges for this enterprise
        # Returns: logicalId, name, serialNumber, modelNumber, deviceFamily,
        #   selfMacAddress, softwareVersion, edgeState, systemUpSince, modified
        # Does NOT return ipAddress.
        # ------------------------------------------------------------------
        my ($edge_res, $edge_err) = $self->api_v2_get_enterprise_edges(
            enterpriseLogicalId => $ent_logical_id,
        );
        if ($edge_err) {
            $self->handle_error($edge_res, "getDevices/edges($ent_name)", 'Devices');
            next;
        }
        my $edges = ref($edge_res) eq 'HASH' ? ($edge_res->{data} || []) : $edge_res;
        $edges = ref($edges) eq 'ARRAY' ? $edges : [];

        # ------------------------------------------------------------------
        # v1: Bulk edge status — single POST returns ipAddress for all edges
        # POST /portal/ method=enterprise/getEnterpriseEdgeStatus
        # Returns: array of {edgeId, logicalId, ipAddress, ...}
        # ------------------------------------------------------------------
        my %ip_by_logical_id;
        if (defined $ent_int_id) {
            my ($status_res, $status_err) = $self->api_v1_get_enterprise_edge_status(
                enterpriseId => $ent_int_id,
            );
            if ($status_err) {
                $self->{logger}->warn("VeloCloud[$fabric_id] getDevices: "
                    . "v1 edge status failed for '$ent_name': $status_err");
            } else {
                my $statuses = ref($status_res) eq 'ARRAY' ? $status_res : [];
                foreach my $s (@$statuses) {
                    next unless ref($s) eq 'HASH' && $s->{logicalId};
                    $ip_by_logical_id{$s->{logicalId}} = $s->{ipAddress} || '';
                }
                $self->{logger}->info("VeloCloud[$fabric_id] getDevices: "
                    . "v1 edge status returned " . scalar(keys %ip_by_logical_id) . " IPs");
            }
        } else {
            $self->{logger}->warn("VeloCloud[$fabric_id] getDevices: "
                . "no numeric enterprise ID for '$ent_name', cannot fetch v1 edge status");
        }

        # ------------------------------------------------------------------
        # Build SaveDevices rows — join v2 edge data with v1 IP addresses
        # ------------------------------------------------------------------
        my $edge_count = 0;
        foreach my $edge (@$edges) {
            next unless ref($edge) eq 'HASH';
            my $logical_id = $edge->{logicalId} || next;

            # Map v2 edgeState to normalized DeviceStatus.
            my $edge_state = lc($edge->{edgeState} || 'offline');
            my $device_status;
            if ($edge_state eq 'connected') {
                $device_status = 'connected';
            } elsif ($edge_state eq 'degraded') {
                $device_status = 'degraded';
            } else {
                $device_status = 'offline';
            }

            # Skip offline devices unless configured to collect them.
            unless ($collect_offline) {
                if ($device_status eq 'offline') {
                    $self->{logger}->debug("VeloCloud[$fabric_id] getDevices: "
                        . "skipping offline edge $logical_id ($edge->{name})");
                    next;
                }
            }

            # IP address from v1 edge status (v2 does not provide it).
            my $ip = $ip_by_logical_id{$logical_id} || '';
            unless ($ip) {
                $self->{logger}->debug("VeloCloud[$fabric_id] getDevices: "
                    . "no IP for edge $logical_id ($edge->{name}), skipping");
                next;
            }

            push @devices, {
                SdnControllerId => $fabric_id,
                SdnDeviceDN     => "$ent_logical_id/$logical_id",
                IPAddress       => $ip,
                SdnDeviceMac    => $edge->{selfMacAddress} || '',   # NOT macAddress
                DeviceStatus    => $device_status,
                Name            => $edge->{name} || '',
                NodeRole        => 'VeloCloud Edge',
                Vendor          => $self->{vendor_name},
                Model           => $edge->{modelNumber} || '',
                Serial          => $edge->{serialNumber} || '',
                SWVersion       => $edge->{softwareVersion} || '',
                modTS           => NetMRI::Util::Date::formatDate(
                                       str2time($edge->{modified} || '') || time()
                                   ),
                UpTime          => _compute_uptime_secs($edge->{systemUpSince}),
            };
            $edge_count++;
        }

        $self->{logger}->info("VeloCloud[$fabric_id] getDevices: "
            . "enterprise '$ent_name' — " . scalar(@$edges) . " edges from API, "
            . "$edge_count accepted");
    }

    $self->{logger}->info("VeloCloud[$fabric_id] getDevices: " . scalar(@devices) . " total devices");
    $self->{logger}->info("VeloCloud[$fabric_id] getDevices: finished");
    return \@devices;
}

# Convert an ISO timestamp (e.g., "2025-06-23T10:51:30.000Z") to uptime in seconds.
sub _compute_uptime_secs {
    my ($system_up_since) = @_;
    return 0 unless defined $system_up_since && length $system_up_since;
    my $up_epoch = str2time($system_up_since);
    return 0 unless defined $up_epoch;
    my $uptime_secs = time() - $up_epoch;
    return $uptime_secs > 0 ? $uptime_secs : 0;
}

sub obtainSystemInfo {
    my ($self, $sdn_devices) = @_;

    my $fabric_id = $self->{fabric_id};
    $self->{logger}->info("VeloCloud[$fabric_id] obtainSystemInfo: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH';
        next unless $dev->{DeviceID};

        my $device_id = $dev->{DeviceID};
        $self->{dn} = $dev->{SdnDeviceDN};
        $self->{device_info_loaded} = 0;

        # Compute reboot time from uptime (stored in seconds by getDevices).
        my $pRebootTime;
        if ($dev->{UpTime} && $dev->{UpTime} > 0) {
            $pRebootTime = NetMRI::Util::Date::formatDate(time() - int($dev->{UpTime}));
        }

        # SystemInfo hash.
        my $device = {
            LastTimeStamp   => NetMRI::Util::Date::formatDate(time()),
            Name            => $dev->{Name} || '',
            Vendor          => $dev->{Vendor} || $self->{vendor_name},
            Model           => $dev->{Model} || '',
            DeviceMAC       => $dev->{SdnDeviceMac} || '',
            DeviceStatus    => $dev->{DeviceStatus} || '',
            SWVersion       => $dev->{SWVersion} || '',
            SdnControllerId => $dev->{SdnControllerId} || '',
            IPAddress       => $dev->{IPAddress} || '',
            UpTime          => (defined $dev->{UpTime}) ? ($dev->{UpTime} * 100) : 0,
        };

        # ---- Device Properties ----
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];

        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'sysModel', '', 'SNMP'], $dev->{Model})
            if $dev->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'sysName', '', 'SNMP'], $self->_remove_utf8($dev->{Name}))
            if $dev->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'sysVendor', '', 'SNMP'], $self->{vendor_name});
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'sysVersion', '', 'SNMP'], $dev->{SWVersion} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'DeviceMAC', '', 'SNMP'], $dev->{SdnDeviceMac} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{SdnControllerId})
            if $dev->{SdnControllerId};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset,
            [$device_id, 'pRebootTime', '', 'SNMP'], $pRebootTime)
            if defined $pRebootTime;

        # ---- Inventory — single chassis entry ----
        my $timestamp = NetMRI::Util::Date::formatDate(time());
        $self->saveInventory({
            DeviceID               => $device_id,
            entPhysicalIndex       => 1,
            entPhysicalClass       => 'chassis',
            entPhysicalDescr       => 'VeloCloud Edge',
            entPhysicalName        => $dev->{Name} || '',
            entPhysicalSerialNum   => $dev->{Serial} || 'N/A',
            entPhysicalModelName   => $dev->{Model} || '',
            entPhysicalFirmwareRev => $dev->{SWVersion} || 'VeloCloud OS',
            entPhysicalSoftwareRev => $dev->{SWVersion} || '',
            entPhysicalMfgName     => $self->{vendor_name},
            StartTime              => $timestamp,
            EndTime                => $timestamp,
        });

        # ---- Persist ----
        $self->saveSystemInfo($device);

        # ---- Reachability ----
        if ($dev->{DeviceStatus} && ($dev->{DeviceStatus} eq 'connected' || $dev->{DeviceStatus} eq 'degraded')) {
            $self->setReachable();
        } else {
            $self->setUnreachable();
        }

        $self->updateDataCollectionStatus('System', 'OK', $device_id);
        $self->updateDataCollectionStatus('Inventory', 'OK', $device_id);
    }

    $self->{logger}->info("VeloCloud[$fabric_id] obtainSystemInfo: "
        . scalar(@$sdn_devices) . " devices processed");
    $self->{logger}->info("VeloCloud[$fabric_id] obtainSystemInfo: finished");
}

sub api_v2_get_enterprises {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_enterprises(%args);
}

sub api_v2_get_enterprise_edges {
    my ($self, %args) = @_;
    return $self->getApiClient()->v2_get_enterprise_edges(%args);
}

sub api_v1_get_edge_interface_metrics {
    my ($self, %args) = @_;
    return $self->getApiClient()->v1_get_edge_interface_metrics(%args);
}

sub api_v1_get_enterprise_edge_status {
    my ($self, %args) = @_;
    return $self->getApiClient()->v1_get_enterprise_edge_status(%args);
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
