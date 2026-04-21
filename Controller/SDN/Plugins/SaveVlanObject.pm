package NetMRI::SDN::Plugins::SaveVlanObject;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.VlanTable';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      vtpVlanIndex
      VTPDomain
      dot1dStpDesignatedRoot
      vtpVlanState
      vtpVlanType
      vtpVlanName
      vtpVlanIfIndex
      dot1dBaseBridgeAddress
      dot1dBaseNumPorts
      dot1dStpProtocolSpecification
      dot1dStpPriority
      dot1dStpTopChanges
      dot1dStpRootCost
      dot1dStpRootPort
      dot1dStpMaxAge
      dot1dStpHelloTime
      dot1dStpHoldTime
      dot1dStpForwardDelay
      dot1dStpBridgeMaxAge
      dot1dStpBridgeHelloTime
      dot1dStpBridgeForwardDelay
      )];
}

sub required_fields {
  return {
    DeviceID     => '^\d+$',
    StartTime    => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime      => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vtpVlanIndex => '^\d+$'
  };
}

1;
