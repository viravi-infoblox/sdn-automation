package NetMRI::SDN::Mist;
use strict;
use warnings;
use Encode;
use Data::Dumper;
use Date::Parse;
use NetMRI::Util::Network qw (netmaskFromPrefix InetAddr);
use NetMRI::Util::Wildcard::V4;
use Net::IP;
use NetAddr::IP;
use Socket;
use NetMRI::Util::Subnet qw (subnet_matcher);
use NetMRI::Util::Date;

use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    
    my $self = $class->SUPER::new(@_);
    $self->{vendor_name} = 'Juniper Mist';
    
    return bless $self, $class;
}

sub getOrganizations {
    my $self = shift;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizations: started");    

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveMistNetworks');
    my $query = "select DISTINCT organization_id as id from " . $device_plugin->target_table() . " where fabric_id=" . $sql->escape($self->{fabric_id});
    my $orgs = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$orgs) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getOrganizations: No Organizations for FabricID ");
        return;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizations: " . scalar(@$orgs) . " organizations:");
    $self->{logger}->debug(Dumper(\@$orgs)) if (scalar(@$orgs));

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizations: finished");    

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
    $self->{logger}->debug(Dumper(\@$sites)) if (scalar(@$sites));

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSites: finished");    

    return \@$sites;
}

sub getOrganizationDevices {
    my ($self, $orgs) = @_;
    
    my @orgDevices;

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: started");    

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {
        $self->{logger}->error("Mist[$self->{fabric_id}] getOrganizationDevices: Error getting the Mist API Client");
        return;
    }
    
    foreach my $org (@$orgs) {   
        my ($devices,$msg) = $api_helper->get_organization_devices($org->{id});
        unless ($devices) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] getOrganizationDevices/get_organization_devices: No data for Org $org->{id}: " . ($msg||""));
            next;
        }
        push @orgDevices, {
            org_id => $org->{id},
            devices => $devices
        };
    }       

    my $orgDevicesTotal = 0;
    $orgDevicesTotal += $_ for map { scalar @{ $_->{devices} } } @orgDevices;

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: " . $orgDevicesTotal . " entries:");
    $self->{logger}->debug(Dumper(\@orgDevices)) if ($orgDevicesTotal);

    $self->{logger}->info("Mist[$self->{fabric_id}] getOrganizationDevices: finished");    

    return \@orgDevices;
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
    $self->{logger}->debug(Dumper(\@$sdnDevices)) if (scalar(@$sdnDevices));

    $self->{logger}->info("Mist[$self->{fabric_id}] loadSdnDevices: finished");    

    return \@$sdnDevices;
}

