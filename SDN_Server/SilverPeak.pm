package NetMRI::SDN::SilverPeak;
use strict;
use warnings;
use Encode;
use Data::Dumper;
use NetMRI::SDN::Base;
use base 'NetMRI::SDN::Base';
use Date::Parse;
use NetMRI::Util::Date;
use NetMRI::Util::Network qw (netmaskFromPrefix maskStringFromPrefix InetAddr);
use NetMRI::Util::Wildcard::V4;
use Net::IP;
use NetAddr::IP;
use NetMRI::Util::Subnet qw (subnet_matcher);

sub new {
    my $class = shift;
    
    my $self = $class->SUPER::new(@_);
    $self->{vendor_name} = 'SilverPeak';
    return bless $self, $class;
}

sub getApiClient {
    my $self = shift;
    
    unless (ref($self->{api_helper})) {
        $self->{logger}->error("Error getting the SilverPeak API Client: $@") if $@;
        return undef;
    }
    return $self->{api_helper};
}

sub getSdnDevices {
    my $self = shift;
    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveDevices');
    my $query;

    if ($self->{dn} eq '' ) {
        $query = "select * from " . $device_plugin->target_table() . " where SdnControllerId=" . $sql->escape($self->{fabric_id});
    } else {
        $query = "select * from " . $device_plugin->target_table() . " where SdnDeviceDN = " . $sql->escape($self->{dn}) . " and SdnControllerId=" . $sql->escape($self->{fabric_id});
    }
    my $sdnDevices = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$sdnDevices) {
        $self->{logger}->info("No devices for FabricID " . $self->{fabric_id});
        return;
    }
    return \@$sdnDevices;
}

sub getDevices { 
    my $self = shift;
    my @devices;
    $self->{logger}->debug("getDevices started");
    my $api_helper = $self->getApiClient();

    my ($devices, $message) =$self->{api_helper}->get_silverpeak_devices();
    unless (defined $devices) {
        $self->{logger}->warn('getDevices for SilverPeak failed: ' . $message);
	return [];
    }
    foreach my $dev (@$devices) {
        next unless ($dev->{IP}); # skip devices without IP address
	push @devices,{
	    SdnControllerId => $api_helper->{fabric_id},
	    IPAddress => $dev->{IP},
	    SdnDeviceDN => "$dev->{id}",
	    Name => $dev->{hostName},
	    NodeRole => "SilverPeak $dev->{mode}",
	    Vendor => $self->{vendor_name},
	    Model => $dev->{model},
	    Serial => $dev->{serial} || 'N/A',
	    SWVersion => $dev->{softwareVersion},
        };
    }
    $self->{logger}->debug("getDevices finished");
    $self->{logger}->debug(Dumper());
    return \@devices;

}
sub obtainEverything {
    my $self = shift;
    my $sdnDevices = $self->getSdnDevices();
    return unless $sdnDevices;
    $self->obtainInventory($sdnDevices);
    $self->obtainInterfaces($sdnDevices);
    $self->obtainArp($sdnDevices);
    $self->obtainRoute($sdnDevices);
    
}
sub obtainSystemInfo {

    my $self = shift;
    my $sdnDevices = $self->getSdnDevices();
    return unless $sdnDevices;
    $self->{logger}->debug("obtainSystemInfo started for SilverPeak");
    
    foreach my $dev (@$sdnDevices) {
        next unless ($dev->{DeviceID});
        my $device_id = $dev->{DeviceID};
        $self->{dn} = $dev->{SdnDeviceDN};
        $self->{device_info_loaded} = 0;
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
        };
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysModel', '', 'SNMP'], $dev->{Model}) if $dev->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysName', '', 'SNMP'], $self->_remove_utf8($dev->{Name})) if $dev->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVendor', '', 'SNMP'], $dev->{vendor_name});
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVersion', '', 'SNMP'], $dev->{SWVersion} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'DeviceMAC', '', 'SNMP'], $dev->{SdnDeviceMac} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{SdnControllerId}) if $dev->{SdnControllerId};

        $self->saveSystemInfo($device);
        $self->updateDataCollectionStatus('System', 'OK', $device_id) if ($device);
        $self->{logger}->debug("obtainSystemInfo finished" . Dumper($device));
    }
}   

