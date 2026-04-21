package NetMRI::SDN::ApiHelperFactory;

use strict;
use warnings;
use NetMRI::HTTP::Client::ACI::Controller;
use NetMRI::HTTP::Client::ACI::Node;
use NetMRI::HTTP::Client::ACI::Global;
use NetMRI::HTTP::Client::Meraki;
use NetMRI::HTTP::Client::Viptela;
use NetMRI::HTTP::Client::Mist;
use NetMRI::HTTP::Client::SilverPeak;
use NetMRI::HTTP::Client::VeloCloud;
use NetMRI::SDN::ACI;
use NetMRI::SDN::Meraki;
use NetMRI::SDN::Viptela;
use NetMRI::SDN::Mist;
use NetMRI::SDN::SilverPeak;
use NetMRI::SDN::VeloCloud;
use NetMRI::LoggerShare;
use NetMRI::Config;

# We cache session for every ACI fabric. Clients are not expected to have many fabrics (nor they're expected
# to constantly create and delete fabrics), so this cache shouldn't grow to unreasonable size
our %aci_session_cache;

sub get_device_helper {
    my %opts = @_;
    die "Sql connection was not provided" unless($opts{sql});
    my $sdn_type = _get_sdn_type($opts{sql}, $opts{fabric_id});
    my $user_agent_string = get_user_agent_string($opts{cfg});
    unless (defined($sdn_type)) {
        # We can get here if the fabric is deleted, but polling schedule hasn't been updated yet
        NetMRI::LoggerShare::logError("Fabric $opts{fabric_id} wasn't found. Has it been deleted recently?");
        return undef;
    }
    $sdn_type = uc($sdn_type);
    if ($sdn_type eq 'MERAKI') {
        my $org_id = '';
        if ($opts{dn}) {
            ($org_id, undef) = split /\//, $opts{dn}, 2;
        }
        $opts{api_helper} ||= get_meraki_helper($opts{sql}, $opts{fabric_id}, $org_id, $user_agent_string);
        return NetMRI::SDN::Meraki->new(%opts);
    }
    elsif ($sdn_type eq 'CISCO_APIC') {
        $opts{api_helper} ||= get_aci_helper($opts{sql}, $opts{fabric_id}, $opts{dn}, $user_agent_string);
        return NetMRI::SDN::ACI->new(%opts);
    }
    elsif ($sdn_type eq 'VIPTELA') {
        $opts{api_helper} ||= get_viptela_helper($opts{sql}, $opts{fabric_id}, $user_agent_string);
        return NetMRI::SDN::Viptela->new(%opts);
    }
    elsif ($sdn_type eq 'MIST') {
        $opts{api_helper} ||= get_mist_helper($opts{sql}, $opts{fabric_id}, $user_agent_string);
        $opts{api_helper_class} = "NetMRI::HTTP::Client::Mist";
        return NetMRI::SDN::Mist->new(%opts);
    }
    elsif ($sdn_type eq 'SILVERPEAK') {
        $opts{api_helper} ||= get_silverpeak_helper($opts{sql}, $opts{fabric_id}, $user_agent_string);
        return NetMRI::SDN::SilverPeak->new(%opts);
    }
    elsif ($sdn_type eq 'VELOCLOUD') {
        $opts{api_helper} ||= get_velocloud_helper($opts{sql}, $opts{fabric_id}, $user_agent_string);
        return NetMRI::SDN::VeloCloud->new(%opts);
    }
}

sub get_helper {
    my $sql = shift;
    my $fabric_id = shift;
    my $dn = shift;
    my $sdn_type = _get_sdn_type($sql, $fabric_id);
    my $user_agent_string = get_user_agent_string();
    $sdn_type = uc($sdn_type || '');
    if ($sdn_type eq 'MERAKI') {
        my $org_id = '';
        if ($dn) {
            ($org_id, undef) = split /\//, $dn, 2;
        }
        return get_meraki_helper($sql, $fabric_id, $org_id, $user_agent_string);
    }
    elsif ($sdn_type eq 'CISCO_APIC') {
        return get_aci_helper($sql, $fabric_id, $dn, $user_agent_string);
    }
    elsif ($sdn_type eq 'VIPTELA') {
        return get_viptela_helper($sql, $fabric_id, $user_agent_string);
    }
    elsif ($sdn_type eq 'MIST') {
        return get_mist_helper($sql, $fabric_id, $user_agent_string);
    }
    elsif ($sdn_type eq 'SILVERPEAK') {
        return get_silverpeak_helper($sql, $fabric_id, $user_agent_string);
    }
    elsif ($sdn_type eq 'VELOCLOUD') {
        return get_velocloud_helper($sql, $fabric_id, $user_agent_string);
    }
}

