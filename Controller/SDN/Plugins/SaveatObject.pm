package NetMRI::SDN::Plugins::SaveatObject;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.atTable';
}

sub target_table_fields {
  return [qw(
      DeviceID
      RowID
      StartTime
      EndTime
      atIfIndex
      atPhysAddress
      atNetAddress
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    StartTime     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime       => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    RowID         => '^\d+$',
    atIfIndex     => '^\d+$',
    atPhysAddress => '^(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}',
    atNetAddress  => '^\d+$'
  };
}

sub onBeforeRecordSave {
  my ($self, $record) = @_;
  $record->{atPhysAddress} = lc($record->{atPhysAddress});
}

1;
