package NetMRI::SDN::Plugins::SaveRoutingPerfObject;

use strict;
use warnings;
use NetMRI::Util::Date;
use base qw(NetMRI::SDN::Plugins::BaseCombined);

sub combine_plugins {
  return [qw(SaveDeviceProperty)];
}

sub combined_process_data {
  my ($self, $data, $fields) = @_;
  my $updated_data = [@$data];
  foreach my $record (@$updated_data) {
    $record->{Timestamp}     = NetMRI::Util::Date::formatTimestamp(time);
    $record->{PropertyIndex} = '';
    $record->{Source}        = 'SDN';
  }
  $self->SUPER::combined_process_data($updated_data, $fields);
}

sub required_fields {
  return {
    DeviceID     => '^\d+$',
    PropertyName => '',
    Value        => ''
  };
}

1;
