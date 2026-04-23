package NetMRI::SDN::Meraki;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use NetMRI::SDN::Base;
use base 'NetMRI::SDN::Base';
use Date::Parse;
use NetMRI::Util::Date;
use NetMRI::Util::Network qw (netmaskFromPrefix InetAddr);
use NetMRI::Util::Wildcard::V4;
use Net::IP;
use NetAddr::IP;
use NetMRI::Util::Subnet qw (subnet_matcher);

my %model_to_role_map = (
    MX => 'Meraki Security',
    MS => 'Meraki Switching',
    MR => 'Meraki Radios',
    CW => 'Meraki Radios',
    MV => 'Meraki Vision',          # end host
    MC => 'Meraki Communication',   # end host
    MI => 'Meraki Insight',
    SM => 'Meraki Systems Manager',
    Z3 => 'Meraki Teleworker Gateway',
);

my %network_types = map {$_ => 1} qw(MX MS MR CW MI SM Z3);

my %port_map = (
    lanip  => 'wan1',
    wan1ip => 'wan1',
    wan2ip => 'wan2',
    wired0 => 'wan1',
    wired1 => 'wan2',
    wan0   => 'wan1',
    port0  => 'wan1'
);

my @deviceIpOrder = ("lanIp", "wan1Ip", "wan2Ip", "publicIp");

# The timespan for which LLDP and CDP information will be fetched.
# Must be in seconds and less than or equal to a month (2592000 seconds).
my $cdp_lldp_timespan = 7200;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{SaveDevices_unique_fieldname} = 'Serial';
    $self->{vendor_name} = 'Cisco Meraki';
    return bless $self, $class;
}

sub obtainEverything {
    my $self = shift;
    my $dev_role = $self->getDeviceRole();
    $self->obtainSystemInfo();
    $self->obtainSdnFabricInterface();
    $self->obtainCdpLldp();
    $self->obtainSwitchPort() if $dev_role eq 'Meraki Switching' || $dev_role eq 'Meraki Security';
    $self->obtainWireless() if $dev_role eq 'Meraki Radios';
    $self->obtainRoute();
}

sub getDevices {
    my $self = shift;

    my $statuses;
    my $msg;

    $self->{logger}->debug("getDevices started");
    my ($organizations, $networks) = $self->obtainOrganizationsAndNetworks();

    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_all_devices of Meraki client");
    my ($res, $message) = $api_helper->get_all_devices();
    unless (defined $res) {
        $self->{logger}->warn('getDevices for Meraki failed: ' . $message);
        return [];
    }
    $self->{logger}->debug("received info: ");
    $self->{logger}->debug(Dumper($res));

    my $rec = $self->{sql}->record(
                "select collect_offline_devices from " . $self->{config_db} . ".sdn_controller_settings where id = $api_helper->{fabric_id}",
                RefWanted => 1, AllowNoRows => 1
            );

    unless ($rec->{collect_offline_devices}) {
        ($statuses, $msg) = $api_helper->get_all_devices_statuses($organizations);
        $self->{logger}->warn('getDeviceStatuses for Meraki failed: '.($msg||'')) unless defined $statuses;

        $self->{logger}->debug("received info about devices status: (orgId/networkId/serial => status)  ");
        $self->{logger}->debug(Dumper($statuses));
    }


    my @devices;
	  my %uniqueIP;

    foreach my $dev (@$res) {
        my $model_prefix = substr($dev->{model}, 0, 2);
        $self->{logger}->warn('Unknown Meraki model: ' . $dev->{model}) unless (defined $model_to_role_map{$model_prefix});
        next unless defined $network_types{$model_prefix};

        my $node_role = $model_to_role_map{$model_prefix};
        # SDN-72 - NI has troubles with displaying utf-8 charachers
        # so we replace such characters within "name" field
        my %device = (
            SdnControllerId => $api_helper->{fabric_id},
            SdnDeviceDN => "$dev->{orgId}/$dev->{networkId}/$dev->{serial}",
            Name => $self->_get_device_name($dev),
            NodeRole => $node_role,
            Vendor => $self->{vendor_name},
            Model => $dev->{model},
            Serial => $dev->{serial},
            SWVersion => $dev->{firmware},
            # since v1 api version time format is like "2019-08-02T09:11:58.869297Z"
            modTS => NetMRI::Util::Date::formatDate(str2time($dev->{claimedAt}) || time()),
        );

        # Determine mgmt IP for a device.
        my $vnid;

        if ($self->{cfg}->{SdnNetworkMappingPolicy} eq "DISABLED") {
            $vnid = $self->{cfg}->{DefaultSdnVirtualNetwork};
        } else {
            my $record = $self->{sql}->record(
                "select virtual_network_id from " . $self->{netmri_db} . ".SdnNetwork where sdn_network_key = '$dev->{orgId}/$dev->{networkId}'",
                RefWanted => 1, AllowNoRows => 1
            );

            $vnid =  $record->{virtual_network_id} // 0;

        }

        foreach my $ip (@deviceIpOrder) {
            next unless $dev->{$ip};

            my $digest = $vnid . '-' . $dev->{$ip};
            next if ( defined $uniqueIP{"$digest"}); 

            $device{IPAddress} = $dev->{$ip};
            $uniqueIP{"$digest"} = $dev->{$ip};
            last;
        }

        unless ($device{IPAddress}) {
            $self->{logger}->debug("Skipping $device{SdnDeviceDN} without IP");
            next;  # skip devices without IP address
        }


        unless ($rec->{collect_offline_devices}) {
            if ($statuses->{$device{SdnDeviceDN}} && ($statuses->{$device{SdnDeviceDN}} eq 'offline' || $statuses->{$device{SdnDeviceDN}} eq 'unreachable')) {

                $self->{logger}->debug("Skipping device $device{SdnDeviceDN} is offline");
                next;
            }#skip devices in offline status
        }


        push @devices, \%device;

    }

    $self->{logger}->debug("getDevices finished");
    return \@devices;
}

sub getApiClient {
    my $self = shift;
    unless (ref($self->{api_helper})) {
        $self->{logger}->error("Error getting the Meraki API Client: $@") if $@;
        return undef;
    }
    return $self->{api_helper};
}

