package NetMRI::HTTP::Client::ACI::FabricElement;
use strict;
use warnings;

use NetMRI::HTTP::Client::ACI;

sub new {
    my $class = shift;
    my %options = @_;
    my $self = {};
    $self->{client} = $options{client};
    $self->{dn} = $options{dn};
    # This module doesn't use it, but it needed by NetMRI::SDN::ACI
    $self->{fabric_id} = $options{fabric_id};
    return bless $self, $class;
}

sub get_node_info {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}});
}

sub get_sys {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys'});
}

sub get_snmp {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/snmp/inst'});
}

sub get_environmental_temp {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/ch', 'query-target' => 'subtree', 'target-subtree-class' => 'eqptSensor', 'rsp-subtree-include' => 'stats', 'rsp-subtree-class' => 'eqptTemp5min'});
}

sub get_environmental_fan {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/ch', 'query-target' => 'subtree', 'target-subtree-class' => 'eqptFan'});
}

sub get_environmental_psu {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/ch', 'query-target' => 'subtree', 'target-subtree-class' => 'eqptPsu'});
}


sub get_fabric_link {
    my $self = shift;
    return $self->{client}->aci_request({class => 'fabricLink'});
}

1;
