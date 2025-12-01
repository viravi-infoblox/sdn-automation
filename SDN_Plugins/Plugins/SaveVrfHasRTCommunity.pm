package NetMRI::SDN::Plugins::SaveVrfHasRTCommunity;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.vrfHasRTCommunity';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      vrfName
      Direction
      Type
      LeftSide
      RightSide
      Timestamp
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vrfName       => '^.{0,64}$',
    Direction     => '^.{0,1}$',
    Type          => '^.{0,4}$',
    LeftSide      => '^\d+$',
    RightSide     => '^\d+$'
  };
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{vrfName} = '' unless defined $record->{vrfName};
}

1;
