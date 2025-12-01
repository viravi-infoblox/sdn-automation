package NetMRI::SDN::Plugins::SaveDeviceProperty;

use strict;
use warnings;
use NetMRI::Util::Date;
use base qw(NetMRI::SDN::Plugins::Base);

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.DeviceProperty';
}

sub update_method {
  return 'replace';
}

sub target_table_fields {
  return [qw(
      DeviceID
      Timestamp
      PropertyName
      PropertyIndex
      Source
      Value
      SecureVersion
      )];
}

sub required_fields {
  return {
    DeviceID      => '^\d+$',
    Timestamp     => '^\d{4}\-\d{2}\-\d{2}( \d{2}\:\d{2}\:\d{2})?$',
    PropertyName  => '',
    PropertyIndex => undef,
    Source        => ''
  };
}

#
# methods that can be used by other modules
#
sub updateDevicePropertyValueIfChanged {
  my ($self, $search_fieldset, $search_fieldvalues, $value) = @_;
  my $res = undef;
  my $condition = $self->_make_field_value_pairs($search_fieldset, $search_fieldvalues, '', ' AND ');
  unless (defined($condition)) {
    my $pkg = ref($self);
    $self->{parent}->{logger}->error("${pkg}: updateDevicePropertyValueIfChanged, unable to update");
    return $res;
  }
  my $sql       = $self->{parent}->{sql};
  my $query     = 'select Value from ' . $self->target_table() . ' WHERE ' . $condition;
  my $old_value = $sql->single_value($query, AllowDuplicateRows => 1, AllowNoRows => 1);
  my $timestamp = NetMRI::Util::Date::formatTimestamp(time);
  if (defined($old_value)) {
    if ($old_value ne $value) {
      $self->updateDeviceProperty($search_fieldset, $search_fieldvalues, [qw(Value Timestamp)], [$value, $timestamp]);
      $res = $timestamp;
    }
  } else {
    #record does not exists, insert a new one
    my $data = {};
    for (my $i = 0; $i < scalar(@$search_fieldset); $i++) {
      $data->{$search_fieldset->[$i]} = $search_fieldvalues->[$i];
    }
    $data->{Value}     = $value;
    $data->{Timestamp} = $timestamp;
    $self->saveValidatedData($data);
    $res = $timestamp;
  }
  return $res;
}

sub updateDeviceProperty {
  my ($self, $search_fieldset, $search_fieldvalues, $fieldset, $fieldvalues) = @_;

  my $condition = $self->_make_field_value_pairs($search_fieldset, $search_fieldvalues, '', ' AND ');
  unless (defined($condition)) {
    my $pkg = ref($self);
    $self->{parent}->{logger}
      ->error("${pkg}: updateDeviceProperty, unable to update. search_fieldset/search_fieldvalues pair is wrong");
    return;
  }
  my $update = $self->_make_field_value_pairs($fieldset, $fieldvalues, 'SET ', ', ');
  unless (defined($update)) {
    my $pkg = ref($self);
    $self->{parent}->{logger}->error("${pkg}: updateDeviceProperty, unable to update. fieldset/fieldvalues pair is wrong");
    return;
  }
  my $query = 'update ' . $self->target_table() . ' ' . $update . ' WHERE ' . $condition;
  $self->{parent}->{sql}->execute($query);
}

sub _make_field_value_pairs {
  my ($self, $search_fieldset, $search_fieldvalues, $prefix, $separator) = @_;
  $prefix    //= '';
  $separator //= ' AND ';
  unless (ref($search_fieldset) eq 'ARRAY'
    && ref($search_fieldvalues) eq 'ARRAY'
    && scalar(@$search_fieldset) > 0
    && scalar(@$search_fieldset) == scalar(@$search_fieldvalues)) {
    my $pkg = ref($self);
    $self->{parent}->{logger}->error("${pkg}: _make_search_condition, invalid input parameters");
    return undef;
  }
  my $sql        = $self->{parent}->{sql};
  my $conditions = [];
  for (my $i = 0; $i < scalar(@$search_fieldset); $i++) {
    push @$conditions, $search_fieldset->[$i] . ' = ' . $sql->escape($search_fieldvalues->[$i]);
  }
  return $prefix . join($separator, @$conditions);
}

1;