sub getDevices {
    my ($self, $orgs, $orgDevices, $allEdgesStats) = @_;
    
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
                        $self->{logger}->warn("Skipping device $org->{id}/$edge->{site_id}/$edge->{id} is offline");
                        next;
                    }
                }
                my $SdnMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/, ($edge->{mac});
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

    foreach my $data (@$orgDevices) {
        foreach my $row (@{$data->{devices}}) {
            next unless ($row->{ip}); #Skip devices without IP address
            unless ($settings_rec->{collect_offline_devices}) {
                if ($row->{status} eq 'disconnected') {
                    $self->{logger}->warn("Skipping device $data->{org_id}/$row->{site_id}/$row->{id} is offline");
                    next;
                }
            }
            my $SdnMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/,($row->{mac});
            push @devices, {
                SdnControllerId => $self->{fabric_id},
                IPAddress => $row->{ip},
                SdnDeviceMac => $SdnMac || '',
                DeviceStatus => $row->{status},
                SdnDeviceDN => "$data->{org_id}/$row->{site_id}/$row->{id}",
                Name => $row->{name} || $SdnMac,
                NodeRole => "MIST $row->{type}",
                Vendor => $self->{vendor_name},
                Model => $row->{model},
                Serial => $row->{serial},
                SWVersion => $row->{version},
                modTS => NetMRI::Util::Date::formatTimestamp($row->{modified_time}),
                UpTime => $row->{uptime}
            };
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: " . scalar(@devices) . " entries:");
    $self->{logger}->debug(Dumper(\@devices)) if (scalar (@devices));

    $self->{logger}->info("Mist[$self->{fabric_id}] getDevices: finished");

    return \@devices;
}

sub obtainDevices {
    my ($self, $orgs, $orgDevices, $allEdgesStats) = @_;
  
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainDevices: started");
    $self->saveDevices($self->makeDevicesPoolWrapper($self->getDevicesWrapper($orgs, $orgDevices, $allEdgesStats)));
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainDevices: finished");
}

sub getDevicesWrapper {
    my ($self, $orgs, $orgDevices, $allEdgesStats) = @_;
  
    $self->{logger}->debug("Mist[$self->{fabric_id}] getDevicesWrapper: started");
    my $res = $self->getDevices($orgs, $orgDevices, $allEdgesStats);
    $self->{logger}->debug("Mist[$self->{fabric_id}] getDevicesWrapper: finished");
    return $res;
}

sub obtainEverything {
    my $self = shift;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEverything: started");
    my ($organizations, $allEdgesStats) = $self->obtainOrganizationsAndNetworks();
    return unless $organizations;
    my $orgDevices = $self->getOrganizationDevices($organizations);
    $self->obtainDevices($organizations, $orgDevices, $allEdgesStats);
    my $sdnDevices = $self->loadSdnDevices();
    return unless $sdnDevices;
    $self->obtainSystemInfo($sdnDevices);
    $self->obtainPerformance($sdnDevices, $organizations, $allEdgesStats, $orgDevices);  
    $self->obtainEnvironment($sdnDevices, $organizations, $allEdgesStats, $orgDevices);
    $self->obtainInterfaces($sdnDevices, $organizations, $allEdgesStats);
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
    my %allEdgesStats;
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

            my ($edges_stats, $msg2) = $api_helper->get_edges_stats($priv->{org_id});
            unless ($edges_stats){
                $self->{logger}->warn("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks/get_edges_stats: No data for Org $org->{id}:" . ($msg2||""));
                next;
            }

            $allEdgesStats{$priv->{org_id}} = $edges_stats;
        }
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: Organizations " . scalar(@all_orgs) . " entries:");
    $self->{logger}->debug(Dumper(\@all_orgs)) if (scalar(@all_orgs));
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: Sites " . scalar(@sites) . " entries:");
    $self->{logger}->debug(Dumper(\@sites)) if (scalar(@sites));
    my $allEdgesTotal = 0;
    $allEdgesTotal += $_ for map { scalar @$_ } values %allEdgesStats;
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: AllEdges  " . $allEdgesTotal . " entries:");
    $self->{logger}->debug(Dumper(\%allEdgesStats)) if ($allEdgesTotal);

    $self->saveMistOrganizations(\@all_orgs);
    $self->saveMistNetworks(\@sites);
    $self->saveSdnNetworks(\@sites);

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainOrganizationsAndNetworks: finished");

    return \@all_orgs, \%allEdgesStats;
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
    $self->{logger}->debug(Dumper(\%sdnDevices_hash));
    
    foreach my $org (@$orgs) {
        next unless ($allEdgesStats->{$org->{id}});
        foreach my $edgeStats ($allEdgesStats->{$org->{id}}) {
            foreach my $edge (@$edgeStats) {
                next unless $edge->{org_id} && $edge->{site_id} && $edge->{id};
                my @cpu;
                my @memory;
                my $SdnDeviceDN = "$edge->{org_id}/$edge->{site_id}/$edge->{id}";
                my $deviceID = $sdnDevices_hash{$SdnDeviceDN};
                next unless $deviceID;
                foreach my $cpus ($edge->{cpu_stat}->{cpus}) {
                    foreach my $cpu (keys %{$cpus}) {
                        my %cpu_row = (
                            DeviceID => $deviceID,
                            StartTime => $start_time,
                            EndTime => $end_time,
                            CpuIndex => $cpu =~ /(\d+)$/,
                            CpuBusy => int(100 - $cpus->{$cpu}->{idle}),
                        );
                        push @cpu, \%cpu_row;
                    }
                }
                foreach my $mem ($edge->{memory_stat}) {
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

                $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/cpu(allEdges): " . scalar(@cpu) . " entries:");
                $self->{logger}->debug(Dumper(\@cpu)) if (scalar(@cpu));

                if (scalar @cpu) {
                    $self->saveDeviceCpuStats(\@cpu);
                    $self->updateDataCollectionStatus('CPU', 'OK', $deviceID);
                } else {
                    $self->updateDataCollectionStatus('CPU', 'N/A', $deviceID);
                }
                
                $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/memory(allEdges): " . scalar(@memory) . " entries:");
                $self->{logger}->debug(Dumper(\@memory)) if (scalar(@memory));

                if (scalar @memory) {
                    $self->saveDeviceMemStats(\@memory);
                    $self->updateDataCollectionStatus('Memory', 'OK', $deviceID);
                } else {
                    $self->updateDataCollectionStatus('Memory', 'N/A', $deviceID);
                }
            }   
        }
    }
    
    foreach my $org (@$orgDevices) {
        foreach my $perf (@{$org->{devices}}) {
            my @memory;
            my @cpu;
            my $SdnDeviceDN = "$perf->{org_id}/$perf->{site_id}/$perf->{id}";
            my $deviceID = $sdnDevices_hash{$SdnDeviceDN};
            next unless $deviceID;
            foreach my $perfRow (@{$perf->{module_stat}}) {
                my $index = 1;
                foreach my $cpu_device ($perfRow->{cpu_stat}) {
                    next unless ($cpu_device->{idle});
                    my %cpu_row = (
                        DeviceID => $deviceID,
                        StartTime => $start_time,
                        EndTime => $end_time,
                        CpuIndex => $index++,
                        CpuBusy => int(100 - $cpu_device->{idle})
                   );
                   push @cpu, \%cpu_row;
                }
                foreach my $mem_device ($perfRow->{memory_stat}) {
                    next unless ($mem_device->{usage});
                    my %mem_row = (
                        DeviceID => $deviceID,
                        StartTime => $start_time,
                        EndTime => $end_time,
                        UsedMem => $mem_device->{usage},
                        FreeMem => int(100 - $mem_device->{usage}),
                        Utilization5Min => $mem_device->{usage}
                    );
                    push @memory, \%mem_row;
                } 
            }

            $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/cpu(orgDevices): " . scalar(@cpu) . " entries:");
            $self->{logger}->debug(Dumper(\@cpu)) if (scalar(@cpu));

            if (scalar @cpu) {
                $self->saveDeviceCpuStats(\@cpu);
                $self->updateDataCollectionStatus('CPU', 'OK', $deviceID);
            } else {
                $self->updateDataCollectionStatus('CPU', 'N/A', $deviceID);
            }
                
            $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance/memory(orgDevices): " . scalar(@memory) . " entries:");
            $self->{logger}->debug(Dumper(\@memory)) if (scalar(@memory));

            if (scalar @memory) {
                $self->saveDeviceMemStats(\@memory);
                $self->updateDataCollectionStatus('Memory', 'OK', $deviceID);
            } else {
                $self->updateDataCollectionStatus('Memory', 'N/A', $deviceID);
            }
        }        
    }
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainPerformance finished");
}
   
sub obtainEnvironment {
    my ($self, $sdnDevices, $orgs, $allEdgesStats, $orgDevices) = @_;
    
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: started");
    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    my %sdnDevices_hash = map { $_->{SdnDeviceDN}  => $_->{DeviceID} } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainEnvironment: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash));

    foreach my $org (@$orgDevices) {
        foreach my $dev (@{$org->{devices}}) {
            my @environment;
            my @cpu;
            my @memory;
            my $SdnDeviceDN = "$dev->{org_id}/$dev->{site_id}/$dev->{id}";
            my $deviceID = $sdnDevices_hash{$SdnDeviceDN};
            next unless $deviceID;
            foreach my $env (@{$dev->{'module_stat'}}) {
                my $index = 1;
                foreach my $fan_stat (@{$env->{fans}}){
                    my %fan = (
                        DeviceID => $deviceID,
                        StartTime => $start_time,
                        EndTime => $end_time,
                        envIndex => $index++,
                        envType => "fan",
                        envDescr => $fan_stat->{name},
                        envState => $fan_stat->{status},
                        envStatus => $fan_stat->{rpm},
                        envMeasure => "RPM"
                    );
                    push @environment, \%fan;
                }
                foreach my $temp_stat (@{$env->{temperatures}}) {
                    my %temp = (
                        DeviceID => $deviceID,
                        StartTime => $start_time,
                        EndTime => $end_time,
                        envIndex => $index++,
                        envType => "temperature",
                        envDescr => $temp_stat->{name},
                        envState => $temp_stat->{status},
                        envStatus => $temp_stat->{celsius},
                        envMeasure => "degrees C"
                    );
                    push @environment, \%temp;
                }
                foreach my $power_stat (@{$env->{psus}}) {
                    my %power = (
                        DeviceID => $deviceID,
                        StartTime => $start_time,
                        EndTime => $end_time,
                        envIndex => $index++,
                        envType => "power",
                        envDescr => $power_stat->{name},
                        envState => $power_stat->{status},
                    );
                    push @environment, \%power;
                }
            }

            if (scalar @environment) {
                $self->saveEnvironmental(\@environment);
                $self->updateDataCollectionStatus('Environmental', 'OK', $deviceID);
                $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: For DeviceID $deviceID - " . scalar(@environment) . " entries:");
                $self->{logger}->debug(Dumper(\@environment)) if (scalar(@environment));
            } else {
                $self->updateDataCollectionStatus('Environmental', 'N/A', $deviceID);
                $self->{logger}->warn("Mist[$self->{fabric_id}] obtainEnvironment: Not collected for DeviceID $deviceID");
            }
        }
    }
    $self->{logger}->info("Mist[$self->{fabric_id}] obtainEnvironment: finished");
}

