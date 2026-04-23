package NetMRI::SDN::Mist;
use strict;
use warnings;
use Encode;
use Date::Parse;
use NetMRI::Util::Network qw (netmaskFromPrefix InetAddr);
use NetMRI::Util::Wildcard::V4;
use Net::IP;
use NetAddr::IP;
use Socket;
use NetMRI::Util::Subnet qw (subnet_matcher);
use NetMRI::Util::Date;
use Data::Dumper;

use base 'NetMRI::SDN::Base';

my @orgDeviceTypes = qw( switch gateway ap );

sub new {
    my $class = shift;
    
    my $self = $class->SUPER::new(@_);
    $self->{vendor_name} = 'Juniper Mist';
    
    # Force endhost/AP collection on (bypass IgnoreMistAP config)
    $self->{cfg}->{IgnoreMistAP} = 'off';
    if (($self->{cfg}->{IgnoreMistAP} // 'off') eq 'on') {
        @orgDeviceTypes = grep { $_ ne 'ap' } @orgDeviceTypes;
    }

    return bless $self, $class;
}

sub loadOrganizations {
    my $self = shift;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] loadOrganizations: started");    

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveMistOrganizations');
    my $query = "select DISTINCT organization_id as id from " . $device_plugin->target_table() . " where fabric_id=" . $sql->escape($self->{fabric_id});
    my $orgs = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$orgs) {
        $self->{logger}->error("Mist[$self->{fabric_id}] loadOrganizations: No Organizations for FabricID ");
        return;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] loadOrganizations: " . scalar(@$orgs) . " organizations:");
    $self->{logger}->debug(Dumper(\@$orgs)) if ($self->{logger}->{Debug} && scalar(@$orgs));

    $self->{logger}->info("Mist[$self->{fabric_id}] loadOrganizations: finished");    

    return \@$orgs;
}

sub loadSites {
    my $self = shift;

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSites: started");    

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveMistNetworks');
    my $query = "select * from " . $device_plugin->target_table() . " where fabric_id=" . $sql->escape($self->{fabric_id});
    my $sites = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$sites) {
        $self->{logger}->error("Mist[$self->{fabric_id}] loadSites: No Sites for FabricID ");
        return;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSites: " . scalar(@$sites) . " entries:");
    $self->{logger}->debug(Dumper(\@$sites)) if ($self->{logger}->{Debug} && scalar(@$sites));

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSites: finished");    

    return \@$sites;
}

sub loadSdnDevices {
    my $self = shift;

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSdnDevices: started");    

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveDevices');
    my $query;

    $self->{dn} = '' unless defined $self->{dn};
    
    if ($self->{dn} eq '' ) {
        $query = "select * from " . $device_plugin->target_table() . " where SdnControllerId=" . $sql->escape($self->{fabric_id});
    } else {
        $query = "select * from " . $device_plugin->target_table() . " where SdnDeviceDN = " . $sql->escape($self->{dn}) . " and SdnControllerId=" . $sql->escape($self->{fabric_id});
    }
    my $sdnDevices = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$sdnDevices) {
        $self->{logger}->error("Mist[$self->{fabric_id}] loadSdnDevices: No devices for FabricID ");
        return;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSdnDevices: " . scalar(@$sdnDevices) . " entries:");
    $self->{logger}->debug(Dumper(\@$sdnDevices)) if ($self->{logger}->{Debug} && scalar(@$sdnDevices));

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSdnDevices: finished");    

    return \@$sdnDevices;
}

