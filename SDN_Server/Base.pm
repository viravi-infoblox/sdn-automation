package NetMRI::SDN::Base;

require 5.000;

use strict;
no strict 'refs';
use Carp;
use JSON;
use Redis;
use NetMRI::Config;
use NetMRI::Isl;
use NetMRI::DiscoveryStatus;
use Scalar::Util qw(blessed);
use NetMRI::Util::Date;
use NetMRI::HTTP::Client::Generic;
use NetMRI::SDN::Plugins::Base;

our $AUTOLOAD;

sub new {
  my ($type, %args) = @_;
  my $self = \%args;
  foreach my $prop (qw(sql logger)) {
    croak "The property \"${prop}\" is not defined" unless ref($self->{$prop});
  }
  $self->{cfg} = NetMRI::Config->new() unless ref($self->{cfg});

  $self->{curPollTime}                     = time();
  $self->{netmri_db}                     ||= "netmri";
  $self->{report_db}                     ||= "report";
  $self->{config_db}                     ||= "config";
  $self->{api_helper_class}              ||= "NetMRI::HTTP::Client::Generic";
  $self->{api_helper_constructor_params} ||= {};

  $self->{plugins} = {};
  $self->{device_info_loaded} = 0;
  $self->{interface_map_loaded} = 0;
  $self->{warning_no_device_id_assigned} = 'SDN device dn=%dn% is not curently processed by discoveryEngine, try next time';
  $self->{warning_no_node_role_assigned} = 'SDN device dn=%dn% has not NodeRole';

  $self->{autoload_save_methods}->{$_} = 1 foreach (qw(
    Devices
    SystemInfo
    DeviceContext
    SwitchPortObject
    IPAddress
    atObject
    ipRouteTable
    Inventory
    Forwarding
    RoutingPerfObject
    Firewall
    VlanObject
    Environmental
    Performance
    ifTableObject
    RoutingInfo
    VrfObject
    QoSObject
    FirewallHitCount
    Wireless
    bsnAPTable
    bsnMobileStationTable

    OpenPorts
    LLDPNeighbors
    DeviceProperty
    vlanTrunkPortTable
    dot1dBasePortTable
    bgpPeerTable
    SdnFabricInterface
    DeviceCpuStats
    DeviceMemStats
    hrStorageTable

    SdnNetworks
    MerakiOrganizations
    MerakiNetworks
    MistOrganizations
    MistNetworks
    MistSdnEndpoint

    Vrf
    VrfARP
    VrfRoute
    VrfHasRTCommunity
    VrfHasInterface

    CDP
    LLDP
    SdnEndpoint

    AciTenant
    AciBridgeDomain
    AciVrf
    AciAppProfile
    AciEpg
    AciAppProfileMembership
    AciBridgeDomainMembership

    VlanTrunkPortTable
    ifConfig
    ifStatus
    ifPerf
  ));

  $self->{redis} = Redis->new(reconnect => 300) unless ref($self->{redis}) eq 'Redis';
  $self->{debug} //= (blessed($self->{logger}) && $self->{logger}->can('getDebug') ? $self->{logger}->getDebug() : 0);
  $self->{ds} = NetMRI::DiscoveryStatus->new(
    Debug => $self->{debug},
    Log => $self->{logger},
    Sql => $self->{sql},
    DB => $self->{netmri_db}
  );

  my $res = bless $self, $type;

  #do not reload cfg now
  $res->reloadConfig(load_cfg => 0);
  $res->_initLwpLocalAddr() if ($res->{network_interface} || $res->{fabric_id} || $res->{virtual_network_id});
  
  return $res;
}

# Create save* method on the fly
# The first time the method "saveBlaBla" is called it will be created by AUTOLOAD method (as method is not exists)
# The next time the same method is called, it will be found in the symbol table - since
#   we’ve just created it - and we won't go through AUTOLOAD again
sub AUTOLOAD {
  my ($self) = @_;
  if ($AUTOLOAD =~ /.*::save(.*)/ && exists($self->{autoload_save_methods}->{$1})) {
    my $object_name = $1;
    *$AUTOLOAD = sub {
      my ($self, $data) = @_;
      $self->{logger}->debug("save${object_name} started");
      $self->getPlugin('Save' . $object_name)->run($data);
      $self->{logger}->debug("save${object_name} finished");
    };
    goto &$AUTOLOAD;
  }
}

sub reloadConfig {
  my ($self, %args) = @_;
  $self->{cfg}->load() if ($args{load_cfg} > 0 || !exists($args{load_cfg}));
}

