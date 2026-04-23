package NetMRI::SDN::Plugins::SaveFirewall;

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use NetMRI::Util::Date;
use NetMRI::Util::Network;
use base qw(NetMRI::SDN::Plugins::Base);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.fwConnectionStatsTable';
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      currentInUse
      high
      fwIndex
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    fwIndex       => '',
    sessionActive => '^\d+$',
    sessionMax    => '^\d+$'
  };
}

sub get_device_redis_keys {
  return [qw(statistics)];
}

sub insert_data {
  my ($self, $data, $fields) = @_;
  my $device_records = [];
  my $device_data    = {};
  foreach my $record (@$data) {
    $device_data->{$record->{DeviceID}} = [] unless ref($device_data->{$record->{DeviceID}});
    unless (scalar(keys %$record) == 1 && defined $record->{DeviceID}) {
      push @{$device_data->{$record->{DeviceID}}}, $record;
    }
  }
  foreach my $device_id (keys %$device_data) {
    my $specific_device_data = $device_data->{$device_id};
    if (scalar(@$specific_device_data) > 0) {
      $self->insert_device_id_data($device_id, $specific_device_data, $fields);
    }
  }
}

sub insert_device_id_data {
  my ($self, $device_id, $data, $fields) = @_;
  my $pkg             = ref($self);
  my $logger          = $self->{parent}->{logger};
  my $table           = $self->target_table();
  my $sql             = $self->{parent}->{sql};
  my $state           = $self->{saved_state};
  my $device_hash_key = "${device_id}_statistics";
  $state->{$device_hash_key} = {} unless (ref($state->{$device_hash_key}) eq 'HASH');
  my $share                     = $state->{$device_hash_key};
  my $curTimestamp              = time();
  my $lastFwConnectionStatsTime = $share->{lastFwConnectionStatsTime} || time();
  my $dp_table                  = $self->{parent}->getPlugin('SaveDeviceProperty')->target_table();

  my $startTimeStr = NetMRI::Util::Date::formatDate($lastFwConnectionStatsTime);
  my $endTimeStr   = NetMRI::Util::Date::formatDate($curTimestamp);

  my $updateSQL = "";

  foreach my $record (@$data) {
    my $fwIndex = $record->{fwIndex};
    if (defined $record->{sessionActive} && $record->{sessionActive} ne "" && defined $record->{sessionMax} && $record->{sessionMax} ne "") {
      if (!defined $share->{md5_hex($fwIndex)} || ($share->{md5_hex($fwIndex)} ne $record->{sessionActive} . '|' . $record->{sessionMax})) {
        $updateSQL .= "
        replace into $table (" . join(",", @{$self->target_table_fields()}) . ")
         values
          ($device_id, '$startTimeStr', '$endTimeStr', '$record->{sessionActive}', "
          . (
          (!defined($record->{sessionHigh}) || $record->{sessionHigh} =~ /^n\/a/i)
          ? 'NULL'
          : "'$record->{sessionHigh}'"
          )
          . ",
          '$fwIndex');

        replace into $dp_table 
          (DeviceID, PropertyName, PropertyIndex,
                            Source, Value, Timestamp) values
          ($device_id, 'ConnectionCountMaximum', '$fwIndex', 
          'SDN', '$record->{sessionMax}', '$endTimeStr');
      ";
      } else {
        $updateSQL = "
        update $table
        set    EndTime = '$endTimeStr'
        where  DeviceID = $device_id and fwIndex='$fwIndex';"
      }

      $share->{md5_hex($fwIndex)} = $record->{sessionActive} . '|' . $record->{sessionMax};

    }
  }

  $sql->execute($updateSQL);
  if ($sql->errormsg()) {
    $logger->error("$pkg: $updateSQL");
    $logger->error("$pkg: " . $self->{Sql}->errormsg());
  }

  $share->{lastFwConnectionStatsTime} = $curTimestamp;

}

1;
