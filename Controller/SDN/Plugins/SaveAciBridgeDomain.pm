package NetMRI::SDN::Plugins::SaveAciBridgeDomain;

use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.AciBridgeDomain';
}

sub target_table_fields {
  return [qw(
    controller_id
    dn
    name
    descr
    scope
    segment
  )];
}

sub required_fields {
  return {
    controller_id => '^\d+$', # non-empty string - field value should match the regex
    dn            => '.+',
    name          => '.+',
    descr         => '',
    scope         => '^\d+$',
    segment       => '^\d+$',
  };
}

1;