sub getApiClient {
  my $self = shift;
  unless (ref($self->{api_helper})) {
    my $cmd = $self->_getConstructorCommand();
    eval $cmd;
    $self->{logger}->error("Error getting the API Client: $@") if $@;
  }
  return $self->{api_helper};
}

sub obtainDevices {
  my $self = shift;
  $self->{logger}->debug("obtainDevices started");
  $self->saveDevices(
    $self->makeDevicesPoolWrapper( $self->getDevicesWrapper() )
  );
  $self->{logger}->debug("obtainDevices finished");
}

sub getDevicesWrapper {
  my $self = shift;
  $self->{logger}->debug("getDevices started");
  my $res = $self->getDevices();
  $self->{logger}->debug("getDevices finished, got " . (ref($res) ? scalar(@$res) : 0) . ' devices');
  return $res;
}

sub makeDevicesPoolWrapper {
  my ($self, $data) = @_;
  $self->{logger}->debug("makeDevicesPool started");
  my $res = $self->makeDevicesPool($data);
  $self->{logger}->debug("makeDevicesPool finished");
  return $res;
}

sub makeDevicesPool {
  my ($self, $data) = @_;
  return $data;
}

sub getDevices {
  return [];
}

sub loadDeviceInfo {
  my $self = shift;
  $self->{logger}->debug("enter loadDeviceInfo, dn=$self->{dn}, fabric_id=$self->{fabric_id}");
  return if $self->{device_info_loaded};
  return unless ($self->{dn} && $self->{fabric_id});
  my $sql = $self->{sql};
  my $device_plugin = $self->getPlugin('SaveDevices');
  my $query = "select * from " . $device_plugin->target_table() . " where SdnDeviceDN = " . $sql->escape($self->{dn}) . " and SdnControllerId=" . $sql->escape($self->{fabric_id});
  my $device_info = $sql->record($query, AllowNoRows => 1, RefWanted => 1);
  $self->{cached_device_info} = $device_info;
  $self->{device_info_loaded} = 1;
}

sub getDeviceField {
  my ($self, $field_name) = @_;
  $self->loadDeviceInfo();
  return $self->{cached_device_info}->{$field_name} || undef;
}

sub loadInterfaceMap {
  my $self = shift;
  my $if_config_table = shift;
  return if $self->{interface_map_loaded};
  return unless ($self->{dn} && $self->{fabric_id});
  my $sdn_device_id = $self->getDeviceField('SdnDeviceID');
  return unless $sdn_device_id;
  $self->{cached_interface_map} = {};

  if ($if_config_table) {
    my $device_id = $self->getDeviceField('DeviceID');
    return unless $device_id;
    my $plugin = $self->getPlugin('SaveifConfig');
    $self->{sql}->table("select ifIndex, Name from " . $plugin->target_table() . ' where DeviceID = ' . $self->{sql}->escape($device_id),
      Callback => sub {
        my $row = shift;
        $self->{cached_interface_map}->{$row->{Name}} = $row->{ifIndex};
      },
      AllowNoRows => 1
    );
  } else {
    my $plugin = $self->getPlugin('SaveSdnFabricInterface');
    $self->{sql}->table("select SdnInterfaceID, Name from " . $plugin->target_table() . ' where SdnDeviceID = ' . $self->{sql}->escape($sdn_device_id),
      Callback => sub {
        my $row = shift;
        $self->{cached_interface_map}->{$row->{Name}} = $row->{SdnInterfaceID};
      },
      AllowNoRows => 1
    );
  }
  $self->{interface_map_loaded} = 1;
}

sub obtainSwitchPort {
  my $self = shift;
  $self->{logger}->debug("obtainSwitchPort started");
  my $res = $self->getSwitchPort();
  $self->{logger}->debug("getSwitchPort finished, got " . (ref($res) ? scalar(@$res) : 0) . ' records');
  $self->savedot1dBasePortTable($res);
  $self->{logger}->debug("obtainSwitchPort finished");
}

sub getSwitchPort {
  return [];
}

sub getInterfaceIndex {
  my ($self, $interface_name, $if_config_table) = @_;
  $self->loadInterfaceMap($if_config_table);
  return $self->{cached_interface_map}->{$interface_name} || undef;
}

sub getDeviceID {
  my ($self, $log_template) = @_;
  my $device_id = $self->getDeviceField('DeviceID');
  if ($log_template && !$device_id) {
    $log_template =~ s/\%dn\%/$self->{dn}/ig;
    $self->{logger}->warn($log_template);
  }
  return $device_id;
}

