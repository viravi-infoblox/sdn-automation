package NetMRI::SDN::Plugins::SaveInventory;

use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.EntPhysicalTable';
}

sub target_table_fields {
  return [qw(
    DeviceID
    StartTime
    EndTime
    entPhysicalIndex
    entPhysicalDescr
    entPhysicalVendorType
    entPhysicalContainedIn
    entPhysicalClass
    entPhysicalParentRelPos
    entPhysicalName
    entPhysicalHardwareRev
    entPhysicalFirmwareRev
    entPhysicalSoftwareRev
    entPhysicalSerialNum
    entPhysicalMfgName
    entPhysicalModelName
    entPhysicalAlias
    entPhysicalAssetID
    UnitState
  )];
}

sub required_fields {
  return {
    DeviceID          => '^\d+$', # non-empty string - field value should match the regex
    StartTime         => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime           => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    entPhysicalIndex  => '^\d+$'
  };
}

1;