sub obtainInventory {
   
    my ($self, $sdnDevices) = @_;
    my @inventory;
    return unless $sdnDevices;
    $self->{logger}->debug("obtainInventory started for SilverPeak");

    foreach my $dev (@$sdnDevices) {
        next unless ($dev->{DeviceID});
        my $device_id = $dev->{DeviceID};
        $self->{dn} = $dev->{SdnDeviceDN};
        push @inventory, {
                DeviceID               => $device_id,
                entPhysicalSerialNum   => $dev->{Serial} || 'N/A',
                entPhysicalModelName   => $dev->{Model},
                entPhysicalFirmwareRev => $dev->{SWVersion} || 'SilverPeak OS',
                entPhysicalName        => $dev->{Name},
                entPhysicalIndex       => '1',
                entPhysicalClass       => 'chassis',
                StartTime              => NetMRI::Util::Date::formatDate(time()),
                EndTime                => NetMRI::Util::Date::formatDate(time())
        };
        $self->updateDataCollectionStatus('Inventory', 'OK', $device_id) if (@inventory);
    }

    $self->{logger}->debug("Inventory data collected: " . Dumper(@inventory));
    $self->saveInventory(\@inventory);
}

sub obtainInterfaces {
    my ($self, $sdnDevices) = @_;
    my (@intdata,@ifaddr,@ifvlans,@dev_vlans,@trunk_vlans);
    $self->{logger}->debug("obtainInterfaces started");
    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my $plugin = $self->getPlugin('SaveSdnFabricInterface');
    foreach my $dev (@$sdnDevices) {
	$self->{dn} = $dev->{SdnDeviceDN};
        my ($res, $msg) = $self->{api_helper}->get_silverpeak_intf($dev->{SdnDeviceDN});
        unless ($res) {
            $self->{logger}->warn("obtainInterfaces: get_silverpeak_intf failed for SilverPeak device $dev->{SdnDeviceDN}: ".($msg||''));
            next;
        }
        my $sdnDeviceID = $dev->{SdnDeviceID};
        my $deviceID = $dev->{DeviceID};
        $self->{logger}->debug("recieved interface info for Device $dev->{SdnDeviceDN} ==> ");
        $self->{logger}->debug(Dumper($res));
        foreach my $data ($res->{ifInfo}) {
            next unless $data;
            foreach my $port (@$data) {
                $self->{interface_map_loaded} = 0;
                $self->{device_info_loaded} = 0;
                my $if_index;
                my $sdn_interface_data = $self->{sql}->table("select SdnInterfaceID, Name  from " . $plugin->target_table() . " where SdnDeviceID = " . $sdnDeviceID, AllowNoRows => 1, RefWanted => 1);
                if ($sdn_interface_data && @$sdn_interface_data) {
                    $if_index = $self->getInterfaceIndex($port->{ifname});
                    unless($if_index) {
                        $self->{logger}->warn("getSwitchPort: can't determine ifIndex for interface with name=$port->{ifname} for SilverPeak DeviceID $deviceID");
                    }
                }
                my $speed = ($port->{speed} =~ /(\d+)/ ? "$1" : "");
                $speed = int($speed * 1000) if ($speed ne ''); 
                my $addr_dotted = $port->{ipv4} if (defined $port->{ipv4});
                my $addr_num = InetAddr($addr_dotted) if (defined $addr_dotted && $addr_dotted ne '');
                my $mask = $port->{ipv4mask};
                my $address_family = (($addr_dotted =~ /:/) ? "ipv6" : "ipv4") if ($addr_dotted);
                my $netmask_num = netmaskFromPrefix($address_family,$mask);
                my $addr_bigint = Math::BigInt->new("$addr_num") if ($addr_num);
                my $mask_bigint = Math::BigInt->new("$netmask_num") if ($netmask_num);
                my $subnet = $addr_bigint->band($mask_bigint) if ($mask_bigint);
                my $type = (($port->{ifname} =~ /([A-z]+)/) ? "$1" : "NA") if ($port->{ifname});
                my $duplex = (($port->{duplex} =~ /full/) ? "full" : "Unknown") if ($port->{duplex});
                push @intdata, {
                    SdnDeviceID => $sdnDeviceID,
                    Name => $port->{ifname},
                    Descr => "Interface name " .$port->{ifname},
                    MAC => $port->{mac},
                    operSpeed => $speed,
                    Timestamp => $timestamp,
                    Duplex => $duplex,
                    Type => $type,
                };
                if ($addr_dotted && $if_index) {
                    push @ifaddr, {
                        DeviceID => $deviceID,
                        ifIndex => $if_index,
                        Timestamp => $timestamp,
                        IPAddress => $addr_num,
                        IPAddressDotted => $addr_dotted,
                        NetMask => $netmask_num || InetAddr('255.255.255.255'),
                        SubnetIPNumeric => $subnet,
                        operStatus => ($addr_dotted ? "up" : "down"),
                        adminStatus => ($addr_dotted ? "up" : "down"),
                    };
                }
                if ($if_index && $port->{ifname} =~ /\S+\.(\d+)/) {
                    push @ifvlans, {
                        DeviceID => $deviceID,
                        StartTime => $timestamp,
                        EndTime => $timestamp,
                        vtpVlanIndex => ($port->{ifname} =~ /\.(\d+)/) ? "$1" : "",
                        vtpVlanName => ($port->{ifname} =~ /\.(\S+)/) ? "$1" : "",
                        vtpVlanIfIndex => $if_index,
                        vtpVlanType => 'SilverPeak'
                    };
                    push @dev_vlans, {
                        DeviceID => $deviceID,
                        dot1dBasePort => $if_index,
                        dot1dBasePortIfIndex => $if_index,
                        vlan => ($port->{ifname} =~ /\.(\d+)/) ? "$1" : "",
                    };
                    push @trunk_vlans, {
                        DeviceID => $deviceID,
                        StartTime => $timestamp,
                        EndTime => $timestamp,
                        vlanTrunkPortIfIndex => $if_index,
                        vlanTrunkPortNativeVlan => ($port->{ifname} =~ /\.(\d+)/) ? "$1" : "",
                        vlanTrunkPortDynamicState => 'NA',
                        vlanTrunkPortDynamicStatus => 'NA'
                    };
                }
            }
        }    
    }

    $self->saveSdnFabricInterface(\@intdata);
    $self->{logger}->debug("obtainSdnFabricInterface finished");
    $self->saveIPAddress(\@ifaddr);
    $self->saveVlanObject(\@ifvlans);
    $self->saveVlanTrunkPortTable(\@trunk_vlans);
    $self->savedot1dBasePortTable(\@dev_vlans);
    $self->updateDataCollectionStatus('Vlans', 'OK') if (@ifvlans);
    $self->{logger}->debug("Obtained ifaddr" . Dumper(@ifaddr));
    $self->{logger}->debug("Obtained Vlan data" . Dumper(@ifvlans));
    $self->{logger}->debug("Obtained Vlan Trunk data" . Dumper(@trunk_vlans));
    $self->{logger}->debug("Obtained BasePort data" . Dumper(@dev_vlans));
    $self->{logger}->debug("obtainInterfaces finished");

}

