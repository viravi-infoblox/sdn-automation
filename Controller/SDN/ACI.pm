package NetMRI::SDN::ACI;
use strict;
use warnings;
use Data::Dumper;
use NetMRI::SDN::Base;
use NetMRI::Util::Network qw (netmaskFromPrefix InetAddr);
use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{vendor_name} = 'Cisco';

    return bless $self, $class;
}

sub getDevices {
    my $self = shift;

    $self->{logger}->debug("obtainDevices started");
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Collecting data from fabric $api_helper->{fabric_id}");
    $self->{logger}->debug("Calling get_fabric_nodes of ACI client");
    my ($res, $message) = $api_helper->get_fabric_nodes();
    unless ($res) {
        $self->{logger}->error('getDevices failed: ' . $message);
        return [];
    }
    $self->{logger}->debug("received device list: ");
    $self->{logger}->debug(Dumper($res));


    my @devices;
    foreach my $dev (@$res) {
        my %device = (
            SdnControllerId => $api_helper->{fabric_id},
            SdnDeviceDN => $dev->{fabricNode}{attributes}{dn},
            Name => $dev->{fabricNode}{attributes}{name},
            NodeRole => $dev->{fabricNode}{attributes}{role},
            Vendor => $dev->{fabricNode}{attributes}{vendor},
            Model => $dev->{fabricNode}{attributes}{model},
            Serial => $dev->{fabricNode}{attributes}{serial},
            modTS => $self->_format_timestamp($dev->{fabricNode}{attributes}{modTs}),
        );

        (my $node_info, $message) = $api_helper->{client}->aci_request({dn => $device{SdnDeviceDN}, subpath => 'sys'});
        unless ($node_info) {
            $self->{logger}->error("getDevices: cannot get info for $device{SdnDeviceDN}: " . $message);
            next;
        }
        $device{IPAddress} = $self->_select_node_mgmt_ip($node_info->[0]{topSystem}{attributes});

        push @devices, \%device;

    }

    $self->{logger}->debug("obtainDevices finished");
    return \@devices;
}

sub obtainSystemInfo {
    my $self = shift;
    $self->{logger}->debug("obtainSystemInfo started");
    return unless my $device_id = $self->getDeviceID('obtainSystemInfo: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Collecting data from fabric $api_helper->{fabric_id}, device dn is $api_helper->{dn}");
    $self->{logger}->debug("Calling get_node_info of ACI client");
    my ($res, $message) = $api_helper->get_node_info();
    unless ($res) {
        $self->{logger}->error('obtainSystemInfo: get_node_info failed: ' . $message);
        $self->setUnreachable('Cannot retrieve system information');
        $self->updateDataCollectionStatus('System', 'Error');
        return undef;
    }
    my $node_info = _extract_attributes($res);
    $self->{logger}->debug("received node info: ");
    $self->{logger}->debug(Dumper($node_info));

    $self->{logger}->debug("Calling get_sys of ACI client");
    ($res, $message) = $api_helper->get_sys();
    unless ($res) {
        $self->{logger}->error('obtainSystemInfo: get_sys failed: ' . $message);
        $self->setUnreachable('Cannot retrieve system information');
        $self->updateDataCollectionStatus('System', 'Error');
        return undef;
    }
    my $sys_info = _extract_attributes($res);
    $self->{logger}->debug("received sys info: ");
    $self->{logger}->debug(Dumper($sys_info));

    $self->{logger}->debug("Calling get_firmware of ACI client");
    ($res, $message) = $api_helper->get_firmware();
    unless ($res) {
        $self->{logger}->error('obtainSystemInfo: get_firmware failed: ' . $message);
        $self->setUnreachable('Cannot retrieve system information');
        $self->updateDataCollectionStatus('System', 'Error');
        return undef;
    }
    my $fw_info = _extract_attributes($res);
    $self->{logger}->debug("received fw info: ");
    $self->{logger}->debug(Dumper($fw_info));

    my $data = {
        LastTimeStamp => NetMRI::Util::Date::formatDate(time()), # This timestamp is used to check if device is still alive 
        Name => $node_info->{name},
        Vendor => 'Cisco',
        Model => $node_info->{model},
        SWVersion => $fw_info->{version},
        UpTime => _uptime_to_seconds($sys_info->{systemUpTime}),
    };

    if ($device_id) {
        my $dp = $self->getPlugin('SaveDeviceProperty');
        my $dp_fieldset = [qw(DeviceID PropertyName PropertyIndex Source)];

        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysModel', '', 'SNMP'], $node_info->{model}) if $node_info->{model};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysName', '', 'SNMP'], $node_info->{name}) if $node_info->{name};
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVendor', '', 'SNMP'], $self->{vendor_name});
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'sysVersion', '', 'SNMP'], $fw_info->{version} || '');
        $dp->updateDevicePropertyValueIfChanged($dp_fieldset, [$device_id, 'SdnControllerID', '', 'NetMRI'], $api_helper->{fabric_id}) if $api_helper->{fabric_id};
    }

    $self->saveSystemInfo($data);
    $self->setReachable();
    $self->updateDataCollectionStatus('System', 'OK');
    $self->{logger}->debug("obtainSystemInfo finished");
}

