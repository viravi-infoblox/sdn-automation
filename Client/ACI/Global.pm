package NetMRI::HTTP::Client::ACI::Global;
use strict;
use warnings;

use NetMRI::HTTP::Client::ACI;

sub new {
    my $class = shift;
    my %options = @_;
    my $self = {};
    $self->{client} =  $options{client};
    # This module doesn't use it, but it needed by NetMRI::SDN::ACI
    $self->{fabric_id} = $options{fabric_id};

    return bless $self, $class;
}

sub get_policy_objects {
    my $self = shift;
    return $self->{client}->aci_request({dn => 'uni', 'query-target' => 'subtree', 'target-subtree-class' => [qw(fvTenant fvAp fvAEPg fvBD fvCtx)]});
}

sub get_bd_to_vrf_relationship {
    my $self = shift;
    return $self->{client}->aci_request({class => 'fvRtCtx'});
}

sub get_epg_to_bd_relationship {
    my $self = shift;
    return $self->{client}->aci_request({class => 'fvRtBd'});
}

sub get_fabric_nodes {
    my $self = shift;
    return $self->{client}->aci_request({class => 'fabricNode'});
}

1;
