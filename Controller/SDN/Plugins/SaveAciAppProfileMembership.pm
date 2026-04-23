package NetMRI::SDN::Plugins::SaveAciAppProfileMembership;

use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.AciAppProfileMembership';
}

sub target_table_fields {
  return [qw(
    controller_id
    tenant_dn
    app_profile_dn
    epg_dn
  )];
}

sub required_fields {
  return {
    controller_id  => '^\d+$', # non-empty string - field value should match the regex
    tenant_dn      => '.+',
    app_profile_dn => '.+',
    epg_dn         => '.+',
  };
}

1;
