package NetMRI::SDN::Plugins::SaveVrf;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.vrf';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      Name
      ArtificialInd
      DefaultInd
      Description
      DefaultRDType
      DefaultRDLeft
      DefaultRDRight
      DefaultVPNID
      RouteLimit
      WarningLimit
      CurrentCount
      Timestamp
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    Name          => '^.{0,64}$',
    Description   => '^.{0,255}$',
    ArtificialInd => '^\d+$',
    DefaultInd    => '^\d+$'
  };
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{ArtificialInd} = 0 unless defined $record->{ArtificialInd};
  $record->{DefaultInd}    = 0 unless defined $record->{DefaultInd};
  $record->{Name}          = '' unless defined $record->{Name};
}

1;
