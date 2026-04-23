package NetMRI::SDN::Plugins::SavebsnAPTable;

# Save Wireless APs. This data will flow to report.WirelessSubordinant table

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.bsnAPTable';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      bsnAPDot3MacAddress
      bsnAPNumOfSlots
      bsnAPName
      bsnAPLocation
      bsnAPMonitorOnlyMode
      bsnAPOperationStatus
      bsnAPSoftwareVersion
      bsnAPBootVersion
      bsnAPModel
      bsnAPSerialNumber
      bsnApIpAddress
      bsnAPType
      bsnAPGroupVlanName
      bsnAPAdminStatus
      bsnAPIOSVersion
      )];
}

sub required_fields {
  return {
    DeviceID             => '^\d+$',
    StartTime            => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime              => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    bsnAPDot3MacAddress  => '',
  };
}

1;
