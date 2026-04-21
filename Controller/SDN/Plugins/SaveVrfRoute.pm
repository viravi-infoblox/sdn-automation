package NetMRI::SDN::Plugins::SaveVrfRoute;

use strict;
use warnings;
use NetMRI::Util::Checksum;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.vrfRoute';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      Timestamp
      vrfName
      Destination
      Interface
      Mask
      Metric1
      Metric2
      NextHop
      Protocol
      Type
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vrfName       => '^.{0,64}$',
    Destination   => '^.{0,39}$',
    Interface     => '^.{0,32}$',
    Mask          => '^.{0,39}$',
    Metric1       => '^-?\d+$',
    Metric2       => '^-?\d+$',
    NextHop       => '^.{0,39}$',
    Protocol      => '^.{0,16}$',
    Type          => '^.{0,16}$'
  };
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{vrfName} = '' unless defined $record->{vrfName};
}

1;