sub obtainOrganizationsAndNetworks {
    my $self = shift;

    $self->{logger}->debug("obtainOrganizationsAndNetworks started");
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Collecting data from fabric $api_helper->{fabric_id}");
    $self->{logger}->debug("Calling get_organizations of Meraki client");
    my ($organizations, $message) = $api_helper->get_organizations();
    unless (defined $organizations) {
        $self->{logger}->warn('obtainOrganizationsAndNetworks for Meraki failed: ' . $message);
        return [];
    }
    $self->{logger}->debug("received organizations: ");
    $self->{logger}->debug(Dumper($organizations));

    my $fabric_id = $self->{api_helper}->{fabric_id};
    my $fabric_info = $self->{sql}->record(
        "select virtual_network_id, handle from " . $self->{config_db} . ".sdn_controller_settings where id = $fabric_id",
        RefWanted => 1, AllowNoRows => 1
    );
    my @networks;
    foreach my $org (@$organizations) {
        $org->{fabric_id} = $fabric_id;
        $self->{logger}->debug("Calling get_networks of Meraki client for organization $org->{id}");
        my ($org_networks, $msg) = $self->{api_helper}->get_networks($org->{id});
        $self->{logger}->debug("received networks for organization $org->{id}: ");
        $self->{logger}->debug(Dumper($org_networks));
        next unless ($org_networks);
        foreach my $nw (@$org_networks) {
            $nw->{sdn_network_key} = "$org->{id}/$nw->{id}";
            $nw->{sdn_network_name} = "$org->{name}/$nw->{name}";
            $nw->{fabric_id} = $fabric_id;
            $nw->{organization_id} = $nw->{organizationId};
            push @networks, $nw;
        }
    }

    $self->saveMerakiOrganizations($organizations);
    $self->saveMerakiNetworks(\@networks);

    # Save aggregated Organizations and Networks
    $self->saveSdnNetworks(\@networks);
    # If it's Network Insigth node, newly created Virtual Networks will be synced from OC to NIOS Grid Master
    $self->{logger}->debug("obtainOrganizationsAndNetworks finished");

    return ($organizations, \@networks);
}

sub obtainSdnFabricInterface {
    my $self = shift;
    $self->{logger}->debug("obtainSdnFabricInterface started");
    my $res = $self->getSdnFabricInterface();
    $self->{logger}->debug("getSdnFabricInterface finished, got " . (ref($res) ? scalar(@$res) : 0) . ' interfaces');
    $self->saveSdnFabricInterface($res);
    $self->{logger}->debug("obtainSdnFabricInterface finished");
}

