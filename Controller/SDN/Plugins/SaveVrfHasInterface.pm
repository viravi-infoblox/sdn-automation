package NetMRI::SDN::Plugins::SaveVrfHasInterface;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.vrfHasInterface';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      vrfName
      Interface
      Timestamp
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    vrfName       => '^.{0,64}$',
    Interface     => '^.{0,32}$'
  };
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{vrfName} = '' unless defined $record->{vrfName};
}

1;
