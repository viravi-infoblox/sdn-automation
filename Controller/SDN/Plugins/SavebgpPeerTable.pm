package NetMRI::SDN::Plugins::SavebgpPeerTable;

use strict;
use warnings;
use NetMRI::Util::Date;
use NetMRI::Util::Network;
use Scalar::Util qw(looks_like_number);
use base qw(NetMRI::SDN::Plugins::Base);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.bgpPeerTable';
}

# allow use records where only DeviceID field is defined
sub onRecordValidate {
  my ($self, $record, $errors_record) = @_;

  if (ref($record) eq 'HASH' && scalar(keys %$record) == 1 && looks_like_number($record->{DeviceID}) && int($record->{DeviceID}) > 0) {
    @$errors_record = ();
  }
}

sub get_device_redis_keys {
  return [qw(bgpPeerHash lastBgpTime)];
}

sub target_table_fields {
  return [qw(
      DeviceID
      StartTime
      EndTime
      bgpPeerState
      bgpPeerLocalAddr
      bgpPeerLocalPort
      bgpPeerRemoteAddr
      bgpPeerRemotePort
      bgpPeerRemoteAs
      bgpPeerFsmEstablishedTime
      bgpPeerEntryStatus
      )];
}

sub required_fields {
  return {
    DeviceID          => '^\d+$',
    bgpPeerRemoteAddr => '',
    bgpPeerRemotePort => '^\d+$',
    bgpPeerRemoteAs   => '^\d+$',
    bgpPeerLocalAddr  => '',
    bgpPeerLocalPort  => '^\d+$'
  };
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
    $self->{bgpConfigMap} = {};
    my $specific_device_data = $device_data->{$device_id};
    if (scalar(@$specific_device_data) > 0) {
      $self->insert_device_id_data($device_id, $specific_device_data, $fields);
    } else {
      $self->UpdateBgpMissingPeers($device_id);
    }
  }
}

sub insert_device_id_data {
  my ($self, $device_id, $data, $fields) = @_;
  my $pkg                   = ref($self);
  my $logger                = $self->{parent}->{logger};
  my $table                 = $self->target_table();
  my $sql                   = $self->{parent}->{sql};
  my $share                 = $self->{saved_state};
  my $device_hash_key       = "${device_id}_bgpPeerHash";
  my $last_bgptime_hash_key = "${device_id}_lastBgpTime";
  $share->{$device_hash_key} = {} unless (ref($share->{$device_hash_key}) eq 'HASH');
  my $bgpPeerHash = $share->{$device_hash_key};
  my $curPollTime = time();
  my $lastBgpTime = $share->{$last_bgptime_hash_key} || 0;

  my $curPollTimeStr = NetMRI::Util::Date::formatDate($curPollTime);
  my $prevPollStr    = NetMRI::Util::Date::formatDate($lastBgpTime);

  ##
  ## Build up SQL statements for updating HsrpTable.
  ##
  my $tableSQL = "replace into $table (" . join(",", @{$self->target_table_fields()}) . ")";

  my $tableSQLDelim = " values ";
  my $updateDb      = 0;

  for (my $i = 0; $i < scalar(@$data); $i++) {
    my $record = $data->[$i];
    $record->{bgpPeerFsmEstablishedTime} //= 0;

    my $BgpPeerReset = 1;

    ## when this script is run for the first time, create BGP peer
    ## entries in the database in "initial" state. Ignore these entries
    ## during analysis run. Use it only to show the Peers in Device view.
    my $reason = "initial";

    ## converting from dotted to numeric
    my $bgpPeerAddr  = NetMRI::Util::Network::InetAddr($record->{bgpPeerRemoteAddr});
    my $currentId    = $bgpPeerAddr;
    my $bgpLocalAddr = NetMRI::Util::Network::InetAddr($record->{bgpPeerLocalAddr});

    $self->{bgpConfigMap}->{$currentId} = $i;

    if (exists $bgpPeerHash->{$currentId}) {

      $BgpPeerReset = 0;

      if ( $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTransitions} ne ""
        && $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTransitions} ne $record->{bgpPeerFsmEstablishedTransitions}) {
        $BgpPeerReset = 1;
      }

      ## Update the Endtime on the existing record. This is needed to
      ## show peers in Device view
      if (!$BgpPeerReset) {
        my $updateSQL .= "update " . $self->target_table() . "
            set EndTime = '$curPollTimeStr',
             bgpPeerFsmEstablishedTime = $record->{bgpPeerFsmEstablishedTime}
              where  DeviceID = $device_id
              and    bgpPeerRemoteAddr = $bgpPeerAddr
              and    EndTime = '$prevPollStr'
        ";
        $sql->execute($updateSQL);
        if ($sql->errormsg()) {
          $logger->error("${pkg}: ${updateSQL}");
          $logger->error("${pkg}: " . $sql->errormsg());
        }
      }

      $reason = "reset";
    } else {
      ## if lastBgpTime is not zero means, this is not the first run
      ## of this script. So, set reason to "created" to show this is
      ## newly created BGP neighbor
      if ($lastBgpTime) {
        $reason = "created";
      }

      ## create new hash entry
      $bgpPeerHash->{$currentId}->{bgpPeerRemoteAddr}                = $record->{bgpPeerRemoteAddr};
      $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTransitions} = $record->{bgpPeerFsmEstablishedTransitions};

      ## Initialize the 24-hour sliding window for peer changes
      my @counterTrend = ();
      for (my $x = 0; $x < 24; $x++) {
        $counterTrend[$x] = 0;
      }
      $bgpPeerHash->{$currentId}->{CounterTrend} = \@counterTrend;
    }

    ## Save off for issue processing
    if ($record->{bgpPeerFsmEstablishedTransitions} > $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTransitions}) {
      $record->{PeerChanged} =
        $record->{bgpPeerFsmEstablishedTransitions} - $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTransitions};
    } else {
      ## Counter reset or nothing changed
      $record->{PeerChanged} = 0;
    }

    $record->{bgpPeerEntryStatus} = $reason;

    ## update hash with new info
    $bgpPeerHash->{$currentId}->{bgpPeerState}                     = $record->{bgpPeerState};
    $bgpPeerHash->{$currentId}->{bgpPeerLocalAddr}                 = $record->{bgpPeerLocalAddr};
    $bgpPeerHash->{$currentId}->{bgpPeerLocalPort}                 = $record->{bgpPeerLocalPort};
    $bgpPeerHash->{$currentId}->{bgpPeerRemotePort}                = $record->{bgpPeerRemotePort};
    $bgpPeerHash->{$currentId}->{bgpPeerRemoteAs}                  = $record->{bgpPeerRemoteAs};
    $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTransitions} = $record->{bgpPeerFsmEstablishedTransitions};
    $bgpPeerHash->{$currentId}->{bgpPeerFsmEstablishedTime}        = $record->{bgpPeerFsmEstablishedTime};

    ## don't need to write this to db
    next if (!$BgpPeerReset);

    $updateDb = 1;
    $tableSQL .= $tableSQLDelim;

    $tableSQLDelim = "," if ($tableSQLDelim ne ",");

    my ($startTime);

    if ($lastBgpTime) {
      $startTime = $prevPollStr;
    } else {
      $startTime = $curPollTimeStr;
    }

    $tableSQL .= "( $device_id,
        '$startTime',
        '$curPollTimeStr',
        '$record->{bgpPeerState}',
        $bgpLocalAddr,
        $record->{bgpPeerLocalPort},
        $bgpPeerAddr,
        $record->{bgpPeerRemotePort},
        $record->{bgpPeerRemoteAs},
        $record->{bgpPeerFsmEstablishedTime},
        '$reason'
    )";

  }

  if ($updateDb) {
    $sql->execute($tableSQL);
    if ($sql->errormsg()) {
      $logger->error("${pkg}: ${tableSQL}");
      $logger->error("${pkg}: " . $sql->errormsg());
    }
  }
  $self->UpdateBgpMissingPeers($device_id, $curPollTime, $lastBgpTime);
  $share->{$last_bgptime_hash_key} = $curPollTime;
}

