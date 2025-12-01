package NetMRI::SDN::Plugins::SavePerformance;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseCombined);

sub combine_plugins {
  return [qw(SaveDeviceMemStats SaveDeviceCpuStats)];
}

1;