sub obtainArp {
    my ($self, $sdnDevices) = @_;
    my @arp_data;
    my $if_index;
    my $plugin = $self->getPlugin('SaveSdnFabricInterface');
    return unless $sdnDevices;

    $self->{logger}->debug("obtainARP started");
    my $timestamp = NetMRI::Util::Date::formatDate(time());

    foreach my $dev (@$sdnDevices) {
	my $sdnDeviceID = $dev->{SdnDeviceID};
        my $deviceID = $dev->{DeviceID};
        my ($res, $msg) = $self->{api_helper}->get_silverpeak_arp($dev->{SdnDeviceDN});

        unless ($res) {
            $self->{logger}->warn("obtainArp: get_silverpeak_arp failed for SilverPeak device $dev->{SdnDeviceID}: " . ($msg || ''));
            next;
        }

        my @reslines = split /\\n/, $res;

        foreach my $resline (@reslines) {
            if ($resline =~ /(\d{1,3}(?:\.\d{1,3}){3}|[a-fA-F0-9:]+)\s+dev\s+(\w+)\s+lladdr\s+([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})/) {
                my $addr_dotted = $1;
                my $addr_num = InetAddr($addr_dotted) if ($addr_dotted ne '');
		my $sdn_interface_data = $self->{sql}->table("select SdnInterfaceID, Name  from " . $plugin->target_table() . " where SdnDeviceID = " . $sdnDeviceID, AllowNoRows => 1, RefWanted => 1);
                if ($sdn_interface_data && @$sdn_interface_data) {
                    $if_index = $self->getInterfaceIndex($2);
                    unless($if_index) {
                        $self->{logger}->warn("getSwitchPort: can't determine ifIndex for interface with name= ($2) for SilverPeak DeviceID $deviceID");
                    }
             }

                push @arp_data, {
                    RowID          => '1',
                    atIfIndex      => $if_index,
                    DeviceID       => $deviceID,
                    StartTime      => $timestamp,
                    EndTime        => $timestamp,
                    atPhysAddress  => $3,
                    atNetAddress   => $addr_num,
                };
            }
        }
    }

    $self->saveatObject(\@arp_data);
    $self->{logger}->debug("Obtained ARP data: " . Dumper(\@arp_data));
    $self->updateDataCollectionStatus('ARP', 'OK') if (@arp_data);
    $self->updateDataCollectionStatus('Route', 'OK');
    $self->{logger}->debug("obtainArp finished");
}

