package NetMRI::SDN::Plugins::SaveIPAddress;

use strict;
use warnings;
use NetMRI::Util::Checksum;
use NetMRI::Util::Network;
use base qw(NetMRI::SDN::Plugins::Base);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.ifAddr';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      Timestamp
      IPAddress
      ifIndex
      NetMask
      IPAddressDotted
      SubnetIPNumeric
      AciBdID
      AciEpgID
      )];
}

sub required_fields {
  return {
    DeviceID  => '^\d+$',
    Timestamp => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    IPAddress => '^\d+$',
    ifIndex   => '^\d+$',
  };
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  unless (defined $record->{IPAddress}) {
    $record->{IPAddress} = NetMRI::Util::Network::InetAddr($record->{IPAddressDotted}) if defined $record->{IPAddressDotted};
  }
}

sub onAfterSave {
  my ($self, $data) = @_;
  my $devices_map = {};
  my $device_id;
  foreach my $record (@$data) {
    $device_id = $record->{DeviceID};
    $devices_map->{$device_id} = [] unless defined $devices_map->{$device_id};
    push @{$devices_map->{$device_id}},
      {ifIndex => $record->{ifIndex}, IPAddress => $record->{IPAddress}, NetMask => $record->{NetMask}};
  }

  my $dp = $self->{parent}->getPlugin('SaveDeviceProperty');
  foreach $device_id (keys %$devices_map) {
    my $checksum = NetMRI::Util::Checksum::checkSumIfAddr($devices_map->{$device_id});
    $dp->updateDevicePropertyValueIfChanged([qw(DeviceID PropertyName PropertyIndex Source)],
      [$device_id, 'ifAddrCheckSum', '', 'NetMRI'], $checksum);
  }
}

1;
