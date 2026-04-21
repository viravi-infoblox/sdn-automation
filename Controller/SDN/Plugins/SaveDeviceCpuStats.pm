package NetMRI::SDN::Plugins::SaveDeviceCpuStats;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.DeviceCpuStats';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      CpuIndex
      CpuBusy
      )];
}

sub required_fields {
  return {
    DeviceID  => '^\d+$',
    StartTime => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime   => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    CpuIndex  => '^\d+$',
    CpuBusy   => '^\d+$'
  };
}
1;
