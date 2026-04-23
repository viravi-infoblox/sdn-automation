package NetMRI::SDN::Plugins::SaveifPerf;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
    return undef;
}

sub target_table {
    my $self = shift;
    return $self->{parent}->{netmri_db} . '.ifPerf';
}

sub target_table_fields {
    return [qw(
        StartTime
        EndTime
        DeviceID
        ifIndex
        ifSpeed
        ifTotalChanges
        ifInOctets
        ifInUcastPkts
        ifInNUcastPkts
        ifInMulticastPkts
        ifInBroadcastPkts
        ifInDiscards
        ifInErrors
        ifOutOctets
        ifOutUcastPkts
        ifOutNUcastPkts
        ifOutMulticastPkts
        ifOutBroadcastPkts
        ifOutDiscards
        ifOutErrors
        ifAlignmentErrors
        ifFCSErrors
        ifLateCollisions
      )];
}

sub required_fields {
    return {
        StartTime     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
        EndTime       => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
        DeviceID      => '^\d+$',
        ifIndex       => '^\d+$'
    };
}

1;