sub getDevices {
    my ($self, $orgs, $allEdgesStats, $orgDevices) = @_;
    
    my $statuses;
    my $msg;
    my @devices;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: started");

    my $settings_rec = $self->{sql}->record("select collect_offline_devices from " . $self->{config_db} . ".sdn_controller_settings where id = $self->{fabric_id}",
            RefWanted => 1, AllowNoRows => 1
    );

    foreach my $org (@$orgs) {
        next unless ($allEdgesStats->{$org->{id}});
        foreach my $edgeStats ($allEdgesStats->{$org->{id}}) {
            foreach my $edge (@$edgeStats) {
                next unless ($edge->{tunterm_ip_config}->{ip} || $edge->{oob_ip_config}->{ip}); # skip devices without IP address
                unless ($settings_rec->{collect_offline_devices}) {
                    if (! $edge->{tunterm_registered}) {
                        $self->{logger}->warn("Skipping device $edge->{org_id}/$edge->{site_id}/$edge->{id} is offline");
                        next;
                    }
                }
                my $SdnMac = join(':', $edge->{mac} =~ /../g);
                push @devices, {
                    SdnControllerId => $self->{fabric_id},
                	IPAddress => $edge->{tunterm_ip_config}->{ip} || $edge->{oob_ip_config}->{ip},
                    SdnDeviceMac => $SdnMac || '',
                    DeviceStatus => $edge->{tunterm_registered} ? 'connected' : 'disconnected',
                	SdnDeviceDN => "$edge->{org_id}/$edge->{site_id}/$edge->{id}",
                	Name => $edge->{name} || $SdnMac,
                	NodeRole => "MIST Edge",
                	Vendor => $self->{vendor_name},
                   	Model => $edge->{model},
                	Serial => $edge->{serial} || 'N/A',
                	SWVersion => "MIST OS",
                	modTS => NetMRI::Util::Date::formatTimestamp($edge->{modified_time}),
                	UpTime => $edge->{service_stat}->{tunterm}->{uptime}
                };
            }
        }
    }

    foreach my $org (@$orgs) {
        next unless ($orgDevices->{$org->{id}});
        foreach my $orgDevicesStats ($orgDevices->{$org->{id}}) {
            foreach my $orgDevice (@$orgDevicesStats) {
                next unless ($orgDevice->{ip}); #Skip devices without IP address
                unless ($settings_rec->{collect_offline_devices}) {
                    if ($orgDevice->{status} eq 'disconnected') {
                        $self->{logger}->warn("Skipping device $orgDevice->{org_id}/$orgDevice->{site_id}/$orgDevice->{id} is offline");
                        next;
                    }
                }
                my $SdnMac = join(':', $orgDevice->{mac} =~ /../g);
                push @devices, {
                    SdnControllerId => $self->{fabric_id},
                    IPAddress => $orgDevice->{ip},
                    SdnDeviceMac => $SdnMac || '',
                    DeviceStatus => $orgDevice->{status},
                    SdnDeviceDN => "$orgDevice->{org_id}/$orgDevice->{site_id}/$orgDevice->{id}",
                    Name => $orgDevice->{name} || $SdnMac,
                    NodeRole => "MIST $orgDevice->{type}",
                    Vendor => $self->{vendor_name},
                    Model => $orgDevice->{model},
                    Serial => $orgDevice->{serial},
                    SWVersion => $orgDevice->{version},
                    modTS => NetMRI::Util::Date::formatTimestamp($orgDevice->{modified_time}),
                    UpTime => $orgDevice->{uptime}
                }
            }
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: " . scalar(@devices) . " entries:");
    $self->{logger}->debug(Dumper(\@devices)) if ($self->{logger}->{Debug} && scalar (@devices));

    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: finished");

    return \@devices;
}

sub obtainDevices {
    my ($self, $orgs, $allEdgesStats, $orgDevices) = @_;
  
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainDevices: started");
    $self->saveDevices($self->makeDevicesPoolWrapper($self->getDevicesWrapper($orgs, $allEdgesStats, $orgDevices)));
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainDevices: finished");
}

sub getDevicesWrapper {
    my ($self, $orgs, $allEdgesStats, $orgDevices) = @_;
  
    $self->{logger}->debug("Mist[$self->{fabric_id}] getDevicesWrapper: started");
    my $res = $self->getDevices($orgs, $allEdgesStats, $orgDevices);
    $self->{logger}->debug("Mist[$self->{fabric_id}] getDevicesWrapper: finished");
    return $res;
}

sub obtainEverything {
    my $self = shift;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEverything: started");
    my $organizations = $self->obtainOrganizationsAndNetworks();
    return unless $organizations;
    my $allEdgesStats = $self->getMistEdges($organizations);
    my $orgDevices = $self->getOrganizationDevices($organizations);
    $self->obtainDevices($organizations, $allEdgesStats, $orgDevices);
    my $sdnDevices = $self->loadSdnDevices();
    return unless $sdnDevices;
    $self->obtainSystemInfo($sdnDevices);
    $self->obtainPerformance($sdnDevices, $organizations, $allEdgesStats, $orgDevices);  
    $self->obtainEnvironment($sdnDevices, $organizations, $orgDevices);
    $self->obtainInterfaces($sdnDevices, $organizations, $allEdgesStats, $orgDevices);
    $self->obtainLldpAP($sdnDevices, $organizations);
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEverything: finished");
}

sub obtainOrganizationsAndNetworks {
    my $self = shift;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: started");

    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: Error getting the Mist API Client");
        return;
    }

    my ($organizations, $msg) = $api_helper->get_self();
    unless ($organizations) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks/get_self: No data: " . ($msg||""));
        return;
    }

    my @sites;
    my @all_orgs;
    foreach my $org ($$organizations[0]->{"privileges"}) {
        foreach my $priv (@$org) {
            my %orgs = (
                id => $priv->{org_id},
                name => $priv->{name} // "",
                fabric_id => $self->{fabric_id}
            );
            push @all_orgs, \%orgs;

            my ($org_sites, $msg1) = $api_helper->get_sites($priv->{org_id});
            unless ($org_sites){
                $self->{logger}->warn("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks/get_sites: No data for Org $priv->{org_id}: " . ($msg1||""));
                next;
            }

            foreach my $nw (@$org_sites) {
                push @sites, {
                    id => $nw->{id},
                    name => $nw->{name},
                    organization_id => $nw->{org_id},
                    sdn_network_key => "$priv->{org_id}/$nw->{id}",
                    sdn_network_name => "$priv->{name}/$nw->{name}",
                    fabric_id => $self->{fabric_id},
                    StartTime => $start_time,
                    EndTime  => $end_time
                };
            }

            push @sites, {
                id => '00000000-0000-0000-0000-000000000000',
                name => 'Unassigned',
                organization_id => $priv->{org_id},
                sdn_network_key => "$priv->{org_id}/00000000-0000-0000-0000-000000000000",
                sdn_network_name => "$priv->{name}/Unassigned",
                fabric_id => $self->{fabric_id},
                StartTime => $start_time,
                EndTime  => $end_time
            };
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: Organizations " . scalar(@all_orgs) . " entries:");
    $self->{logger}->debug(Dumper(\@all_orgs)) if ($self->{logger}->{Debug} && scalar(@all_orgs));
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: Sites " . scalar(@sites) . " entries:");
    $self->{logger}->debug(Dumper(\@sites)) if ($self->{logger}->{Debug} && scalar(@sites));

    $self->saveMistOrganizations(\@all_orgs);
    $self->saveMistNetworks(\@sites);
    $self->saveSdnNetworks(\@sites);

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: finished");

    return \@all_orgs;
}

sub getMistEdges {
    my ($self, $orgs) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] getMistEdges: started");

    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getMistEdges: Error getting the Mist API Client");
        return;
    }

    my %allEdgesStats;
    my $allEdgesTotal = 0;

    foreach my $org (@$orgs) {
        my ($edges_stats, $msg) = $api_helper->get_edges_stats($org->{id});
        unless ($edges_stats){
            $self->{logger}->warn("Mist[$self->{fabric_id}] getMistEdges/get_edges_stats: No data for Org $org->{id}:" . ($msg||""));
            next;
        }

        my @new_edges_stats;

        while (my $e = pop @$edges_stats) {
            push @new_edges_stats, {
                (exists $e->{org_id}             ? (org_id             => $e->{org_id}) : ()),
                (exists $e->{site_id}            ? (site_id            => $e->{site_id}) : ()),
                (exists $e->{id}                 ? (id                 => $e->{id}) : ()),
                (exists $e->{mac}                ? (mac                => $e->{mac}) : ()),
                (exists $e->{tunterm_ip_config}  ? (tunterm_ip_config  => $e->{tunterm_ip_config}) : ()),
                (exists $e->{oob_ip_config}      ? (oob_ip_config      => $e->{oob_ip_config}) : ()),
                (exists $e->{tunterm_registered} ? (tunterm_registered => $e->{tunterm_registered}) : ()),
                (exists $e->{name}               ? (name               => $e->{name}) : ()),
                (exists $e->{model}              ? (model              => $e->{model}) : ()),
                (exists $e->{serial}             ? (serial             => $e->{serial}) : ()),
                (exists $e->{modified_time}      ? (modified_time      => $e->{modified_time}) : ()),
                (exists $e->{service_stat}       ? (service_stat       => $e->{service_stat}) : ()),
                (exists $e->{cpu_stat}           ? (cpu_stat           => $e->{cpu_stat}) : ()),
                (exists $e->{port_stat}          ? (port_stat          => $e->{port_stat}) : ()),
                (exists $e->{memory_stat}        ? (memory_stat        => $e->{memory_stat}) : ()),
            };
        }
        $edges_stats = \@new_edges_stats;

        $allEdgesStats{$org->{id}} = $edges_stats;
        $allEdgesTotal += scalar @$edges_stats;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getMistEdges: AllMistEdges  " . $allEdgesTotal . " entries:");
    $self->{logger}->debug(Dumper(\%allEdgesStats)) if ($self->{logger}->{Debug} && $allEdgesTotal);

    $self->{logger}->info("Mist[$self->{fabric_id}] getMistEdges: finished");

    return \%allEdgesStats;
}

sub getOrganizationDevices {
    my ($self, $orgs) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: started");    

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getOrganizationDevices: Error getting the Mist API Client");
        return;
    }

    my %orgDevices;
    my $orgDevicesTotal = 0;

    foreach my $org (@$orgs) {
        my @all_devices;
        foreach my $type (@orgDeviceTypes) {
            $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: start collecting type=$type");

            my ($devices, $msg) = $api_helper->get_organization_devices($org->{id}, { type => $type });
            unless ($devices) {
                $self->{logger}->warn("Mist[$self->{fabric_id}] getOrganizationDevices/get_organization_devices: No data for Org $org->{id}: " . ($msg||""));
                next;
            }

            my @new_devices;

            while (my $d = pop @$devices) {
                push @new_devices, {
                    (exists $d->{org_id}        ? (org_id        => $d->{org_id}) : ()),
                    (exists $d->{site_id}       ? (site_id       => $d->{site_id}) : ()),
                    (exists $d->{id}            ? (id            => $d->{id}) : ()),
                    (exists $d->{mac}           ? (mac           => $d->{mac}) : ()),
                    (exists $d->{ip}            ? (ip            => $d->{ip}) : ()),
                    (exists $d->{status}        ? (status        => $d->{status}) : ()),
                    (exists $d->{name}          ? (name          => $d->{name}) : ()),
                    (exists $d->{type}          ? (type          => $d->{type}) : ()),
                    (exists $d->{model}         ? (model         => $d->{model}) : ()),
                    (exists $d->{serial}        ? (serial        => $d->{serial}) : ()),
                    (exists $d->{version}       ? (version       => $d->{version}) : ()),
                    (exists $d->{modified_time} ? (modified_time => $d->{modified_time}) : ()),
                    (exists $d->{uptime}        ? (uptime        => $d->{uptime}) : ()),
                    (exists $d->{module_stat}   ? (module_stat   => $d->{module_stat}) : ()),
                    (exists $d->{cpu_stat}      ? (cpu_stat      => $d->{cpu_stat}) : ()),
                    (exists $d->{memory_stat}   ? (memory_stat   => $d->{memory_stat}) : ()),
                    (exists $d->{ip_config}     ? (ip_config     => $d->{ip_config}) : ()),
                    (exists $d->{if_stat}       ? (if_stat       => $d->{if_stat}) : ()),
                };
            }
            push @all_devices, @new_devices;

            $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: For type $type: " . scalar(@new_devices) . " entries:");
            $self->{logger}->debug(Dumper(\@new_devices)) if ($self->{logger}->{Debug} && @new_devices);
        }

        # Exclude duplicate IP
        my %by_ip;
        my $dev_removed = 0;

        while (my $dev = pop @all_devices) {
            # Skip devices without IP address
            unless (defined $dev->{ip} && length $dev->{ip}) {
                $dev_removed++;
                next;
            }

            if (!exists $by_ip{$dev->{ip}}) {
                $by_ip{$dev->{ip}} = $dev;
            } else {
                my $current = $by_ip{$dev->{ip}};
                if ((defined $dev->{modified_time} && defined $current->{modified_time} && $dev->{modified_time} > $current->{modified_time}) || (!defined $current->{modified_time})) {
                    $by_ip{$dev->{ip}} = $dev;
                }
                $dev_removed++;
            }
        }

        @all_devices = values %by_ip;

        $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: Removed $dev_removed duplicate devices based on IP or devices without IP") if $dev_removed;

        $orgDevices{$org->{id}} = \@all_devices;
        $orgDevicesTotal += scalar @all_devices;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: " . $orgDevicesTotal . " entries:");
    $self->{logger}->debug(Dumper(\%orgDevices)) if ($self->{logger}->{Debug} && $orgDevicesTotal);

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: finished");    

    return \%orgDevices;
}

sub obtainSystemInfo {
    my ($self, $sdnDevices) = @_;

    return unless $sdnDevices;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainSystemInfo: started");
    
    foreach my $dev (@$sdnDevices) {
        next unless ($dev->{DeviceID});
        my $device_id = $dev->{DeviceID};
        $self->{dn} = $dev->{SdnDeviceDN};
        $self->{device_info_loaded} = 0;
        my $pRebootTime = NetMRI::Util::Date::formatDate(time() - int($dev->{UpTime})) if $dev->{UpTime};
        my $device = {
            LastTimeStamp => NetMRI::Util::Date::formatDate(time()),
            Name => $dev->{Name},
            Vendor => $dev->{Vendor},
            Model => $dev->{Model} || '',
            DeviceMAC => $dev->{SdnDeviceMac} || '',
            DeviceStatus => $dev->{DeviceStatus},
            SWVersion => $dev->{SWVersion} || '',
            SdnControllerId => $dev->{SdnControllerId} || '',
            IPAddress => $dev->{IPAddress},
            UpTime => (defined $dev->{UpTime}) ? ($dev->{UpTime} * 100) : 0
        };
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysModel', '', 'SNMP'], $dev->{Model}) if $dev->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysName', '', 'SNMP'], $self->_remove_utf8($dev->{Name})) if $dev->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVendor', '', 'SNMP'], $dev->{vendor_name});
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVersion', '', 'SNMP'], $dev->{SWVersion} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'DeviceMAC', '', 'SNMP'], $dev->{SdnDeviceMac} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{SdnControllerId}) if $dev->{SdnControllerId};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'pRebootTime', '', 'SNMP'], $pRebootTime) if $dev->{UpTime};        
        $self->saveInventory({
            DeviceID               => $device_id,
            entPhysicalSerialNum   => $dev->{Serial} || 'N/A',
            entPhysicalModelName   => $dev->{Model},
            entPhysicalFirmwareRev => $dev->{SWVersion} || 'MIST OS',
            entPhysicalName        => $dev->{Name},
            entPhysicalIndex       => 1,
            entPhysicalClass       => 'chassis',
            StartTime              => NetMRI::Util::Date::formatDate(time()),
            EndTime                => NetMRI::Util::Date::formatDate(time())
        });
        $self->saveSystemInfo($device);
        if ($dev->{DeviceStatus} eq 'connected') {
            $self->setReachable();
        } else {
            $self->setUnreachable();
        } 
        $self->updateDataCollectionStatus('System', 'OK', $device_id);
        $self->updateDataCollectionStatus('Inventory', 'OK', $device_id);
    }
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainSystemInfo: finished");
}