sub getSdnFabricInterface {
    my $self = shift;
    $self->{logger}->debug("getSdnFabricInterface started");
    return [] unless my $device_id = $self->getDeviceID('getSdnFabricInterface: ' . $self->{warning_no_device_id_assigned});
    my ($org_id, $network_id, $serial) = $self->meraki_ids();
    $self->{logger}->debug("Calling get_device of Meraki client for device $serial from network $network_id");
    my ($dev, $msg) = $self->{api_helper}->get_device($serial);
    unless ($dev) {
        $self->{logger}->warn("getSdnFabricInterface: get_device failed for Meraki device $self->{dn}: ".($msg||''));
        $self->setUnreachable('Cannot retrieve interfaces list');
        return [];
    }
    $self->{logger}->debug("Got device: ");
    $self->{logger}->debug(Dumper($dev));

    #NETMRI-33753 SDN: Meraki: Location field contains wrong information.
    if ($device_id) {
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];

        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysLocation', '', 'SNMP'], $self->_remove_utf8($dev->{address})) if $dev->{address};       
    }

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my @interfaces;

    $self->{logger}->debug("Calling get_mgmt_interface_settings of Meraki client for device $serial from network $network_id");
    (my $mgmt_settings, $msg) = $self->{api_helper}->get_mgmt_interface_settings($serial);

    my %if_status;

    # From uplink info we can correctly recognize operational status of mgmt interfaces
    (my $uplink_info, $msg) = $self->{api_helper}->get_device_uplinks($org_id, $serial);
    if (defined $uplink_info && (ref($uplink_info) eq 'ARRAY') && scalar(@$uplink_info)) {
        $self->{logger}->debug("received device uplinks: ");
        $self->{logger}->debug(Dumper($uplink_info));
        foreach my $row (@$uplink_info) {
            next unless ($row->{serial} && $row->{serial} eq $serial);
            foreach my $uplink (@{$row->{uplinks}}) {
                (my $if_name = $uplink->{interface}) =~ s/\s+//g;
                $if_status{lc($if_name)} = (lc($uplink->{status}) eq "active") ? "up" : "down";
            }
        }
    } else {
        $self->{logger}->warn("getSdnFabricInterface: get_device_uplinks failed for Meraki device $self->{dn}: ".($msg||''));
    }

    if (ref $mgmt_settings) {
        $self->{logger}->debug("Got mgmt interface:");
        $self->{logger}->debug(Dumper($mgmt_settings));
        foreach my $key (keys %$mgmt_settings) {
            next if ($key eq 'ddnsHostnames'); # NETMRI-32716
            my $if_setting = $mgmt_settings->{$key};
            my $ip = $if_setting->{staticIp} || '';
            my $enabled_flg = ($if_setting->{wanEnabled} || '') eq 'enabled';
            my $intf = {
                Name => $self->genPortId($key),
                MAC => $dev->{mac},
                adminStatus => ($enabled_flg ? "up" : "down"),
                Timestamp => $timestamp,                
                Type => 'ethernet-csmacd'
            };
            $intf->{operStatus} = $if_status{$key} || $intf->{adminStatus};
            if ($ip) {
                $intf->{IPAddress} = InetAddr($ip);
                $intf->{IPAddressDotted} = $ip;
                $intf->{NetMask} = InetAddr($if_setting->{staticSubnetMask});
                my $subnet;
                eval {
                    my $addr_bigint = Math::BigInt->new("$intf->{IPAddress}");
                    my $mask_bigint = Math::BigInt->new("$intf->{NetMask}");
                    $subnet = $addr_bigint->band($mask_bigint);
                };
                $self->{logger}->warn("Cannot compute subnet address for IP $ip and mask $if_setting->{staticSubnetMask}: $@") if ($@);
                $intf->{SubnetIPNumeric} = $subnet if (defined $subnet);
            }
            push @interfaces, $intf;
        }
    } else {
        $self->{logger}->warn("getSdnFabricInterface: get_device_management_interface_settings failed for Meraki device $self->{dn}: ".($msg||''));
        foreach my $key (qw(wan1 wan2)) {
            # Meraki API provides only 1 MAC address for all the ports (sourceMac), it's the same as device MAC
            next unless exists $dev->{$key . 'Ip'};
            my $ip = $dev->{$key . 'Ip'} || '';
            my $intf = {
                Name => $self->genPortId($key),
                MAC => $dev->{mac},
                adminStatus => "up",
                operStatus => "up",
                Timestamp => $timestamp,
                Type => 'ethernet-csmacd'
            };
            if ($ip) {
                $intf->{IPAddress} = InetAddr($ip);
                $intf->{IPAddressDotted} = $ip;
                $intf->{NetMask} = InetAddr('255.255.255.255');
                $intf->{SubnetIPNumeric} = $intf->{IPAddress};
            }
            push @interfaces, $intf;
        }
    }

    my $ports = [];
    my $port_statuses = [];
    my $vlans = [];
    my $dev_role = $self->getDeviceRole();
    $self->setReachable();
    unless ($dev_role eq 'Meraki Security' || $dev_role eq 'Meraki Switching') {
        $self->{logger}->debug("getSdnFabricInterface finished");
        return \@interfaces;
    }
    if ($dev_role eq 'Meraki Security') {
        $self->{logger}->debug("Calling get_mx_ports of Meraki client for network $network_id");
        ($ports, $msg) = $self->{api_helper}->get_mx_ports($network_id);
        $self->{logger}->warn("get_mx_ports: error message: $msg") if $msg;
    } else {
        $self->{logger}->debug("Calling get_switch_port_statuses of Meraki client for serial $serial");
        ($port_statuses, $msg) = $self->{api_helper}->get_switch_port_statuses($serial);
        $self->{logger}->warn("get_switch_port_statuses: error message: $msg") if $msg;
        $self->{logger}->debug("Calling get_switch_ports of Meraki client for serial $serial");
        ($ports, $msg) = $self->{api_helper}->get_switch_ports($serial);
        $self->{logger}->warn("get_switch_ports: error message: $msg") if $msg;
    }
    $self->{logger}->debug("ports: ");
    $self->{logger}->debug(Dumper($ports));

    $port_statuses = [] unless defined $port_statuses;
    my %switch_port_statuses;
    foreach my $port_status (@$port_statuses) {
        my @speed_parts = split / /, $port_status->{speed};
        my $speed = $speed_parts[0] || 0;
        my $measure = $speed_parts[1] || '';
        $speed = $speed * ($measure eq 'Gbps' ? 1000000000 : $measure eq 'Mbps' ? 1000000 : $measure eq 'Kbps' ? 1000 : 1);
        $switch_port_statuses{$port_status->{portId}}{operSpeed} = $port_status->{speed} eq "" ? undef : $speed;
        $switch_port_statuses{$port_status->{portId}}{operStatus} = $port_status->{status} eq "Connected" ? "up" : "down";
    }

    unless (defined $ports) {
        $self->{logger}->warn("getSdnFabricInterface: getting ports for Meraki device $self->{dn} failed: ".($msg||''));
        $ports = [];
    }
    foreach my $port (@$ports) {
        # since API version v1
        # MX ports are identified by 'number', and MS ports -- by portId.
        my $port_number = $port->{portId} || $port->{number};
        my $switch_port_status_details = $switch_port_statuses{$port_number};
        my %itf = (
            Name => $self->genPortId($port_number),
            Descr => $port->{name} || $self->genPortId($port_number),
            MAC => $dev->{mac},
            operStatus => $switch_port_status_details->{operStatus} || ($port->{enabled} ? "up" : "down"),
            adminStatus => $port->{enabled} ? "up" : "down",
            operSpeed => $switch_port_status_details->{operSpeed},
            Timestamp => $timestamp,
            Type => 'ethernet-csmacd'
        );
        push @interfaces, \%itf;
    }

    ($vlans, $msg) = $self->{api_helper}->get_vlans($network_id);
    $self->{logger}->warn("get_vlans: error message: $msg") if $msg;
    $self->{logger}->debug("vlans: ");
    $self->{logger}->debug(Dumper($vlans));

    unless (defined $vlans) {
        $self->{logger}->warn("getSdnFabricInterface: getting vlans for Meraki device $self->{dn} failed: ".($msg||''));
        $vlans = [];
    }

    foreach my $vlan (@$vlans) {
        my %itf = (
            Name => "Vlan" . $vlan->{id},
            Descr => $vlan->{name},
            MAC => $dev->{mac},
            operStatus => "up",
            adminStatus => "up",
            Timestamp => $timestamp,
            Type => 'propVirtual'
        );
        if ($vlan->{applianceIp}) {
            $vlan->{subnet} =~ /([0-9a-fA-F.:]+)\/(\d+)/;
            my $subnet = $1;
            my $prefix = $2;
            my $address_family = ($vlan->{applianceIp} =~ /:/) ? "ipv6" : "ipv4";
            $itf{IPAddress} = InetAddr($vlan->{applianceIp});
            $itf{IPAddressDotted} = $vlan->{applianceIp};
            $itf{NetMask} = netmaskFromPrefix($address_family, $prefix);
            $itf{SubnetIPNumeric} = InetAddr($subnet);
        }
        push @interfaces, \%itf;
    }
    @interfaces = sort {$a->{Name} cmp $b->{Name}} @interfaces;
    $self->{logger}->debug("getSdnFabricInterface finished");
    return \@interfaces;
}

sub obtainSystemInfo {
    my $self = shift;
    $self->{logger}->debug("obtainSystemInfo started");
    return unless my $device_id = $self->getDeviceID('obtainSystemInfo: ' . $self->{warning_no_device_id_assigned});
    my ($org_id, $network_id, $serial) = $self->meraki_ids();
    $self->{logger}->debug("Get info from DB for device $serial from network $network_id");
    my $dev = $self->{sql}->record("SELECT Model, SWVersion, Name, SdnControllerId FROM " . $self->{netmri_db} . ".SdnFabricDevice
                                    WHERE SdnDeviceDN = '$org_id/$network_id/$serial'", RefWanted => 1, AllowNoRows => 1);
    unless ($dev) {
        $self->{logger}->warn("obtainSystemInfo: get device info from DB failed for Meraki device $self->{dn}");
        return;
    }
    $self->{logger}->debug("received device: ");
    $self->{logger}->debug(Dumper($dev));

    my $device = {
        LastTimeStamp => NetMRI::Util::Date::formatDate(time()),
        Name => $dev->{Name},
        Vendor => $self->{vendor_name},
        Model => $dev->{Model} || '',
        SWVersion => $dev->{SWVersion} || '',
        SdnControllerId => $dev->{SdnControllerId} || ''
    };
    
    if ($device_id) {
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];
        
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysModel', '', 'SNMP'], $dev->{Model}) if $dev->{Model};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysName', '', 'SNMP'], $self->_remove_utf8($dev->{Name})) if $dev->{Name};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVendor', '', 'SNMP'], $self->{vendor_name});
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVersion', '', 'SNMP'], $dev->{SWVersion} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{SdnControllerId}) if $dev->{SdnControllerId};


        $self->saveInventory({
            DeviceID               => $device_id,
            entPhysicalSerialNum   => $serial,
            entPhysicalModelName   => $dev->{Model} || '',
            entPhysicalFirmwareRev => $dev->{SWVersion} || '',
            entPhysicalName        => $dev->{Name},
            entPhysicalIndex       => 1,
            entPhysicalClass       => 'chassis',
            StartTime              => NetMRI::Util::Date::formatDate(time()),
            EndTime                => NetMRI::Util::Date::formatDate(time())
        });
    }

    $self->saveSystemInfo($device);
    $self->setReachable();
    $self->updateDataCollectionStatus('System', 'OK');
    $self->updateDataCollectionStatus('Inventory', 'OK');
    $self->{logger}->debug("obtainSystemInfo finished");
}

