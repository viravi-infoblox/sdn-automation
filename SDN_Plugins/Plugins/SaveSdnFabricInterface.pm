package NetMRI::SDN::Plugins::SaveSdnFabricInterface;

use strict;
use warnings;
use NetMRI::Util::Date;
use NetMRI::Util::Network;
use base qw(NetMRI::SDN::Plugins::BaseDeleteObsolete);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.SdnFabricInterface';
}

sub affected_tables {
  my $self = shift;
  my $res  = $self->SUPER::affected_tables();
  return undef unless defined $res;
  $res = [$res] unless ref($res);
  push @$res, 'ifConfig', 'ifStatus';
  return $res;
}

sub target_table_fields {
  return [qw(
      SdnDeviceID
      Timestamp
      Name
      Descr
      Mtu
      MAC
      operMode
      adminStatus
      operStatus
      operStQual
      operSpeed
      sfpPresent
      Type
      Duplex
      )];
}

sub required_fields {
  return {
    SdnDeviceID => '^\d+$',
    Name        => '^\S.{0,199}$',
    Descr       => '(^$|^\S.{0,199}$)',
    Timestamp   => '\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$'
  };
}

sub getFieldsGroup {
  return [qw(SdnDeviceID)];
}

sub getUniqueFieldName {
  return 'Name';
}

sub set_defaults {
  my ($self, $record) = @_;
  unless ($record->{SdnDeviceID} && $record->{SdnDeviceID} =~ /^\d+$/) {
    my $hash_key = (defined($record->{SdnDeviceDN}) ? $record->{SdnDeviceDN} : (defined($self->{parent}->{dn}) ? $self->{parent}->{dn} : undef));
    $record->{SdnDeviceID} = 
      $self->{device_id_mappings}->{"SdnDeviceDN-SdnDeviceID"}->{"$self->{parent}->{fabric_id}/$hash_key"} if defined $hash_key;
  }
  $record->{Timestamp} = $self->{curPollTimeStr}
    unless (defined($record->{Timestamp}) && $record->{Timestamp} =~ /^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$/);
  $record->{Descr} = $record->{Name} if (defined($record->{Name}) && !defined($record->{Descr}));
}

