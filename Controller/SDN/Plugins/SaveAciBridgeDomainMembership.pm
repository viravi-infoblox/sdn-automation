package NetMRI::SDN::Plugins::SaveAciBridgeDomainMembership;

use base qw(NetMRI::SDN::Plugins::Base);

sub primary_key {
  return undef;
}

sub target_table {
  my $self = shift;
  return $self->{parent}->{netmri_db} . '.AciBridgeDomainMembership';
}

sub target_table_fields {
  return [qw(
    controller_id
    tenant_dn
    bridge_domain_dn
    vrf_dn
    epg_dn
  )];
}

sub required_fields {
  return {
    controller_id    => '^\d+$', # non-empty string - field value should match the regex
    tenant_dn        => '.+',
    bridge_domain_dn => '.+',
    vrf_dn           => '.+',
    epg_dn           => '.*',
  };
}

1;