sub obtainPerformance  {
    my ($self, $sdnDevices, $orgs, $allEdgesStats, $orgDevices) = @_;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance: started");

    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    $self->{dn}= "";

    my %sdnDevices_hash = map { $_->{SdnDeviceDN}  => $_->{DeviceID} } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainPerformance: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash)) if ($self->{logger}->{Debug});

    # Collected Performance for MistEdges
    # We dont have any information about CPU for MistEdges
    my %mem_stats_count;
    foreach my $org (@$orgs) {
        next unless ($allEdgesStats->{$org->{id}});
        foreach my $edgeStats ($allEdgesStats->{$org->{id}}) {
            foreach my $edge (@$edgeStats) {
                next unless $edge->{org_id} && $edge->{site_id} && $edge->{id};
                my @memory = ();
                my $SdnDeviceDN = "$edge->{org_id}/$edge->{site_id}/$edge->{id}";
                my $deviceID = $sdnDevices_hash{$SdnDeviceDN};
                next unless $deviceID;
                if (exists $edge->{memory_stat}) {
                    my $mem = $edge->{memory_stat};
                    if (exists $mem->{total} && exists $mem->{free}) {
                        my $util_mem = $mem->{total} ? int( (($mem->{total} - $mem->{free}) / $mem->{total}) * 100 ) : 0;
                        my %mem_row = (
                            DeviceID => $deviceID,
                            StartTime => $start_time,
                            EndTime => $end_time,
                            UsedMem => ($mem->{total} - $mem->{free}),
                            FreeMem => ($mem->{free}),
                            Utilization5Min =>$util_mem
                        );
                        push @memory, \%mem_row;
                    }
                }

                $mem_stats_count{ scalar(@memory) }++;

                $self->updateDataCollectionStatus('CPU', 'N/A', $deviceID);

                if (scalar @memory) {
                    $self->saveDeviceMemStats(\@memory);
                    $self->updateDataCollectionStatus('Memory', 'OK', $deviceID);
                } else {
                    $self->updateDataCollectionStatus('Memory', 'N/A', $deviceID);
                }
            }   
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/memory(allEdges): Summary of Memory collections:");
    foreach my $count (sort { $a <=> $b } keys %mem_stats_count) {
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/memory(allEdges):  Devices with $count Memory entries: $mem_stats_count{$count}");
    }

    # Collected Performance for OrgDevices
    # We dont have full information about Memory for orgDevices (AP, Switches, Gateways)
    my %cpu_stats_count;
    foreach my $org (@$orgs) {
        next unless ($orgDevices->{$org->{id}});
        foreach my $orgDevicesStats ($orgDevices->{$org->{id}}) {
            foreach my $orgDevice (@$orgDevicesStats) {
                my @cpu = ();
                my $SdnDeviceDN = "$orgDevice->{org_id}/$orgDevice->{site_id}/$orgDevice->{id}";
                my $deviceID = $sdnDevices_hash{$SdnDeviceDN};
                next unless $deviceID;
                if (exists $orgDevice->{cpu_stat}) {
                    my $cpu_device = $orgDevice->{cpu_stat};
                    if (exists $cpu_device->{idle}) {
                        my %cpu_row = (
                            DeviceID => $deviceID,
                            StartTime => $start_time,
                            EndTime => $end_time,
                            CpuIndex => 1,
                            CpuBusy => int(100 - $cpu_device->{idle})
                        );
                        push @cpu, \%cpu_row;
                    }
                }

                $cpu_stats_count{ scalar(@cpu) }++;

                if (scalar @cpu) {
                    $self->saveDeviceCpuStats(\@cpu);
                    $self->updateDataCollectionStatus('CPU', 'OK', $deviceID);
                } else {
                    $self->updateDataCollectionStatus('CPU', 'N/A', $deviceID);
                }

                $self->updateDataCollectionStatus('Memory', 'N/A', $deviceID);
            }    
        }    
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/cpu(orgDevices): Summary of CPU collections:");
    foreach my $count (sort { $a <=> $b } keys %cpu_stats_count) {
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/cpu(orgDevices):  Devices with $count CPU entries: $cpu_stats_count{$count}");
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance finished");
}
   
sub obtainEnvironment {
    my ($self, $sdnDevices, $orgs, $orgDevices) = @_;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: started");
    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    my %sdnDevices_hash = map { $_->{SdnDeviceDN}  => $_->{DeviceID} } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainEnvironment: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash)) if ($self->{logger}->{Debug});

    # Collected Environment for orgDevices
    my %fan_stats_count;
    my %temp_stats_count;
    my %power_stats_count;
    foreach my $org (@$orgs) {
        next unless ($orgDevices->{$org->{id}});
        foreach my $orgDevicesStats ($orgDevices->{$org->{id}}) {
            foreach my $dev (@$orgDevicesStats) {
                my @environment = ();
                my $cntFan = 0;
                my $cntTemp = 0;
                my $cntPower = 0;
                my $SdnDeviceDN = "$dev->{org_id}/$dev->{site_id}/$dev->{id}";
                my $deviceID = $sdnDevices_hash{$SdnDeviceDN};
                next unless $deviceID;
                my $indFAN = 1;
                my $indTEMP = 1;
                my $indPS = 1;
                if (exists $dev->{'module_stat'} && ref $dev->{'module_stat'} eq 'ARRAY')  {
                    my $envStats = $dev->{'module_stat'};
                    foreach my $env (@{$envStats}) {
                        if (exists $env->{'fans'} && ref $env->{'fans'} eq 'ARRAY') {
                            my $envFans = $env->{'fans'};
                            foreach my $fan_stat (@{$envFans}){
                                if (exists $fan_stat->{'name'} && exists $fan_stat->{'status'} && exists $fan_stat->{'rpm'}) {
                                    my %fan_row = (
                                        DeviceID => $deviceID,
                                        StartTime => $start_time,
                                        EndTime => $end_time,
                                        envIndex => $indFAN++,
                                        envType => "fan",
                                        envDescr => $fan_stat->{'name'},
                                        envState => $fan_stat->{'status'},
                                        envStatus => $fan_stat->{'rpm'},
                                        envMeasure => "RPM"
                                    );
                                    $cntFan++;
                                    push @environment, \%fan_row;
                                }
                            }
                        }
                        if (exists $env->{'temperatures'} && ref $env->{'temperatures'} eq 'ARRAY') {
                            my $envTemps = $env->{'temperatures'};
                            foreach my $temp_stat (@{$envTemps}) {
                                if (exists $temp_stat->{'name'} && exists $temp_stat->{'status'} && exists $temp_stat->{'celsius'}) {
                                    my %temp_row = (
                                        DeviceID => $deviceID,
                                        StartTime => $start_time,
                                        EndTime => $end_time,
                                        envIndex => $indTEMP++,
                                        envType => "temperature",
                                        envDescr => $temp_stat->{'name'},
                                        envState => $temp_stat->{'status'},
                                        envStatus => $temp_stat->{'celsius'},
                                        envMeasure => "degrees C"
                                    );
                                    $cntTemp++;
                                    push @environment, \%temp_row;
                                }
                            }
                        }
                        if (exists $env->{'psus'} && ref $env->{'psus'} eq 'ARRAY') {
                            my $envPSUs = $env->{'psus'};
                            foreach my $power_stat (@{$envPSUs}) {
                                if (exists $power_stat->{'name'} && exists $power_stat->{'status'}) {
                                    my %power_row = (
                                        DeviceID => $deviceID,
                                        StartTime => $start_time,
                                        EndTime => $end_time,
                                        envIndex => $indPS++,
                                        envType => "power",
                                        envDescr => $power_stat->{'name'},
                                        envState => $power_stat->{'status'},
                                    );
                                    $cntPower++;
                                    push @environment, \%power_row;
                                }
                            }
                        }
                    }
                }

                $fan_stats_count{ $cntFan }++;
                $temp_stats_count{ $cntTemp }++;
                $power_stats_count{ $cntPower }++;

                if (scalar @environment) {
                    $self->saveEnvironmental(\@environment);
                    $self->updateDataCollectionStatus('Environmental', 'OK', $deviceID);
                } else {
                    $self->updateDataCollectionStatus('Environmental', 'N/A', $deviceID);
                }
            }
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: Summary of FAN collections:");
    foreach my $count (sort { $a <=> $b } keys %fan_stats_count) {
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment:  Devices with $count fan entries: $fan_stats_count{$count}");
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: Summary of TEMPERATURE collections:");
    foreach my $count (sort { $a <=> $b } keys %temp_stats_count) {
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment:  Devices with $count temperature entries: $temp_stats_count{$count}");
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: Summary of POWER collections:");
    foreach my $count (sort { $a <=> $b } keys %power_stats_count) {
        $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment:  Devices with $count power entries: $power_stats_count{$count}");
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: finished");
}

sub obtainInterfaces {
    my ($self, $sdnDevices, $orgs, $allEdgesStats, $orgDevices) = @_;
    
    my (@intdata, @lldpdata, @trunkdata, @ipaddr, @routes, @routes_devices, @lldp_devices, @vlans, @forwarding_info, @vlans_ids, @forwarding_ids);

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: started");
    my $timestamp = NetMRI::Util::Date::formatDate(time());
    $self->{dn}= "";

    my %sdnDevices_hash = map { $_->{SdnDeviceMac}  => {SdnDeviceID => $_->{SdnDeviceID},DeviceID => $_->{DeviceID},SdnDeviceDN => $_->{SdnDeviceDN} } } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainInterfaces: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash)) if ($self->{logger}->{Debug});

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainInterfaces: Error getting the Mist API Client");
        return;
    }
   
    my $curr_device = 0;
    foreach my $org (@$orgs) {
        my ($res, $msg) = $api_helper->get_mist_intf($org->{id});
        unless ($res) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] obtainInterfaces/get_mist_intf: No data for Org $org->{id}: " . ($msg||""));
            next;
        }

        my @new_res;
        while (my $r = pop @$res) {
            push @new_res, {
                (exists $r->{port_mac}           ? (port_mac           => $r->{port_mac}) : ()),
                (exists $r->{mac}                ? (mac                => $r->{mac}) : ()),
                (exists $r->{port_id}            ? (port_id            => $r->{port_id}) : ()),
                (exists $r->{port_desc}          ? (port_desc          => $r->{port_desc}) : ()),
                (exists $r->{up}                 ? (up                 => $r->{up}) : ()),
                (exists $r->{speed}              ? (speed              => $r->{speed}) : ()),
                (exists $r->{port_mode}          ? (port_mode          => $r->{port_mode}) : ()),
                (exists $r->{full_duplex}        ? (full_duplex        => $r->{full_duplex}) : ()),
                (exists $r->{device_interface_type} ? (device_interface_type => $r->{device_interface_type}) : ()),
                (exists $r->{port_parent}        ? (port_parent        => $r->{port_parent}) : ()),
                (exists $r->{site_id}            ? (site_id            => $r->{site_id}) : ()),
                (exists $r->{neighbor_mac}       ? (neighbor_mac       => $r->{neighbor_mac}) : ()),
                (exists $r->{neighbor_port_desc} ? (neighbor_port_desc => $r->{neighbor_port_desc}) : ()),
                (exists $r->{neighbor_system_name} ? (neighbor_system_name => $r->{neighbor_system_name}) : ()),
            };
        }
        $res = \@new_res;

        foreach my $port (@$res) {
            my $SdnIntfMac = $port->{port_mac} ? join(':', $port->{port_mac} =~ /../g) : undef;
            my $DeviceMac = $port->{mac} ? join(':', $port->{mac} =~ /../g) : undef;
            next unless $DeviceMac;
            my $sdnDeviceID = $sdnDevices_hash{$DeviceMac}->{SdnDeviceID};
            my $deviceID = $sdnDevices_hash{$DeviceMac}->{DeviceID};
            next unless $deviceID;
            if ($curr_device != $sdnDeviceID) {
                $curr_device = $sdnDeviceID;
                $self->{interface_map_loaded} = 0;
                $self->{device_info_loaded} = 0;
            }
            $self->{dn} = $sdnDevices_hash{$DeviceMac}->{SdnDeviceDN};
            my $if_index = $self->getInterfaceIndex($port->{port_id});
            next unless $port->{port_id};
            push @intdata, {
                SdnDeviceID => $sdnDeviceID,
                Name => $port->{port_id},
                Descr => $port->{port_desc} || $port->{port_id},
                MAC => $SdnIntfMac || "",
                operStatus => $port->{up} ? "up" : "down",
                adminStatus => $port->{up} ? "up" : "down",
                operSpeed => (int($port->{speed} || 0) * 1000 * 1000),
                Timestamp => $timestamp,
                Mode => $port->{port_mode},
                Duplex => $port->{full_duplex} ? "fullDuplex" : "halfDuplex",
                Type => $port->{device_interface_type}
            };
            if (($port->{port_mode} || $port->{port_parent}) && $if_index ) {
                my @parent_port = grep({$_->{port_id} eq $port->{port_parent} && $_->{mac} eq $port->{mac} && $_->{site_id} eq $port->{site_id}} @$res) if defined $port->{port_parent};
                my $port_mode = (@parent_port) ? $parent_port[0]->{port_mode} : $port->{port_mode};

                push @trunkdata, {
                    DeviceID => $deviceID,    
                    vlanTrunkPortIfIndex => $if_index,
                    vlanTrunkPortDynamicStatus => ((defined $port_mode && $port_mode eq "trunk") ? "trunking" :"nottrunking"),
                    vlanTrunkPortDynamicState =>  ((defined $port_mode && $port_mode eq "trunk") ? "tagged" : "untagged" ),
                    StartTime => $timestamp,
                    EndTime => $timestamp
                };
            }
            if ($port->{neighbor_mac}) {
                my $neighbor_mac = join(':', $port->{neighbor_mac} =~ /../g);
                my $neighbor_mgmt_ip = $self->_getNeighborIP($neighbor_mac, $port->{neighbor_port_desc} || '', $port->{neighbor_system_name});
                push @lldpdata, {
                    DeviceID => $deviceID,
                    RemSysName => $port->{neighbor_system_name},
                    RemPortDesc => $port->{neighbor_port_desc},
                    RemChassisID => $neighbor_mac,
                    RemManPrimaryAddr => $neighbor_mgmt_ip,
                    RemChassisIdSubtype => 'macAddress',
                    RemPortIdSubtype => 'interfaceName',
                    LocalPortIdSubtype => 'macAddress',
                    LocalPortId => $SdnIntfMac,
                    RemPortID => $port->{neighbor_port_desc},
                    Timestamp => $timestamp
                };
                push @lldp_devices, $deviceID unless grep({$_  eq $deviceID}  @lldp_devices);
            } 
        }
    }

    $curr_device = 0;

    foreach my $org (@$orgs) {
        next unless ($orgDevices->{$org->{id}});
        foreach my $orgDevicesStats ($orgDevices->{$org->{id}}) {
            foreach my $orgDevice (@$orgDevicesStats) {
                my ($routeIP, $routeNetmask, $routeGW) = ("", "", "");
                my $DeviceMac = $orgDevice->{mac} ? join(':', $orgDevice->{mac} =~ /../g) : undef;

                if ($orgDevice->{ip_config}->{type} && $orgDevice->{ip_config}->{type} eq 'static') {
                    $routeIP = $orgDevice->{ip_config}->{ip};
                    $routeNetmask = $orgDevice->{ip_config}->{netmask};
                    $routeGW = $orgDevice->{ip_config}->{gateway};
                }

                my $ip_values = $orgDevice->{if_stat};
                next unless ($ip_values);
                foreach my $data (values %$ip_values) {
                    next unless($data->{ips});
                    my $deviceID = $sdnDevices_hash{$DeviceMac}->{DeviceID};
                    next unless $deviceID;
                    if ($curr_device != $deviceID) {
                        $curr_device = $deviceID;
                        $self->{interface_map_loaded} = 0;
                        $self->{device_info_loaded} = 0;
                    }
                    $self->{dn} = $sdnDevices_hash{$DeviceMac}->{SdnDeviceDN};
                    my $if_index = $self->getInterfaceIndex($data->{port_id});
                    next unless ($if_index);
                    my $intf_ip = $data->{ips};
                    foreach my $ips (@$intf_ip) {
                        if ($ips =~ /(.+)\/(\d+)/) { 
                            my $addr_dotted = $1;
                            my $addr_num = InetAddr($addr_dotted);
                            my $mask = $2;
                            my $address_family = ($addr_dotted =~ /:/) ? "ipv6" : "ipv4";
                            my $netmask_num = netmaskFromPrefix($address_family,$mask);
                            my $addr_bigint = Math::BigInt->new("$addr_num");
                            my $mask_bigint = Math::BigInt->new("$netmask_num");
                            my $subnet = $addr_bigint->band($mask_bigint);

                            if ($addr_dotted eq $routeIP) {
                                push @routes, {
                                    RowID              => 1,
                                    DeviceID           => $deviceID,
                                    StartTime          => $timestamp,
                                    EndTime            => $timestamp,
                                    ipRouteDestStr     => inet_ntoa(pack('N', (unpack('N', inet_aton($routeIP)) & unpack('N', inet_aton($routeNetmask))))),
                                    ipRouteDestNum     => unpack('N', inet_aton($routeIP)) & unpack('N', inet_aton($routeNetmask)),
                                    ipRouteMaskStr     => $routeNetmask,
                                    ipRouteMaskNum     => unpack('N', inet_aton($routeNetmask)),
                                    ipRouteNextHopStr  => $routeGW,
                                    ipRouteNextHopNum  => InetAddr($routeGW) || '0',
                                    ifDescr            => $data->{port_id},
                                    ipRouteIfIndex     => $if_index,
                                    ipRouteProto       => 'local',
                                    ipRouteType        => 'local',
                                    ipRouteMetric1     => 0,
                                    ipRouteMetric2     => 1,
                                };
                                push @routes_devices, $deviceID unless grep({$_  eq $deviceID} @routes_devices); 
                            }
                            push @ipaddr, {
                                DeviceID => $deviceID,
                                IPAddress => $addr_num,
                                Timestamp => $timestamp,
                                ifIndex => $if_index,
                                IPAddressDotted => $addr_dotted,
                                NetMask => $netmask_num,
                                SubnetIPNumeric => $subnet
                            };
                        }
                    }

                    if (exists $data->{vlan} && defined $data->{vlan} && $if_index) {
                        push @vlans, {
                            DeviceID => $deviceID,
                            StartTime => $timestamp,
                            EndTime => $timestamp,
                            vtpVlanIndex => $data->{vlan},
                            vtpVlanName => 'Vlan '.$data->{vlan},
                            vtpVlanType => 'Mist'
                        };
                        push @vlans_ids, $deviceID unless grep({$_  eq $deviceID}  @vlans_ids);

                        push @forwarding_info, {
                            DeviceID => $deviceID,
                            StartTime => $timestamp,
                            EndTime => $timestamp,
                            vlan => $data->{vlan},
                            dot1dTpFdbPort => $if_index || 0,
                            dot1dTpFdbStatus => 'learned',
                            dot1dTpFdbAddress => $DeviceMac
                        };
                        push @forwarding_ids , $deviceID unless grep({$_  eq $deviceID}  @forwarding_ids);
                    }
                }    
            }
        }
    }

    %sdnDevices_hash = map { $_->{SdnDeviceDN}  => {SdnDeviceID => $_->{SdnDeviceID}, DeviceID => $_->{DeviceID} } } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainInterfaces: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash)) if ($self->{logger}->{Debug});

    foreach my $org (@$orgs) {
        next unless ($allEdgesStats->{$org->{id}});
        foreach my $edge_stat ($allEdgesStats->{$org->{id}}) {
            foreach my $edge (@$edge_stat) {
                next unless (defined $edge->{org_id} && defined $edge->{site_id} && defined $edge->{id});
                my $SdnDeviceDN = "$edge->{org_id}/$edge->{site_id}/$edge->{id}";
                my $sdnDeviceID = $sdnDevices_hash{$SdnDeviceDN}->{SdnDeviceID};
                my $deviceID = $sdnDevices_hash{$SdnDeviceDN}->{DeviceID};
                next unless $deviceID;
                foreach my $edge_port (keys %{$edge->{port_stat}}) {
                    my $SdnIntfMac = $edge->{port_stat}->{$edge_port}->{mac} ? join(':', $edge->{port_stat}->{$edge_port}->{mac} =~ /../g) : undef;
                    push @intdata, {
                        SdnDeviceID => $sdnDeviceID,
                        Name => $edge_port,
                        Descr => $edge_port,
                        MAC => $SdnIntfMac || "",
                        operStatus => $edge->{port_stat}->{$edge_port}->{up} ? "up" : "down",
                        adminStatus => $edge->{port_stat}->{$edge_port}->{up} ? "up" : "down",
                        operSpeed => (int($edge->{port_stat}->{$edge_port}->{speed} || 0) * 1000 * 1000),
                        Timestamp => $timestamp,
                        Duplex => $edge->{port_stat}->{$edge_port}->{full_duplex} ? "fullDuplex" : ""
                    };
                    if ($edge->{port_stat}->{$edge_port}->{lldp_stats}) {
                        push @lldpdata, {
                            DeviceID => $deviceID,
                            RemPortIdSubtype => 'interfaceName',
                            RemChassisIdSubtype => 'macAddress',
                            RemManPrimaryAddr => $edge->{port_stat}->{$edge_port}->{lldp_stats}->{mgmt_addr},
                            RemSysName => $edge->{port_stat}->{$edge_port}->{lldp_stats}->{system_name},
                            RemPortDesc => $edge->{port_stat}->{$edge_port}->{lldp_stats}->{port_id},
                            RemPortID => $edge->{port_stat}->{$edge_port}->{lldp_stats}->{port_id},
                            RemChassisID => $edge->{port_stat}->{$edge_port}->{lldp_stats}->{chassis_id},
                            RemSysDesc => $edge->{port_stat}->{$edge_port}->{lldp_stats}->{system_desc},
                            LocalPortIdSubtype => 'macAddress',
                            LocalPortId => $SdnIntfMac,
                            Timestamp => $timestamp
                        };
                        push @lldp_devices, $deviceID unless grep({$_  eq $deviceID}  @lldp_devices); 
                    }
                }
            }
        }
    }
    
    @intdata = sort {$a->{Name} cmp $b->{Name}} @intdata;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Interfaces " . scalar(@intdata) . " entries:");
    if (scalar @intdata) {
        $self->{logger}->debug(Dumper(\@intdata)) if ($self->{logger}->{Debug});
        $self->saveSdnFabricInterface(\@intdata);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Forwarding " . scalar(@forwarding_info) . " entries:");
    if (scalar(@forwarding_info)) {
        $self->{logger}->debug(Dumper(\@forwarding_info)) if ($self->{logger}->{Debug});
        $self->saveForwarding(\@forwarding_info);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Forwarding DevIDs " . scalar(@forwarding_ids) . " entries:");
    if (scalar(@forwarding_ids)) {
        $self->{logger}->debug(Dumper(\@forwarding_ids)) if ($self->{logger}->{Debug});
        $self->updateDataCollectionStatus('Forwarding', 'OK', $_) for @forwarding_ids;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: VLAN " . scalar(@vlans) . " entries:");
    if (scalar(@vlans)) {
        $self->{logger}->debug(Dumper(\@vlans)) if ($self->{logger}->{Debug});
        $self->saveVlanObject(\@vlans);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: VLAN DevIDs " . scalar(@vlans_ids) . " entries:");
    if (scalar(@vlans_ids)) {
        $self->{logger}->debug(Dumper(\@vlans_ids)) if ($self->{logger}->{Debug});
        $self->updateDataCollectionStatus('Vlans', 'OK', $_) for @vlans_ids;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Trunks " . scalar(@trunkdata) . " entries:");
    if (scalar @trunkdata) {
        $self->{logger}->debug(Dumper(\@trunkdata)) if ($self->{logger}->{Debug});
        $self->saveVlanTrunkPortTable(\@trunkdata);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: IPADDresses " . scalar(@ipaddr) . " entries:");
    if (scalar @ipaddr) {
        $self->{logger}->debug(Dumper(\@ipaddr)) if ($self->{logger}->{Debug});
        $self->saveIPAddress(\@ipaddr);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: LLDP " . scalar(@lldpdata) . " entries:");
    if (scalar @lldpdata) {
        $self->{logger}->debug(Dumper(\@lldpdata)) if ($self->{logger}->{Debug});
        $self->saveLLDP(\@lldpdata);
        $self->updateDataCollectionStatus('Neighbor', 'OK', $_) for @lldp_devices;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Routes " . scalar(@routes) . " entries:");
    if (scalar @routes) {
        $self->{logger}->debug(Dumper(\@routes)) if ($self->{logger}->{Debug});
        $self->saveipRouteTable(\@routes);
        $self->updateDataCollectionStatus('Route', 'OK', $_) for @routes_devices;
    }
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: finished");
}

sub obtainLldpAP {
    my ($self, $sdnDevices, $organizations) = @_;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainLldpAP: started");

    my $timestamp = NetMRI::Util::Date::formatDate(time());

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] obtainLldpAP: Error getting the Mist API Client");
        return;
    }

    $self->{dn}= "";
    #Converting Array to Hash/SdnDeviceDN
    my %sdnDevices_hash = map { $_->{SdnDeviceMac}  => $_->{DeviceID}} @{$sdnDevices};
    my (@lldpdata, @lldp_devices);

    foreach my $id(@$organizations) {
        my ($res, $msg) = $api_helper->get_device_lldp($id->{id});
        unless ($res) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] obtainLldpAP/get_device_lldp: No data for OrgId=$id->{id}: ".($msg||''));
            next;
        }

        foreach my $port (@$res) {
            next unless $port->{lldp_chassis_id};
            my $DeviceMac = $port->{mac} ? join(':', $port->{mac} =~ /../g) : undef;
            my $deviceID = $DeviceMac ? $sdnDevices_hash{$DeviceMac} : undef;
            next unless $deviceID;
            push @lldpdata, {
                DeviceID => $deviceID,
                LocalPortIdSubtype => 'DeviceIP',
                RemPortIdSubtype => 'interfaceName',
                RemChassisIdSubtype => 'macAddress',
                LocalPortId => $port->{ip},
                RemManPrimaryAddr => $port->{lldp_mgmt_addr},
                RemSysName => $port->{lldp_system_name},
                RemPortDesc => $port->{lldp_port_desc},
                RemPortID => $port->{lldp_port_id},
                RemChassisID => $port->{lldp_chassis_id},
                RemSysDesc => $port->{lldp_system_desc},
                Timestamp => $timestamp
            };  
            push @lldp_devices, $deviceID unless grep({$_  eq $deviceID}  @lldp_devices);
        } 
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainLldpAP: " . scalar(@lldpdata) . " entries:");
    $self->{logger}->debug(Dumper(\@lldpdata)) if ($self->{logger}->{Debug} && scalar(@lldpdata));

    $self->saveLLDP(\@lldpdata);
    $self->updateDataCollectionStatus('Neighbor', 'OK', $_) for @lldp_devices;
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainLldpAP: finished");
}

sub _getNeighborIP {
    my ($self, $neighbor_mac, $neighbor_port_desc, $neighbor_system_name) = @_;

    my $query = "select IPAddressDotted from $self->{netmri_db}.ifAddr join $self->{netmri_db}.ifConfig using (DeviceID, ifIndex) where PhysAddress = '$neighbor_mac' and Descr = '$neighbor_port_desc' limit 1";
    my $neighbor_ip = $self->{sql}->single_value($query, AllowNoRows => 1, RefWanted => 1);   
    return $$neighbor_ip[0] if $neighbor_ip;
    $query = "select IPAddress from $self->{netmri_db}.Device join $self->{netmri_db}.ifConfig using (DeviceID) where PhysAddress = '$neighbor_mac' and Descr = '$neighbor_port_desc' limit 1";
    $neighbor_ip = $self->{sql}->single_value($query, AllowNoRows => 1, RefWanted => 1);
    return $$neighbor_ip[0] if $neighbor_ip;
    $query = "select DeviceIPDotted from $self->{report_db}.Device where DeviceMAC= '$neighbor_mac' and DeviceName = '$neighbor_system_name'";
    $neighbor_ip = $self->{sql}->single_value($query, AllowNoRows => 1, RefWanted => 1);
    return $$neighbor_ip[0];
}

sub obtainEndhosts {
    my $self = shift;

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEndhosts: started");
    if ($self->{cfg}->{IgnoreMistAP} eq "off") {
        my $sdnDevices = $self->loadSdnDevices(); 
        if ($sdnDevices) {
            my ($endhosts, $wireless_fwd, $vlans, $vlans_ids) = $self->getWirelessEndhosts($sdnDevices);
            # Collecting data without SdnInterfaceID 
            $self->saveMistSdnEndpoint($endhosts);
            $self->saveVlanObject($vlans);
            $self->savebsnMobileStationTable($wireless_fwd);
            $self->updateDataCollectionStatus('Vlans', 'OK',$_) for $vlans_ids;

            # Information is not provided via API
            # my ($forwarding_info, $forwarding_ids);
            # ($endhosts, $forwarding_info, $vlans, $vlans_ids, $forwarding_ids) = $self->getWiredEndhosts($sdnDevices);    
            # # Collecting data with SdnInterfaceID 
            # $self->saveSdnEndpoint($endhosts);
            # $self->saveForwarding($forwarding_info);
            # $self->saveVlanObject($vlans);
            # $self->updateDataCollectionStatus('Forwarding', 'OK',$_) for $forwarding_ids;
            # $self->updateDataCollectionStatus('Vlans', 'OK',$_) for $vlans_ids;
        } else {
            $self->{logger}->warn("Mist[$self->{fabric_id}] obtainEndhosts: The SdnDevices are not collected");
        }
    } else {
        $self->{logger}->warn("Mist[$self->{fabric_id}] obtainEndhosts: IgnoreMistAP is ENABLED. Skipping Endhosts collection.");
    }
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEndhosts: finished");
}

sub getWirelessEndhosts {
    my ($self, $sdnDevices) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: started");

    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getWirelessEndhosts: Error getting the Mist API Client");
        return;
    }

    my %device_hash = map { $_->{SdnDeviceMac}  => {SdnDeviceID => $_->{SdnDeviceID},DeviceID => $_->{DeviceID},SdnDeviceDN => $_->{SdnDeviceDN} } } @{$sdnDevices};
    my $sites = $self->loadSites();
    unless (defined $sites) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getWirelessEndhosts: No Sites");
        return;
    }

    my $curr_device;
    my (@endhosts, @vlans, @wireless_fwd,@vlans_ids);
    foreach my $site_id (@$sites) {
        my ($wireless_endhosts_data, $msg) = $api_helper->get_endhosts($site_id->{id});
        unless ($wireless_endhosts_data) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] getWirelessEndhosts/get_wireless_endhosts: No data for Site $site_id->{id}: ".($msg||''));
            next;
        }
        foreach my $endhost (@$wireless_endhosts_data) {
            my ($endhostMac, $apMac, $deviceID);

            $endhostMac = $endhost->{mac} ? join(':', $endhost->{mac} =~ /../g) : undef;
            next unless $endhostMac;

            $apMac = $endhost->{ap_mac} ? join(':', $endhost->{ap_mac} =~ /../g) : undef;
            $deviceID = $device_hash{$apMac}->{DeviceID} if ($apMac);
            next unless $deviceID;

            push @endhosts, {
                IP => $endhost->{ip} || $endhost->{ip6},
                MAC => $endhostMac,
                Name => $endhost->{hostname} || $endhost->{username} || '',
                Vendor => $endhost->{manufacture},
                OS => $endhost->{os},
                DeviceID => $deviceID
            };

            push @wireless_fwd, {
                bsnMobileStationMacAddress => $endhostMac,
                bsnMobileStationIpAddress => InetAddr($endhost->{ip} || $endhost->{ip6}),
                bsnMobileStationUserName => $endhost->{hostname} || $endhost->{username} || '',
                bsnMobileStationSsid => $endhost->{ssid},
                bsnMobileStationVlanId => $endhost->{vlan_id},
                bsnMobileStationAPMacAddr => $apMac,
                DeviceID => $deviceID
            };
            if ($endhost->{vlan_id}){
                push @vlans, {
                    DeviceID => $deviceID,
                    StartTime => $start_time,
                    EndTime => $end_time,
                    vtpVlanIndex => $endhost->{vlan_id},
                    vtpVlanName => 'Vlan '.$endhost->{vlan_id},
                    vtpVlanType => 'Mist'
                };
                push @vlans_ids, $deviceID unless grep({$_  eq $deviceID}  @vlans_ids);
            }
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: EndHosts " . scalar(@endhosts) . " entries:");
    $self->{logger}->debug(Dumper(\@endhosts)) if ($self->{logger}->{Debug} && scalar(@endhosts));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: LLDPAP " . scalar(@wireless_fwd) . " entries:");
    $self->{logger}->debug(Dumper(\@wireless_fwd)) if ($self->{logger}->{Debug} && scalar(@wireless_fwd));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: VLAN " . scalar(@vlans) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans)) if ($self->{logger}->{Debug} && scalar(@vlans));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: VLAN ID " . scalar(@vlans_ids) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans_ids)) if ($self->{logger}->{Debug} && scalar(@vlans_ids));

    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: finished");

    return \@endhosts,\@wireless_fwd,\@vlans,\@vlans_ids;
}

