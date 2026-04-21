package NetMRI::SDN::Plugins::SavevlanTrunkPortTable;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.vlanTrunkPortTable';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      vlanTrunkPortIfIndex
      vlanTrunkPortManagementDomain
      vlanTrunkPortEncapsulationType
      vlanTrunkPortVlansEnabled
      vlanTrunkPortNativeVlan
      vlanTrunkPortRowStatus
      vlanTrunkPortInJoins
      vlanTrunkPortOutJoins
      vlanTrunkPortOldAdverts
      vlanTrunkPortVlansPruningEligible
      vlanTrunkPortVlansXmitJoined
      vlanTrunkPortVlansRcvJoined
      vlanTrunkPortDynamicState
      vlanTrunkPortDynamicStatus
      vlanTrunkPortVtpEnabled
      vlanTrunkPortEncapsulationOperType
      vlanTrunkPortVlansEnabled2k
      vlanTrunkPortVlansEnabled3k
      vlanTrunkPortVlansEnabled4k
      vtpVlansPruningEligible2k
      vtpVlansPruningEligible3k
      vtpVlansPruningEligible4k
      vlanTrunkPortVlansXmitJoined2k
      vlanTrunkPortVlansXmitJoined3k
      vlanTrunkPortVlansXmitJoined4k
      vlanTrunkPortVlansRcvJoined2k
      vlanTrunkPortVlansRcvJoined3k
      vlanTrunkPortVlansRcvJoined4k
      vlanTrunkPortDot1qTunnel
      )];
}

sub required_fields {
  return {
    DeviceID                   => '^\d+$',
    StartTime                  => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime                    => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vlanTrunkPortIfIndex       => '^\d+$',
    vlanTrunkPortNativeVlan    => '^\d+$',
    vlanTrunkPortDynamicState  => '',
    vlanTrunkPortDynamicStatus => ''
  };
}

1;
