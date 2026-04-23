package NetMRI::SDN::Plugins::SaveEnvironmental;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.DeviceEnvMon';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      envIndex
      envType
      envDescr
      envState
      envStatus
      envMeasure
      envLowWarnVal
      envLowShutdown
      envHighWarnVal
      envHighShutdown
      )];
}

sub required_fields {
  return {
    DeviceID  => '^\d+$',
    StartTime => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime   => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    envIndex  => '',
    envType   => ''
  };
}

1;
