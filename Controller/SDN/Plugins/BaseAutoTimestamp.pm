package NetMRI::SDN::Plugins::BaseAutoTimestamp;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub get_timestamp_fields {
  return ['Timestamp'];
}

1;