sub obtainRoute {
    my ($self, $sdnDevices) = @_;
    $self->{logger}->debug("obtainRoute started");

    return unless my $device_id = $self->getDeviceID('obtainRoute: ' . $self->{warning_no_device_id_assigned});
    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my $plugin = $self->getPlugin('SaveSdnFabricInterface');
    my @route_data;

    foreach my $dev (@$sdnDevices) {
        $self->{dn} = $dev->{SdnDeviceDN};
        my ($res, $msg) = $self->{api_helper}->get_silverpeak_route($dev->{SdnDeviceDN});

        unless ($res) {
            $self->{logger}->warn("obtainInterfaces: get_silverpeak_intf failed for SilverPeak device $dev->{SdnDeviceDN}: " . ($msg || ''));
            next;
        }

        my $sdnDeviceID = $dev->{SdnDeviceID};
        my $deviceID = $dev->{DeviceID};
        $self->{logger}->debug("Received route info for Device $dev->{SdnDeviceDN}");
        $self->{logger}->debug(Dumper($res));

        foreach my $entry (@{$res->{subnets}->{entries}}) {
            next unless $entry->{'state'}->{'ifName'};
            
            my ($prefix, $mask) = split('/', $entry->{'state'}->{'prefix'});
            next unless defined $prefix;

            my $addr_num = InetAddr($prefix);
            next unless defined $addr_num;

            my $nexthop_num = InetAddr($entry->{'state'}->{'nextHop'}) if $entry->{'state'}->{'nextHop'};
            my $netmask_num = netmaskFromPrefix('ipv4', $mask);
            my $netmask_str = maskStringFromPrefix("$prefix/$mask");
            my $addr_bigint = Math::BigInt->new($addr_num);
            my $mask_bigint = Math::BigInt->new($netmask_num);

            my $sdn_interface_data = $self->{sql}->table("select SdnInterfaceID, Name  from " . $plugin->target_table() . " where SdnDeviceID = " . $sdnDeviceID, AllowNoRows => 1, RefWanted => 1);
            if ($sdn_interface_data && @$sdn_interface_data) {
                my $if_index = $self->getInterfaceIndex($entry->{'state'}->{'ifName'}) || 0;
                unless ($if_index) {
                    $self->{logger}->warn("getSwitchPort: can't determine ifIndex for interface with name=($entry->{'state'}->{'ifName'}) for SilverPeak DeviceID $deviceID");
                    next;
                }

                my $network = NetAddr::IP->new($prefix, $mask)->network;
                my $route_dest = $network->addr;

                push @route_data, {
                    RowID              => 1,
                    DeviceID           => $deviceID,
                    StartTime          => $timestamp,
                    EndTime            => $timestamp,
                    ipRouteDestStr     => $route_dest,
                    ipRouteDestNum     => $addr_num || '0',
                    ipRouteMaskStr     => $netmask_str,
                    ipRouteMaskNum     => $netmask_num,
                    ipRouteNextHopStr  => $entry->{'state'}->{'nextHop'},
                    ipRouteNextHopNum  => $nexthop_num || '0',
                    ifDescr            => $entry->{'state'}->{'ifName'},
                    ipRouteIfIndex     => $if_index,
                    ipRouteProto       => 'local',
                    ipRouteType        => 'local',
                    ipRouteMetric1     => 0,
                    ipRouteMetric2     => 1,
                };
            }
        }
    }

    if (@route_data) {
        $self->saveipRouteTable(\@route_data);
        $self->{logger}->debug("Obtained Route data: " . Dumper(\@route_data));
        $self->updateDataCollectionStatus('Route', 'OK');
    }

    $self->{logger}->debug("obtainRoute finished");
}

1;