sub get_meraki_helper {
    my ($sql, $fabric_id, $org_id, $user_agent_string) = @_;
    my $info = $sql->record("select controller_address as address, protocol as proto, max_requests_per_second as requests_per_second, " .
                            "NetmriDecrypt(api_key, 'password', SecureVersion) as api_key, use_global_proxy " .
                            "from ${main::CONFIG_DB}.sdn_controller_settings " .
                            "where id = $fabric_id", RefWanted => 1, AllowNoRows => 1);

    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }
    _add_proxy($sql, $info);
    _add_requests_per_hour_limit($sql, $fabric_id, $info);
    NetMRI::HTTP::Client::Meraki->new(%$info, fabric_id => $fabric_id, org_id => $org_id, agent => $user_agent_string);
}

sub get_aci_helper {
    my ($sql, $fabric_id, $dn, $user_agent_string) = @_;

    if ($aci_session_cache{$fabric_id}) {
        # NIOS-77537: check if ACI fabric was changed in db
        my $db_updated_at = $sql->single_value("select unix_timestamp(updated_at) from ${main::CONFIG_DB}.sdn_controller_settings
                                                where id = $fabric_id", AllowNoRows => 1);
        unless ($db_updated_at) {
            NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
            return undef;
        }
        my $cache_updated_at = $aci_session_cache{$fabric_id}->{updated_at};
        if ($cache_updated_at < $db_updated_at) {
            NetMRI::LoggerShare::logInfo("ACI fabric $fabric_id was modified recently, updating aci_session_cache for this fabric");
            $aci_session_cache{$fabric_id} = undef;
        }
    }
    $aci_session_cache{$fabric_id} ||= _get_aci_client($sql, $fabric_id, $user_agent_string);
    my $client = $aci_session_cache{$fabric_id};
    return NetMRI::HTTP::Client::ACI::Global->new(client => $client, fabric_id => $fabric_id) unless ($dn);

    my $node_record = $sql->record("select NodeRole, SWVersion from ${main::NETMRI_DB}.SdnFabricDevice where SdnControllerId = $fabric_id and SdnDeviceDN = '$dn'", AllowNoRows => 1, RefWanted => 1);
    return undef unless ($node_record);
    if ($node_record->{NodeRole} eq 'controller') {
        return NetMRI::HTTP::Client::ACI::Controller->new(client => $client, dn => $dn, fabric_id => $fabric_id);
    } else {
        return NetMRI::HTTP::Client::ACI::Node->new(client => $client, dn => $dn, fabric_id => $fabric_id);
    }
}

sub get_viptela_helper {
    my ($sql, $fabric_id, $user_agent_string) = @_;
    my $info = $sql->record("select cs.controller_address as address, cs.protocol as proto,
                            NetmriDecrypt(cs.sdn_username, 'username', cs.SecureVersion) as username,
                            NetmriDecrypt(cs.sdn_password, 'password', cs.SecureVersion) as password,
                            cs.max_requests_per_second as requests_per_second, 
                            cs.use_global_proxy, uc.path as ca_cert
                            from ${main::CONFIG_DB}.sdn_controller_settings cs
                            left join ${main::CONFIG_DB}.uploaded_certificates uc on (cs.ca_cert_id = uc.id)
                            where cs.id = $fabric_id", RefWanted => 1, AllowNoRows => 1);
    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }
    _add_proxy($sql, $info);
    _add_requests_per_hour_limit($sql, $fabric_id, $info);
    NetMRI::HTTP::Client::Viptela->new(%$info, fabric_id => $fabric_id, agent => $user_agent_string);
}

sub get_mist_helper {
    my ($sql, $fabric_id, $user_agent_string) = @_;
    my $info = $sql->record("select controller_address as address, protocol as proto, max_requests_per_second as requests_per_second, " .
                            "NetmriDecrypt(api_key, 'password', SecureVersion) as api_key, use_global_proxy " .
                            "from ${main::CONFIG_DB}.sdn_controller_settings " .
                            "where id = $fabric_id", RefWanted => 1, AllowNoRows => 1);

    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }
    _add_proxy($sql, $info);
    _add_requests_per_hour_limit($sql, $fabric_id, $info);
    NetMRI::HTTP::Client::Mist->new(%$info, fabric_id => $fabric_id, agent => $user_agent_string);
}

sub get_silverpeak_helper {
    my ($sql, $fabric_id, $user_agent_string) = @_;
    my $info = $sql->record("select controller_address as address, protocol as proto, max_requests_per_second as requests_per_second, " .
                            "NetmriDecrypt(api_key, 'password', SecureVersion) as api_key, use_global_proxy " .
                            "from ${main::CONFIG_DB}.sdn_controller_settings " .
                            "where id = $fabric_id", RefWanted => 1, AllowNoRows => 1);

    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }
    _add_proxy($sql, $info);
    _add_requests_per_hour_limit($sql, $fabric_id, $info);
    NetMRI::HTTP::Client::SilverPeak->new(%$info, fabric_id => $fabric_id, agent => $user_agent_string);
}

