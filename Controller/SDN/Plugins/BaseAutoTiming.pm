package NetMRI::SDN::Plugins::BaseAutoTiming;

use strict;
use warnings;
use NetMRI::Util::Date;
use base qw(NetMRI::SDN::Plugins::Base);

sub get_device_redis_keys {
  my $self = shift;
  my $res  = $self->SUPER::get_device_redis_keys();
  $res = [] unless ref($res) eq 'ARRAY';
  push @$res, 'lastupdate';
  return $res;
}

sub get_affected_device_ids {
  my $self = shift;
  my $res = $self->SUPER::get_affected_device_ids(@_);
  my $current_device_id = $self->{parent}->getDeviceID();
  push @$res, $current_device_id if $current_device_id;
  return $res;
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);

  my $hash_key = defined($record->{DeviceID}) ? $record->{DeviceID} . "_lastupdate" : "table_timestamp";
  unless (defined $record->{StartTime}) {
    $self->{saved_state}->{$hash_key} = time() unless defined $self->{saved_state}->{$hash_key};
    $record->{StartTime} = NetMRI::Util::Date::formatDate($self->{saved_state}->{$hash_key});
  }
  #$self->{saved_state}->{$hash_key} = time() if defined($record->{DeviceID});
  $record->{EndTime} = NetMRI::Util::Date::formatDate(time()+1);
}

1;
