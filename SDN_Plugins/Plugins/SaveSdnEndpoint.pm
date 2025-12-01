package NetMRI::SDN::Plugins::SaveSdnEndpoint;

use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.SdnEndpoint';
}

#it's possible to use ifName instead of SdnInterfaceID
#in this case SdnInterfaceID will be populated automatically
sub target_table_fields {
  return [qw(
      DeviceID
      SdnInterfaceID
      Name
      MAC
      IP
      EPG
      Encap
      OS
      Vendor
      Description
      )];
}

sub required_fields {
  return {
    DeviceID       => '^\d+$',
    SdnInterfaceID => '^\d+$',
    Name           => '',
    MAC            => ''
  };
}

sub onBeforeValidate {
  my ($self, $data) = @_;
  $self->SUPER::onBeforeValidate($data);
  if (ref $self->{device_id_mappings}->{"DeviceID-SdnDeviceDN"}) {
    my @dev = map {my ($fabric_id, $dev_id) = split /\//, $_; {DeviceID => $dev_id}} keys %{$self->{device_id_mappings}->{"DeviceID-SdnDeviceDN"}};
    $self->build_mapping('DeviceID', 'SdnDeviceID', \@dev);
  }
  my @ifnames = map {{Name => $_->{ifName}};} grep {$_->{ifName}} @$data;
  $self->build_interface_mapping('Name', 'SdnInterfaceID', \@ifnames);
}

sub set_defaults {
  my ($self, $record) = @_;
  $self->SUPER::set_defaults($record);
  $record->{IP} = '' unless defined $record->{IP};
  if (defined $record->{ifName} && !defined $record->{SdnInterfaceID}) {
    my $sdn_device_id = $record->{SdnDeviceID}
      || $self->{device_id_mappings}->{"DeviceID-SdnDeviceID"}->{"$self->{parent}->{fabric_id}/$record->{DeviceID}"};
    if ($sdn_device_id) {
      $record->{SdnInterfaceID} =
        $self->{sdn_if_mappings}->{"Name-SdnInterfaceID"}->{$sdn_device_id}->{$record->{ifName}};
    }
  }
}

1;