sub obtainCdpLldp {
    my $self = shift;
    $self->{logger}->debug("obtainCdpLldp started");
    return unless my $device_id = $self->getDeviceID('obtainCdpLldp: ' . $self->{warning_no_device_id_assigned});
    my ($org_id, $network_id, $serial) = $self->meraki_ids();
    # NIOS-73040: special case for MX:
    # they are able to successfully return cdp/lldp info while throwing 400/Bad Request on getting switch ports
    my $dev_role = $self->getDeviceRole();
    if ($dev_role eq 'Meraki Security') {
      my ($fetched_data, $msg) = $self->{api_helper}->get_mx_ports($network_id);
      unless ($fetched_data) {
        $self->{logger}->warn("obtainCdpLldp: get_mx_ports return no port info for Meraki MX device $self->{dn}: ".($msg||''));
        $self->setUnreachable('Cannot retrieve neighbors info');
        $self->updateDataCollectionStatus('Neighbor', 'Error');
        return;
      }
    }
    $self->{logger}->debug("Calling get_device_lldp_cdp of Meraki client for device $serial from network $network_id");
    my ($fetched_data, $msg) = $self->{api_helper}->get_device_lldp_cdp($serial, {timespan => $cdp_lldp_timespan});
    unless ($fetched_data) {
        $self->{logger}->warn("obtainCdpLldp: get_device_lldp_cdp failed for Meraki device $self->{dn}: ".($msg||''));
        $self->setUnreachable('Cannot retrieve neighbors info');
        $self->updateDataCollectionStatus('Neighbor', 'Error');
        return;
    }
    $self->{logger}->debug("received CDP/LLDP info: ");
    $self->{logger}->debug(Dumper($fetched_data));

    unless (ref($fetched_data->{ports}) eq 'HASH') {
        $self->{logger}->warn("obtainCdpLldp: get_device_lldp_cdp returns no ports information for Meraki device $self->{dn}");
        return;
    }

    my @cdp = ();
    my @lldp = ();
    my @collected_local_interfaces = ();
    foreach my $port (keys %{$fetched_data->{ports}}) {
      next unless length $port;
      my $data = $fetched_data->{ports}->{$port};
      my $name = $self->genPortId($port);
      push @collected_local_interfaces, {
          Name => $name,
          MAC  => $fetched_data->{sourceMac},
          adminStatus => "up",
          operStatus => "up",
          Timestamp => NetMRI::Util::Date::formatDate(time())
      };
      push @cdp, {
            Name => $name,
            cdpCachePrimaryMgmtAddr => $data->{cdp}->{address},
            cdpCacheAddress => $data->{cdp}->{address},
            cdpCacheDeviceId => $data->{cdp}->{deviceId},
            cdpCacheDevicePort => $self->genPortId($data->{cdp}->{portId})
      } if (ref $data->{cdp});
      push @lldp, {
              LocalPortIdSubtype => 'interfaceName',
              RemPortIdSubtype => 'interfaceName',
              LocalPortId => $self->genPortId($port),
              RemManPrimaryAddr => $data->{lldp}->{managementAddress},
              RemSysName => $data->{lldp}->{systemName},
              RemPortDesc => $self->genPortId($data->{lldp}->{portId}),
              RemPortID => $self->genPortId($data->{lldp}->{portId})
      } if (ref $data->{lldp});
    }
    # check if interfaces are already collected
    my $sdn_device_id = $self->getDeviceField('SdnDeviceID');
    my $plugin = $self->getPlugin('SaveSdnFabricInterface');
    my $table = $plugin->target_table();
    my $cnt  = $self->{sql}->single_value("select count(*) from ${table} where SdnDeviceID='${sdn_device_id}'");
    unless ($cnt) {
      $self->{logger}->warn("Interfaces were not collected for Meraki device $self->{dn} yet, will save cdp/lldp next time");
      return;
    }
    $self->saveCDP(\@cdp);
    @lldp = sort {$a->{RemPortID} cmp $b->{RemPortID}} @lldp;
    $self->saveLLDP(\@lldp);
    $self->setReachable();
    $self->updateDataCollectionStatus('Neighbor', 'OK');
    $self->{logger}->debug("obtainCdpLldp finished");
}

sub getDeviceRole {
  my $self = shift;
  my $fabric_id = $self->{sql}->escape($self->{api_helper}->{fabric_id});
  my $dev_type = $self->{sql}->single_value("
      select NodeRole from " . $self->{netmri_db} . ".SdnFabricDevice where
        SdnControllerId = $fabric_id and
        SdnDeviceDN = " . $self->{sql}->escape($self->{dn}),
      AllowNoRows => 1);
  return $dev_type || '';
}

