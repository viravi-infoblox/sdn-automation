package NetMRI::SDN::Viptela;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use NetMRI::SDN::Base;
use base 'NetMRI::SDN::Base';
use NetMRI::Util::Date;
use NetMRI::Util::Network qw (netmaskFromPrefix InetAddr maskStringFromPrefix);
use NetMRI::Util::Wildcard::V4;
use NetMRI::Util::Validate qw (isValidIPv4 isValidNetmask);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{vendor_name} = 'Cisco Viptela';
    return bless $self, $class;
}

sub getDevices {
    my $self = shift;
    
    $self->{logger}->debug("Viptela getDevices started");

    my $api_helper = $self->getApiClient();

    $self->{logger}->debug("Calling get_devices of Viptela HTTP client");

    my ($res, $message) = $api_helper->get_devices();

    unless (defined $res) {
        $self->{logger}->warn("Viptela getDevices failed for SdnControllerId=$self->{fabric_id}: " . Dumper($message));
        return [];
    }
    $self->{logger}->debug("Viptela getDevices received info: ");
    $self->{logger}->debug(Dumper($res));

    my @devices;
    foreach my $dev (@$res) {
        # NETMRI-34506: don't request data for unreachable devices
        next unless ($dev->{reachability} eq 'reachable');

        # SDN-72 - NI has troubles with displaying utf-8 charachers
        # so we replace such characters within "name" field
        my %device = (
            SdnControllerId => $api_helper->{fabric_id},
            SdnDeviceDN => $dev->{deviceId},
            IPAddress => $dev->{'system-ip'} || $dev->{deviceId},
            Name => $self->_get_device_name($dev),
            NodeRole => $dev->{'device-type'},  # device-type can be: vmanage, vsmart, vbond, vedge
            Vendor => $self->{vendor_name},
            Model => $dev->{'device-model'},
            Serial => $dev->{'uuid'},
            SWVersion => $dev->{version},            
            modTS => NetMRI::Util::Date::formatTimestamp($dev->{lastupdated}/1000),
            UpTime => ($dev->{'uptime-date'} || 0)/1000    # UpTime value is returned in msec
        );

        next unless ($device{IPAddress});  # skip devices without IP address

        push @devices, \%device;

    }
    $self->{logger}->debug("Viptela getDevices finished");
    return \@devices;
}

sub handle_error {
    my $self = shift;
    my $resp = shift;
    my $datapoint = shift;
    my $dataset = shift || 0;

    my $err_text = "Viptela $datapoint failed for device $self->{dn}: ";
    my $reach_text = "$datapoint failed";

    if (defined $resp->{message} && $resp->{message} eq 'Bad Request') {
        $self->setUnreachable($reach_text);
        $err_text .= "device unreachable (400)";
    } else {
        $err_text .= Dumper $resp;
    }
    $self->{logger}->warn($err_text);

    $self->updateDataCollectionStatus($dataset, 'Error') if ($dataset);
}


