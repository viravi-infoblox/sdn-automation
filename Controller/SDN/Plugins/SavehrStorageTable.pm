package NetMRI::SDN::Plugins::SavehrStorageTable;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub target_table {
    my $self = shift;
    return $self->{parent}->{netmri_db} . '.hrStorageTable';
}

sub update_method {
    return 'replace';
}

sub target_table_fields {
    return [qw(
        DeviceID
        StartTime
        EndTime
        hrStorageIndex
        hrStorageDescr
        hrStorageAllocationUnits
        hrStorageSize
        hrStorageUsed
        )];
}

sub required_fields {
    return {
        DeviceID                 => '^\d+$',
        StartTime                => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
        EndTime                  => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
        hrStorageIndex           => '^\d+$',
        hrStorageDescr           => '^$|^\S.{0,199}$',
        hrStorageAllocationUnits => '^\d+$',
        hrStorageSize            => '^\d+$',
        hrStorageUsed            => '^\d+$'
    };
}

1;
