package NetMRI::SDN::Plugins::Base;

use strict;
use warnings;
use Carp;
use JSON;
use NetMRI::Util::Date;
use feature qw(switch);

sub new {
  my ($type, $parent) = @_;
  croak "The property \"parent\" is not defined" unless ref($parent);
  my $self = {parent => $parent, json_marker => 'json:'};
  $self->{redis_base_path} = "/SDNEngine/plugins";
  return bless $self, $type;
}

sub primary_key {
  return undef;
}

sub required_fields {
  return {};
}

sub target_table {
  return undef;
}

sub affected_tables {
  my $self = shift;
  my $res =  $self->target_table();
  return undef unless defined $res;
  $res =~ s/^.*?\.//;
  return [$res];
}

sub update_timing {
  my ($self, $data) = @_;
  my $tables = $self->affected_tables();
  if (ref($tables) eq 'ARRAY') {
    my $sql = $self->{parent}->{sql};
    my $end_time = time();
    my $cur_poll_time = $self->{curPollTime} || time();
    my $poll_duration = $end_time - $cur_poll_time;
    my $netmri_db = $self->{parent}->{netmri_db};
    my $device_ids = $self->get_affected_device_ids($data);
    foreach my $device_id (@$device_ids) {
      foreach my $table_name (@$tables) {
        my $cur_end_time = NetMRI::Util::Date::formatDate($end_time);
        my $cur_poll_duration = $poll_duration;        
        if ($table_name =~ /^(?:VlanTable|vlanTrunkPortTable)$/ && @$data[-1]->{EndTime}) {
          $cur_end_time = @$data[-1]->{EndTime};
          $cur_poll_duration = "GREATEST(UNIX_TIMESTAMP('$cur_end_time') - $cur_poll_time, 0)";
        }        
        $sql->executeBinded(
           "replace into ${netmri_db}.SNMPTableStatus (DeviceID, TableName, EndTime, PollDuration) values (?,?,?,?)",
           [$device_id, $table_name, $cur_end_time, $cur_poll_duration]
        );
      }
    }
  }
}

sub target_table_fields {
  return [];
}

# possible values are: insert, replace, update, combined
sub update_method {
  return 'insert';
}

sub data_contains_errors {
  my ($self, $data) = @_;
  return undef if ref($data) eq 'HASH'  && scalar(keys %$data) == 0;
  return undef if ref($data) eq 'ARRAY' && scalar(keys @$data) == 0;
  my $errors                = [];
  my $primary_key_fieldname = $self->primary_key();
  my $method                = $self->update_method();
  if ($method eq 'update' && length($primary_key_fieldname) == 0) {
    push @$errors, "For the 'update' method the primary key field name should be specified";
    return $errors;
  }

  my $required_fields = $self->required_fields();
  return undef if (ref($required_fields) eq 'HASH' && scalar(keys %$required_fields) == 0);

  my $new_data = (ref($data) eq 'HASH' ? [$data] : (ref($data) eq 'ARRAY' ? $data : undef));
  unless ($new_data) {
    push @$errors, "input data should be either array reference or hash reference";
    return $errors;
  }

  my $row_number = 0;
  $self->onBeforeValidate($new_data);
  $self->load_state($method, $new_data);
  foreach my $record (@$new_data) {
    $self->set_defaults($record);
    my $errors_record = [];
    foreach my $field_name (keys %$required_fields) {
      if (!exists($record->{$field_name})) {
        push @$errors_record, "Field ${field_name} does not exists";
      } elsif (defined($required_fields->{$field_name}) && !defined($record->{$field_name})){
        push @$errors_record, "Value of the field ${field_name} is undefined";
      } elsif (defined($required_fields->{$field_name}) && length($required_fields->{$field_name}) > 0 && $record->{$field_name} !~ /$required_fields->{$field_name}/) {
        push @$errors_record, "Value of the field ${field_name} does not match the regexp " . $required_fields->{$field_name};
      }
    }
    $self->onRecordValidate($record, $errors_record);
    if (scalar(@$errors_record)) {
      my $primary_key = $self->primary_key();
      push @$errors,
        (    $primary_key
          && $record->{$primary_key} ? "${primary_key}=" . $record->{$primary_key} . ': ' : "Record # ${row_number}: ")
        . join(', ', @$errors_record);
    }
    $row_number++;
  }
  return scalar(@$errors) ? $errors : undef;
}

