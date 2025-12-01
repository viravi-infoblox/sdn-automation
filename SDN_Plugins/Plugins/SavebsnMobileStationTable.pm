package NetMRI::SDN::Plugins::SavebsnMobileStationTable;

# Save Wireless Neighbors. This data will flow to report.WirelessFwd table via WirelessForwarding2 consolidator

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseDeleteObsolete);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.bsnMobileStationTable';
}

sub update_method {
  return 'replace';
}

sub getFieldsGroup {
  return [qw(DeviceID)];
}

sub getUniqueFieldName {
  return 'bsnMobileStationMacAddress';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      bsnMobileStationMacAddress
      bsnMobileStationIpAddress
      bsnMobileStationUserName
      bsnMobileStationAPMacAddr
      bsnMobileStationSsid
      bsnMobileStationStatus
      bsnMobileStationVlanId
      )];
}

sub required_fields {
  return {
    DeviceID                    => '^\d+$',
    StartTime                   => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime                     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    bsnMobileStationVlanId      => '^\d+$',
    bsnMobileStationMacAddress  => '.+',
  };
}

1;