sub obtainInterfaces {
    my ($self, $sdnDevices, $orgs, $allEdgesStats) = @_;
    
    my (@intdata, @lldpdata, @trunkdata, @ipaddr, @routes, @routes_devices, @lldp_devices);

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: started");
    my $timestamp = NetMRI::Util::Date::formatDate(time());
    $self->{dn}= "";

    my %sdnDevices_hash = map { $_->{SdnDeviceMac}  => {SdnDeviceID => $_->{SdnDeviceID},DeviceID => $_->{DeviceID},SdnDeviceDN => $_->{SdnDeviceDN} } } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainInterfaces: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash));

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

        foreach my $port (@$res) {
            my $SdnIntfMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/, ($port->{port_mac}) if $port->{port_mac};
            my $DeviceMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/, ($port->{mac}) if $port->{mac};
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
                my $neighbor_mac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/, ($port->{neighbor_mac});
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
    my $site_info = $self->loadSites();

    foreach my $site (@$site_info) {
        my ($fetched_data, $msg) = $api_helper->get_ipaddr($site->{id});
        unless ($fetched_data) {
            $self->{logger}->warn("Mist[$self->{fabric_id}] obtainInterfaces/get_ipaddr: No data for Site $site->{id}: " . ($msg || ''));
            next;
        }

        foreach my $res (@$fetched_data) {
            my ($routeIP, $routeNetmask, $routeGW) = ("", "", "");
            my $DeviceMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/,($res->{mac}) if ($res->{mac});

            if ($res->{ip_config}->{type} && $res->{ip_config}->{type} eq 'static') {
                $routeIP = $res->{ip_config}->{ip};
                $routeNetmask = $res->{ip_config}->{netmask};
                $routeGW = $res->{ip_config}->{gateway};
            }

            my $ip_values = $res->{if_stat};
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
            }    
        }
    }

    %sdnDevices_hash = map { $_->{SdnDeviceDN}  => {SdnDeviceID => $_->{SdnDeviceID}, DeviceID => $_->{DeviceID} } } @{$sdnDevices};
    $self->{logger}->debug("Mist[$self->{fabric_id}] obtainInterfaces: Hash sdnDevices_hash:");
    $self->{logger}->debug(Dumper(\%sdnDevices_hash));

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
                    my $SdnIntfMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/, ($edge->{port_stat}->{$edge_port}->{mac}) if $edge->{port_stat}->{$edge_port}->{mac};
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
        $self->{logger}->debug(Dumper(\@intdata));
        $self->saveSdnFabricInterface(\@intdata);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Trunks " . scalar(@trunkdata) . " entries:");
    if (scalar @trunkdata) {
        $self->{logger}->debug(Dumper(\@trunkdata));
        $self->saveVlanTrunkPortTable(\@trunkdata);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: IPADDresses " . scalar(@ipaddr) . " entries:");
    if (scalar @ipaddr) {
        $self->{logger}->debug(Dumper(\@ipaddr));
        $self->saveIPAddress(\@ipaddr);
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: LLDP " . scalar(@lldpdata) . " entries:");
    if (scalar @lldpdata) {
        $self->{logger}->debug(Dumper(\@lldpdata));
        $self->saveLLDP(\@lldpdata);
        $self->updateDataCollectionStatus('Neighbor', 'OK', $_) for @lldp_devices;
    }

    $self->{logger}->info("Mist[$self->{fabric_id}] obtainInterfaces: Routes " . scalar(@routes) . " entries:");
    if (scalar @routes) {
        $self->{logger}->debug(Dumper(\@routes));
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
            my $DeviceMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/,($port->{mac}) if ($port->{mac});
            my $deviceID = $sdnDevices_hash{$DeviceMac};
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
    $self->{logger}->debug(Dumper(\@lldpdata)) if (scalar(@lldpdata));

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
    my $sdnDevices = $self->loadSdnDevices(); 
    if ($sdnDevices) {
        my ($endhosts, $wireless_fwd, $vlans, $vlans_ids) = $self->getWirelessEndhosts($sdnDevices);
        # Collecting data without SdnInterfaceID 
        $self->saveMistSdnEndpoint($endhosts);
        $self->saveVlanObject($vlans);
        $self->savebsnMobileStationTable($wireless_fwd);
        $self->updateDataCollectionStatus('Vlans', 'OK',$_) for $vlans_ids;

        my ($forwarding_info, $forwarding_ids);
        ($endhosts, $forwarding_info, $vlans, $vlans_ids, $forwarding_ids) = $self->getWiredEndhosts($sdnDevices);    
        # Collecting data with SdnInterfaceID 
        $self->saveSdnEndpoint($endhosts);
        $self->saveForwarding($forwarding_info);
        $self->saveVlanObject($vlans);
        $self->updateDataCollectionStatus('Forwarding', 'OK',$_) for $forwarding_ids;
        $self->updateDataCollectionStatus('Vlans', 'OK',$_) for $vlans_ids;
    } else {
        $self->{logger}->warn("Mist[$self->{fabric_id}] obtainEndhosts: The SdnDevices are not collected");
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

            $endhostMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/,($endhost->{mac}) if ($endhost->{mac});
            next unless $endhostMac;

            $apMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/,($endhost->{ap_mac}) if ($endhost->{ap_mac});
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
    $self->{logger}->debug(Dumper(\@endhosts)) if (scalar(@endhosts));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: LLDPAP " . scalar(@wireless_fwd) . " entries:");
    $self->{logger}->debug(Dumper(\@wireless_fwd)) if (scalar(@wireless_fwd));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: VLAN " . scalar(@vlans) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans)) if (scalar(@vlans));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWirelessEndhosts: VLAN ID " . scalar(@vlans_ids) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans_ids)) if (scalar(@vlans_ids));

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
            my $endhostMac = join ':', map {sprintf "%s", $_} split /(?(?{ pos() % 2 })(?!))/,($endhost->{mac});
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
    $self->{logger}->debug(Dumper(\@endhosts)) if (scalar(@endhosts));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: Forwarding " . scalar(@forwarding_info) . " entries:");
    $self->{logger}->debug(Dumper(\@forwarding_info)) if (scalar(@forwarding_info));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: Forwarding ID " . scalar(@forwarding_ids) . " entries:");
    $self->{logger}->debug(Dumper(\@forwarding_ids)) if (scalar(@forwarding_ids));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: VLAN " . scalar(@vlans) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans)) if (scalar(@vlans));
    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: VLAN ID " . scalar(@vlans_ids) . " entries:");
    $self->{logger}->debug(Dumper(\@vlans_ids)) if (scalar(@vlans_ids));

    $self->{logger}->info("Mist[$self->{fabric_id}] getWiredEndhosts: finished");

    return \@endhosts,\@forwarding_info,\@vlans,\@vlans_ids,\@forwarding_ids;
}

1;
