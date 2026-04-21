package NetMRI::SDN::Plugins::SaveifConfig;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

sub primary_key {
    return undef;
}

sub target_table {
    my $self = shift;
    return $self->{parent}->{netmri_db} . '.ifConfig';
}

sub target_table_fields {
    return [qw(
        DeviceID
        ifIndex
        Timestamp
        Name
        Descr
        Type
        Mtu
        PhysAddress
        LinkUpDownTrapEnable
        ConnectorPresent
        Duplex
        LowerLayer
        ifAlias
        ifDescrRaw
        ifAdminDuplex
      )];
}

sub required_fields {
    return {
        DeviceID      => '^\d+$',
        ifIndex       => '^\d+$',
        Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$'
    };
}

sub onBeforeRecordSave {
    my ($self, $record) = @_;
    $record->{PhysAddress} = uc($record->{PhysAddress});
}

1;