sub getNodeRole {
  my ($self, $log_template) = @_;
  my $node_role = $self->getDeviceField('NodeRole');
  if ($log_template && !$node_role) {
    $log_template =~ s/\%dn\%/$self->{dn}/ig;
    $self->{logger}->warn($log_template);
  }
  return $node_role;
}

sub getPlugin {
  my ($self, $pluginName) = @_;
  unless (defined($self->{plugins}->{$pluginName})) {
    my $module_name = 'NetMRI::SDN::Plugins::'.$pluginName;
    my $cmd = 'require '. $module_name . '; $self->{plugins}->{$pluginName} = ' . $module_name . '->new($self);';
    eval $cmd;
    if ($@) {
      $self->{logger}->error("Error creating the plugin ${module_name}: " . $@);
      delete $self->{plugins}->{$pluginName};
      return NetMRI::SDN::Plugins::Base->new($self);
    }
  }
  return $self->{plugins}->{$pluginName};
}

sub updateDiscoveryStatus {
  my ($self, $type, $status, $msg, $device_id) = @_;
  $device_id = $self->getDeviceID() unless $device_id > 0;
  unless ($device_id) {
    $self->{logger}->error("Unable to update DiscoveryStatus for dn=" . $self->{dn} . " type=${type} status=${status} msg='${msg}' since DeviceID is not provided");
    return;
  }
  $self->{ds}->setValues(
    objType  => $type,
    DeviceID => $device_id,
    Status   => $status,
    Message  => $msg,
  );
  $self->{ds}->commit();
}

sub setReachable {
  my $self = shift;
  $self->updateDiscoveryStatus('Reachable', 'OK', 'Reachable: Successfully reached / Source: SDN Controller');
}

sub setUnreachable {
  my ($self, $msg) = @_;
  $self->updateDiscoveryStatus('Reachable', 'Error', 'Reachable: ' . ($msg || ''));
}

