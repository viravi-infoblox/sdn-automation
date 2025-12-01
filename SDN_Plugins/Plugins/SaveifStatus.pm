package NetMRI::SDN::Plugins::SaveifStatus;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTimestamp);

use constant ADMIN_STATUS => {
    'up' => 'up',
    'down' => 'down',
    'if-state-unknown' => 'down',
    'if-state-up' => 'up',
    'if-state-down' => 'down',
    'if-state-test' => 'up',
};
use constant OPER_STATUS => {
    'up' => 'up',
    'down' => 'down',
    'if-oper-state-invalid' => 'down',
    'if-oper-state-ready' => 'up',
    'if-oper-state-no-pass' => 'down',
    'if-oper-state-test' => 'up',
    'if-oper-state-unknown' => 'down',
    'if-oper-state-dormant' => 'down',
    'if-oper-state-not-present' => 'down',
    'if-oper-state-lower-layer-down' => 'lowerlayerdown',
};

sub primary_key {
    return undef;
}

sub target_table {
    my $self = shift;
    return $self->{parent}->{netmri_db} . '.ifStatus';
}

sub target_table_fields {
    return [qw(
        DeviceID
        ifIndex
        Timestamp
        PerfStartTime
        Speed
        AdminStatus
        OperStatus
        LastChange
        LastChangeRaw
      )];
}

sub required_fields {
    return {
        DeviceID      => '^\d+$',
        ifIndex       => '^\d+$',
        Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
        PerfStartTime => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$'
    };
}

sub onBeforeRecordSave {
    my ($self, $record) = @_;
    $record->{AdminStatus} = ADMIN_STATUS->{lc($record->{AdminStatus})};
    $record->{OperStatus} = OPER_STATUS->{lc($record->{OperStatus})};
}

1;
