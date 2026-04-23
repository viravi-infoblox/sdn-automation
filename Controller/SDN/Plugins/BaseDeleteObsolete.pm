package NetMRI::SDN::Plugins::BaseDeleteObsolete;

use strict;
use warnings;
use base qw(NetMRI::SDN::Plugins::BaseAutoTiming);

sub getFieldsGroup {
  return undef;
}

sub getUniqueFieldName {
  return undef;
}

sub onAfterSave {
  my ($self, $data) = @_;
  $self->deleteObsolete($data);
  $self->SUPER::onAfterSave($data);
}

sub deleteObsolete {
  my ($self, $data) = @_;
  my $unique_field_name = $self->getUniqueFieldName();
  return unless $unique_field_name;
  my $fields_group = $self->getFieldsGroup();
  return unless (ref($fields_group) eq 'ARRAY' && scalar(@$fields_group) > 0);

  my $cache = {};
  foreach my $record (@$data) {
    my $cache_key = $self->_getRecordConditionKey($fields_group, $record);
    push @{$cache->{$cache_key}}, $record->{$unique_field_name};
  }

  my $sql = $self->{parent}->{sql};
  foreach my $condition (keys %$cache) {
    my $query = 'delete from ' . $self->target_table() . " where "
      . "${condition} and ${unique_field_name} not in ("
      . join(", ", map {$sql->escape($_);} @{$cache->{$condition}})
      . ')';
    $sql->execute($query);
    $self->{parent}->{logger}->error(ref($self) . ': ' . $sql->errormsg()) if ($sql->errormsg());
  }
}

# we ensure that @$fields_group is not empty here
sub _getRecordConditionKey {
  my ($self, $fields_group, $record) = @_;
  my $conds = $self->_getRecordConditions($fields_group, $record) || [];
  return join ' AND ',  @$conds;
}

sub _getRecordConditions {
  my ($self, $fields_group, $record) = @_;
  my $res = [];

  foreach my $field (@$fields_group) {
    push @$res, $field . "=" . $self->{parent}->{sql}->escape($record->{$field} || '');
  }
  return $res;
}

1;