sub getSwitchPort {
    my $self = shift;
    $self->{logger}->debug("getSwitchPort started");
    return unless my $device_id = $self->getDeviceID('getSwitchPort: ' . $self->{warning_no_device_id_assigned});
    my ($org_id, $network_id, $serial) = $self->meraki_ids();
    my $dev_role = $self->getDeviceRole();
    return [] unless $dev_role eq 'Meraki Switching' || $dev_role eq 'Meraki Security';
    my $fetched_data = [];
    if ($dev_role eq 'Meraki Switching') {
      $self->{logger}->debug("Calling get_switch_ports of Meraki client for serial $serial");
      ($fetched_data, my $msg) = $self->{api_helper}->get_switch_ports($serial);
      unless ($fetched_data) {
        $self->setUnreachable('Cannot retrieve list of switch ports');
        $self->updateDataCollectionStatus('Vlans', 'Error');
        $self->{logger}->warn("getSwitchPort: get_switch_ports failed for Meraki device $self->{dn}: ".($msg||''));
        return [];
      }
    } elsif ($dev_role eq 'Meraki Security') {
      $self->{logger}->debug("Calling get_mx_ports of Meraki client for network $network_id");
      ($fetched_data, my $msg) = $self->{api_helper}->get_mx_ports($network_id);
      unless ($fetched_data) {
        $self->setUnreachable('Cannot retrieve list of mx ports');
        $self->updateDataCollectionStatus('Vlans', 'Error');
        $self->{logger}->warn("getSwitchPort: get_mx_ports failed for Meraki network $network_id: ".($msg||''));
        return [];
      }
    }
    $self->{logger}->debug("received switch ports: ");
    $self->{logger}->debug(Dumper($fetched_data));

    $self->{logger}->debug("Calling get_vlans of Meraki client for network $network_id");
    my ($nw_vlans, $message) = $self->{api_helper}->get_vlans($network_id);
    $self->{logger}->warn("get_vlans: error message: $message") if $message;
    $self->{logger}->debug("received vlans: ");
    $self->{logger}->debug(Dumper($nw_vlans));
    unshift @$nw_vlans, {id => 1, name => 'Default'};
    my %vlan_hash = map { $_->{id} => $_ } @$nw_vlans;
    my @if_vlans = ();
    my @dev_vlans = ();
    my @trunk_table = ();
    $fetched_data = [$fetched_data] if ref($fetched_data) eq 'HASH';
    foreach my $data (@$fetched_data) {
      # since API version v1
      # MX ports are identified by 'number', and MS ports -- by portId.
      my $port_number = $data->{portId} || $data->{number};
      my $if_name = $self->genPortId($port_number);
      my $if_index = $self->getInterfaceIndex($if_name);
      unless ($if_index) {
        $self->{logger}->warn("getSwitchPort: can't determine ifIndex for interface with name=${if_name} for Meraki device $self->{dn}");
        next;
      }
      my $vlan_id = $data->{vlan};
      unless ($vlan_id) {
        $self->{logger}->debug("getSwitchPort: vlan is empty for port $port_number on Meraki device $self->{dn}");
        next;
      }
      my $port_vlans = ($data->{allowedVlans} eq 'all' && $data->{type} eq 'trunk' ?
                        $nw_vlans : [$vlan_hash{$vlan_id} || {id => $vlan_id, name => "Vlan$vlan_id"}]);

      my $native_vlan_id = $vlan_id;
      push @dev_vlans, {
        dot1dBasePort => $if_index,
        dot1dBasePortIfIndex => $if_index,
        vlan => $native_vlan_id
      };
      push @trunk_table, {
        vlanTrunkPortIfIndex       => $if_index,
        vlanTrunkPortNativeVlan    => $native_vlan_id,
        vlanTrunkPortDynamicState  => ($data->{type} eq 'trunk' ? 'trunking' : 'notTrunking'),
        vlanTrunkPortDynamicStatus => ($data->{type} eq 'trunk' ? 'tagged'   : 'untagged'),
      };
      foreach my $vlan (@$port_vlans) {
        push @if_vlans, {
            vtpVlanIfIndex => $if_index,
            vtpVlanIndex => $vlan->{id},
            vtpVlanName => $vlan->{name} || "Vlan$vlan->{id}",
            vtpVlanType => 'Meraki'
        };
      }
    }
    $self->saveVlanObject(\@if_vlans);
    $self->saveVlanTrunkPortTable(\@trunk_table);
    $self->setReachable();
    $self->updateDataCollectionStatus('Vlans', 'OK');
    $self->{logger}->debug("getSwitchPort finished");
    return \@dev_vlans;
}

sub genPortId {
    my ($self, $port_name) = @_;
    my $res = $port_name;
    $res = 'port'. $res if $res =~ /^\d+$/;
    $res =~ s/\s+//g;
    $res = lc($res) if $res =~ /^(wan|port|wired)\d/i;
    return defined $port_map{$res} ? $port_map{$res} : $res;
}

#should returns an array (organization_id, network_id, serial)
sub meraki_ids {
  my $self = shift;
  return split /\//, $self->{dn};
}

