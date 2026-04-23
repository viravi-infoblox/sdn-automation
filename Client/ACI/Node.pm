package NetMRI::HTTP::Client::ACI::Node;
use strict;
use warnings;

use NetMRI::HTTP::Client::ACI::FabricElement;
use base 'NetMRI::HTTP::Client::ACI::FabricElement';

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    return bless $self, $class;
}

sub get_firmware {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/fwstatuscont/running'});
}

sub get_inventory {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/ch', 'query-target' => 'subtree', 'target-subtree-class' => [qw(eqptCh eqptSupC eqptLC eqptFt eqptPsu)]});
}

sub get_inventoryFex {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, class => 'eqptExtCh'});
}

sub get_interfaces {
    my $self = shift;
    my $target = [qw(l1PhysIf ethpmPhysIf ethpmFcot ethpmPortCap sviIf l3LbRtdIf l3EncRtdIf mgmtMgmtIf tunnelIf pcAggrIf ethpmAggrIf)];
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => $target});
}

sub get_vxlans {
    my $self = shift;
    my $dn = shift;
    
    return $self->{client}->aci_request({dn => $dn, 'query-target' => 'children', 'target-subtree-class' => 'l2BD'});
}

sub get_interface_stats {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => 'l1PhysIf', 'rsp-subtree-include' => 'stats'});
}

sub get_route_ipv4_nexthop {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => 'uribv4Nexthop'});
}
sub get_route_interface_definition_relationship {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'ipRsRtDefIpAddr'});
}
sub get_route_subnet_definition_relationship {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'ipRsRouteToRouteDef'});
}

sub get_lldp_neighbors {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/lldp/inst', 'rsp-subtree' => 'full', 'rsp-subtree-class' => [qw(lldpIf lldpAdjEp)], 'rsp-subtree-include' => 'required'});
}

sub get_cdp_neighbors {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, class => 'cdpIf', 'rsp-subtree' => 'full'});
}

sub get_endpoint_epg_binding {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => [qw(vlanRsVlanEppAtt vxlanRsVxlanEppAtt)] });
}

sub get_endpoints {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'class' => "epmMacEp", 'rsp-subtree' => 'full'});
}

sub get_performance {
    my $self = shift;
    my ($cpu_stats, $message) = $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/procsys/HDprocSysCPU5min-0'});
    return (undef, $message) unless ($cpu_stats);
    (my $mem_stats, $message) = $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/procsys/HDprocSysMem5min-0'});
    return (undef, $message) unless ($mem_stats);
    return [@$cpu_stats, @$mem_stats];
}

sub get_vrf_deployed {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => [qw(l3Inst l3Ctx)]});
}

sub get_vrf_ctx {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => 'l3Ctx'});
}

sub get_vrf_configured {
    my $self = shift;
    return $self->{client}->aci_request({'class' => 'fvCtx'});
}

sub get_ip_addresses {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'subpath' => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'ipv4Addr'});
}

sub get_ip_address_attachment {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'subpath' => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'ipRsRtDefIpAddr'});
}

sub get_ip_interfaces {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'subpath' => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'ipv4If'});
}

sub get_vlan {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'subpath' => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'l2Dom'});
}

sub get_vlan_switchport_relations {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'subpath' => 'sys', 'query-target' => 'subtree', 'target-subtree-class' => 'l2Cons'});
}

sub get_static_paths {
    my $self = shift;
    return $self->{client}->aci_request({'class' => 'fvRsPathAtt'});
}

sub get_attachable_entity_profiles {
    my $self = shift;
    return $self->{client}->aci_request({'class' => 'infraRsFuncToEpg'});
}

sub get_attachable_entity_profile_paths {
    my $self = shift;
    my $profile = shift;
    $self->{dn} =~ m!/node-(\d+)$!o;
    my $node_id = $1;
    return $self->{client}->aci_request({dn => "uni/infra/attentp-$profile", 'rsp-subtree-include' => 'full-deployment', 'target-node' => $node_id, 'target-path' => 'AttEntityPToPthIf'});
}

1;
