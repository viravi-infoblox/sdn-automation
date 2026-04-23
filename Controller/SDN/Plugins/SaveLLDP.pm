package NetMRI::SDN::Plugins::SaveLLDP;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.ifLLDPNeighbor';
}

sub update_method {
  return 'replace';
}

sub primary_key {
  return undef;
}

sub target_table_fields {
  return [qw(
      DeviceID
      Timestamp
      RemLocalPortNum
      RemIndex
      LocalPortId
      LocalPortIdSubtype
      RemLocalPortDescr
      RemChassisIdSubtype
      RemChassisID
      RemPortIdSubtype
      RemPortID
      RemPortDesc
      RemSysName
      RemSysDesc
      RemSysCapSupported
      RemSysCapEnabled
      RemManPrimaryAddr
      RemManSecondaryAddr
      lldpXMedRemSoftwareRev
      )];
}

sub required_fields {
  return {
    DeviceID        => '^\d+$',
    Timestamp       => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    RemLocalPortNum => '^\d+$',
    RemIndex        => '^\d+$'
  };
}

sub onBeforeValidate {
  my ($self, $data) = @_;
  $self->SUPER::onBeforeValidate($data);
  $self->{CurrentRemIndex}        = 0;
  $self->{CurrentRemLocalPortNum} = 0;
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{RemIndex}        = ++$self->{CurrentRemIndex}        unless defined $record->{RemIndex};
  $record->{RemLocalPortNum} = ++$self->{CurrentRemLocalPortNum} unless defined $record->{RemLocalPortNum};
}

1;