sub obtainEndhosts {
    my $self = shift;

    $self->{logger}->debug("obtainEndhosts started");
    my $api_helper = $self->getApiClient();
    my $fabric_id = $self->{api_helper}->{fabric_id};
    my @networks = $self->{sql}->table("
        select id, organization_id from " . $self->{netmri_db} . ".MerakiNetwork where fabric_id = $fabric_id
    ");
    unless (scalar @networks) {
        $self->{logger}->warn('obtainEndhosts for Meraki failed: Meraki networks must be collected');
        return [];
    }

    my @endpoints;
    my @wireless_fwd;
    my @forwarding_info;
    foreach my $network (@networks) {
        # collect devices and clients per network to minimize number of api calls
        $self->{logger}->debug("Calling get_network_devices of Meraki client for $network->{id}");
        my ($nw_devices, $message) = $api_helper->get_network_devices($network->{id});
        unless (defined $nw_devices) {
            $self->{logger}->warn("Failed to collect devices from Meraki network $network->{id}: $message"
                . ($message =~ /Not\s+Found/ ? ". The network may have been deleted after the previous collection." : '')
            );
            next;
        }
        $self->{logger}->debug("received network devices: ");
        $self->{logger}->debug(Dumper($nw_devices));

        $self->{logger}->debug("Calling get_network_clients of Meraki client for $network->{id}");
        (my $nw_clients, $message) = $api_helper->get_network_clients($network->{id});
        $self->{logger}->debug("received network clients: ");
        $self->{logger}->debug(Dumper($nw_clients));
        my $dev_clients = {};
        foreach my $client (@$nw_clients) {
            push @{$dev_clients->{$client->{recentDeviceSerial}}}, $client;
        }

        foreach my $dev (@$nw_devices) {
            my $model_prefix = substr($dev->{model}, 0, 2);
            unless (defined $model_to_role_map{$model_prefix}) {
                $self->{logger}->warn('Unknown Meraki model: ' . $dev->{model});
                next;
            }

            # 1. Save clients of Meraki Switch, Meraki Security
            #    Api returns non-empty "switchport" field for them,
            #    so we can easily find neighbor interfaces.
            # 2. For another network types we consider clients as wireless
            #    since clients' "switchport" field appears empty
            # 3. Save MV and MC devices as endpoints,
            #    trying to find a neighbor using cdp/lldp info

            if ($model_prefix eq 'MX' || $model_prefix eq 'MS') {
                # collect clients of Meraki Switch and Meraki Security

                foreach my $client (@{$dev_clients->{$dev->{serial}}}) {
                    my $neigh_switchport = $client->{switchport};
                    next unless ($neigh_switchport);  # cannot find switch neighbor
                    my $dn = "$network->{organization_id}/$dev->{networkId}/$dev->{serial}";
                    my $neigh_sdn_device = $self->{sql}->record("
                        select SdnDeviceID, DeviceID from " . $self->{netmri_db} . ".SdnFabricDevice where
                          SdnControllerId = $fabric_id and
                          SdnDeviceDN = '$dn' and
                          DeviceID is not null",
                        RefWanted => 1, AllowNoRows => 1);
                    next unless ($neigh_sdn_device);  # cannot find current switch in DB

                    my $neigh_interface = $self->{sql}->record("
                        select SdnInterfaceID from " . $self->{netmri_db} . ".SdnFabricInterface where
                          SdnDeviceID = $neigh_sdn_device->{SdnDeviceID} and
                          Name = '" . $self->genPortId($neigh_switchport) . "'",
                        RefWanted => 1, AllowNoRows => 1);
                    next unless ($neigh_interface->{SdnInterfaceID});  # cannot find neighbor
                    
                    unless ($client->{mac}) {
                        $self->{logger}->warn("Meraki Switching client $client->{id} has no MAC address, ignoring");
                        next;
                    }

                    my %endpoint = (
                        IP => $client->{ip} || $client->{ip6},
                        MAC => $client->{mac},
                        Name => $client->{dhcpHostname} || $client->{mdnsName} || $client->{description} || $client->{mac},
                        Vendor => $client->{manufacturer},
                        OS => $client->{os},
                        Description => $client->{description},
                        SdnInterfaceID => $neigh_interface->{SdnInterfaceID},
                        DeviceID => $neigh_sdn_device->{DeviceID},
                    );

                    push @endpoints, \%endpoint;

                    my $fw_ifindex = $self->{sql}->single_value("
                        select ifIndex from " . $self->{netmri_db} . ".ifConfig where
                          DeviceID = '$neigh_sdn_device->{DeviceID}' and
                          Name = '" . $self->genPortId($neigh_switchport) . "'
                        limit 1",
                        AllowNoRows => 1);
                    push @forwarding_info, {
                        DeviceID => $neigh_sdn_device->{DeviceID},
                        StartTime => NetMRI::Util::Date::formatDate(time()),
                        EndTime => NetMRI::Util::Date::formatDate(time()),
                        vlan => $client->{vlan} || 0,
                        dot1dTpFdbPort => $fw_ifindex || 0,
                        dot1dTpFdbStatus => 'learned',
                        dot1dTpFdbAddress => $client->{mac},
                    };

                }
            }
            elsif ($model_prefix eq 'MR' || $model_prefix eq 'CW') {
                foreach my $client (@{$dev_clients->{$dev->{serial}}}) {
                    next unless ($client->{ssid});
                    my $dn = "$network->{organization_id}/$dev->{networkId}/$dev->{serial}";
                    my $neigh_sdn_device = $self->{sql}->record("
                        select SdnDeviceID, DeviceID from " . $self->{netmri_db} . ".SdnFabricDevice where
                          SdnControllerId = $fabric_id and
                          SdnDeviceDN = '$dn' and
                          DeviceID is not null",
                        RefWanted => 1, AllowNoRows => 1);
                    next unless ($neigh_sdn_device);  # cannot find current switch in DB
                    # WirelessFwd consolidator will try to infere RemoteDeviceID field
                    # from RemoteMAC (=bsnMobileStationMacAddress), but it will always be 0
                    # since we do not save wireless clients as devices.
                    push @wireless_fwd, {
                        bsnMobileStationMacAddress => $client->{mac},
                        bsnMobileStationIpAddress => InetAddr($client->{ip} || $client->{ip6}) || 0,
                        bsnMobileStationUserName => $client->{user} || '',
                        bsnMobileStationSsid => $client->{ssid},
                        bsnMobileStationVlanId => $client->{vlan} || 0,
                        DeviceID => $neigh_sdn_device->{DeviceID},
                    };

                    unless ($client->{mac}) {
                        $self->{logger}->warn("Meraki Radio client $client->{id} has no MAC address and will not be saved as an end host");
                        next;
                    }

                    # find any interface of MR
                    my $mr_interface = $self->{sql}->single_value("
                        select SdnInterfaceID from " . $self->{netmri_db} . ".SdnFabricInterface where
                          SdnDeviceID = '$neigh_sdn_device->{SdnDeviceID}' limit 1",
                        AllowNoRows => 1);
                    next unless ($mr_interface);  # cannot find neighbor
                    # save wireless client as endhost
                    my %endpoint = (
                        IP => $client->{ip} || $client->{ip6},
                        MAC => $client->{mac},
                        Name => $client->{dhcpHostname} || $client->{mdnsName} || $client->{description} || $client->{mac},
                        Vendor => $client->{manufacturer},
                        OS => $client->{os},
                        Description => $client->{description},
                        SdnInterfaceID => $mr_interface,
                        DeviceID => $neigh_sdn_device->{DeviceID},
                    );

                    push @endpoints, \%endpoint;
                }
            }
            elsif (not defined $network_types{$model_prefix}) {
                # Meraki Communication and Meraki Vision are saved as end points
                $self->{logger}->debug("Calling get_device_lldp_cdp of Meraki client for network $network->{id} and serial $dev->{serial}");
                my ($fetched_data, $msg) = $self->{api_helper}->get_device_lldp_cdp(
                    $dev->{serial}, {timespan => $cdp_lldp_timespan}
                );
                next unless ($fetched_data);  # cannot find neighbor
                $self->{logger}->debug("received lldp/cdp data: ");
                $self->{logger}->debug(Dumper($fetched_data));


                my $neigh_ip = undef;
                my $neigh_port_id = undef;
                foreach my $port (keys %{$fetched_data->{ports}}) {
                    my $data = $fetched_data->{ports}->{$port};
                    if (length $data->{lldp}) {
                        $neigh_port_id = $self->genPortId($data->{lldp}->{portId});
                        $neigh_ip = $data->{lldp}->{managementAddress};
                        last;
                    }
                    elsif (length $data->{cdp}) {
                        $neigh_port_id = $self->genPortId($data->{cdp}->{portId});
                        $neigh_ip = $data->{cdp}->{address};
                        last;
                    } 
                    else {
                        next;  # search for another source port
                    }
                }
                next unless ($neigh_ip && $neigh_port_id);  # cannot find neighbor

                # find device by network id and IP address, then find interface by port and device id
                my $neigh_sdn_device = $self->{sql}->record("
                    select SdnDeviceID, DeviceID from " . $self->{netmri_db} . ".SdnFabricDevice where
                      SdnControllerId = $fabric_id and 
                      substring_index(SdnDeviceDN, '/', 2) = '$network->{organization_id}/$network->{id}' and
                      IPAddress = '$neigh_ip' and
                      DeviceID is not null order by Name",
                    RefWanted => 1, AllowNoRows => 1);
                next unless ($neigh_sdn_device);  # cannot find neighbor
                my $neigh_sdn_interface = $self->{sql}->record("
                    select SdnInterfaceID from " . $self->{netmri_db} . ".SdnFabricInterface where
                      SdnDeviceID = '$neigh_sdn_device->{SdnDeviceID}' and
                      Name = '$neigh_port_id' order by Name",
                    RefWanted => 1, AllowNoRows => 1);
                next unless ($neigh_sdn_interface);  # cannot find neighbor

                unless ($dev->{mac}) {
                    $self->{logger}->warn("Meraki device $dev->{serial} has no MAC address, ignoring");
                    next;
                }
                my %endpoint = (
                    IP => $dev->{lanIp} || $dev->{wan1Ip} || $dev->{wan2Ip} || $dev->{publicIp} || '',
                    MAC => $dev->{mac},
                    Name => $self->_get_device_name($dev),
                    Vendor => $self->{vendor_name},
                    OS => $model_to_role_map{$model_prefix},
                    SdnInterfaceID => $neigh_sdn_interface->{SdnInterfaceID},
                    DeviceID => $neigh_sdn_device->{DeviceID},
                );

                push @endpoints, \%endpoint;

                my $fw_ifindex = $self->{sql}->single_value("
                    select ifIndex from " . $self->{netmri_db} . ".ifConfig where
                      DeviceID = '$neigh_sdn_device->{DeviceID}' and
                      Name = '$neigh_port_id'
                    limit 1",
                    AllowNoRows => 1);
                push @forwarding_info, {
                    DeviceID => $neigh_sdn_device->{DeviceID},
                    StartTime => NetMRI::Util::Date::formatDate(time()),
                    EndTime => NetMRI::Util::Date::formatDate(time()),
                    vlan => 0,
                    dot1dTpFdbPort => $fw_ifindex || 0,
                    dot1dTpFdbStatus => 'learned',
                    dot1dTpFdbAddress => $dev->{mac},
                };

            }

        }
    }
    @endpoints = sort {$a->{Name} cmp $b->{Name}} @endpoints;
    @forwarding_info = sort {$a->{dot1dTpFdbPort} cmp $b->{dot1dTpFdbPort}} @forwarding_info;
    $self->saveSdnEndpoint(\@endpoints);
    $self->saveForwarding(\@forwarding_info);
    $self->savebsnMobileStationTable(\@wireless_fwd);
    $self->{logger}->debug("obtainEndhosts finished");
}

# Meraki doesn't provide routing tables of traditional form via API.
# The most complete info can be obtained from /uplink url: at least we have a gateway and an interface.
# We calculate the subnet mask assuming that device ip and the gateway ip lay in the same subnet:
# we find the smallest subnet that contains both IPs.
# If the mask appears larger than /24, we'll create /24 subnet to avoid containerizing /25, /26, /27... networks.
# Set RouteProto and RouteType to "local", Subnet consolidator will lift such routes to report.Subnet table.
sub obtainRoute {
    my $self = shift;
    $self->{logger}->debug("obtainRoute started");
    return unless my $device_id = $self->getDeviceID('obtainRoute: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
   
    my $start_time = NetMRI::Util::Date::formatDate(time());
    
    my ($org_id, $network_id, $serial) = $self->meraki_ids();

    $self->{logger}->debug("Calling get_mgmt_interface_settings of Meraki client for device $serial from network $network_id");
    my ($mgmt_settings, $msg) = $self->{api_helper}->get_mgmt_interface_settings($serial);
    $self->{logger}->warn("get_mgmt_interface_settings: error message: $msg") if $msg;
    $self->{logger}->debug("received device management interface settings: ");
    $self->{logger}->debug(Dumper($mgmt_settings));

    my $end_time = NetMRI::Util::Date::formatDate(time());

    my @routes;
    my %subnets;
    
    if ($mgmt_settings && ref($mgmt_settings) eq 'HASH') {
        foreach my $if_name (keys %$mgmt_settings) {
            next unless $mgmt_settings->{$if_name}->{staticIp};
            my $mask = $mgmt_settings->{$if_name}->{staticSubnetMask} || "255.255.255.0"; # We can try to define subnet mask from mgmt interface settings
            my $network = NetAddr::IP->new($mgmt_settings->{$if_name}->{staticIp}, $mask)->network;
            my $route_dest = $network->addr;
            my $prefix = $network->masklen;
            my %route = (
                RowID => 0,
                StartTime => $start_time,
                EndTime => $end_time,
                ipRouteDestStr => $route_dest,
                ipRouteDestNum => InetAddr($route_dest),
                ipRouteMaskStr => $mask,
                ipRouteMaskNum => InetAddr($mask),
                ifDescr => $if_name,
                ipRouteNextHopStr => $mgmt_settings->{$if_name}->{staticGatewayIp},
                ipRouteNextHopNum => InetAddr($mgmt_settings->{$if_name}->{staticGatewayIp}),
                ipRouteProto => 'local',
                ipRouteType => 'local',
                ipRouteMetric1 => 0,
                ipRouteMetric2 => -1,
            );
            $route{ipRouteIfIndex} = $self->getInterfaceIndex($self->genPortId($route{ifDescr})) || 0;
        
            push @routes, \%route;

            $subnets{$network} = $route{ipRouteIfIndex}; # We need this to determine outgoing interface for static route later
        }
    }

    my $dev_role = $self->getDeviceRole();
    if ($dev_role eq 'Meraki Security') {
        $self->{logger}->debug("Calling get_vlans Meraki Security for device $serial from network $network_id");
        (my $vlans, $msg) = $api_helper->get_vlans($network_id);
        if (defined $vlans) {
            $self->{logger}->debug("received device vlans: ");
            $self->{logger}->debug(Dumper($vlans));
            foreach my $vlan (@$vlans) {
                $vlan->{subnet} =~ /([0-9a-fA-f.:]+)\/(\d+)/;
                next if (exists $subnets{$vlan->{subnet}});
                my $route_dest = $1;
                my $route_dest_prefix = $2;
                my $address_family = ($route_dest =~ /:/) ? "ipv6" : "ipv4";
                
                my %route = (
                    RowID => 0,
                    StartTime => $start_time,
                    EndTime => $end_time,
                    ipRouteDestStr => $route_dest,
                    ipRouteMaskNum => netmaskFromPrefix($address_family, $route_dest_prefix),
                    ifDescr => "Vlan" . $vlan->{id},
                    ipRouteNextHopStr => $vlan->{applianceIp} || '',
                    ipRouteProto => 'local',
                    ipRouteType => 'local',
                    ipRouteMetric1 => 0,
                    ipRouteMetric2 => -1
                );
                $route{ipRouteIfIndex} = $self->getInterfaceIndex($route{ifDescr}) || 0;
                $route{ipRouteMaskStr} = Net::IP->new($vlan->{subnet})->mask();
                $route{ipRouteDestNum} = InetAddr($route{ipRouteDestStr});
                $route{ipRouteNextHopNum} = InetAddr($route{ipRouteNextHopStr});

                push @routes, \%route;

                $subnets{$vlan->{subnet}} = $route{ipRouteIfIndex};
            }
        } else {
            $self->{logger}->warn("get_vlans: error message: $msg") if $msg;
        }

        $self->{logger}->debug("Calling get_static_routes Meraki Security for device $serial from network $network_id");
        (my $static_routes, $msg) = $api_helper->get_static_routes($network_id);
        if (defined $static_routes) {
            $self->{logger}->debug("received device static routes: ");          
            $self->{logger}->debug(Dumper($static_routes));
            foreach my $rt (@$static_routes) {
                $rt->{subnet} =~ /([0-9a-fA-f.:]+)\/(\d+)/;
                my $route_dest = $1;
                my $route_dest_prefix = $2;
                my $address_family = ($route_dest =~ /:/) ? "ipv6" : "ipv4";
                my $nexthop_addr = $rt->{'gatewayIp'} if (exists $rt->{'gatewayIp'});
                my %route = (
                    RowID => 0,
                    StartTime => $start_time,
                    EndTime => $end_time,
                    ipRouteDestStr => $route_dest,
                    ipRouteMaskNum => netmaskFromPrefix($address_family, $route_dest_prefix),
                    ifDescr => $rt->{name},
                    ipRouteNextHopStr => $nexthop_addr || '',
                    ipRouteProto => 'netmgmt',
                    ipRouteType => 'indirect',
                    ipRouteMetric1 => 0,
                    ipRouteMetric2 => -1,
                    ipRouteIfIndex => 0 
                );
                $route{ipRouteMaskStr} = Net::IP->new($rt->{subnet})->mask();
                $route{ipRouteDestNum} = InetAddr($route{ipRouteDestStr});
                $route{ipRouteNextHopNum} = InetAddr($route{ipRouteNextHopStr});
                
                foreach my $key (keys %subnets) {
                    my $matcher = subnet_matcher $key;
                    $route{ipRouteIfIndex} = $subnets{$key} if ($matcher->($nexthop_addr));
                }
                push @routes, \%route;
            }
        } else {
            $self->{logger}->warn("get_static_routes: error message: $msg") if $msg;
        }
    }

    $self->saveipRouteTable(\@routes);
    $self->setReachable();
    scalar @routes ? $self->updateDataCollectionStatus('Route', 'OK') : $self->updateDataCollectionStatus('Route', 'N/A');
    $self->{logger}->debug("obtainRoute finished");
}

# find the largest common part of two IP addresses, but no longer than /24
sub guessSubnetAndPrefix {
    my $self = shift;
    my $ip1 = shift;
    my $ip2 = shift;

    my $prefix_num = InetAddr($ip1) ^ InetAddr($ip2);
    my $len = ($prefix_num > 0 ? int(log($prefix_num)/log(2)) : 0);  # length of address 'diff'

    # we'll not create subnets smaller than /24
    $len = 8 if ($len < 8);
    my $subnet = NetMRI::Util::Wildcard::V4::to_dotted('ipv4', InetAddr($ip1) >> $len << $len);
    my $prefix_len = 32 - $len;

    return ($subnet, $prefix_len);
}

sub obtainWireless {
  my $self = shift;
  $self->{logger}->debug("obtainWireless started");
  return unless my $device_id = $self->getDeviceID('obtainWireless: ' . $self->{warning_no_device_id_assigned});
  my $api_helper = $self->getApiClient();
  my ($org_id, $network_id, $serial) = $self->meraki_ids();
  $self->{logger}->debug("Calling get_wireless_bss of Meraki client for network $network_id serial $serial");
  my ($fetched_data, $msg) = $self->{api_helper}->get_wireless_bss($serial);
  unless ($fetched_data) {
    $self->{logger}->warn("obtainWireless: get_wireless_bss failed for Meraki device $self->{dn}: ".($msg||''));
    return;
  }
  $self->{logger}->debug("received wireless data: ");
  $self->{logger}->debug(Dumper($fetched_data));

  my $bss = $fetched_data->{basicServiceSets};
  my @saved_aps = ();
  foreach my $ap (@$bss) {
    push @saved_aps, {
        bsnAPDot3MacAddress => $ap->{bssid},
        bsnAPOperationStatus => $ap->{visible} ? 'enable' : 'disable',
        bsnAPAdminStatus => $ap->{enabled} ? 'associated' : 'disassociated',
        bsnAPName => $ap->{ssidName} . ($ap->{band} ? ' (' . $ap->{band} . ')' : ''),
        bsnApIpAddress => 0,  # prevent converting null to '::'
    } if (defined $ap->{bssid});
  }
  $self->savebsnAPTable(\@saved_aps);
  $self->{logger}->debug("obtainWireless finished");
}

sub _get_device_name {
    my ($self, $dev) = @_;
    return $self->_remove_utf8($dev->{name}) || $dev->{mac} || '(no name)';
}

sub _remove_utf8 {
    my ($self, $str) = @_;
    return Encode::encode("ISO-8859-1", $str || '');
}

1;