sub run {
  my ($self, $data) = @_;
  $self->{curPollTime}    = $self->{parent}->{curPollTime} || time();
  $self->{curPollTimeStr} = NetMRI::Util::Date::formatDate($self->{curPollTime});
  my $logger = $self->{parent}->{logger};
  my $pkg    = ref($self);
  $logger->debug("${pkg} plugin started");
  my $errors;
  if ($errors = $self->data_contains_errors($data)) {
    $logger->error("${pkg}: Data Validation errors:");
    $logger->error($_) foreach @$errors;
  } else {
    $self->{parent}->{logger}->debug("${pkg} saveValidatedData started");
    $self->saveValidatedData($data);
    $self->{parent}->{logger}->debug("${pkg} saveValidatedData finished");
  }
  $self->{parent}->{logger}->debug("${pkg} plugin finished");
}

sub saveValidatedData {
  my ($self, $data) = @_;
  return if ref($data) eq 'HASH'  && scalar(keys %$data) == 0;
  return if ref($data) eq 'ARRAY' && scalar(keys @$data) == 0;
  my $logger = $self->{parent}->{logger};
  my $pkg    = ref($self);
  my $method = $self->update_method();
  my $fields = $self->target_table_fields();
  unless (scalar(@$fields)) {
    #if no fields returned by target_table_fields method, use list of required fields
    my $required_fields = $self->required_fields();
    my @f               = keys %$required_fields;
    $fields = \@f if scalar(@f);
    unless (scalar(@$fields)) {
      $logger->error("${pkg} - fields set of the target table is not defined");
      return;
    }
  }

  my $table = $self->target_table();
  unless ($method eq 'combined' || length($table) > 0 ) {
    $logger->error("${pkg} - target table name is not set");
    return;
  }

  my $new_data = (ref($data) eq 'HASH' ? [$data] : $data);
  $self->onBeforeSave($new_data);
  if ($method eq 'replace') {
    $self->replace_data($new_data, $fields);
  } elsif ($method eq 'update') {
    $self->update_data($new_data, $fields);
  } elsif ($method eq 'combined') {
    $self->combined_process_data($new_data, $fields);
  } else {
    $self->insert_data($new_data, $fields);
  }
  $self->onAfterSave($new_data);
  $self->update_state($method, $new_data);
  $self->update_timing($new_data);
}

sub get_affected_device_ids {
  my ($self, $data) = @_;
  my $device_ids = {};
  foreach my $record (@$data) {
    $device_ids->{$record->{DeviceID}}++ if defined($record->{DeviceID});
  }
  my @res =  keys %$device_ids;
  return wantarray ? @res : \@res;
}

sub get_redis_path {
  my $self = shift;
  return $self->{redis_base_path} . '/' . $self->target_table();
}

sub get_redis_keys {
  [qw(table_timestamp)];
}

sub get_device_redis_keys {
  return [];
}

sub load_state {
  my ($self, $method, $data) = @_;
  $self->{saved_state} = {};
  return if $method eq 'combined';
  my $keys = $self->get_redis_keys($data);

  #load device's specific data
  my $additional_keys = $self->get_device_redis_keys();
  foreach my $device_id (@{$self->get_affected_device_ids($data)}) {
    foreach my $key (@$additional_keys) {
      push @$keys, "${device_id}_${key}";
    }
  }
  $self->load_selected_state($keys);
}

sub load_selected_state {
  my ($self, $keys) = @_;
  return if scalar(@$keys) == 0;
  my @state = $self->{parent}->{redis}->hmget($self->get_redis_path(), @$keys);
  for (my $i=0; $i < scalar(@$keys); $i++) {
    my $val = $state[$i] || undef;
    $val = JSON::decode_json($val) if defined($val) && $val=~s/^\Q$self->{json_marker}\E//;
    $self->{saved_state}->{$keys->[$i]} = $val;
  }
}

sub update_state {
  my ($self, $method, $data) = @_;
  return if $method eq 'combined';
  foreach my $key (keys %{$self->{saved_state}}) {
    $self->{saved_state}->{$key} = time() if $key =~ /\_timestamp$/;
    my $val = $self->{saved_state}->{$key};
    $val //= '';
    $val = $self->{json_marker} . JSON::encode_json($val) if ref($val);
    $self->{parent}->{redis}->hmset($self->get_redis_path(), $key, $val);
  }
}

