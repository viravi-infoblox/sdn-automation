package NetMRI::SDN::Plugins::SaveDevices;

use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return 'SdnDeviceDN';
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.SdnFabricDevice';
}

sub target_table_fields {
  return [qw(
    SdnDeviceID
    SdnControllerId
    SdnDeviceDN
    IPAddress
    SdnDeviceMac
    DeviceStatus
    Name
    NodeRole
    Vendor
    Model
    SWVersion
    Serial
    modTS
    UpTime
  )];
}

sub required_fields {
  return {
    SdnControllerId => '^\d+$', # non-empty string - field value should match the regex
    SdnDeviceDN     => '',      # empty string  -> field value should be non-empty
    IPAddress       => '',
    NodeRole        => ''
  };
}

sub onBeforeSave {
  my ($self, $data) = @_;
  my $unique_field_name = $self->{parent}->{SaveDevices_unique_fieldname} || $self->primary_key();
  return if $unique_field_name eq $self->primary_key();
  my $cache = {};
  my $fields_cache = {};
  for (my $i=0; $i < scalar(@$data); $i++) {
    my $record = $data->[$i];
    push @{$cache->{$record->{SdnControllerId}}}, $record->{$unique_field_name};
    $fields_cache->{$record->{SdnControllerId} . '-' . $record->{$unique_field_name}} = $i;
  }
  my $sql = $self->{parent}->{sql};
  foreach my $sdn_controller_id (keys %$cache) {
    my $query = "select  SdnDeviceID, SdnControllerId, ${unique_field_name} from " 
      . $self->target_table() . ' where SdnControllerId='
      . $sql->escape($sdn_controller_id) . " and ${unique_field_name} in ("
      . join(", ", map {$sql->escape($_)} @{$cache->{$sdn_controller_id}})
      .')';
    $sql->table($query,
      Callback => sub {
        my $record = shift;
        my $index = $fields_cache->{$record->{SdnControllerId} . '-' . $record->{$unique_field_name}};
        if (defined $index) {
          $data->[$index]->{SdnDeviceID} = $record->{SdnDeviceID};
        }
      },
      AllowNoRows => 1
    );
    $self->{parent}->{logger}->error(ref($self) . ': ' . $sql->errormsg()) if ($sql->errormsg());
  }
}

sub onAfterSave {
  my ($self, $data) = @_;
  return if $self->{parent}->{SaveDevices_keep_nonexistent};

  my $unique_field_name = $self->{parent}->{SaveDevices_unique_fieldname} || $self->primary_key();
  my $sql = $self->{parent}->{sql};
  my $cache = {};
  foreach my $record (@$data) {
    push @{$cache->{$record->{SdnControllerId}}}, $record->{$unique_field_name};
  }
  foreach my $sdn_controller_id (keys %$cache) {
    my $query = 'delete from ' . $self->target_table() . ' where SdnControllerId='
      . $sql->escape($sdn_controller_id) . " and ${unique_field_name} not in ("
      . join(", ", map {$sql->escape($_);} @{$cache->{$sdn_controller_id}})
      .')';
    $sql->execute($query);
    $self->{parent}->{logger}->error(ref($self) . ': ' . $sql->errormsg()) if ($sql->errormsg());
  }
}

1;
