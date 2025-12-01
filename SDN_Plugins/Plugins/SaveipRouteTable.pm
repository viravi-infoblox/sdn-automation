package NetMRI::SDN::Plugins::SaveipRouteTable;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.ipRouteTable';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      RowID
      ipRouteDestStr
      ipRouteDestNum
      ipRouteIfIndex
      ifDescr
      ipRouteMaskStr
      ipRouteMaskNum
      ipRouteMetric1
      ipRouteMetric2
      ipRouteNextHopStr
      ipRouteNextHopNum
      ipRouteProto
      ipRouteType
      )];
}

sub required_fields {
  return {
    DeviceID          => '^\d+$',
    StartTime         => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    EndTime           => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    RowID             => '^\d+$',
    ipRouteDestStr    => '',
    ipRouteDestNum    => '^\d+$',
    ipRouteIfIndex    => '^\d+$',
    ifDescr           => '',
    ipRouteMaskStr    => '',
    ipRouteMaskNum    => '^\d+$',
    ipRouteMetric1    => '^-?\d+$',
    ipRouteMetric2    => '^-?\d+$',
    ipRouteNextHopStr => '',
    ipRouteNextHopNum => '^\d+$',
    ipRouteProto      => '',
    ipRouteType       => ''
  };
}

1;
