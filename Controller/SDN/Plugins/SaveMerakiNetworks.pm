package NetMRI::SDN::Plugins::SaveMerakiNetworks;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseDeleteObsolete);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.MerakiNetwork';
}

sub target_table_fields {
  return [qw(
      id
      name           
      organization_id
      fabric_id      
      StartTime
      EndTime
      )];
}

sub required_fields {
  return {
    id                 => '',
    name               => '',
    organization_id    => '^\d+$',
    fabric_id          => '^\d+$',
    StartTime          => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime            => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
  };
}

sub getFieldsGroup {
  return [qw(fabric_id organization_id)];
}

sub getUniqueFieldName {
  return 'name';
}

1;