sub obtainInterfaces {
    my $self = shift;
    $self->{logger}->debug("obtainInterfaces started");
    return [] unless my $device_id = $self->getDeviceID('obtainInterfaces: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_interfaces of ACI client");
    my ($res, $message) = $api_helper->get_interfaces();
    unless ($res) {
        $self->{logger}->error('obtainInterfaces failed: ' . $message);
        $self->setUnreachable('Cannot retrieve interfaces list');
        return undef;
    }
    my $interface_info = _extract_attributes($res);
    $self->{logger}->debug("received interface info: ");
    $self->{logger}->debug(Dumper($interface_info));

    my %consolidated_info;
    foreach my $data (@{$interface_info}) {
        my $class_name = $data->{__class};

        # Attach info on ethpmFcot, ethpmPhysIf and ethpmPortCap to parent l1PhysIf interface
        my $base_dn = $data->{dn};
        $base_dn =~ s/(.*phys-\[.*?\]).*/$1/ if ($class_name =~ /^(ethpmFcot|ethpmPhysIf|ethpmPortCap)$/);
        # Attach info on ethpmAggrIf and ethpmPortCap to parent pcAggrIf interface
        $base_dn =~ s/(.*\/aggr-\[.*?\]).*/$1/ if ($class_name =~ /^(ethpmAggrIf|ethpmPortCap)$/);

        $consolidated_info{$base_dn} //= {};
        $consolidated_info{$base_dn}->{$class_name} = $data;

    }

    my %final_info;

    my $oper_modes = $self->_get_interface_oper_modes();
    my %trunking_info;

    for my $dn (keys(%consolidated_info)) {
        if ($dn =~ /[^c]phys-\[.*?\]/) {
            my $oper_speed = '';
            if ($consolidated_info{$dn}->{ethpmPhysIf}{operSpeed}) {
                # Possible values can be found in https://pubhub.devnetcloud.com/media/apic-mim-ref-221/docs/TYPE-l1-Speed.html
                if ($consolidated_info{$dn}->{ethpmPhysIf}{operSpeed} =~ m/^(\d+)([MG])$/) {
                    my $multiplier = ($2 eq 'G') ? 1000000000 : 1000000;
                    $oper_speed = $1 * $multiplier;
                }
            }

            $final_info{$dn} = {
                Timestamp => $consolidated_info{$dn}->{l1PhysIf}{modTs},
                Name => $consolidated_info{$dn}->{l1PhysIf}{id},
                Descr => $consolidated_info{$dn}->{l1PhysIf}{descr} || '',
                Mtu => $consolidated_info{$dn}->{l1PhysIf}{mtu},
                MAC => $consolidated_info{$dn}->{ethpmPhysIf}{backplaneMac},
                operMode => $consolidated_info{$dn}->{l1PhysIf}{mode},
                adminStatus => $consolidated_info{$dn}->{l1PhysIf}{adminSt},
                operStatus => $consolidated_info{$dn}->{ethpmPhysIf}{operSt},
                operStQual => $consolidated_info{$dn}->{ethpmPhysIf}{operStQual},
                operSpeed => $oper_speed,
                sfpPresent => $consolidated_info{$dn}->{ethpmFcot}{isFcotPresent},
                Type => $consolidated_info{$dn}->{ethpmFcot}{typeName},
                Duplex => $consolidated_info{$dn}->{ethpmPortCap}{duplex}
            };
            my $if_name = $final_info{$dn}->{Name};
            $final_info{$dn}->{operMode} = $oper_modes->{$if_name}{trunk_status} if ($oper_modes->{$if_name}{trunk_status});
            if ($oper_modes->{$if_name}{native_encap} && $oper_modes->{$if_name}{native_encap} ne 'unknown' && $oper_modes->{$if_name}{native_encap} =~ m/vlan-(\d+)/) {
                $trunking_info{$if_name}->{vlanTrunkPortNativeVlan} = $1;
            }
            if ($final_info{$dn}->{operMode} eq 'trunk') {
                $trunking_info{$if_name}->{vlanTrunkPortDynamicStatus} = 'trunking';
                $trunking_info{$if_name}->{vlanTrunkPortDynamicState} = 'tagged';
            } else {
                $trunking_info{$if_name}->{vlanTrunkPortDynamicStatus} = 'notTrunking';
                $trunking_info{$if_name}->{vlanTrunkPortDynamicState} = 'admitAll';
            }
        } else {
            my @consolidated_info_keys = keys(%{$consolidated_info{$dn}});
            my $class = $consolidated_info_keys[0];
            my $l1pc = (grep (/^pcAggrIf$/, @consolidated_info_keys)) ? 'pcAggrIf' : $class;
            my $ethpm = (grep (/^ethpmAggrIf$/, @consolidated_info_keys)) ? 'ethpmAggrIf' : $class;
            my $ethpmPortCap = (grep (/^ethpmPortCap$/, @consolidated_info_keys)) ? 'ethpmPortCap' : $class;

            my $mac = NetMRI::Util::Format::sanitizeMAC($consolidated_info{$dn}->{$ethpm}{backplaneMac}) ||
                      NetMRI::Util::Format::sanitizeMAC($consolidated_info{$dn}->{$ethpm}{mac}) ||
                      NetMRI::Util::Format::sanitizeMAC($consolidated_info{$dn}->{$ethpm}{operRouterMac}) ||
                      NetMRI::Util::Format::sanitizeMAC($consolidated_info{$dn}->{$ethpm}{routerMac});
            $final_info{$dn} = {
                Timestamp => $consolidated_info{$dn}->{$l1pc}{modTs},
                Name => $consolidated_info{$dn}->{$l1pc}{id},
                Descr => $consolidated_info{$dn}->{$l1pc}{descr} || '',
                Mtu => ($class eq "tunnelIf" ? $consolidated_info{$dn}->{$class}{cfgdMtu} : $consolidated_info{$dn}->{$ethpm}{mtu}),
                adminStatus => $consolidated_info{$dn}->{$l1pc}{adminSt},
                operStatus => $consolidated_info{$dn}->{$ethpm}{operSt},
                operStQual => $consolidated_info{$dn}->{$ethpm}{operStQual},
                MAC => $mac,
            };

            $final_info{$dn}->{operMode} = $consolidated_info{$dn}->{$l1pc}{operSt} if $consolidated_info{$dn}->{$l1pc}{operSt};
            $final_info{$dn}->{Duplex} = $consolidated_info{$dn}->{$ethpmPortCap}{duplex} if $consolidated_info{$dn}->{$ethpmPortCap}{duplex};

            if ($dn =~ /[^c]tunnel-\[.*?\]/) {
                $final_info{$dn}->{Type} = 'tunnel';
            } elsif ($class ne 'cnwPhysIf') {
                $final_info{$dn}->{Type} = 'propVirtual';
            }

        }

    }

    # Adding info about VxLANs
    $self->{logger}->info("Getting VxLANs data started");
    my $node_role = $self->getNodeRole('obtainInterfaces/vxlan: ' . $self->{warning_no_node_role_assigned});
    if (defined $node_role and $node_role eq "leaf") {
        $self->{logger}->debug("Calling get_vrf_ctx of ACI client");
        my ($res_ctx, $mes_ctx) = $api_helper->get_vrf_ctx();
        unless ($res_ctx) {
            $self->{logger}->error('obtainInterfaces/vrf_ctx failed: ' . $mes_ctx);
        } else {
            my $ctx_info = _extract_attributes($res_ctx);
            $self->{logger}->debug("received context info: ");
            $self->{logger}->debug(Dumper($ctx_info));
            for my $ctx (@$ctx_info) {
                $self->{logger}->debug("Calling get_vxlans of ACI client for DN:" . $ctx->{dn});
                my ($res_vxlan, $mes_vxlan) = $api_helper->get_vxlans($ctx->{dn});
                unless ($res_vxlan) {
                    $self->{logger}->error('obtainInterfaces/vxlan failed: ' . $mes_vxlan);
                } else {
                    $self->{logger}->debug("received vxlan info: ");
                    $self->{logger}->debug(Dumper(\@$res_vxlan));
                    my $vrf = $ctx->{name};
                    my @intf_vrf;
                    for my $vxlan (@$res_vxlan) {
                        $self->{logger}->info("VxLAN added. DN:" . $self->{dn} .", VxLAN:". $vxlan->{l2BD}{attributes}{fabEncap});
                        my $intf_dn = $self->{dn} ."/" . $vxlan->{l2BD}{attributes}{fabEncap};
                        $final_info{$intf_dn} = {
                            Timestamp => $vxlan->{l2BD}{attributes}{modTs},
                            Name => $vxlan->{l2BD}{attributes}{fabEncap},
                            Descr => '',
                            Mtu => undef,
                            MAC => $vxlan->{l2BD}{attributes}{addr},
                            operMode => $vxlan->{l2BD}{attributes}{mode},
                            adminStatus => 'Up',
                            operStatus => $vxlan->{l2BD}{attributes}{operSt},
                            operStQual => $vxlan->{l2BD}{attributes}{operStQual},
                            Type => 'VxLAN'
                        };
                        push @intf_vrf, {
                            Timestamp => NetMRI::Util::Date::formatDate(time()),
                            vrfName => $vrf,
                            Interface => $vxlan->{l2BD}{attributes}{fabEncap}
                        };
                    }
                    $self->saveVrfHasInterface(\@intf_vrf) if (scalar @intf_vrf);
                }
            }
        }
    } else {
        $self->{logger}->info("VxLAN data is collected only from Leaf devices.");
    }
    $self->{logger}->info("Getting VxLANs data end");

    $self->saveSdnFabricInterface([values(%final_info)]);

    # NIOS-72952: set vlanTrunkPortIfIndex right after saving SdnFabricInterface
    for my $if_name (keys(%trunking_info)) {
        $trunking_info{$if_name}->{vlanTrunkPortIfIndex} = $self->getInterfaceIndex($if_name);
    }

    $self->saveVlanTrunkPortTable([values(%trunking_info)]);

    $self->setReachable();
    $self->{logger}->debug("obtainInterfaces finished");
}

sub _get_interface_oper_modes {
    my $self = shift;

    my $api_helper = $self->getApiClient();

    $self->{dn} =~ m!topology/pod-(\d+)/node-(\d+)!o;
    my ($node_pod, $node_id) = ($1, $2);
    $self->{logger}->info("Collectiong OperModes for Pod: $node_pod, Node: $node_id");

    my %interface_oper_modes;

    unless ($api_helper->can("get_attachable_entity_profiles")) {
        $self->{logger}->debug("Skipping get_attachable_entity_profiles on device $self->{dn}");
        return {};
    }
    $self->{logger}->debug("Calling get_attachable_entity_profiles of ACI client");
    my ($aeps, $message) = $api_helper->get_attachable_entity_profiles();
    unless ($aeps) {
        $self->{logger}->warn("Cannot get AEP data: $message");
        $aeps = [];
    }
    $self->{logger}->debug("received AEP info: ");
    $self->{logger}->debug(Dumper($aeps));

    my %profileList = ();

    for my $aep (map {$_->{(keys(%$_))[0]}->{attributes}} @$aeps) {
        if ($aep->{dn} =~ m!uni/infra/attentp-([^/]*)/gen-default!o) {
            $profileList{$1} = $aep;
        }
    }

    $self->{logger}->debug("Collected Profiles from AEPs: ");
    $self->{logger}->debug(Dumper(\%profileList));

    foreach my $profile (keys %profileList) {
        (my $aep_paths, $message) = $api_helper->get_attachable_entity_profile_paths($profile);
        for my $aep_path (@$aep_paths) {
            for my $node_deploy (@{$aep_path->{infraAttEntityP}{children}}) {
                for my $pcons (@{$node_deploy->{pconsNodeDeployCtx}{children}}) {
                    my $class = (keys(%$pcons))[0];
                    next unless $class eq 'pconsResourceCtx';
                    $pcons->{$class}{attributes}{ctxDn} =~ m!/phys-\[(.*?)\]!;
                    my $aep_interface = $1;
                    $interface_oper_modes{$aep_interface} = {
                        trunk_status => $profileList{$profile}->{mode} eq 'regular' ? 'trunk' : 'access',
                        encap => $profileList{$profile}->{encap},
                        native_encap => $profileList{$profile}->{primaryEncap}
                    };
                }
            }
        }
    }

    $self->{logger}->debug("Calling get_static_paths of ACI client");
    (my $paths, $message) = $api_helper->get_static_paths();
    unless ($paths) {
        $self->{logger}->warn("Cannot get static path data: $message");
        $paths = [];
    }
    $self->{logger}->debug("received static paths info: ");
    $self->{logger}->debug(Dumper($paths));
    for my $path (map {$_->{(keys(%$_))[0]}->{attributes}} @$paths) {
	    if ( $path->{tDn} =~ m!topology/pod-(\d+)/paths-(\d+)/pathep-\[(.*?)\]!o ) {
            my ($path_pod, $path_node, $path_interface) = ($1, $2, $3);
            next unless ($path_pod == $node_pod && $path_node == $node_id);

            $interface_oper_modes{$path_interface} = {
                trunk_status => $path->{mode} eq 'regular' ? 'trunk' : 'access',
                encap => $path->{encap},
                native_encap => $path->{primaryEncap}
            };
		}
    }
    return \%interface_oper_modes;
}

sub obtainIPAddress {
    my $self = shift;
    $self->{logger}->debug("obtainIPAddress started");
    return [] unless my $device_id = $self->getDeviceID('obtainIPAddress: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_ip_addresses of ACI client");
    my ($res, $message) = $api_helper->get_ip_addresses();
    unless ($res) {
        $self->{logger}->error('obtainIPAddress failed: ' . $message);
        $self->setUnreachable('Cannot retrieve list of ip addresses');
        return undef;
    }
    $self->{logger}->debug("received interface info: ");
    $self->{logger}->debug(Dumper($res));

    $self->{logger}->debug("Calling get_ip_addresses of ACI client");
    (my $interface_attachment, $message) = $api_helper->get_ip_address_attachment();
    unless ($interface_attachment) {
        $self->{logger}->warn('Cannot get interface association: ' . $message);
        $interface_attachment = [];
    }

    my %intf_bd_epg_info;
    for my $att (@$interface_attachment) {
        my $data = $att->{ipRsRtDefIpAddr}{attributes};
        $data->{dn} =~ m!dom-[^/]+/if-\[(.*?)\]/addr-\[(.*?)\]/rsrtDefIpAddr-!o;
        my ($ifname, $addr) = ($1, $2);
        my ($bd, $epg);
        if ($data->{tDn} =~ m!bd-\[(.*?)\]-isSvc-no/epgDn-\[(.*?)\]/rt-!o) {
            $bd = $1;
            $epg = $2;
        } else {
            $data->{tDn} =~ m!bd-\[(.*?)\]-isSvc-no/rt-!o;
            $bd = $1;
        }

        $intf_bd_epg_info{$ifname}{$addr} = {bd => $bd, epg => $epg};
    }
    $self->{logger}->debug("received interface association: ");
    $self->{logger}->debug(Dumper(\%intf_bd_epg_info));

    my @final_info;
    my @if_routes;
    for my $addr_struct (@$res) {
        my $route_dest_str = $addr_struct->{ipv4Addr}{attributes}{addr};
        my ($addr, $prefix) = split m!/!, $route_dest_str;
        my $addr_num = InetAddr($addr);
        my $netmask_num = netmaskFromPrefix('ipv4', $prefix);

        my $subnet;
        eval {
            my $addr_bigint = Math::BigInt->new("$addr_num");
            my $mask_bigint = Math::BigInt->new("$netmask_num");
            $subnet = $addr_bigint->band($mask_bigint);
        };
        if ($@) {
            $self->{logger}->warn("Cannot compute subnet address for IP $addr_num ($addr) and mask $netmask_num (/$prefix): $@");
            next;
        }
        $addr_struct->{ipv4Addr}{attributes}{dn} =~ m!if-\[([a-zA-Z0-9]+)\]/addr-!;
        my $ifname = $1;
        my $ifindex = $self->{sql}->single_value("select SdnInterfaceID from $main::NETMRI_DB.SdnFabricInterface i 
            join $main::NETMRI_DB.SdnFabricDevice d using (SdnDeviceID) 
            where d.SdnControllerId = '$api_helper->{fabric_id}' and i.Name = '$ifname' and d.SdnDeviceDN = '$api_helper->{dn}'", AllowNoRows => 1);
        unless ($ifindex) {
            $self->{logger}->warn("Ip address " . $addr_struct->{ipv4Addr}{attributes}{dn} . "was collected before corresponding interface was collected");
            next;
        }

        my %route = (
            RowID => 0,
            StartTime => NetMRI::Util::Date::formatDate(time()),
            EndTime => NetMRI::Util::Date::formatDate(time()),
            ipRouteDestStr => $route_dest_str,
            ipRouteMaskNum => $netmask_num,
            ifDescr => $ifname,
            ipRouteNextHopStr => $addr,
            ipRouteProto => 'local',
            ipRouteType => 'local',
            ipRouteMetric1 => 0,
            ipRouteMetric2 => -1,
        );
     
        $route{ipRouteIfIndex} = $ifindex;
        $route{ipRouteMaskStr} = join('.', unpack('CCCC', pack('N', $netmask_num)));
        $route{ipRouteDestNum} = $subnet;
        $route{ipRouteNextHopNum} = $addr_num;

        push @if_routes, \%route;

        my $bd_dn = $intf_bd_epg_info{$ifname}->{$addr_struct->{ipv4Addr}{attributes}{addr}}{bd};
        my $epg_dn = $intf_bd_epg_info{$ifname}->{$addr_struct->{ipv4Addr}{attributes}{addr}}{epg};
        my $info = {
            Timestamp => NetMRI::Util::Date::formatDate(time()),
            IPAddress => $addr_num,
            ifIndex => $ifindex,
            NetMask => $netmask_num,
            IPAddressDotted => $addr,
            SubnetIPNumeric => $subnet,
            AciBdID => $self->getAciBdId($bd_dn),
            AciEpgID => $self->getAciEpgId($epg_dn),
        };
        push @final_info, $info;
    }
    $self->saveIPAddress(\@final_info);
    $self->setReachable();
    $self->{logger}->debug("obtainIPAddress finished");
}

sub loadAciPolicyObjectsMap {
    my $self = shift;
    return if $self->{aci_policy_objects_map_loaded};
    return unless ($self->{fabric_id});
    $self->{aci_policy_objects_map} = {};
    # Add new objects as needed
    for my $object (qw(BridgeDomain Epg)) {
        my $plugin = $self->getPlugin("SaveAci$object");
        $self->{aci_policy_objects_map}->{$object} = {};
        for my $row ($self->{sql}->table("select Aci${object}ID, Aci${object}Dn from $main::REPORT_DB.Aci$object where AciControllerID = $self->{fabric_id}")) {
            $self->{aci_policy_objects_map}->{$object}->{$row->{"Aci${object}Dn"}} = $row->{"Aci${object}ID"};
        }
    }
    $self->{aci_policy_objects_map_loaded} = 1;
}

sub getAciBdId {
    my $self = shift;
    my $dn = shift;
    $self->loadAciPolicyObjectsMap();
    return undef unless ($dn);
    return $self->{aci_policy_objects_map}->{BridgeDomain}->{$dn};

}

sub getAciEpgId {
    my $self = shift;
    my $dn = shift;
    $self->loadAciPolicyObjectsMap();
    return undef unless ($dn);
    return $self->{aci_policy_objects_map}->{Epg}->{$dn};
}

sub obtainVlan {
    my $self = shift;
    $self->{logger}->debug("obtainVlan started");
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_vlan of ACI client");
    my ($res, $message) = $api_helper->get_vlan();
    unless ($res) {
        $self->{logger}->error('obtainVlan failed: ' . $message);
        $self->setUnreachable('Cannot retrieve list of ip addresses');
        $self->updateDataCollectionStatus('Vlans', 'Error');
        return undef;
    }
    $self->{logger}->debug("received vlan info: ");
    $self->{logger}->debug(Dumper($res));

    my @save_data;
    my @switch_port;
    my ($fabEncap, $vlan_id);
    foreach my $vlan (@$res) {
        my $class = (keys(%$vlan))[0];
        my $encap = $vlan->{$class}{attributes}{encap};
        unless($encap) {
           #NIOS-88894 add some data to switchport
           if ($fabEncap && ($fabEncap eq $vlan->{$class}{attributes}{fabEncap})) {
               my $if_index = $self->getInterfaceIndex("vlan$vlan->{$class}{attributes}{id}");
               push @switch_port, {
                   dot1dBasePort => $if_index,
                   dot1dBasePortIfIndex => $if_index,
                   vlan => $vlan_id
               } if $if_index;
               $fabEncap = "";
           }
           next;
        } # Not all l2Dom subclasses have this attribute. We don't need those
        $encap =~ m/vlan-(\d+)/;
        unless ($1) {
            $self->{logger}->info("Cannot store encap $encap: vxlans are not supported by netmri");
            next;
        }
        $vlan_id = $1;

        push @save_data, {
            SdnDeviceDN => $self->{dn},
            vtpVlanIndex => $vlan_id,
            vtpVlanName => $vlan->{$class}{attributes}{name},
            vtpVlanType => 'ACI'
        };
        my $dn = $vlan->{$class}{attributes}{dn};
        $dn =~ m/bd-\[([\w\-]+)\]/;
        $fabEncap = $1;
    }
    $self->{logger}->debug("Calling get_vlan_switchport_relations of ACI client");
    ($res, $message) = $api_helper->get_vlan_switchport_relations();

    unless ($res) {
        $self->{logger}->error('Cannot get vlan to switchport relationships for obtainSwitchPort: ' . $message);
        $self->setUnreachable('Cannot retrieve list of switch ports');
    }
    $self->{logger}->debug("received switchport info: ");
    $self->{logger}->debug(Dumper($res));

    my @dot1dports;
    for my $vlan (@$res) {
        my $dn = $vlan->{l2Cons}{attributes}{dn};
        $dn =~ m!/rspathDomAtt-\[(.*)\]/cons-\[(.*)\]$!;
        my $path = $1; # topology/pod-1/node-101/sys/conng/path-[po1]
        my $target = $2; # topology/pod-1/node-101/sys/ctx-[vxlan-2424832]/bd-[vxlan-16285610]/vlan-[vlan-3036]
        unless ($target =~ m!/vlan-\[vlan-(.*)\]$!) {
            $self->{logger}->debug("Skipping $target because it doesn't end with vlan");
            next;
        }
        my $vlan = $1;
        $path =~ m!/path-\[(.*)\]$!;
        my $ifname = $1;
        my $if_index = $self->getInterfaceIndex($ifname);
        next unless $if_index; # Skip this table if the interface hasn't been collected yet
        push @dot1dports, {
             dot1dBasePort => $if_index,
             dot1dBasePortIfIndex => $if_index,
             vlan => $vlan,
        };
    }
    push @switch_port, @dot1dports;

    $self->saveVlanObject(\@save_data);
    $self->savedot1dBasePortTable(\@switch_port);
    $self->setReachable();
    $self->updateDataCollectionStatus('Vlans', 'OK');
    $self->{logger}->debug("obtainVlan finished");
}

sub obtainRoute {
    my $self = shift;
    $self->{logger}->debug("obtainRoute started");
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_route_ipv4_nexthop of ACI client");
    my ($res, $message) = $api_helper->get_route_ipv4_nexthop();
    unless ($res) {
        $self->{logger}->error('obtainRoute failed: ' . $message);
        $self->setReachable();
        $self->updateDataCollectionStatus('Route', 'Error');
        return undef;
    }
    $self->{logger}->debug("received route info: "); 
    $self->{logger}->debug(Dumper($res));


    my @routes;
    foreach my $nh (@$res) {
        my $nexthop = $nh->{uribv4Nexthop}{attributes};

        $nexthop->{dn} =~ m!db-rt/rt-\[([0-9a-fA-F.:]+)/(\d+)\]/!;
        my $route_dest = $1;
        my $route_dest_prefix = $2;

        my $nexthop_addr = $nexthop->{addr};
        $nexthop_addr =~ s!/\d+$!!; # ACI returns nexthop address as CIDR, e.g. 20.0.0.30/32 . We need to cut off prefix length to be able to handle it in netmri
		
        next unless $nexthop->{if};
        my %route = (
            RowID => 0,
            StartTime => NetMRI::Util::Date::formatDate(time()),
            EndTime => NetMRI::Util::Date::formatDate(time()),
            ipRouteDestStr => $route_dest,
            ipRouteMaskNum => netmaskFromPrefix('ipv4', $route_dest_prefix),
            ifDescr => $nexthop->{if},
            ipRouteNextHopStr => $nexthop_addr,
            ipRouteProto => $nexthop->{owner}, # TODO: we might want to keep this value in line with ones from config.route_admin_distances
            ipRouteType => $nexthop->{routeType},
            ipRouteMetric1 => $nexthop->{metric},
            ipRouteMetric2 => -1,
            Vrf => $nexthop->{vrf},
            _dn => $nexthop->{dn},
        );
     
        push @routes, \%route;
    }
    my %rd2if;
    $self->{logger}->debug("Calling get_route_interface_definition_relationship of ACI client");
    ($res, $message) = $api_helper->get_route_interface_definition_relationship();
    $self->{logger}->debug("received interface definition info: "); 
    $self->{logger}->debug(Dumper($res));

    if ($res) {
        foreach my $rel (@$res) {
            $rel->{ipRsRtDefIpAddr}{attributes}{dn} =~ m!/if-\[([^/]+)\]/.*/rsrtDefIpAddr-\[(.+)\]$!;
            my ($ifname, $rd) = ($1, $2);
            $rd2if{$rd} = $ifname;
        }  
    } else {
        $self->{logger}->warn("Cannot get relatioships between IP addresses and route definitions: $message; recursive routes won't be processed");
    }

    $self->{logger}->debug("Calling get_route_subnet_definition_relationship of ACI client");
    (my $subnet_definitions, $message) = $api_helper->get_route_subnet_definition_relationship();
    $self->{logger}->debug("received subnet definition info: "); 
    $self->{logger}->debug(Dumper($subnet_definitions));
    unless ($subnet_definitions) {
        $self->{logger}->warn("Cannot get additional info for routes: $message; skipping");
        $subnet_definitions = [];
    }

    my @final_routes;
    foreach my $route (@routes) {
        # Routes from interface 'unspecified' have bogus interface and vrf. Need to query ACI for correct values
        if ($route->{ifDescr} eq 'unspecified') {
            $route->{_dn} =~ m!dom-([^/]+)/db-rt/rt-\[([a-zA-Z0-9/.:]+)\]/nh-!;
            my ($dom, $rn) = ($1, $2);
            foreach my $rd (@{$subnet_definitions}) {
			    next if (index($rd->{ipRsRouteToRouteDef}{attributes}{dn}, "dom-$dom/rt-[$rn]") == -1); # Make sure we got correct route
                my $rd_dn = $rd->{ipRsRouteToRouteDef}{attributes}{tDn};
				next unless $rd2if{$rd_dn};
                my %fixed_route = %$route;

                $rd_dn =~ m!/rt-\[([a-fA-F0-9.:]+)/[0-9]+\]$!;
                my $fixed_nexthop = $1; # ACI returns primary IP of the interface it uses as nexthop; we'll get proper IP here
                $fixed_route{ipRouteNextHopStr} = $fixed_nexthop;
                $fixed_route{ifDescr} = $rd2if{$rd_dn};

                $fixed_route{ipRouteType} = 'direct';
                $fixed_route{Vrf} = $dom;

                push @final_routes, \%fixed_route;
				last;
            }
        } else {
            push @final_routes, $route;
        }

    }
   
    # There are some fields that are derived from ones we know
    foreach my $route (@final_routes) {    
	if ($route->{ipRouteMaskNum}->{value}[0] == 0) {
		$route->{ipRouteMaskNum}->{sign} = '+';
	}
	$route->{ipRouteIfIndex} = $self->getInterfaceIndex($route->{ifDescr}) || 0;
	$route->{ipRouteMaskStr} = join('.', unpack('CCCC', pack('N', $route->{ipRouteMaskNum})));
	$route->{ipRouteDestNum} = InetAddr($route->{ipRouteDestStr});
	$route->{ipRouteNextHopNum} = InetAddr($route->{ipRouteNextHopStr});
    }

    my @vrf_routes;
    foreach my $r (@final_routes) {
        push @vrf_routes, {
            Timestamp => NetMRI::Util::Date::formatDate(time()),
            vrfName => $r->{Vrf},
            Destination => $r->{ipRouteDestStr},
            Interface => $r->{ifDescr},
            Mask => $r->{ipRouteMaskStr},
            Metric1 => $r->{ipRouteMetric1},
            Metric2 => $r->{ipRouteMetric2},
            NextHop => $r->{ipRouteNextHopStr},
            Protocol => $r->{ipRouteProto},
            Type => $r->{ipRouteType}
        }
    }

    $self->saveVrfRoute(\@vrf_routes);
    $self->setReachable();
    $self->updateDataCollectionStatus('Route', 'OK');
    $self->{logger}->debug("obtainRoute finished");
}

sub obtainVrf {
    my $self = shift;
    $self->{logger}->debug("obtainVrf started");
    my $api_helper = $self->getApiClient();
    
    $self->{logger}->debug("Calling get_vrf_configured of ACI client");
    my ($fabric_vrfs, $message) = $api_helper->get_vrf_configured();
    unless ($fabric_vrfs) {
        $self->{logger}->error('obtainVrf failed: ' . $message);
        $self->setUnreachable('Cannot retrieve list of vrfs');
        $self->updateDataCollectionStatus('Vrf', 'Error');
        return undef;
    }
    $self->{logger}->debug("received configured vrf info: "); 
    $self->{logger}->debug(Dumper($fabric_vrfs));

    $self->{logger}->debug("Calling get_vrf_deployed of ACI client");
    (my $device_vrfs, $message) = $api_helper->get_vrf_deployed();
    $self->{logger}->debug("received deployed vrf info: "); 
    $self->{logger}->debug(Dumper($device_vrfs));

    my %fvCtx_to_l3Ctx;
    for my $ctx (@$device_vrfs) {
        my $class = (keys(%$ctx))[0];
        my $attrs = $ctx->{$class}{attributes};
        if ($attrs->{ctxPKey}) {
            $fvCtx_to_l3Ctx{$attrs->{ctxPKey}} = $attrs;
        } 

    }

    my @final_info;
    for my $ctx (@$fabric_vrfs) {
        my $class = (keys(%$ctx))[0];
        $ctx->{$class}{attributes}{dn} =~ m!tn-(.*?)/ctx-(.*?)$!;
		my $name = $ctx->{$class}{attributes}{name} ? $ctx->{$class}{attributes}{name} : "$1:$2";
        my $item = {
            Name => $name,
            Description => $ctx->{$class}{attributes}{descr},
            DefaultRDType => '',
            DefaultRDLeft => 0,
            DefaultRDRight => 0,
            DefaultVPNID => 0,
            CurrentCount => 0,
            Timestamp => NetMRI::Util::Date::formatDate(time())
        };
        if ($fvCtx_to_l3Ctx{$ctx->{$class}{attributes}{dn}}) {
            my ($rd_left, $rd_right) = split(/:/, $fvCtx_to_l3Ctx{$ctx->{$class}{attributes}{dn}}->{bgpRdDisp});
            # rd_left can be either BGP AS number or an IPv4 address. rd_right is always integer
            # Refer to https://www.cisco.com/c/en/us/td/docs/ios/12_2sr/12_2sra/feature/guide/srbgprid.htm#wp1054547 for further explanation
            my ($rd_type, $rd_left_sql) = ('', $rd_left);
            if ($rd_left =~ /[.]/) {
                $rd_type = 'ipv4';
                $rd_left = InetAddr($rd_left);
            }
            $item->{Name} = $fvCtx_to_l3Ctx{$ctx->{$class}{attributes}{dn}}->{name} if defined $fvCtx_to_l3Ctx{$ctx->{$class}{attributes}{dn}}->{name};
            $item->{DefaultRDType} = $rd_type;
            $item->{DefaultRDLeft} = $rd_left;
            $item->{DefaultRDRight} = $rd_right;
        }
        push @final_info, $item;
    }
    $self->saveVrf(\@final_info);
    $self->setReachable();
    $self->updateDataCollectionStatus('Vrf', 'OK');
    $self->{logger}->debug("obtainVrf finished");
}

sub obtainVrfHasInterface {
    my $self = shift;
    $self->{logger}->debug("obtainVrfHasInterface started");
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_ip_interfaces of ACI client");
    my ($res, $message) = $api_helper->get_ip_interfaces();
    unless ($res) {
        $self->{logger}->error('obtainVrfHasInterface failed: ' . $message);
        return undef;
    }
    $self->{logger}->debug("received ip interfaces info: "); 
    $self->{logger}->debug(Dumper($res));

    my @vrf_info;
    for my $record (@$res) {
        $record->{ipv4If}{attributes}{dn} =~ m!dom-(.*?)/if-\[(.*?)\]!;
        push @vrf_info, {
            Timestamp => NetMRI::Util::Date::formatDate(time()),
            vrfName => $1,
            Interface => $2
        };
    }

    $self->saveVrfHasInterface(\@vrf_info);
    $self->{logger}->debug("obtainVrfHasInterface finished");
}

sub obtainPerformance {
    my $self = shift;
    $self->{logger}->debug("obtainPerformance started");
    return unless my $device_id = $self->getDeviceID('obtainPerformance: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_performance of ACI client");
    my ($res, $message) = $api_helper->get_performance();
    unless ($res) {
        $self->{logger}->error('obtainPerformance failed: ' . $message);
        $self->setUnreachable('Cannot retrieve performance information');
        return undef;
    }
    $self->{logger}->debug("received perforance info: "); 
    $self->{logger}->debug(Dumper($res));

    my %perf_data = (
        CpuIndex => 0, # ACI always returns aggregate stats
        StartTime => NetMRI::Util::Date::formatDate(time()),
        EndTime => NetMRI::Util::Date::formatDate(time()),
    );
    foreach my $item (@$res) {
        my $class = (keys(%$item))[0];
        if ($class eq 'procSysCPUHist5min') {
            my $cpu_idle = $item->{procSysCPUHist5min}{attributes}{idleAvg};
            $perf_data{CpuBusy} = int(100 - $cpu_idle);
        }
        if ($class eq 'procSysMemHist5min') {
            $perf_data{UsedMem} = $item->{procSysMemHist5min}{attributes}{usedAvg} * 1024; # For fabric node, ACI returns data in kilobytes
            $perf_data{FreeMem} = $item->{procSysMemHist5min}{attributes}{freeAvg} * 1024;
        }
        if ($class eq 'procEntity') {
            $perf_data{CpuBusy} = $item->{procEntity}{attributes}{cpuPct};
            $perf_data{UsedMem} = $item->{procEntity}{attributes}{maxMemAlloc};
            $perf_data{FreeMem} = $item->{procEntity}{attributes}{memFree};
        }
    }
    $perf_data{Utilization5Min} = $perf_data{UsedMem};
    
    $self->savePerformance([\%perf_data]);
    $self->setReachable();
    $self->{logger}->debug("obtainPerformance finished");
}

sub obtainEnvironmental {
    my $self = shift;
    $self->{logger}->debug("obtainEnvironmental started");
    my $res = $self->getEnvironmental();
    my $count = (ref($res) ? scalar(@$res) : 0);
    $self->{logger}->debug("obtainEnvironmental finished, got ${count} records");
    $self->saveEnvironmental($res);
    $self->{logger}->debug("obtainEnvironmental finished");
}

sub getEnvironmental {
    my $self = shift;
    $self->{logger}->debug("getEnvironmental started");
    return [] unless my $device_id = $self->getDeviceID('getEnvironmental: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();

    my @environmental_data;
    $self->{logger}->debug("Calling get_environmental_temp of ACI client");
    my $errors = [];
    my ($res, $message) = $api_helper->get_environmental_temp();
    if ($res) {
        $self->{logger}->debug("received temperatures info: "); 
        $self->{logger}->debug(Dumper($res));
        push @environmental_data, $self->_prepare_environmental_data($res, 
            env_type => 'temperature',
            sensor_class => 'eqptSensor',
            measurements_class => 'eqptTemp5min',
            measurements_attr => 'currentLast',
            env_index_regex => '(?:slot-(\d+)|bslot).*sensor-(\d+)'
        );

    } else {
        $self->{logger}->error('getEnvironmental (temperatures) failed: ' . $message);
        push @$errors, 'temperatures';
    }

    $self->{logger}->debug("Calling get_environmental_fan of ACI client");
    ($res, $message) = $api_helper->get_environmental_fan();
    if ($res) {
        $self->{logger}->debug("received fan info: "); 
        $self->{logger}->debug(Dumper($res));
        push @environmental_data, $self->_prepare_environmental_data($res,
            env_type => 'fan',
            sensor_class => 'eqptFan',
            env_index_regex => 'ftslot-(\d+).*fan-(\d+)'
        );
    } else {
        $self->{logger}->error('getEnvironmental (fan) failed: ' . $message);
        push @$errors, 'fan';
    }

    $self->{logger}->debug("Calling get_environmental_psu of ACI client");
    ($res, $message) = $api_helper->get_environmental_psu();
    if ($res) {
        $self->{logger}->debug("received power supply info: "); 
        $self->{logger}->debug(Dumper($res));
        push @environmental_data, $self->_prepare_environmental_data($res,
            env_type => 'power',
            sensor_class => 'eqptPsu',
            env_index_regex => 'psuslot-(\d+)/psu'
        );
    } else {
        $self->{logger}->error('getEnvironmental (psu) failed: ' . $message);
        push @$errors, 'psu';
    }

    if (scalar(@$errors)) {
        $self->setUnreachable('Cannot retrieve Environmental information: ' . join(', ', @$errors));
        $self->updateDataCollectionStatus('Environmental', 'Error');  
    } else {
        $self->setReachable();
        $self->updateDataCollectionStatus('Environmental', 'OK');  
    }

    return \@environmental_data;
}

sub obtainEndhosts {
    my $self = shift;
    $self->{logger}->debug("obtainEndhosts started");
    return unless my $device_id = $self->getDeviceID('obtainEndhosts: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();

    $self->{logger}->debug("Calling get_endpoint_epg_binding of ACI client");
    my ($endpoint_bindings, $message) = $api_helper->get_endpoint_epg_binding();
    unless ($endpoint_bindings) {
        $self->{logger}->error('obtainEndhosts failed: ' . $message);
        $self->setUnreachable('Cannot retrieve endpoint EPG binding');
        return undef;
    }
    $self->{logger}->debug("received endpoint-epg binding: "); 
    $self->{logger}->debug(Dumper($endpoint_bindings));

    my %encap2epg;
    foreach my $rel (@$endpoint_bindings) {
        my $class = (keys(%$rel))[0];

        $rel->{$class}{attributes}{dn} =~ m!(.*)/rsvlanEppAtt-\[.*\[(.*)\]\]!;
        $encap2epg{$1} = $2;
    }

    $self->{logger}->debug("Calling get_endpoints of ACI client");
    (my $res, $message) = $api_helper->get_endpoints();
    unless ($res) {
        $self->{logger}->error('obtainEndpoints failed: ' . $message);
        $self->setUnreachable('Cannot retrieve endpoints');
        return undef;
    }
    $self->{logger}->debug("received endpoints info: "); 
    $self->{logger}->debug(Dumper($res));

    my @endpoint_info;
    my @forwarding_info;
    foreach my $ep (@$res) {
        my $class = (keys %$ep)[0];
        next if ( $ep->{$class}{attributes}{flags} =~ /peer-attached/ && $ep->{$class}{attributes}{ifId} !~ /tunnel/ ); # Ignore endpoints that come from another node
        my $encap = 0;
        # ACI supports encapsulating endpoint traffic into vxlan, which we don't support
        if ($ep->{$class}{attributes}{dn} =~ m!vlan-\[vlan-(\d+)\]/db-ep/!) {
            $encap = $1;
        }
        my $if_index = $self->getInterfaceIndex($ep->{$class}{attributes}{ifId});
        $ep->{$class}{attributes}{dn} =~ m!(.*)/db-ep/!;
        my $epg_dn = $encap2epg{$1};


        push @forwarding_info, {
            StartTime => NetMRI::Util::Date::formatDate(time()),
            EndTime => NetMRI::Util::Date::formatDate(time()),
            vlan => $encap,
            dot1dTpFdbPort => $if_index || 0,
            dot1dTpFdbStatus => 'learned',
            dot1dTpFdbAddress => $ep->{$class}{attributes}{addr},
        };

        my @ip_endpoints;
        if (exists($ep->{$class}{children})) {
            for my $chld (@{$ep->{$class}{children}}) {
                my $chld_class = (keys %$chld)[0];
                next unless ($chld_class eq 'epmRsMacEpToIpEpAtt');
                if ($chld->{$chld_class}{attributes}{tDn} =~ m!db-ep/ip-\[(.*?)\]!) {
                    push @ip_endpoints, {
                        SdnInterfaceID => $if_index,
                        Name => $ep->{$class}{attributes}{name},
                        MAC => $ep->{$class}{attributes}{addr},
                        IP => $1,
                        EPG => $epg_dn,
                        Encap => $encap,
                    } if $if_index;
                } else {
                    $self->{logger}->warn("Unknown IP endpoint format: " . $chld->{$chld_class}{attributes}{tDn});
                }

            }
        }
        if (@ip_endpoints) {
            push @endpoint_info, @ip_endpoints;
        } else {
            push @endpoint_info, {
                SdnInterfaceID => $if_index,
                Name => $ep->{$class}{attributes}{name},
                MAC => $ep->{$class}{attributes}{addr},
                IP => '',
                EPG => $epg_dn,
                Encap => $encap,
            } if $if_index;
         }
    }

    $self->{logger}->debug("Calling get_fabric_link of ACI client");
    ($res, $message) = $api_helper->get_fabric_link();
    unless ($res) {
        $self->{logger}->error('obtainEndhosts: Topology failed: ' . $message);
        return undef;
    }
    $self->{logger}->debug("received topology info: ");
    $self->{logger}->debug(Dumper($res));

    my $topology_info = $self->getTopologyInfo($res, $api_helper->{fabric_id}, $device_id);
    push @forwarding_info, @$topology_info;    
    $self->saveSdnEndpoint(\@endpoint_info);
    $self->saveForwarding(\@forwarding_info);
    $self->setReachable();
    $self->updateDataCollectionStatus('Forwarding', 'OK');
    $self->{logger}->debug("obtainEndhosts finished");
}

sub obtainTopology {
    my $self = shift;

    $self->{logger}->debug("obtainFabricTopology started");
    my $api_helper = $self->getApiClient();
    my $device_id = $self->getDeviceID('obtainTopology: ' . $self->{warning_no_device_id_assigned});
    $self->{logger}->debug("Calling get_fabric_link of ACI client");
    my ($res, $message) = $api_helper->get_fabric_link();
    unless ($res) {
        $self->{logger}->error('obtainTopology failed: ' . $message);
        return undef;
    }
    $self->{logger}->debug("received topology info: ");
    $self->{logger}->debug(Dumper($res));
    my $info = $self->getTopologyInfo($res, $api_helper->{fabric_id}, $device_id);
    $self->saveForwarding($info);
    $self->{logger}->debug("obtainTopology finished");
    $self->updateDataCollectionStatus('Forwarding', 'OK');
}        

sub getTopologyInfo{
    my ($self, $res, $fabric_id, $device_id) = @_;
    $self->{logger}->debug("getTopologyInfo started: fabricID = $fabric_id, deviceID = $device_id");
    my $if_indexes = {};

    foreach my $row ($self->{sql}->table("select fd.SdnDeviceDN, fd.DeviceID, ic.ifIndex, ic.Name, ic.PhysAddress from $main::NETMRI_DB.SdnFabricDevice fd join $main::NETMRI_DB.ifConfig ic using (DeviceID) where fd.SdnControllerId = $fabric_id")) {
        my ($pod_id, $node_id);
        if ($row->{SdnDeviceDN} =~ m!topology/pod-(\d+)/node-(\d+)$!) {
            $pod_id = $1;
            $node_id = $2;
        } else {
            $self->{logger}->warn("getTopologyInfo: Cannot parse device DN $row->{SdnDeviceDN}");
            next;
        }
        $if_indexes->{$pod_id}{$node_id}{$row->{Name}} = {mac => $row->{PhysAddress}, if_index => $row->{ifIndex}, device_id => $row->{DeviceID}};
    }

    my @info;
    foreach my $item (@$res) {
        my $link = $item->{(keys %$item)[0]}{attributes};
        # Node IDs are supposed to be unique, but this is ACI, so I'm not taking any chances and include pod ID as well
        $link->{dn} =~ m!topology/pod-(\d+)/!;
        my $pod = $1;
        next unless exists($if_indexes->{$pod}{$link->{n1}});
        next unless exists($if_indexes->{$pod}{$link->{n1}}{"eth$link->{s1}/$link->{p1}"}{device_id});
        next unless $device_id == $if_indexes->{$pod}{$link->{n1}}{"eth$link->{s1}/$link->{p1}"}{device_id};
        my %rec = (
            DeviceID => $if_indexes->{$pod}{$link->{n1}}{"eth$link->{s1}/$link->{p1}"}{device_id},
            StartTime => NetMRI::Util::Date::formatDate(time()),
            EndTime => NetMRI::Util::Date::formatDate(time()),
            vlan => 0,
            dot1dTpFdbPort => $if_indexes->{$pod}{$link->{n1}}{"eth$link->{s1}/$link->{p1}"}{if_index},
            dot1dTpFdbStatus => 'learned',
            dot1dTpFdbAddress => $if_indexes->{$pod}{$link->{n2}}{"eth$link->{s2}/$link->{p2}"}{mac} || '',
            dot1dTpFdbNeighborInterface => "eth$link->{s2}/$link->{p2}",
        );
        push @info, \%rec;
    }
    return \@info;       
}
            
sub obtainCdp {
    my $self = shift;
    $self->{logger}->debug("obtainCdp started");
    return unless my $device_id = $self->getDeviceID('obtainCdp: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_cdp_neighbors of ACI client");
    my ($res, $message) = $api_helper->get_cdp_neighbors();
    unless ($res) {
        $self->{logger}->error('obtainCdp failed: ' . $message);
        $self->setUnreachable('Cannot retrieve CDP neighbors');
        $self->updateDataCollectionStatus('Neighbor', 'Error');
        return undef;
    }
    $self->{logger}->debug("received cdp neighbors: "); 
    $self->{logger}->debug(Dumper($res));

    my @cdp_info;
    foreach my $intf (@$res) {
        my @neighbors = grep {(keys(%$_))[0] eq 'cdpAdjEp'} @{$intf->{cdpIf}{children}};
        next unless (@neighbors);
        foreach my $neighbor (@neighbors) {
            my $neighbor_addr = (sort {$a->{cdpIntfAddr}{attributes}{addr} cmp $b->{cdpIntfAddr}{attributes}{addr}} (grep {(keys(%$_))[0] eq 'cdpIntfAddr'} (@{$neighbor->{cdpAdjEp}{children}})))[0]; # Always take the lowest address for consistency
            unless ($neighbor_addr) {
                $self->{logger}->info("CDP neighbor $neighbor->{cdpAdjEp}{attributes}{rn} on $intf->{cdpIf}{attributes}{dn} doesn't have address information. Skipping");
                next;
            }
            my $addr_type = $neighbor_addr->{cdpIntfAddr}{attributes}{addr} =~/:/ ? 1 : 'ip';

            my $capabilities = $self->reconstruct_cdp_capabilities(split(/,/, $neighbor->{cdpAdjEp}{attributes}{cap}));
            my $sys_object_id = join('.', (split(/,/, $neighbor->{cdpAdjEp}{attributes}{sysObjIdV}))[0..($neighbor->{cdpAdjEp}{attributes}{sysObjIdL}-1)]);
            my $cdp_cache_native_vlan = $neighbor->{cdpAdjEp}{attributes}{nativeVlan} eq 'unspecified' ? 0 : $neighbor->{cdpAdjEp}{attributes}{nativeVlan};

            push @cdp_info, {
                StartTime => NetMRI::Util::Date::formatDate(time()),
                EndTime => NetMRI::Util::Date::formatDate(time()),
                interface => $intf->{cdpIf}{attributes}{id},
                cdpCacheIfIndex => $self->getInterfaceIndex($intf->{cdpIf}{attributes}{id}),
                cdpCacheDeviceIndex => $neighbor->{cdpAdjEp}{attributes}{index},
                cdpCacheAddressType => $addr_type,
                cdpCacheAddress => $neighbor_addr->{cdpIntfAddr}{attributes}{addr},
                cdpCacheVersion => $neighbor->{cdpAdjEp}{attributes}{ver},
                cdpCacheDeviceId => $neighbor->{cdpAdjEp}{attributes}{devId},
                cdpCacheDevicePort => $neighbor->{cdpAdjEp}{attributes}{portId},
                cdpCachePlatform => $neighbor->{cdpAdjEp}{attributes}{platId},
                cdpCacheCapabilities => $capabilities,
                cdpCacheNativeVLAN => $cdp_cache_native_vlan,
                cdpCacheDuplex => $neighbor->{cdpAdjEp}{attributes}{duplex},
                #cdpCacheApplianceID => '', 
                #cdpCacheVlanID => '', 
                #cdpCachePowerConsumption => '', 
                cdpCacheMTU => $neighbor->{cdpAdjEp}{attributes}{mtu},
                cdpCacheSysName => $neighbor->{cdpAdjEp}{attributes}{sysName},
                cdpCacheSysObjectID => $sys_object_id,
                cdpCachePrimaryMgmtAddrType => $addr_type, 
                cdpCachePrimaryMgmtAddr => $neighbor_addr->{cdpIntfAddr}{attributes}{addr}, 
                #cdpCacheSecondaryMgmtAddrType => '', 
                #cdpCacheSecondaryMgmtAddr => '', 
                cdpCachePhysLocation => $neighbor->{cdpAdjEp}{attributes}{sysLoc},
                #cdpCacheLastChange => '', 
            };
        }

    }
    $self->saveCDP(\@cdp_info);
    $self->setReachable();
    $self->updateDataCollectionStatus('Neighbor', 'OK');
    $self->{logger}->debug("obtainCdp finished");
}

sub obtainLldp {
    my $self = shift;
    $self->{logger}->debug("obtainLldp started");
    return unless my $device_id = $self->getDeviceID('obtainLldp: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_lldp_neighbors of ACI client");
    my ($res, $message) = $api_helper->get_lldp_neighbors();
    unless ($res) {
        $self->{logger}->error('obtainLldp failed: ' . $message);
        $self->setUnreachable('Cannot retrieve LLDP neighbors');
        $self->updateDataCollectionStatus('Neighbor', 'Error');
        return undef;
    }
    $self->{logger}->debug("received lldp info: "); 
    $self->{logger}->debug(Dumper($res));

    my @lldp_info;
    for my $if (@{$res->[0]{lldpInst}{children}}) {
        my @endpoints = grep {(keys %$_)[0] eq 'lldpAdjEp'} @{$if->{lldpIf}{children}};
        for my $endpoint (@endpoints) {
            push @lldp_info, {
                Timestamp => NetMRI::Util::Date::formatDate(time()),
                LocalPortId => $if->{lldpIf}{attributes}{id},
                LocalPortIdSubtype => 'interfaceAlias',
                RemLocalPortDescr => $if->{lldpIf}{attributes}{portDesc},
                RemChassisIdSubtype => _lldp_id_type($endpoint->{lldpAdjEp}{attributes}{chassisIdT}),
                RemChassisID => ($endpoint->{lldpAdjEp}{attributes}{chassisIdT} eq 'mac') ? uc $endpoint->{lldpAdjEp}{attributes}{chassisIdV} : $endpoint->{lldpAdjEp}{attributes}{chassisIdV},
                RemPortIdSubtype => _lldp_id_type($endpoint->{lldpAdjEp}{attributes}{portIdT}),
                RemPortID => ($endpoint->{lldpAdjEp}{attributes}{portIdT} eq 'mac') ? uc $endpoint->{lldpAdjEp}{attributes}{portIdV} : $endpoint->{lldpAdjEp}{attributes}{portIdV},
                RemPortDesc => $endpoint->{lldpAdjEp}{attributes}{portDesc},
                RemSysName => $endpoint->{lldpAdjEp}{attributes}{sysName},
                RemSysDesc => $endpoint->{lldpAdjEp}{attributes}{sysDesc},
                RemSysCapSupported => $endpoint->{lldpAdjEp}{attributes}{capability},
                RemSysCapEnabled => $endpoint->{lldpAdjEp}{attributes}{enCap},
            };
        }
    }
    $self->saveLLDP(\@lldp_info);
    $self->setReachable();
    $self->updateDataCollectionStatus('Neighbor', 'OK');
    $self->{logger}->debug("obtainLldp finished");
}

sub _lldp_id_type {
    my ($t) = @_;
    return 'macAddress'    if $t eq 'mac';
    return 'interfaceName' if $t eq 'if-name';
    return $t;
}

sub reconstruct_cdp_capabilities {
    my $self = shift;
    my @caps = @_;

    #Taken from https://developer.cisco.com/media/mim-ref/TYPE-cdp-CapT.html
    my %capability_map = (
        'router' => 1,
        'trans-bridge' => 2,
        'src-bridge' => 4,
        'switch' => 8,
        'host' => 16,
        'igmp-filter' => 32,
        'repeater' => 64,
        'voip' => 128,
        'remote-manage' => 256,
        'stp-dispute' => 512,
    );

    my $cap_numeric = 0;

    foreach my $cap (@caps) {
        unless ($capability_map{$cap}) {
            $self->{logger}->warn("Found unknown CDP capability: $cap");
            next;
        }
        $cap_numeric = $cap_numeric | $capability_map{$cap};
    }

    return $cap_numeric;
}

sub obtainInventory {
    my $self = shift;
    $self->{logger}->debug("obtainInventory started");
    return unless my $device_id = $self->getDeviceID('obtainInventory: ' . $self->{warning_no_device_id_assigned});
    my $api_helper = $self->getApiClient();
    my $collectFEX = 0;
    
    $self->{logger}->debug("Calling get_inventory of ACI client");
    my ($res, $message) = $api_helper->get_inventory();
    unless ($res) {
        $self->{logger}->error('obtainInventory failed: ' . $message);
        $self->setUnreachable('Cannot retrieve inventory');
        $self->updateDataCollectionStatus('Inventory', 'Error');
        return undef;
    }
    $self->{logger}->debug("received inventory info: "); 
    $self->{logger}->debug(Dumper($res));

    my %class_offsets = (
        eqptCh => 10000,
        eqptSupC => 20000,
        eqptLC => 30000,
        eqptFt => 40000,
        eqptPsu => 50000,
        eqptFan => 60000,
        eqptSensor => 70000,
        eqptExtCh => 80000,
    );

    my @final_info;
    foreach my $r (@$res) {
        my $class = (%$r)[0];
        my $data = $r->{$class}{attributes};

        my %res = ( 
            StartTime               => NetMRI::Util::Date::formatDate(time()),
            EndTime                 => NetMRI::Util::Date::formatDate(time()),
            entPhysicalIndex        => $class_offsets{$class} + $data->{id},
            entPhysicalDescr        => $data->{descr},
            entPhysicalVendorType   => $data->{vendor} || '',
            entPhysicalContainedIn  => '', 
            entPhysicalParentRelPos => '', 
            entPhysicalHardwareRev  => $data->{hwVer} || '', 
            entPhysicalFirmwareRev  => '', 
            entPhysicalSoftwareRev  => '', 
            entPhysicalSerialNum    => $data->{ser},
            entPhysicalMfgName      => $data->{vendor} || '', 
            entPhysicalModelName    => $data->{model},
            entPhysicalAlias        => '', 
            entPhysicalAssetID      => '', 
            UnitState               => $data->{operSt},
        );  

        if ($class eq 'eqptSupC' || $class eq 'eqptLC'){
            $res{entPhysicalName}  = $data->{descr};
            $res{entPhysicalClass} = $data->{type};
        }   
        elsif ($class eq 'eqptFt'){
            $res{entPhysicalName}  = $data->{fanName};
            $res{entPhysicalClass} = 'fan';
        }   
        elsif ($class eq 'eqptPsu'){
            $res{entPhysicalName}  = $data->{descr};
            $res{entPhysicalClass} = 'power';
        }   
        elsif ($class eq 'eqptCh'){
            $res{entPhysicalName}  = $data->{descr};
            $res{entPhysicalClass} = 'chassis';
            if ($data->{role} =~ /leaf/) {
                $collectFEX = 1;
            }
            
        } elsif ($class eq 'eqptFan') {
            $res{entPhysicalName}  = (split m!/!, $data->{dn})[-1];
            $res{entPhysicalClass} = 'fan';
        } elsif ($class eq 'eqptSensor') {
            $res{entPhysicalName}  = (split m!/!, $data->{dn})[-1];
            $res{entPhysicalClass} = $data->{type};
        }

        push @final_info, \%res;
    } 

    if ($collectFEX) {
        $self->{logger}->debug("Calling get_inventoryFEX of ACI client");
        my ($resFex, $messageFex) = $api_helper->get_inventoryFex();
#        my ($resFex, $messageFex) = $api_helper->get_inventory();
        $self->{logger}->debug("received inventory info for FEX modules: "); 
        $self->{logger}->debug(Dumper($resFex));

        if ($resFex) {
            foreach my $r (@$resFex) {
                my $class = (%$r)[0];
                my $data = $r->{$class}{attributes};
        
                my %res = ( 
                    StartTime               => NetMRI::Util::Date::formatDate(time()),
                    EndTime                 => NetMRI::Util::Date::formatDate(time()),
                    entPhysicalIndex        => $class_offsets{$class} + $data->{id},
                    entPhysicalDescr        => $data->{descr},
                    entPhysicalVendorType   => $data->{vendor} || '',
                    entPhysicalContainedIn  => '', 
                    entPhysicalParentRelPos => '', 
                    entPhysicalHardwareRev  => $data->{hwVer} || '', 
                    entPhysicalFirmwareRev  => '', 
                    entPhysicalSoftwareRev  => '', 
                    entPhysicalSerialNum    => $data->{ser},
                    entPhysicalMfgName      => $data->{vendor} || '', 
                    entPhysicalModelName    => $data->{model},
                    entPhysicalAlias        => '', 
                    entPhysicalAssetID      => '', 
                    UnitState               => $data->{extChSt} || 'unknown',
                );  
        
                if ($class eq 'eqptExtCh'){
                    $res{entPhysicalName}  = ($data->{id} <= 999) ? 'FEX0' . $data->{id} : 'FEX' . $data->{id};
                    $res{entPhysicalClass} = 'fex';
                    push @final_info, \%res;
                }   
            }
        }
    }
    
    $self->saveInventory(\@final_info);
    $self->setReachable();
    $self->updateDataCollectionStatus('Inventory', 'OK');
    $self->{logger}->debug("obtainInventory finished");
}

sub obtainAciPolicyObjects {
    my $self = shift;
    $self->{logger}->debug("obtainAciPolicyObjects started");
    my $api_helper = $self->getApiClient();
    $self->{logger}->debug("Calling get_policy_objects of ACI client");
    my ($res, $message) = $api_helper->get_policy_objects();
    unless ($res) {
        $self->{logger}->error('obtainPolicyObjects failed: ' . $message);
        return undef;
    }
    $self->{logger}->debug("received policy objects info: "); 
    $self->{logger}->debug(Dumper($res));

    my %policy_objects;
    my @ap_membership;
    foreach my $obj (@$res) {
        my $class = (keys(%$obj))[0];
        my $attrs = $obj->{$class}{attributes};

        my $data;
        if ($class eq 'fvTenant') {
            $data = {
                controller_id => $api_helper->{fabric_id},
                dn => $attrs->{dn},
                name => $attrs->{name},
                descr => $attrs->{descr}
            };
        } elsif ($class eq 'fvBD' || $class eq 'fvCtx') {
            $data = {
                controller_id => $api_helper->{fabric_id},
                dn => $attrs->{dn},
                name => $attrs->{name},
                descr => $attrs->{descr},
                scope => $attrs->{scope},
                segment => $attrs->{seg},
            };
        } elsif ($class eq 'fvAp') {
            $data = {
                controller_id => $api_helper->{fabric_id},
                dn => $attrs->{dn},
                name => $attrs->{name},
                descr => $attrs->{descr}
            };
        } elsif ($class eq 'fvAEPg') {
            $attrs->{dn} =~ m!((uni/.*?)/.*?)/.*?!;
            push @ap_membership, {
                controller_id => $api_helper->{fabric_id},
                epg_dn => $attrs->{dn},
                app_profile_dn => $1,
                tenant_dn => $2
            };

            $data = {
                controller_id => $api_helper->{fabric_id},
                dn => $attrs->{dn},
                name => $attrs->{name},
                descr => $attrs->{descr},
                scope => $attrs->{scope},
            };
        }
        $policy_objects{$class} //= [];
        push @{$policy_objects{$class}}, $data;
    }

    $self->saveAciTenant($policy_objects{fvTenant});
    $self->saveAciBridgeDomain($policy_objects{fvBD});
    $self->saveAciVrf($policy_objects{fvCtx});
    $self->saveAciAppProfile($policy_objects{fvAp});
    $self->saveAciEpg($policy_objects{fvAEPg});
    $self->saveAciAppProfileMembership(\@ap_membership);

    $self->{logger}->debug("Calling get_bd_to_vrf_relationship of ACI client");
    (my $vrf_rels, $message) = $api_helper->get_bd_to_vrf_relationship();
    unless ($vrf_rels) {
        $self->{logger}->error('obtainPolicyObjects failed: ' . $message);
        return undef;
    }
    $self->{logger}->debug("received bd - vrf relationships: "); 
    $self->{logger}->debug(Dumper($vrf_rels));

    $self->{logger}->debug("Calling get_epg_to_bd_relationship of ACI client");
    (my $epg_rels, $message) = $api_helper->get_epg_to_bd_relationship();
    unless ($epg_rels) {
        $self->{logger}->error('obtainPolicyObjects failed: ' . $message);
        return undef;
    }
    $self->{logger}->debug("received epg - bd relationships: "); 
    $self->{logger}->debug(Dumper($epg_rels));

    my %bd_membership;
    foreach my $r (@$vrf_rels) {
        my $rel = $r->{fvRtCtx}{attributes};
        unless ($rel->{tCl} eq 'fvBD') { # If we encountered relationship with something other than BD, log it and skip
            $self->{logger}->warn("Unknown relationship $rel->{dn} encountered. Skipping");
            next;
        }

        $rel->{dn} =~ m!^(.*?)/rtctx-\[(.*?)\]!;
        my $vrf_dn = $1;
        my $bd_dn = $2;

        $bd_membership{$bd_dn} //= {};
        $bd_membership{$bd_dn}->{vrf_dn} //= {};
        $bd_membership{$bd_dn}->{vrf_dn}{$vrf_dn} = 1;
    }
    foreach my $r (@$epg_rels) {
        my $rel = $r->{fvRtBd}{attributes};
        unless ($rel->{tCl} eq 'fvAEPg') { # If we encountered relationship with something other than EPG, log it and skip
            $self->{logger}->warn("Unknown relationship $rel->{dn} encountered. Skipping");
            next;
        }

        $rel->{dn} =~ m!^(.*?)/rtbd-\[(.*?)\]!;
        my $bd_dn = $1;
        my $epg_dn = $2;

        $bd_membership{$bd_dn} //= {};
        $bd_membership{$bd_dn}->{epg_dn} //= {};
        $bd_membership{$bd_dn}->{epg_dn}{$epg_dn} = 1;
    }

    my @bd_membership_data;
    foreach my $bd_dn (keys(%bd_membership)) {
        $bd_dn =~ m!^(.*)/[^/]*$!;
        my $tenant_dn = $1;

        foreach my $vrf_dn (keys(%{$bd_membership{$bd_dn}->{vrf_dn}})) {
            my %info = (
                controller_id => $api_helper->{fabric_id},
                tenant_dn => $tenant_dn,
                bridge_domain_dn => $bd_dn,
                vrf_dn => $vrf_dn
            );
            if (keys(%{$bd_membership{$bd_dn}->{epg_dn}})) {
                foreach my $epg_dn (keys(%{$bd_membership{$bd_dn}->{epg_dn}})) {
                    push @bd_membership_data, {%info, epg_dn => $epg_dn};
                }
            } else {
                push @bd_membership_data, {%info, epg_dn => ''};
            }
        }
    }

    $self->saveAciBridgeDomainMembership(\@bd_membership_data);
    $self->{logger}->debug("obtainAciPolicyObjects finished");
}

sub _prepare_environmental_data {
    my $self = shift;
    my $data = shift;
    my %opts = @_;

    my @sensor_information;
    foreach my $sensor (@{$data}) {
        next if ($opts{measurements_class} && !$sensor->{$opts{sensor_class}}{children}[0]{$opts{measurements_class}}); # skip sensors without data

        # decr is more human readable, so we'll pick it if it's available
        my $env_descr = ($sensor->{$opts{sensor_class}}{attributes}{descr} || $sensor->{$opts{sensor_class}}{attributes}{type});
        $sensor->{$opts{sensor_class}}{attributes}{dn} =~ m/$opts{env_index_regex}/;
        my ($slot, $sensor_id) = ($1, $2); 
        my $index = ($slot || 0)*1000 + ($sensor_id || 0);
        # Sometimes we don't have slot# (as in environmental sensors on APIC controller)
        # Sometimes we don't have sensor# (as in sensors on psu's).
        # We need to update description based on information available
        my @sensor_location;
        push @sensor_location, "slot #$slot" if (defined($slot));
        push @sensor_location, "sensor #$sensor_id" if (defined($sensor_id));
        if (@sensor_location) {
            $env_descr .= ' (' . join(' ', @sensor_location) . ')'; 
        }    

        my $sensor_info = {
            SdnDeviceDN => $self->{dn},
            envIndex => $index,
            StartTime => NetMRI::Util::Date::formatDate(time()),
            EndTime => NetMRI::Util::Date::formatDate(time()),
        };
        $sensor_info->{envType} = $opts{env_type};
        $sensor_info->{envDescr} = $env_descr;
        $sensor_info->{envState} = $sensor->{$opts{sensor_class}}{attributes}{operSt};
        if ($opts{measurements_class}) {
            $sensor_info->{envStatus} = $sensor->{$opts{sensor_class}}{children}[0]{$opts{measurements_class}}{attributes}{$opts{measurements_attr}};
            $sensor_info->{envMeasure} = '';
        }    
     
        push @sensor_information, $sensor_info;
    }    

    return @sensor_information;
}

sub _extract_attributes {
    my $imdata = shift;
    
    my @res;
    for my $item (@$imdata) {
        for my $class (keys(%$item)) {
            $item->{$class}{attributes}{__class} = $class;
            push @res, $item->{$class}{attributes};
        }
    }
    return $res[0] if scalar(@res) == 1;
    return \@res;
}

sub _format_timestamp {
    my $self = shift;
    my $ts = shift;
    my $res = substr($ts, 0, 19);
    $res =~ s/T/ /;
    return $res;
}

sub _uptime_to_seconds {
    my ($v) = @_;
    my ($d,$h,$m,$s) = $v =~ m{^(\d+):(\d+):(\d+):(\d+)\.}io;
    return (( $d*24 + $h)*60 + $m)*60 + $s;
}


# List of possible attributes where management address of fabric node or APIC controller can be foune
# 'address' attribute is special because it's internal TEP (Tunnel End Point) address for the device.
# This address won't be accessible from outside the fabric (and most likely it'll be limited to infrastructure VLAN), 
# but it'll give NetMRI something to use as device address if management addresses aren't configured
my @mgmt_address_attributes = qw/oobMgmtAddr oobMgmtAddr6 inbMgmtAddr inbMgmtAddr6 address/;

# ACI device can have multiple management interfaces. Here we prefer out-of-band management over in-band management
# (this is unlikely to cause problems because Cisco recommends against configuring both at the same time)
# and IPv4 addresses over IPv6.
sub _select_node_mgmt_ip {
    my $self = shift;
    my $sys_info = shift;

    for my $attr (@mgmt_address_attributes) {
        return $sys_info->{$attr} if ($sys_info->{$attr} && ($sys_info->{$attr} ne '0.0.0.0') && ($sys_info->{$attr} ne '::'));
    }   

    return undef;
}

sub getApiClient {
    my $self = shift;
    unless (ref($self->{api_helper})) {
        $self->{logger}->error("Error getting the API Client: $@") if $@; 
        return undef;
    }
    return $self->{api_helper};
}

1;