sub obtainSystemInfo {
    my $self = shift;
    $self->{logger}->debug("Viptela SystemInfo and Inventory collection started");
    return unless my $device_id = $self->getDeviceID('obtainSystemInfo: ' . $self->{warning_no_device_id_assigned});
   
    my $start_time = NetMRI::Util::Date::formatDate(time()); 
    my $api_helper = $self->getApiClient();

    $self->{logger}->debug("Calling get_device_info of Viptela client for device $self->{dn}");
    my ($dev, $message) = $self->{api_helper}->get_device_info($self->{dn});
    unless ($dev) {
        $self->handle_error($message, 'obtainSystemInfo', 'System');
        return;
    }
    $self->{logger}->debug("obtainSystemInfo: get_device_info received device: ");
    $self->{logger}->debug(Dumper($dev));

    $self->{logger}->debug("Calling get_hardware of Viptela client for device $self->{dn}");
    my ($res, $message1) = $api_helper->get_hardware($self->{dn}, "inventory");
    unless ($res) {
        $self->handle_error($message1, 'obtainSystemInfo-Inventory', 'Inventory');
        return undef;
    }    
    $self->{logger}->debug("Viptela DeviceID=$device_id received inventory info: ");
    $self->{logger}->debug(Dumper($res));

    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);
    my $device = {
        LastTimeStamp => $end_time,
        Name => $self->_get_device_name($dev->[0]),
        Vendor => $self->{vendor_name},
        Model => $dev->[0]->{'device-model'} || '',
        SWVersion => $dev->[0]->{version} || '',
        UpTime => ($dev->[0]->{'uptime-date'} || 0)/1000,
        SdnControllerId => $api_helper->{fabric_id} || ''
    };

    my @inventory;
    my $index = 1;
    my %inv = (
            DeviceID               => $device_id,
            entPhysicalSerialNum   => $dev->[0]->{'uuid'},
            entPhysicalModelName   => $dev->[0]->{'device-model'},
            entPhysicalFirmwareRev => $dev->[0]->{version},
            entPhysicalIndex       => $index++,
            entPhysicalClass       => 'chassis',
            entPhysicalDescr       => 'Board Serial',
            StartTime              => $start_time,
            EndTime                => $end_time
    );
    push @inventory, \%inv;

    foreach my $inv_row (@$res) {
        my %inv = (
            DeviceID => $device_id,
            StartTime => $start_time,
            EndTime => $end_time,
            entPhysicalIndex => $index++,
            entPhysicalDescr => $inv_row->{'hw-description'}
        );
        # Class 'chassis' has already been defined for board serial number.
        $inv{entPhysicalClass} = $inv_row->{'hw-type'} eq 'Chassis' ? 'other' : $inv_row->{'hw-type'}; 
        $inv{entPhysicalModelName} = $inv_row->{'part-number'} unless ( $inv_row->{'part-number'} eq 'None' );
        $inv{entPhysicalHardwareRev} = $inv_row->{version} unless ( $inv_row->{version} eq 'None' );
        $inv{entPhysicalSerialNum} = $inv_row->{'serial-number'} unless ( $inv_row->{'serial-number'} eq 'None' );

        push @inventory, \%inv;
    }

    if ($device_id) {
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];

        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysModel', '', 'SNMP'], $device->{Model}) if $device->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysName', '', 'SNMP'], $device->{Name}) if $device->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVendor', '', 'SNMP'], $self->{vendor_name});
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVersion', '', 'SNMP'], $device->{SWVersion} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'SdnControllerId', '', 'NetMRI'], $device->{SdnControllerId}) if $device->{SdnControllerId};
    }

    $self->saveSystemInfo($device);
    $self->saveInventory(\@inventory);
    $self->setReachable();
    $self->updateDataCollectionStatus('System', 'OK');
    scalar @inventory ? $self->updateDataCollectionStatus('Inventory', 'OK') : $self->updateDataCollectionStatus('Inventory', 'N/A');
    $self->{logger}->debug("Viptela DeviceID=$device_id SystemInfo and Inventory collection finished");
}