sub get_velocloud_helper {
    my ($sql, $fabric_id, $user_agent_string) = @_;
    my $info = $sql->record("select controller_address as address, protocol as proto, max_requests_per_second as requests_per_second, " .
                            "NetmriDecrypt(api_key, 'password', SecureVersion) as api_key, use_global_proxy " .
                            "from ${main::CONFIG_DB}.sdn_controller_settings " .
                            "where id = $fabric_id", RefWanted => 1, AllowNoRows => 1);

    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }
    _add_proxy($sql, $info);
    _add_requests_per_hour_limit($sql, $fabric_id, $info);
    NetMRI::HTTP::Client::VeloCloud->new(%$info, fabric_id => $fabric_id, agent => $user_agent_string);
}

sub _get_sdn_type {
    my $sql = shift;
    my $fabric_id = shift;
    my $info = $sql->record("select sdn_type from ${main::CONFIG_DB}.sdn_controller_settings " .
                            "where id = $fabric_id", RefWanted => 1, AllowNoRows => 1);
    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }
    return $info->{sdn_type};
}

sub _get_aci_client {
     my ($sql, $fabric_id, $user_agent_string) = @_;
    my $info = $sql->record("select cs.controller_address as host, cs.protocol as proto,
                            NetmriDecrypt(cs.sdn_username, 'password', SecureVersion) as username,
                            NetmriDecrypt(cs.sdn_password, 'password', SecureVersion) as password,
                            cs.max_requests_per_second as requests_per_second, 
                            cs.use_global_proxy, uc.path as ca_cert
                            from ${main::CONFIG_DB}.sdn_controller_settings cs
                            left join ${main::CONFIG_DB}.uploaded_certificates uc on (cs.ca_cert_id = uc.id)
                            where cs.id = $fabric_id", RefWanted => 1, AllowNoRows => 1);
    unless ($info) {
        NetMRI::LoggerShare::logError("Cannot get information on fabric $fabric_id");
        return undef;
    }

    $info->{agent} = $user_agent_string;
    $info->{host} = [split /,/, $info->{host}];
    _add_proxy($sql, $info);
    _add_requests_per_hour_limit($sql, $fabric_id, $info);
    return NetMRI::HTTP::Client::ACI->new(%$info, fabric_id => $fabric_id);
}

sub _add_requests_per_hour_limit {
    my ($sql, $fabric_id, $info) = @_;
    my $requests_per_hour;

    eval {
        $requests_per_hour = $sql->single_value(
            "select max_requests_per_hour from ${main::CONFIG_DB}.sdn_controller_settings where id = $fabric_id",
            AllowNoRows => 1
        );
    };

    if ($@) {
        NetMRI::LoggerShare::logDebug("max_requests_per_hour column is unavailable for fabric $fabric_id, using NETMRI_SDN_MAX_REQUESTS_PER_HOUR fallback");
        $requests_per_hour = undef;
    }

    if (!defined $requests_per_hour || $requests_per_hour !~ /^\d+$/) {
        $requests_per_hour = $ENV{NETMRI_SDN_MAX_REQUESTS_PER_HOUR};
    }

    if (defined $requests_per_hour && $requests_per_hour =~ /^\d+$/) {
        $info->{requests_per_hour} = int($requests_per_hour);
    }
}

sub _add_proxy {
    my ($sql, $info) = @_;
    return unless $info->{use_global_proxy};
    my $proxy_data = $sql->record("
        select use_global_proxy,
        proxy_address as host,
        proxy_port as port,
        username,
        NetmriDecrypt(password, 'password', 1) as password
        from ${main::CONFIG_DB}.global_proxy_settings order by id limit 1", 
        RefWanted => 1, AllowNoRows => 1);
    unless ($proxy_data->{use_global_proxy} && $proxy_data->{host}) {
        $info->{use_global_proxy} = 0;
        return;
    }
    $proxy_data->{proto} = 'http' if lc($info->{proto}||'') eq 'http';
    $proxy_data->{username} = encode_proxy_credential($proxy_data->{username});
    $proxy_data->{password} = encode_proxy_credential($proxy_data->{password});
    $info->{proxy} = $proxy_data;
}

sub get_user_agent_string {
    my $cfg = shift;
    unless (ref($cfg)) {
        $cfg = NetMRI::Config->new(skip_advanced => 1);
    }
    return ($cfg->{AutomationGridMember} && $cfg->{AutomationGridMember} eq "1") ? 'infobloxni' : 'infobloxnetmri';
}

# Needed by unit tests
sub reset_aci_session_cache {
    %aci_session_cache = ();
}

sub encode_proxy_credential {
    my $cred = shift;
    $cred =~ s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%0x", ord $1 /eg;
    $cred =~ s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%0x", ord $1 /eg;
    return ($cred);
}

1;