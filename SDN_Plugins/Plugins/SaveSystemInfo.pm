package NetMRI::SDN::Plugins::SaveSystemInfo;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return 'DeviceID';
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.Device';
}

sub update_method {
  return 'update';
}

sub target_table_fields {
  return [qw(
      DeviceID
      LastTimeStamp
      Name
      Vendor
      Model
      SWVersion
      UpTime
      IPAddress
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    LastTimeStamp => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    Name          => '',
    Vendor        => '',
    Model         => ''
  };
}

1;