sub UpdateBgpMissingPeers {
  my ($self, $device_id, $curPollTime, $lastBgpTime) = @_;
  my $share                 = $self->{saved_state};
  my $device_hash_key       = "${device_id}_bgpPeerHash";
  my $last_bgptime_hash_key = "${device_id}_lastBgpTime";
  $share->{$device_hash_key} = {} unless (ref($share->{$device_hash_key}) eq 'HASH');
  my $bgpPeerHash = $share->{$device_hash_key};
  my $sql         = $self->{parent}->{sql};
  $curPollTime //= time();
  $lastBgpTime //= ($share->{$last_bgptime_hash_key} || 0);

  my $pkg    = ref($self);
  my $logger = $self->{parent}->{logger};
  $logger->debug("${pkg}: Updating DB with missing BgpPeers");

  ##
  ## update DB with missing (deleted) BGP peers on the device
  ##
  my $reason         = 'deleted';
  my $curPollTimeStr = NetMRI::Util::Date::formatDate($curPollTime);
  my $prevPollStr    = NetMRI::Util::Date::formatDate($lastBgpTime);
  my ($startTime);

  if ($lastBgpTime) {
    $startTime = $prevPollStr;
  } else {
    $startTime = $curPollTimeStr;
  }

  ##
  ## Build up SQL statements for updating HsrpTable.
  ##
  my $tableSQL = "replace into " . $self->target_table() . " (" . join(",", @{$self->target_table_fields()}) . ")";

  my $tableSQLDelim = " values ";
  my $update        = 0;

  foreach my $peerAddr (keys %$bgpPeerHash) {
    ## find out the ones missing from the device (not made it in this poll)
    if (!exists $self->{bgpConfigMap}->{$peerAddr}) {
      $tableSQL .= $tableSQLDelim;

      $tableSQLDelim = "," if ($tableSQLDelim ne ",");

      ## converting from dotted to numeric
      my $bgpPeerAddr =
        NetMRI::Util::Network::InetAddr($bgpPeerHash->{$peerAddr}->{bgpPeerRemoteAddr});
      my $bgpLocalAddr =
        NetMRI::Util::Network::InetAddr($bgpPeerHash->{$peerAddr}->{bgpPeerLocalAddr});

      $tableSQL .= "( $device_id,
          '$startTime',
          '$curPollTimeStr',
          '$bgpPeerHash->{$peerAddr}->{bgpPeerState}',
          $bgpLocalAddr,
          $bgpPeerHash->{$peerAddr}->{bgpPeerLocalPort},
          $bgpPeerAddr,
          $bgpPeerHash->{$peerAddr}->{bgpPeerRemotePort},
          $bgpPeerHash->{$peerAddr}->{bgpPeerRemoteAs},
          $bgpPeerHash->{$peerAddr}->{bgpPeerFsmEstablishedTime},
          '$reason'
      )";

      $update = 1;

      ## remove the hash entry
      delete $bgpPeerHash->{$peerAddr};
    }
  }

  if ($update) {
    $logger->debug("${pkg}: TABLE REPLACE = $tableSQL");
    $sql->execute($tableSQL);
    if ($sql->errormsg()) {
      $logger->error("${pkg}: $tableSQL");
      $logger->error("${pkg}: " . $sql->errormsg());
    }
  } else {
    $logger->debug("${pkg}: No missing BgpPeers found");
  }
}

1;
