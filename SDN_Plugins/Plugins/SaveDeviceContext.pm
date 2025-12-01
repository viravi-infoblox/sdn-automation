package NetMRI::SDN::Plugins::SaveDeviceContext;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.DeviceContext';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      ContextName
      IPAddress
      Timestamp
      )];
}

sub required_fields {
  return {
    DeviceID    => '^\d+$',
    Timestamp   => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    ContextName => ''
  };
}

sub onAfterSave {
  my ($self, $data) = @_;
  my %processed = ();
  my $netmri_db = $self->{parent}->{netmri_db};
  my $sql       = $self->{parent}->{sql};
  my $query     = "
    update ${netmri_db}.Device
      set ParentDeviceID = 0,
          LastTimestamp = now()
      where ParentDeviceID = ?;

      update ${netmri_db}.Device
      set ParentDeviceID = ?,
          LastTimestamp = now()
      where DeviceID != ? and IPAddress in (
        select IPAddress
        from ${netmri_db}.DeviceContext
        where DeviceID = ?
      );

      select Vendor, Type, TypeProbability, Model, SWVersion
      into \@Vendor, \@Type, \@TypeProbability, \@Model, \@SWVersion
      from ${netmri_db}.Device
      where DeviceID = ?;

      update ${netmri_db}.Device
      set Vendor = \@Vendor,
          Type = \@Type, 
          TypeProbability = \@TypeProbability,
          Model = \@Model,
          SWVersion = \@SWVersion
      where  ParentDeviceID = ?;

      insert into ${netmri_db}.DeviceProperty(Source,DeviceID,PropertyIndex, PropertyName,Value,Timestamp)
        select h.Source, d.DeviceId, h.PropertyIndex, h.PropertyName, h.Value, h.Timestamp
        from ${netmri_db}.Device d
        left join ${netmri_db}.DeviceProperty h on d.ParentDeviceID = h.DeviceID and h.PropertyName in ('sysVersion','sysModel','sysVendor')
        left join ${netmri_db}.DeviceProperty v on d.DeviceID = v.DeviceID and v.PropertyName = h.PropertyName
        where d.ParentDeviceID = ?
        on duplicate key update Source = h.Source, Value = h.Value, Timestamp = h.Timestamp;
  ";

  foreach my $record (@$data) {
    my $device_id = $record->{DeviceID};
    next if defined $processed{$device_id};
    $sql->executeBinded($query, [$device_id], [$device_id, $device_id, $device_id],
      [$device_id], [$device_id], [$device_id]);
    $processed{$device_id} = 1;
  }
}

1;