sub update_data {
  my ($self, $data, $fields) = @_;

  my $pkg                   = ref($self);
  my $logger                = $self->{parent}->{logger};
  my $table                 = $self->target_table();
  my $primary_key_fieldname = $self->primary_key();
  my $sql                   = $self->{parent}->{sql};
  my $query_prefix          = "update ${table} set ";
  my $query_suffix          = " where ${primary_key_fieldname} = ?";
  my $query;
  my $values_list = [];

  foreach my $orig_record (@$data) {
    my $record = { %$orig_record };
    $self->onBeforeRecordSave($record);
    my @actual_fields = grep {exists($record->{$_})} grep {$_ ne $primary_key_fieldname} @$fields;
    $query = $query_prefix . join(",", map {$_ . ' = ?'} @actual_fields) . $query_suffix;
    @$values_list = map {$record->{$_}} @actual_fields;
    push @$values_list, $record->{$primary_key_fieldname};
    $sql->executeBinded($query, $values_list);
    if ($sql->errormsg() ne "") {
      $logger->error("${pkg} error executing query ${query}: " . $sql->errormsg());
    } else {
      #callback
      $self->onAfterRecordSave($record);
    }
  }
}

sub combined_process_data {}

sub insert_data {
  my ($self, $data, $fields) = @_;
  $self->insert_or_replace_data('insert', $data, $fields);
}

sub replace_data {
  my ($self, $data, $fields) = @_;
  $self->insert_or_replace_data('replace', $data, $fields);
}

sub insert_or_replace_data {
  my ($self, $method, $data, $fields) = @_;

  $method = 'insert' unless $method eq 'replace';
  my $pkg          = ref($self);
  my $logger       = $self->{parent}->{logger};
  my $table        = $self->target_table();
  my $sql         = $self->{parent}->{sql};
  my $values_list = [];
  foreach my $orig_record (@$data) {
    my $record = { %$orig_record };
    $self->onBeforeRecordSave($record);
    my @existing_fields = grep {exists($record->{$_})} @$fields;
    my $field_list   = join(",", @existing_fields);
    my $cnt          = scalar(@existing_fields) - 1;
    my $placeholders = "?," x $cnt . "?";

    my $query = "${method} into $table (${field_list}) values(${placeholders})";
    if ($method eq 'insert') {
      my $update_list = join(",", map {$_ . '=VALUES(' . $_ . ')'} @existing_fields);
      $query .= " on duplicate key update ${update_list}";
    }
    @$values_list = map {$record->{$_}} @existing_fields;
    $sql->executeBinded($query, $values_list);
    if ($sql->errormsg() ne "") {
      $logger->error("${pkg} error executing query ${query}: " . $sql->errormsg());
    } else {
      #callback
      $self->onAfterRecordSave($record);
    }
  }
}

sub set_defaults {
  my ($self, $record) = @_;
  my $required_fields = $self->required_fields();
  if (exists($required_fields->{DeviceID}) && !defined($record->{DeviceID})) {
    if (defined $self->{parent}->{dn}) {
      $record->{DeviceID} = $self->{device_id_mappings}->{"SdnDeviceDN-DeviceID"}->{"$self->{parent}->{fabric_id}/$self->{parent}->{dn}"};
    } elsif (defined $record->{SdnDeviceID}) {
      $record->{DeviceID} = $self->{device_id_mappings}->{"SdnDeviceID-DeviceID"}->{"$self->{parent}->{fabric_id}/$record->{SdnDeviceID}"};
    } elsif (defined $record->{SdnDeviceDN}) {
      $record->{DeviceID} = $self->{device_id_mappings}->{"SdnDeviceDN-DeviceID"}->{"$self->{parent}->{fabric_id}/$record->{SdnDeviceDN}"};
    }
  }
  my $timestamp_fields = $self->get_timestamp_fields();
  if (defined($timestamp_fields) && ref($timestamp_fields) eq 'ARRAY' && scalar(@$timestamp_fields) > 0) {
    foreach my $timestamp_field (@$timestamp_fields) {
      $record->{$timestamp_field} = NetMRI::Util::Date::formatDate(time()) unless defined($record->{$timestamp_field});
    }
  }
}

