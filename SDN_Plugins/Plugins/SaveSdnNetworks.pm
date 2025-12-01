package NetMRI::SDN::Plugins::SaveSdnNetworks;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.SdnNetwork';
}

# sdn_network_id is a primary key
# it was removed from list to prevent unnecessary increments
sub target_table_fields {
  return [qw(
      sdn_network_key
      sdn_network_name
      fabric_id
      StartTime
      EndTime
      )];
}

sub required_fields {
  return {
    sdn_network_key         => '',
    sdn_network_name        => '',
    fabric_id               => '^\d+$',
    StartTime               => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime                 => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
  };
}

1;
