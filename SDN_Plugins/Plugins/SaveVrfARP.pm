package NetMRI::SDN::Plugins::SaveVrfARP;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.vrfARP';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      vrfName
      Protocol
      Address
      Age
      HardwareAddress
      Type
      Interface
      Timestamp
      )];
}

sub required_fields {
  return {
    DeviceID        => '^\d+$',
    Timestamp       => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vrfName         => '^.{0,64}$',
    Protocol        => '^.{0,16}$',
    Address         => '^.{0,39}$',
    Age             => '^\d+$',
    HardwareAddress => '^.{0,32}$',
    Type            => '^.{0,16}$',
    Interface       => '^.{0,32}$'
  };
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{Age}     = 0  unless defined $record->{Age};
  $record->{vrfName} = '' unless defined $record->{vrfName};
}

1;