sub obtainInterfaces {
    my $self = shift;
    $self->{logger}->debug("Viptela obtainInterfaces started");
    return [] unless my $device_id = $self->getDeviceID('obtainInterfaces: ' . $self->{warning_no_device_id_assigned});

    my $start_time = NetMRI::Util::Date::formatDate(time());

    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_interfaces of Viptela client for device $self->{dn}");
    my ($res, $message) = $api_helper->get_interfaces($self->{dn});
    unless ($res) {
        $self->handle_error($message, 'obtainInterfaces');
        return undef;
    }

    $self->{logger}->debug("Viptela device $device_id received interfaces info: ");
    $self->{logger}->debug(Dumper($res));

    my @if_config_rows;
    my @if_status_rows;
    my @if_addr_rows;
    my @if_vrf_rows;
    # my @if_perf_rows;
    my %if_config;
    my %if_status;
    # my %if_perf;
    my $addr_num;
    my $IPAddressDotted;
    my $netmask_num;
    my $subnet;
    my $foundIPAddr = 0; # 0 - not found, 1 - found IPv4 or IPv6, 4 - found IPv4, 6 - found IPv6
    
    foreach my $intf ( @$res ) {
        # Example:
        # "ip-address": "10.10.20.99/24"
        if ( $intf->{'ip-address'} =~ /(.+)\/(\d+)/ || $intf->{'ipv6-address'} =~ /(.+)\/(\d+)/) {
            $IPAddressDotted = $1;
            $addr_num = InetAddr($IPAddressDotted); 
            $netmask_num = netmaskFromPrefix($intf->{'af-type'}, $2);
            $foundIPAddr = 1;
        } elsif (isValidIPv4($intf->{'ip-address'}) && isValidNetmask($intf->{'ipv4-subnet-mask'})) {
            $IPAddressDotted = $intf->{'ip-address'};
            $addr_num = InetAddr($IPAddressDotted); 
            $netmask_num = InetAddr($intf->{'ipv4-subnet-mask'});
            $foundIPAddr = 4;
        } else {
            $foundIPAddr = 0;
        }
        if ($foundIPAddr) {
            eval {
                my $addr_bigint = Math::BigInt->new("$addr_num");
                my $mask_bigint = Math::BigInt->new("$netmask_num");
                $subnet = $addr_bigint->band($mask_bigint);
            };
            $self->{logger}->warn("Cannot compute subnet address for IP $addr_num ($1) and mask $netmask_num (/$2): $@") if ($@);
            if ( $subnet ) {
                my %if_addr;
                $if_addr{IPAddress} = $addr_num;
                $if_addr{DeviceID} = $device_id;
                $if_addr{Timestamp} = $start_time;
                $if_addr{ifIndex} = $intf->{ifindex};
                $if_addr{NetMask} = $netmask_num;
                $if_addr{IPAddressDotted} = $IPAddressDotted;
                $if_addr{SubnetIPNumeric} = $subnet;

                push @if_addr_rows, \%if_addr;
            }
        }

        # We can have 2 entries with the same ifIndex value: one for ipv4 address family, another for ipv6.
        # There is no need to reassign values cause they are the same for both families 
        unless ( exists $if_config{$intf->{ifindex}} ) {
            my $ifType = 'ethernet-csmacd' if ( $intf->{ifname} =~ /^(?:eth|ge)/ );
            $if_config{$intf->{ifindex}}{DeviceID} = $device_id;
            $if_config{$intf->{ifindex}}{ifIndex} = $intf->{ifindex};
            $if_config{$intf->{ifindex}}{Timestamp} = $start_time;
            $if_config{$intf->{ifindex}}{Name} = $intf->{ifname} || '';
            $if_config{$intf->{ifindex}}{Descr} = $intf->{desc} || '';
            $if_config{$intf->{ifindex}}{Type} = $ifType || $intf->{'port-type'};
            $if_config{$intf->{ifindex}}{Mtu} = $intf->{mtu};
            $if_config{$intf->{ifindex}}{PhysAddress} = ( exists $intf->{hwaddr} ) ? uc($intf->{hwaddr}) : '00:00:00:00:00:00';
            $if_config{$intf->{ifindex}}{Duplex} = $intf->{duplex};

            $if_status{$intf->{ifindex}}{DeviceID} = $device_id;
            $if_status{$intf->{ifindex}}{ifIndex} = $intf->{ifindex};
            $if_status{$intf->{ifindex}}{Timestamp} = $start_time;
            $if_status{$intf->{ifindex}}{PerfStartTime} = $start_time;
            $if_status{$intf->{ifindex}}{Speed} = $intf->{'speed-mbps'} * 1000000 if ( exists $intf->{'speed-mbps'} );
            $if_status{$intf->{ifindex}}{AdminStatus} = lc($intf->{'if-admin-status'});
            $if_status{$intf->{ifindex}}{OperStatus} = lc($intf->{'if-oper-status'});
            if ( exists $intf->{'uptime-date'} ) {
                my $lastchange_raw = $intf->{'uptime-date'}/1000;
                $if_status{$intf->{ifindex}}{LastChange} = NetMRI::Util::Date::formatTimestamp($lastchange_raw);
                $if_status{$intf->{ifindex}}{LastChangeRaw} = $lastchange_raw;
            }
            push @if_config_rows, $if_config{$intf->{ifindex}};
            push @if_status_rows, $if_status{$intf->{ifindex}};

            my %if_vrf = (
                DeviceID => $device_id,
                vrfName => 'vpn ' . $intf->{'vpn-id'},
                Interface => $intf->{ifname},
                Timestamp => $start_time
            );
            push @if_vrf_rows, \%if_vrf;
        }
    }

# TODO: Interface performance data collection and procesing
=head1
        $if_perf{$intf->{ifindex}}{DeviceID} = $device_id;
        $if_perf{$intf->{ifindex}}{ifIndex} = $intf->{ifindex};
        $if_perf{$intf->{ifindex}}{ifSpeed} = $intf->{'speed-mbps'} * 1000000;
        #$if_perf{$intf->{ifindex}}{ifTotalChanges} = 0;
        $if_perf{$intf->{ifindex}}{ifInOctets} += $intf->{'rx-octets'};
        $if_perf{$intf->{ifindex}}{ifInUcastPkts} += $intf->{'rx-packets'};
        #$if_perf{$intf->{ifindex}}{ifInNUcastPkts} = $intf->{};
        #$if_perf{$intf->{ifindex}}{ifInMulticastPkts} = $intf->{};
        #$if_perf{$intf->{ifindex}}{ifInBroadcastPkts} = $intf->{};
        $if_perf{$intf->{ifindex}}{ifInDiscards} += $intf->{'rx-drops'};
        $if_perf{$intf->{ifindex}}{ifInErrors} += $intf->{'rx-errors'};
        $if_perf{$intf->{ifindex}}{ifOutOctets} += $intf->{'tx-octets'};
        $if_perf{$intf->{ifindex}}{ifOutUcastPkts} += $intf->{'tx-packets'};
        #$if_perf{$intf->{ifindex}}{ifOutNUcastPkts} = $intf->{};
        #$if_perf{$intf->{ifindex}}{ifOutMulticastPkts} = $intf->{};
        #$if_perf{$intf->{ifindex}}{ifOutBroadcastPkts} = $intf->{};
        $if_perf{$intf->{ifindex}}{ifOutDiscards} += $intf->{'tx-drops'};
        $if_perf{$intf->{ifindex}}{ifOutErrors} += $intf->{'tx-errors'};
    }

    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);
    foreach my $ifIndex (keys %if_perf) {
        $if_perf{$ifIndex}{StartTime} = $start_time;
        $if_perf{$ifIndex}{EndTime} = $end_time;
        push @if_perf_rows, $if_perf{$ifIndex};
    }