sub onBeforeSave { }
sub onBeforeRecordSave { }
sub onAfterRecordSave {
  # $record is the hash reference to the field name => field value pairs that just inserted into db
  #  my ($self, $record) = @_;
}

sub onAfterSave { }
sub onRecordValidate { }

sub onBeforeValidate {
  my ($self, $data) = @_;
  $self->build_mapping('SdnDeviceID', 'DeviceID', $data);
  $self->build_mapping('SdnDeviceDN', 'DeviceID', ($self->{parent}->{dn} ? [{SdnDeviceDN => $self->{parent}->{dn}}, @{$data}] : $data));
}

sub build_mapping {
  my ($self, $src_key, $dest_key, $data) = @_;
  return unless scalar(@$data);
  my $cache = {};
  my $reverse_cache = {};
  foreach my $record (@$data) {
    # these keys will hang empty since later we add fabric id as prefix to every key
    $cache->{$record->{$src_key}} = undef if defined $record->{$src_key};
  }
  return unless scalar(keys %$cache);
  
  my $sql    = $self->{parent}->{sql};
  my $sdndev = $self->{parent}->getPlugin('SaveDevices');
  $sql->table(
    "select SdnControllerId, ${src_key}, ${dest_key} from "
      . $sdndev->target_table()
      . " where ${src_key} in ( "
      . join(", ", map {$sql->escape($_)} keys %$cache) . ")",
    Callback => sub {
      my $row = shift;
      # NIOS-73040 DeviceID may be undefined when device is collected recently
      # or its IP duplicates another device, skip such records
      return unless ($row->{$src_key} && $row->{$dest_key});
      $cache->{"$row->{SdnControllerId}/$row->{$src_key}"} = $row->{$dest_key};
      $reverse_cache->{"$row->{SdnControllerId}/$row->{$dest_key}"} = $row->{$src_key};
    },
    AllowNoRows => 1,
  );
  $self->{device_id_mappings}->{"${src_key}-${dest_key}"} = $cache;
  $self->{device_id_mappings}->{"${dest_key}-${src_key}"} = $reverse_cache;
}

sub build_interface_mapping {
  my ($self, $src_key, $dest_key, $data) = @_;
  return unless scalar(@$data);
  my $cache = {};
  my $reverse_cache = {};
  my $device_id_fieldname = "SdnDeviceID";
  foreach my $record (@$data) {
    if ($self->{parent}->{dn}) {
      $record->{DeviceID} = $self->{device_id_mappings}->{"SdnDeviceDN-DeviceID"}->{"$self->{parent}->{fabric_id}/$self->{parent}->{dn}"} unless $record->{DeviceID};
    }
    my $sdn_device_id = 
      $record->{$device_id_fieldname} ||
      $self->{device_id_mappings}->{"DeviceID-${device_id_fieldname}"}->{"$self->{parent}->{fabric_id}/$record->{DeviceID}"};
    next unless defined $sdn_device_id;
    $cache->{$sdn_device_id}->{$record->{$src_key}} = undef if defined $record->{$src_key};
  }
  return unless scalar(keys %$cache);

  my $sql    = $self->{parent}->{sql};
  my $plugin = $self->{parent}->getPlugin('SaveSdnFabricInterface');
  my $device_cond = join " or ", map {
    "(${device_id_fieldname}=" . $sql->escape($_)
    . " and ${src_key} in (" . join(", ", map {$sql->escape($_)} keys %{$cache->{$_}}) . "))"
  } keys %$cache;

  $sql->table(
    "select ${device_id_fieldname}, ${src_key}, ${dest_key} from "
      . $plugin->target_table()
      . " where ${device_cond}",
    Callback => sub {
      my $row = shift;
      $cache->{$row->{$device_id_fieldname}}->{$row->{$src_key}} = $row->{$dest_key};
      $reverse_cache->{$row->{$device_id_fieldname}}->{$row->{$dest_key}} = $row->{$src_key};
    },
    AllowNoRows => 1,
  );
  $self->{sdn_if_mappings}->{"${src_key}-${dest_key}"} = $cache;
  $self->{sdn_if_mappings}->{"${dest_key}-${src_key}"} = $reverse_cache;
}

sub get_timestamp_fields {}
1;
