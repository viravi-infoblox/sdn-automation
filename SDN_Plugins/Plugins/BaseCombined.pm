package NetMRI::SDN::Plugins::BaseCombined;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub load_state {} 
sub update_state {}
sub update_timing {}

sub combine_plugins {
  return [];
}

sub update_method {
  return 'combined';
}

sub combined_process_data {
  my ($self, $data, $fields) = @_;
  my $plugins = $self->combine_plugins();
  foreach my $plugin_name (@$plugins) {
    my $method = lcfirst($plugin_name);
    $self->{parent}->$method($data);
  }
}

sub required_fields {
  my $self    = shift;
  my $res     = {};
  my $plugins = $self->combine_plugins();
  unless (ref($plugins) eq 'ARRAY') {
    my $pkg = ref($self);
    $self->{parent}->{logger}->error(
      "${pkg}: combine_plugins() method should return reference to the ARRAY, " . ref($plugins) . " returned instead of it");
    return $res;
  }
  foreach my $plugin_name (@$plugins) {
    my $plugin          = $self->{parent}->getPlugin($plugin_name);
    my $required_fields = $plugin->required_fields();
    foreach my $field_name (keys %$required_fields) {
      $res->{$field_name} = $required_fields->{$field_name} unless defined $res->{$field_name};
    }
  }
  return $res;
}

1;
