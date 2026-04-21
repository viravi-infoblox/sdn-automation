package NetMRI::SDN::Plugins::SaveMerakiOrganizations;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseDeleteObsolete);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.MerakiOrganization';
}

sub target_table_fields {
  return [qw(
      id
      name           
      fabric_id      
      StartTime
      EndTime
      )];
}

sub required_fields {
  return {
    id                 => '^\d+$',
    name               => '',
    fabric_id          => '^\d+$',
    StartTime          => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime            => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
  };
}

sub getFieldsGroup {
  return [qw(fabric_id)];
}

sub getUniqueFieldName {
  return 'name';
}

1;