# //TODO: it should be moved from here, and from common.pm as well, into a separate module
# this code is taken from NetworkAutomation/Subsystems/Discovery/collectors/dataEngine/common.pm
sub updateDataCollectionStatus {
  my ($self, $field, $status, $device_id) = @_;

  $device_id = $self->getDeviceID() unless $device_id > 0;
  unless ($device_id) {
    $self->{logger}->error("Unable to update DataCollectionStatus for dn=" . $self->{dn} ." field=${field} status='${status}' since DeviceID is not provided");
    return;
  }

  unless (defined $field) {
    $self->{logger}->error("Unable to update DataCollectionStatus: field not defined");
    return;
  }

  unless (defined $status) {
    $self->{logger}->error("Unable to update DataCollectionStatus: status not defined");
    return;
  }

  if ($status ne 'OK' && $status ne 'Error' && $status ne 'N/A' && $status ne "NULL" ) {
    $self->{logger}->error("Unable to update DataCollectionStatus: Status '${status}' not defined or not equal to OK, Error, or N/A");
    return;
  }

  ## "NULL" should only be allowed by unit tests to change things around easily.
  $status = '' if ( $status eq "NULL" );

  my $sql = $self->{sql};
  my $table = $self->{netmri_db} . '.DataCollectionStatus';
  # insert DeviceID entry if one does not already exist.  Then update
  # the table status and timestamp
  $sql->setDelimiter(";");

  my $sqlCmd = "insert ignore into ${table} (DeviceID) values ('${device_id}');
    update ${table} set ${field}Timestamp = now(),
    ${field}Ind = if(${field}Ind = 'N/A', ${field}Ind, '$status')
    where DeviceID = '$device_id'";

  $sql->execute($sqlCmd);

  # make sure there is a status in SDNCollectionStatus of DiscoveryStatus
  # table.  If there is one then if it is an Error and the current table
  # has a status of OK, DO NOT OVERWRITE THE ERROR so the user can see
  # what table failed most recently.
  my %rec = $sql->record("select  
      SystemInd,
      CPUInd,
      MemoryInd,
      VlansInd,
      ForwardingInd,
      EnvironmentalInd,
      InventoryInd,
      ARPInd,
      RouteInd,
      VrfInd,
      AccessInd,
      DeviceLicensedInd,
      SAMLicensedInd
    from ${table} s left outer join " . $self->{report_db} . ".DeviceSetting dc using (DeviceID)
    where s.DeviceID = '${device_id}'", 
    AllowNoRows => 1
  );

  my $outcome = "";

  if ( $rec{DeviceLicensedInd} ne "1" ) {
    if ( $rec{SystemInd} eq "OK" || $rec{SystemInd} eq "N/A" || $rec{SystemInd} eq "" ) {
      $outcome = "OK";
    }
    elsif ( $rec{SystemInd} eq "Error" ) {
      $outcome = "Error";
    }
  } else {
    # collect all applicable indicators for device
    my @checkInds = ();
    my $devType = $sql->single_value("select Type from " . $self->{netmri_db} . ".Device where DeviceID = '${device_id}'", AllowNoRows => 1) || '';
    @checkInds = qw/SystemInd VlansInd ForwardingInd InventoryInd ARPInd RouteInd VrfInd/;
    push @checkInds, qw/CPUInd MemoryInd EnvironmentalInd/ if NetMRI::Isl::isl('Collection_Device_Statistic');
    # check the overall SDN status based on those indicators
    $outcome = $self->_checkOutcome(\%rec, @checkInds);
  }

  $sqlCmd = "update " . $self->{netmri_db} . ".DiscoveryStatus ds, ${table} scs
      set ds.SDNCollectionStatus = if('$outcome' = '', 'Running', '$outcome'),
      ds.SDNCollectionTimestamp = scs.${field}Timestamp,
      ds.SDNCollectionMessage = if(scs.${field}Ind = 'Error', 'SDN Collection: Failed to collect data / Table: ${field}',
      if('$outcome' = 'OK', 'SDN Collection: Successfully collected data / Table: ${field}', if('$outcome' = '', 'SDN Collection: Attempting to collect data / Table: ${field} (Successful)', ds.SDNCollectionMessage)))
        where ds.DeviceID = scs.DeviceID
        and ds.DeviceID = '${device_id}'";

    $sql->execute($sqlCmd);

    # no matter what the status is keep LastAction and LastTimestamp up-to-date
    # with which SDN table was processed.
    $sql->execute("
            update " . $self->{netmri_db} . ".DiscoveryStatus ds,
            ${table} scs
            set ds.LastTimestamp = scs.${field}Timestamp,
            ds.LastAction = ds.SDNCollectionMessage
            where ds.DeviceID = scs.DeviceID
            and ds.DeviceID = '${device_id}'
    ");
}

sub _checkOutcome {
  my $self = shift;
  my $rec = shift;
  my $ok = -1;

  foreach (@_) {
    if ( $rec->{$_} eq 'Error' ) {
      return 'Error';
    } elsif ( $rec->{$_} eq 'OK'  ||
              $rec->{$_} eq 'N/A' ||
              $rec->{$_} eq '' ) {
      $ok++;
    }
  }

  return ($#_ == $ok) ? 'OK' : '' ;
}

sub _getConstructorCommand {
  my $self = shift;
  return '$self->{api_helper} = ' . $self->{api_helper_class} . '->new('
    . join(", ", map { my $val = $self->{api_helper_constructor_params}->{$_}; $val=~s/\'/\\\'/g; "'$_'" .' => ' . "'$val'"; } keys %{$self->{api_helper_constructor_params}} )
    . ');';
}

sub _initLwpLocalAddr {
  my $self = shift;
  my $sql = $self->{sql};
  my $query = "select si.if_dev, si.name, si.ipv4_address, si.ipv6_address from " . $self->{config_db} . ".scan_interfaces si where ";
  if ($self->{network_interface}) {
    $query .= "si.if_dev = ". $sql->escape($self->{network_interface});
  } elsif ($self->{virtual_network_id}) {
    $query .= "si.virtual_network_id = ". $sql->escape($self->{virtual_network_id});
  } else {
    my $controller_settings = $sql->record(
      "select virtual_network_id, scan_interface_id from " . $self->{config_db} . ".sdn_controller_settings where id=" . $sql->escape($self->{fabric_id}),
      AllowNoRows => 1,
      AllowDuplicateRows => 1,
      RefWanted => 1);
    $query .= $controller_settings->{scan_interface_id} ?
      "si.id=" . $sql->escape($controller_settings->{scan_interface_id})
      :
      "si.virtual_network_id=". $sql->escape($controller_settings->{virtual_network_id});
  }

  my $conf = $sql->record($query, AllowNoRows => 1, AllowDuplicateRows => 1, RefWanted => 1);
  my $local_addr = $conf->{ipv4_address} || $conf->{ipv6_address};
  if (ref($conf) && $local_addr) {
    @LWP::Protocol::http::EXTRA_SOCK_OPTS = (
      @LWP::Protocol::http::EXTRA_SOCK_OPTS,
      LocalAddr => $local_addr
    );
    $self->{local_interface_conf} = "LocalAddr ${local_addr} interface $conf->{if_dev} [$conf->{name}]";
    $self->{logger}->debug('Use ' . $self->{local_interface_conf});
  }
}

1;
