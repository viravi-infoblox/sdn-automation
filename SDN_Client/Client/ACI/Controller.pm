package NetMRI::HTTP::Client::ACI::Controller;
use strict;
use warnings;

use NetMRI::HTTP::Client::ACI::FabricElement;
use base 'NetMRI::HTTP::Client::ACI::FabricElement';

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    return bless $self, $class;
}

sub get_inventory {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => [qw(eqptFan eqptPsu eqptSensor eqptCh)]});
}

sub get_interfaces {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, 'query-target' => 'subtree', 'target-subtree-class' => 'cnwPhysIf'});
}

sub get_performance {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/proc'});
}


sub get_firmware {
    my $self = shift;
    return $self->{client}->aci_request({dn => $self->{dn}, subpath => 'sys/ctrlrfwstatuscont/ctrlrrunning'});
}

1;