=cut

    $self->saveifConfig(\@if_config_rows);
    $self->saveifStatus(\@if_status_rows);
    # $self->saveifPerf(\@if_perf_rows);
    $self->saveIPAddress(\@if_addr_rows);
    $self->saveVrfHasInterface(\@if_vrf_rows);
    $self->setReachable();
    $self->{logger}->debug("Viptela device $device_id obtainInterfaces finished");
}

sub obtainRoute {
    my $self = shift;
    $self->{logger}->debug("Viptela obtainRoute started");
    return unless my $device_id = $self->getDeviceID('obtainRoute: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_ip of Viptela client for device $self->{dn}");
    my ($res, $message) = $api_helper->get_ip($self->{dn},'routetable');
    unless ($res) {
        $self->handle_error($message, 'obtainRoute', 'Route');
        return undef;
    }
    $self->{logger}->debug("Viptela (DeviceID=$device_id) received route info: "); 
    $self->{logger}->debug(Dumper($res));

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my @vrf_routes;
    my %vrf;
    my @vrfs;

    foreach my $rt (@$res) {
        next unless $rt->{protocol};
        $rt->{prefix} =~ /([0-9a-fA-F.:]+)\/(\d+)/;
        my $route_dest = $1;
        my $route_dest_prefix = $2;

        my $nexthop_addr = $rt->{'nexthop-addr'} if (exists $rt->{'nexthop-addr'});
        my $route_type = ($rt->{protocol} =~ /connected/) ? "local" : "remote";

        my %vrf_route = (
            DeviceID => $device_id,
            vrfName => 'vpn ' . $rt->{'vpn-id'},
            Destination => $route_dest,
            Interface => $rt->{'nexthop-ifname'} || '',
            Metric1 => -1,
            Metric2 => -1,
            NextHop => $nexthop_addr || '',
            Protocol => $rt->{protocol},
            Type => $route_type,
            Timestamp => $timestamp
        ); 
        $vrf_route{Mask} = maskStringFromPrefix($rt->{prefix});

        push @vrf_routes, \%vrf_route;        

        if ( exists $vrf{$rt->{'vpn-id'}} ) {
            $vrf{$rt->{'vpn-id'}}{CurrentCount}++;
        } else {
            $vrf{$rt->{'vpn-id'}}{DeviceID} = $device_id;
            $vrf{$rt->{'vpn-id'}}{Name} = 'vpn ' . $rt->{'vpn-id'};
            $vrf{$rt->{'vpn-id'}}{Description} = 'vpn ' . $rt->{'vpn-id'};
            $vrf{$rt->{'vpn-id'}}{CurrentCount} = 1;
            $vrf{$rt->{'vpn-id'}}{Timestamp} = $timestamp;
        }
        push @vrfs, $vrf{$rt->{'vpn-id'}};
    }
 
    $self->saveVrfRoute(\@vrf_routes);
    $self->saveVrf(\@vrfs);
    $self->setReachable();
    scalar @vrf_routes ? $self->updateDataCollectionStatus('Route', 'OK') : $self->updateDataCollectionStatus('Route', 'N/A');
    scalar @vrfs ? $self->updateDataCollectionStatus('Vrf', 'OK') : $self->updateDataCollectionStatus('Vrf', 'N/A');
    $self->{logger}->debug("Viptela (DeviceID=$device_id) obtainRoute finished");
}

sub obtainArp {
    my $self = shift;
    $self->{logger}->debug("Viptela obtainArp started");
    return unless my $device_id = $self->getDeviceID('obtainArp: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_arp of Viptela client for device $self->{dn}");
    my ($res, $message) = $api_helper->get_arp($self->{dn});

    unless ($res) {
        $self->handle_error($message, 'obtainARP', 'ARP');
        return undef;
    }
    $self->{logger}->debug("Viptela (DeviceID=$device_id) received arp info: ");
    $self->{logger}->debug(Dumper($res));

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my @vrf_arps;

    foreach my $arp_row (@$res) {
        my %vrf_arp = (
            DeviceID => $device_id,
            vrfName => 'vpn ' . $arp_row->{'vpn-id'},
            Protocol => '',
            Address => $arp_row->{ip},
            Age => 0,
            HardwareAddress => $arp_row->{mac},
            Type => 'arp',
            Interface => $arp_row->{'if-name'},
            Timestamp => $timestamp           
        );

        push @vrf_arps, \%vrf_arp;        
    }

    $self->saveVrfARP(\@vrf_arps);    
    $self->setReachable();
    scalar @vrf_arps ? $self->updateDataCollectionStatus('ARP', 'OK') : $self->updateDataCollectionStatus('ARP', 'N/A');
    $self->{logger}->debug("Viptela (DeviceID=$device_id) obtainArp finished");
}

sub obtainPerformance {
    my $self = shift;
    $self->{logger}->debug("Viptela obtainPerformance started");
    return unless my $device_id = $self->getDeviceID('obtainPerformance: ' . $self->{warning_no_device_id_assigned});
    my $start_time = NetMRI::Util::Date::formatDate(time()); 
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_system of Viptela client for device $self->{dn}");
    my ($res, $message) = $api_helper->get_system($self->{dn});

    unless ($res) {
        $self->handle_error($message, 'obtainPerformance', 'CPU');
        $self->updateDataCollectionStatus('Memory', 'Error');
        return undef;
    }

    $self->{logger}->debug("Viptela (DeviceID=$device_id) received performance info: ");
    $self->{logger}->debug(Dumper($res));

    my @cpu;
    my @memory;
    my @storage;
    my $storage_index = 1;
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);

    foreach my $perf (@$res) {   
        if ( $perf->{cpu_idle} && $perf->{cpu_idle} =~ /\d+/ ) {
            my %cpu_row = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                CpuIndex => "1",
                CpuBusy => int(100 - $perf->{cpu_idle})
            );
            push @cpu, \%cpu_row;
        }
        
        # Devices return amount of memory in KBytes, NetMRI stores in Bytes
        if ( $perf->{mem_total} && $perf->{mem_free} && $perf->{mem_total} =~ /^\d+$/ && $perf->{mem_free} =~ /^\d+$/ ) {
            my $util_mem = int( (($perf->{mem_total} - $perf->{mem_free}) / $perf->{mem_total}) * 100 );
            my %mem_row = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                UsedMem => ($perf->{mem_total} - $perf->{mem_free}) * 1024,
                FreeMem => $perf->{mem_free} * 1024,
                Utilization5Min => $util_mem
            );
            push @memory, \%mem_row;
        }

        if ( $perf->{'disk_size'} && $perf->{'disk_used'} &&  $perf->{'disk_size'} =~ /^\d+/ && $perf->{'disk_used'} =~ /^\d+/ ) {
            my ($disk_size) = $perf->{'disk_size'} =~ /(\d+)/;
            my ($disk_used) = $perf->{'disk_used'} =~ /(\d+)/;
            my %general_storage = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                hrStorageAllocationUnits => 1024
            );

            $general_storage{hrStorageSize} = $disk_size * $general_storage{hrStorageAllocationUnits} * 1024;
            $general_storage{hrStorageUsed} = $disk_used * $general_storage{hrStorageAllocationUnits} * 1024;
            $general_storage{hrStorageIndex} = $storage_index++;
            $general_storage{hrStorageDescr} = $perf->{disk_mount} || '';
            push @storage, \%general_storage;
        }

        # Available on vmanage
        if ( $perf->{'vmanage-storage-disk-size'} && $perf->{'vmanage-storage-disk-used'} && $perf->{'vmanage-storage-disk-size'} =~ /^\d+/ && $perf->{'vmanage-storage-disk-used'} =~ /^\d+/ ) {
            my ($disk_size) = $perf->{'vmanage-storage-disk-size'} =~ /(\d+)/;
            my ($disk_used) = $perf->{'vmanage-storage-disk-used'} =~ /(\d+)/;
            my %vmanage_storage = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                hrStorageAllocationUnits => 1024
            );
            $vmanage_storage{hrStorageSize} = $disk_size * $vmanage_storage{hrStorageAllocationUnits} * 1024;
            $vmanage_storage{hrStorageUsed} = $disk_used * $vmanage_storage{hrStorageAllocationUnits} * 1024;
            $vmanage_storage{hrStorageIndex} = $storage_index++;
            $vmanage_storage{hrStorageDescr} = $perf->{'vmanage-storage-disk-mount'} || '';
            push @storage, \%vmanage_storage;
        }
    }
    $self->saveDeviceCpuStats(\@cpu) if (scalar @cpu);
    $self->saveDeviceMemStats(\@memory) if (scalar @memory);
    $self->savehrStorageTable(\@storage) if (scalar @storage);
    $self->setReachable();
    scalar @cpu ? $self->updateDataCollectionStatus('CPU', 'OK') : $self->updateDataCollectionStatus('CPU', 'N/A');
    scalar @memory ? $self->updateDataCollectionStatus('Memory', 'OK') : $self->updateDataCollectionStatus('Memory', 'N/A');
    $self->{logger}->debug("Viptela (DeviceID=$device_id) obtainPerformance finished");
}

