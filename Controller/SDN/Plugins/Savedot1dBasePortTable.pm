package NetMRI::SDN::Plugins::Savedot1dBasePortTable;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.dot1dBasePortTable';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      dot1dBasePort
      dot1dBasePortIfIndex
      vlan
      dot1dStpPortState
      fastStartState
      dot1dStpPortDesignatedBridge
      dot1dStpPortDesignatedPort
      )];
}

sub required_fields {
  return {
    DeviceID             => '^\d+$',
    StartTime            => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime              => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    dot1dBasePort        => '^\d+$',
    dot1dBasePortIfIndex => '^\d+$',
    vlan                 => '^\d+$'
  };
}

1;