sub getWiredEndhosts {
    my ($self, $sdnDevices) = @_;

    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}]: Error getting the Mist API Client");
        return;
    }

    my %device_hash = map { $_->{SdnDeviceDN} => $_->{DeviceID} } @{$sdnDevices};
    my $sites = $self->loadSites();
    unless (defined $sites) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getWiredEndhosts: No Sites");
        return;
    }
    my (@endhosts, @vlans, @forwarding_info,@vlans_ids,@forwarding_ids);
    my $curr_device = 0;
    foreach my $site_id(@$sites) {
        my $start_time = NetMRI::Util::Date::formatDate(time());
        my $end_time = NetMRI::Util::Date::formatDate(time() + 1);
        my ($wired_endhosts_data, $msg) = $api_helper->get_endhosts($site_id->{id}, {wired=>'true'});
        unless ($wired_endhosts_data) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] getWiredEndhosts/get_wired_endhosts: No data for Site $site_id->{id}: ".($msg||''));
            next;
        }  

        foreach my $endhost (@$wired_endhosts_data) {
            next unless $endhost->{mac};
            my $endhostMac = join(':', $endhost->{mac} =~ /../g);
            my $SdnDeviceDN = "$site_id->{organization_id}/$site_id->{id}/$endhost->{ap_id}";
            my $deviceID = $device_hash{$SdnDeviceDN};
            next unless $deviceID;
            if ($curr_device != $deviceID) {
                $curr_device = $deviceID;
                $self->{interface_map_loaded} = 0;
                $self->{device_info_loaded} = 0;
            }
            $self->{dn} = $SdnDeviceDN;
            my $if_index = $self->getInterfaceIndex($endhost->{eth_port});
            next unless $if_index;
            push @endhosts, {
                IP => $endhost->{ip} || $endhost->{ip6} || '',
                MAC => $endhostMac,
                SdnInterfaceID => $if_index,
                Name => $endhost->{hostname} || $endhost->{username} || '',
                Vendor => $endhost->{manufacture} || "",
                OS => $endhost->{os} || "",
                DeviceID => $deviceID
            };
            if ($endhost->{vlan_id}){
                push @vlans, {
                    DeviceID => $deviceID,
                    StartTime => $start_time,
                    EndTime => $end_time,
                    vtpVlanIndex => $endhost->{vlan_id},
                    vtpVlanName => 'Vlan '.$endhost->{vlan_id},
                    vtpVlanType => 'Mist'
                };
                push @vlans_ids, $deviceID unless grep({$_  eq $deviceID}  @vlans_ids);
            
                push @forwarding_info, {
                    DeviceID => $deviceID,
                    StartTime => $start_time,
                    EndTime => $end_time,
                    vlan => $endhost->{vlan_id},
                    dot1dTpFdbPort => $if_index || 0,
                    dot1dTpFdbStatus => 'learned',
                    dot1dTpFdbAddress => $endhostMac
                };
                push @forwarding_ids , $deviceID unless grep({$_  eq $deviceID}  @forwarding_ids);
            }
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: EndHosts " . scalar(@endhosts) . " entries:");
    $self->{logger}->debug(Dumper(\@endhosts)) if ($self->{logger}->{Debug} && scalar(@endhosts));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: Forwarding " . scalar(@forwarding_info) . " entries:");
    $self->{logger}->debug(Dumper(\@forwarding_info)) if ($self->{logger}->{Debug} && scalar(@forwarding_info));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: Forwarding DevIDs " . scalar(@forwarding_ids) . " entries:");
    $self->{logger}->debug(Dumper(\@forwarding_ids)) if ($self->{logger}->{Debug} && scalar(@forwarding_ids));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: VLAN " . scalar(@vlans) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans)) if ($self->{logger}->{Debug} && scalar(@vlans));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: VLAN DevIDs " . scalar(@vlans_ids) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans_ids)) if ($self->{logger}->{Debug} && scalar(@vlans_ids));

    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: finished");

    return \@endhosts,\@forwarding_info,\@vlans,\@vlans_ids,\@forwarding_ids;
}

1;