sub obtainEnvironment {
    my $self = shift;
    $self->{logger}->debug("Viptela obtainEnvironment started");
    return unless my $device_id = $self->getDeviceID('obtainEnvironment: ' . $self->{warning_no_device_id_assigned});
    my $start_time = NetMRI::Util::Date::formatDate(time());
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_hardware(environment) of Viptela client for device $self->{dn}");
    my ($res, $message) = $api_helper->get_hardware($self->{dn}, "environment");

    unless ($res) {
        $self->handle_error($message, 'obtainEnvironment', 'Environmental');
        return undef;
    }

    $self->{logger}->debug("Viptela (DeviceID=$device_id) received environment info: ");
    $self->{logger}->debug(Dumper($res));

    my @environment;
    my $end_time = NetMRI::Util::Date::formatDate(time() + 1);
    my $index = 1;

    foreach my $env_row (@$res) {
        next unless $env_row->{'hw-class'};
        if ( $env_row->{'hw-class'} eq "Temperature Sensors" && $env_row->{measurement} =~ /(\d+)\s+(degrees C)/ ) {
            my %env = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                envIndex => $index++,
                envType => "temperature",
                envDescr => $env_row->{'hw-item'} . " " . $env_row->{'hw-dev-index'},
                envState => $env_row->{status},
                envStatus => $1,
                envMeasure => $2
            );
            push @environment, \%env;
        }

        if ( $env_row->{'hw-class'} eq "Fans" && $env_row->{measurement} =~ /Spinning at (\d+)/ ) {
            my %env = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                envIndex => $index++,
                envType => "fan",
                envDescr => $env_row->{'hw-item'} . " " . $env_row->{'hw-dev-index'},
                envState => $env_row->{status},
                envStatus => $1,
                envMeasure => "RPM"
            );
            push @environment, \%env;
        }

        if ( $env_row->{'hw-class'} eq "PEM" ) {
            my %env = (
                DeviceID => $device_id,
                StartTime => $start_time,
                EndTime => $end_time,
                envIndex => $index++,
                envType => "power",
                envDescr => $env_row->{'hw-item'} . " " . $env_row->{'hw-dev-index'},
                envState => $env_row->{status}
            );
            push @environment, \%env;
        }
    }

    $self->saveEnvironmental(\@environment);
    $self->setReachable();
    scalar @environment ? $self->updateDataCollectionStatus('Environmental', 'OK') : $self->updateDataCollectionStatus('Environmental', 'N/A');
    $self->{logger}->debug("Viptela (DeviceID=$device_id) obtainEnvironment finished");
}

sub getApiClient {
    my $self = shift;
    unless (ref($self->{api_helper})) {
        $self->{logger}->error("Error getting the Viptela API Client: $@") if $@;
        return undef;
    }
    return $self->{api_helper};
}

sub _get_device_name {
    my ($self, $dev) = @_;
    return $self->_remove_utf8($dev->{'host-name'}) || '(no name)';
}

sub _remove_utf8 {
    my ($self, $str) = @_;
    return Encode::encode("ISO-8859-1", $str || '');
}

1;
