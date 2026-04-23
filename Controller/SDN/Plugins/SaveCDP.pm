package NetMRI::SDN::Plugins::SaveCDP;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.cdpCacheTable';
}

sub update_method {
  return 'replace';
}

sub primary_key {
  return undef;
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      cdpCacheIfIndex
      cdpCacheDeviceIndex
      cdpCacheAddressType
      cdpCacheAddress
      cdpCacheVersion
      cdpCacheDeviceId
      cdpCacheDevicePort
      cdpCachePlatform
      cdpCacheCapabilities
      cdpCacheVTPMgmtDomain
      cdpCacheNativeVLAN
      cdpCacheDuplex
      cdpCacheApplianceID
      cdpCacheVlanID
      cdpCachePowerConsumption
      cdpCacheMTU
      cdpCacheSysName
      cdpCacheSysObjectID
      cdpCachePrimaryMgmtAddrType
      cdpCachePrimaryMgmtAddr
      cdpCacheSecondaryMgmtAddrType
      cdpCacheSecondaryMgmtAddr
      cdpCachePhysLocation
      cdpCacheLastChange
      )];
}

sub required_fields {
  return {
    DeviceID                      => '^\d+$',
    StartTime                     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime                       => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    cdpCacheIfIndex               => '^\d+$',
    cdpCacheDeviceIndex           => '^\d+$',
    cdpCacheAddressType           => '',
    cdpCacheAddress               => '',
    cdpCacheVersion               => '',
    cdpCacheDeviceId              => '',
    cdpCacheDevicePort            => '',
    cdpCachePlatform              => '',
    cdpCacheCapabilities          => '^\d+$',
    cdpCacheVTPMgmtDomain         => '',
    cdpCacheNativeVLAN            => '^\d+$',
    cdpCacheDuplex                => '',
    cdpCacheApplianceID           => '^\d+$',
    cdpCacheVlanID                => '^\d+$',
    cdpCachePowerConsumption      => '^\d+$',
    cdpCacheMTU                   => '^\d+$',
    cdpCacheSysName               => '',
    cdpCacheSysObjectID           => '',
    cdpCachePrimaryMgmtAddrType   => '',
    cdpCachePrimaryMgmtAddr       => '',
    cdpCacheSecondaryMgmtAddrType => '',
    cdpCacheSecondaryMgmtAddr     => '',
    cdpCachePhysLocation          => '',
    cdpCacheLastChange            => '^\d+$'
  };
}

sub onBeforeValidate {
  my ($self, $data) = @_;
  $self->SUPER::onBeforeValidate($data);
  if (ref $self->{device_id_mappings}->{"DeviceID-SdnDeviceDN"}) {
    my @dev = map {my ($fabric_id, $dev_id) = split /\//, $_; {DeviceID => $dev_id}} keys %{$self->{device_id_mappings}->{"DeviceID-SdnDeviceDN"}};
    $self->build_mapping('DeviceID', 'SdnDeviceID', \@dev);
  }
  $self->build_interface_mapping('Name', 'SdnInterfaceID', $data);
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  for my $key (
    qw(cdpCacheDeviceIndex
    cdpCacheCapabilities
    cdpCacheNativeVLAN
    cdpCacheApplianceID
    cdpCacheVlanID
    cdpCachePowerConsumption
    cdpCacheMTU
    cdpCacheLastChange)
    ) {
    $record->{$key} = 0 unless defined $record->{$key};
  }
  for my $key (qw(
    cdpCacheVersion
    cdpCachePlatform
    cdpCacheVTPMgmtDomain
    cdpCacheDuplex
    cdpCacheSysName
    cdpCacheSysObjectID
    cdpCacheSecondaryMgmtAddr
    cdpCachePhysLocation)
    ) {
    $record->{$key} = '' unless defined $record->{$key};
  }
  for my $key (
    qw(cdpCacheAddressType
    cdpCachePrimaryMgmtAddrType
    cdpCacheSecondaryMgmtAddrType)
    ) {
    $record->{$key} = 'ip' unless defined $record->{$key};
  }
  #auto-fill cdpCacheIfIndex by Name using SdnFabricInterface mapping
  if (defined $record->{Name} && !defined $record->{cdpCacheIfIndex}) {
    my $sdn_device_id = $record->{SdnDeviceID}
      || $self->{device_id_mappings}->{"DeviceID-SdnDeviceID"}->{"$self->{parent}->{fabric_id}/$record->{DeviceID}"};
    if ($sdn_device_id) {
      $record->{cdpCacheIfIndex} =
        $self->{sdn_if_mappings}->{"Name-SdnInterfaceID"}->{$sdn_device_id}->{$record->{Name}};
    }
  }
}

1;