sub onAfterSave {
  my ($self, $data) = @_;
  $self->SUPER::onAfterSave($data);
  my $pkg    = ref($self);
  my $logger = $self->{parent}->{logger};
  my $cache  = {};
  my $ip_addresses_cache = [];
  foreach my $record (@$data) {
    $cache->{$record->{SdnDeviceID}}++;
    push @$ip_addresses_cache, $record if (defined($record->{IPAddress}) || defined($record->{IPAddressDotted}));
  }
  my @sdn_device_ids = keys %$cache;
  unless (scalar @sdn_device_ids) {
    $logger->error("${pkg}: device_ids array is empty!");
    return;
  }
  my $sql       = $self->{parent}->{sql};
  my $netmri_db = $self->{parent}->{netmri_db};
  my $sdndev = $self->{parent}->getPlugin('SaveDevices');
  $sql->execute("
        replace into ${netmri_db}.ifConfig (
            DeviceID,
            ifIndex,
            Timestamp,
            Name,
            Descr,
            Type,
            Mtu,
            PhysAddress,
            ConnectorPresent,
            Duplex
        )
        select
            d.DeviceID,
            i.SdnInterfaceID,
            i.Timestamp,
            i.Name,
            i.Descr,
            i.Type,
            i.Mtu,
            i.MAC,
            i.sfpPresent,
            i.Duplex
        from " . $self->target_table() . " i
        join " . $sdndev->target_table() ." d on d.SdnDeviceID = i.SdnDeviceID
        where d.SdnDeviceID in (" . join(",", @sdn_device_ids) . ")");

  # cludge for NETMRI-32716 (NETMRISPT-5475)
  $sql->execute("
        delete i from
        ${netmri_db}.ifConfig i
        join " . $self->target_table() . " si on i.Name = si.Name and i.ifIndex != si.SdnInterfaceID
        join " . $sdndev->target_table() ." sd on sd.SdnDeviceID = si.SdnDeviceID and sd.DeviceID = i.DeviceID
        where sd.SdnDeviceID in (" . join(",", @sdn_device_ids) . ")");
  # NETMRI-35129: drop interfaces that disappeared
  $sql->execute ("
        delete i
        from ${netmri_db}.ifConfig i left join " . $sdndev->target_table() ." sd using(DeviceID)
        where sd.SdnDeviceID in (" . join(",", @sdn_device_ids) . ") and i.Timestamp < '$self->{curPollTimeStr}'");

  $sql->execute("
        replace into ${netmri_db}.ifStatus (
            DeviceID,
            ifIndex,
            Timestamp,
            AdminStatus,
            OperStatus,
            Speed,
            LastChange
        )
        select
            d.DeviceID,
            i.SdnInterfaceID,
            '$self->{curPollTimeStr}',
            i.adminStatus,
            i.operStatus,
            i.operSpeed,
            case
              when (ifs.AdminStatus, ifs.OperStatus) = (i.adminStatus, i.operStatus)
              then ifs.LastChange
              else i.Timestamp
            end
        from " . $self->target_table() . " i
        join " . $sdndev->target_table() . " d on d.SdnDeviceID = i.SdnDeviceID
        left join ${netmri_db}.ifStatus ifs on (ifs.DeviceID = d.DeviceID and ifs.ifIndex = i.SdnInterfaceID)
        where d.SdnDeviceID in (" . join(",", @sdn_device_ids) . ")");
  # NETMRI-35129: drop interfaces that disappeared
  $sql->execute ("
        delete i
        from ${netmri_db}.ifStatus i left join " . $sdndev->target_table() ." sd using(DeviceID)
        where sd.SdnDeviceID in (" . join(",", @sdn_device_ids) . ") and i.Timestamp < '$self->{curPollTimeStr}'");

  # handle ifAddr if such data exists
  return unless scalar(@$ip_addresses_cache);
  my $new_data = [];
  foreach my $record (@$ip_addresses_cache) {
    my $r = $sql->record("select i.SdnInterfaceID as ifIndex, i.Timestamp, d.DeviceID from " . $self->target_table() 
      ." i join " . $sdndev->target_table() ." d on d.SdnDeviceID = i.SdnDeviceID " 
      . " where i.SdnDeviceID=" . $record->{SdnDeviceID} . " and i.Name=" . $sql->escape($record->{Name}),
      AllowNoRows => 1,
      RefWanted => 1
      );
    next unless defined $r->{ifIndex};
    foreach my $field_name (qw(IPAddress NetMask IPAddressDotted SubnetIPNumeric AciBdID AciEpgID)) {
      $r->{$field_name} = $record->{$field_name} if defined $record->{$field_name};
    }
    push @$new_data, $r;
  }
  return unless scalar(@$new_data);
  $self->{parent}->saveIPAddress($new_data);
}

sub get_affected_device_ids {
  my ($self, $data) = @_;
  my $device_ids = {};
  foreach my $record (@$data) {
    $device_ids->{$record->{SdnDeviceID}}++ if defined($record->{SdnDeviceID});
  }
  my @keys = keys %$device_ids;
  my @res  = ();
  if (scalar @keys) {
    my $sql = $self->{parent}->{sql};
    my $sdndev = $self->{parent}->getPlugin('SaveDevices');
    $sql->table(
      "select distinct DeviceID from "
        . $sdndev->target_table()
        . " where SdnDeviceID in ("
        . join(",", @keys) . ")",
      Callback => sub {
        my $row = shift;
        push @res, $row->{DeviceID};
      },
      AllowNoRows => 1
    );
  }
  return wantarray ? @res : \@res;
}

sub onBeforeValidate {
  my ($self, $data) = @_;
  $self->build_mapping('SdnDeviceDN', 'SdnDeviceID', ($self->{parent}->{dn} ? [{SdnDeviceDN => $self->{parent}->{dn}}, @{$data}] : $data));
}

1;
