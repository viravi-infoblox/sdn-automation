package NetMRI::SDN::Plugins::SaveForwarding;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.dot1dTpFdbTable';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      vlan
      dot1dTpFdbAddress
      dot1dTpFdbPort
      dot1dTpFdbStatus
      dot1dTpFdbNeighborInterface
      )];
}

sub required_fields {
  return {
    DeviceID          => '^\d+$',
    StartTime         => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime           => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vlan              => '^\d+$',
    dot1dTpFdbAddress => '',
    dot1dTpFdbPort    => '^\d+$',
    dot1dTpFdbStatus  => ''
  };
}

1;
