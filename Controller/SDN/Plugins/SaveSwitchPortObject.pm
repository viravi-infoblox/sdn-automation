package NetMRI::SDN::Plugins::SaveSwitchPortObject;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseCombined);

sub combine_plugins {
  return [qw(SavevlanTrunkPortTable Savedot1dBasePortTable)];
}

1;
