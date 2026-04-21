#!/usr/bin/perl

use strict;
use Getopt::Long;
use NetMRI::Config;
use NetMRI::Sql;
use NetMRI::API;
use NetMRI::Logger;
use NetMRI::HTTP::Client::Meraki;
use NetMRI::HTTP::Client::Viptela;
use NetMRI::HTTP::Client::ACI;
use NetMRI::HTTP::Client::ACI::Global;
use NetMRI::HTTP::Client::Mist;
use NetMRI::HTTP::Client::SilverPeak;
use NetMRI::SDN::Meraki;
use NetMRI::SDN::ACI;
use NetMRI::SDN::Viptela;
use NetMRI::SDN::Mist;
use NetMRI::SDN::SilverPeak;
use NetMRI::LoggerShare;
use NetMRI::CollectorCommon;
use NetMRI::SDN::ApiHelperFactory;
use Data::Dumper;

$| = 1;

my $ok_string    = 'Result: SUCCESS';
my $error_string = 'Result: FAILURE';

my $debug              = 0;
my $sdn_type           = undef;
my $address            = undef;
my $protocol           = 'https';
my $network_interface  = undef;
my $virtual_network_id = undef;
my $api_key            = undef;
my $username           = undef;
my $password           = undef;
my $proxy_address      = undef;
my $proxy_port         = undef;
my $proxy_username     = undef;
my $proxy_password     = undef;
my $ca_cert            = undef;
my $remove_ca_cert     = 0;
my @addresses          = ();
my $start_blackout_schedule = undef;
my $blackout_duration  = undef;

GetOptions(
  "sdn_type=s"           => \$sdn_type,
  "address=s"            => \$address,
  "protocol=s"           => \$protocol,
  "network_interface=s"  => \$network_interface,
  "virtual_network_id=s" => \$virtual_network_id,
  "api_key=s"            => \$api_key,
  "username=s"           => \$username,
  "password=s"           => \$password,
  "proxy_address=s"      => \$proxy_address,
  "proxy_port=s"         => \$proxy_port,
  "proxy_username=s"     => \$proxy_username,
  "proxy_password=s"     => \$proxy_password,
  "ca_cert=s"            => \$ca_cert,
  "remove_ca_cert"       => \$remove_ca_cert,
  "debug"                => \$debug,
  "start_blackout_schedule=s" => \$start_blackout_schedule,
  "blackout_duration=i"  => \$blackout_duration
);
$protocol = lc($protocol) if $protocol;
@addresses = split /,/, $address;
my $log = NetMRI::Logger->new(
  MessageTag => '',
  LogOptions => {
    CopyToSTDOUT => 1,
    Append       => 1
  },
  Debug => $debug,
  Log   => '/tools/skipjack/logs/checkSdnConnection.log'
);
NetMRI::LoggerShare::logSet($log);
my $cfg = NetMRI::Config->new();
my $sql = NetMRI::Sql->new(Config => $cfg, DBType => 'mysql', 'DBName' => 'netmri', 'DBUser' => 'root');

$log->info('Start testing SDN connection ...');
if ($start_blackout_schedule && NetMRI::CollectorCommon::isBlackoutInEffect('skip', time(), $start_blackout_schedule, $blackout_duration)) {
  $log->info("Skipping Test Connection for fabric $address due to blackout.\nDone");
  exit;
}

if ($sdn_type eq 'MERAKI') {
  test_meraki_sdn();
} elsif ($sdn_type eq 'CISCO_APIC') {
  test_cisco_apic_sdn();
} elsif ($sdn_type eq 'VIPTELA') {
  test_viptela_sdn();
} elsif ($sdn_type eq 'MIST') {
  test_mist_sdn();
} elsif ($sdn_type eq 'SILVERPEAK') {
  test_silverpeak_sdn();
} else {
  $log->error("Unknown sdn_type: $sdn_type");
}
if ($ca_cert && $remove_ca_cert) {
  $log->debug("Removing temporary ca_cert file: $ca_cert");
  unlink $ca_cert;
}
$log->info('Done');

sub test_meraki_sdn {
  $log->info('Testing connection to Meraki');
  unless ($api_key) {
    $log->error('api_key is required');
    $log->info($error_string);
    return;
  }
  my $params = {api_key => $api_key, fabric_id => 1};
  add_common_params($params);
  push @addresses, '' unless scalar(@addresses);
  foreach my $address (@addresses) {
    $params->{address} = $address if $address;
    my $api_helper = NetMRI::HTTP::Client::Meraki->new(%$params);
    my $client     = NetMRI::SDN::Meraki->new(
      sql               => $sql,
      logger            => $log,
      api_helper        => $api_helper,
      network_interface => $network_interface || ''
    );
   
    if ($network_interface && !$client->{local_interface_conf}) {
      $log->error('Failed to determine the source IP address for the given interface. Please check your scan interface settings.');
      $log->info($error_string);
    } else {
      $log->info('Performing request'
          . ($address ? " to $protocol://$address" : '')
          . ($client->{local_interface_conf} ? ' using ' . $client->{local_interface_conf} : ''));
      my ($res, $error) = $client->getApiClient()->get_organizations();
      if ($res) {
        $log->info($ok_string);
      } else {
        $log->error($error);
        $log->info($error_string);
      }
    }
  }
}

sub test_cisco_apic_sdn {
  my $params = {username => $username, password => $password, network_interface => $network_interface};
  unless (scalar(@addresses) && $params->{username} && $params->{password}) {
    $log->error('Parameter "address" is required') unless scalar(@addresses);
    foreach my $key (qw(username password)) {
      $log->error("Parameter \"$key\" is required") unless $params->{$key};
    }
    $log->info($error_string);
    return;
  }
  if ($protocol) {
    $params->{proto} = $protocol;
    $params->{ca_cert} = $ca_cert if ($ca_cert && $protocol eq 'https');
  }
  add_common_params($params);
  foreach my $address (@addresses) {
    $params->{host} = [$address];
    my $api_client = NetMRI::HTTP::Client::ACI->new(%$params);
    my $api_helper = NetMRI::HTTP::Client::ACI::Global->new(client => $api_client, fabric_id => 1);
    my $client     = NetMRI::SDN::ACI->new(
      sql               => $sql,
      logger            => $log,
      api_helper        => $api_helper,
      network_interface => $network_interface || '',
      virtual_network_id => $virtual_network_id || 0
    );
    $log->info("Performing request to Cisco APIC $protocol://$address"
        . ($client->{local_interface_conf} ? ' using ' . $client->{local_interface_conf} : ''));
    my ($res, $error) = $api_helper->get_fabric_nodes();
    if ($res) {
      $log->info($ok_string);
    } else {
      $error =~ s/All controllers are/Controller is/;
      $log->error($error);
      $log->info($error_string);
    }
  }
}

sub test_viptela_sdn {
  $log->info('Testing connection to Viptela');
  my $params = {username => $username, password => $password, network_interface => $network_interface, fabric_id => 1};
  unless (scalar(@addresses) && $params->{username} && $params->{password}) {
    $log->error('Parameter "address" is required') unless scalar(@addresses);
    foreach my $key (qw(username password)) {
      $log->error("Parameter \"$key\" is required") unless $params->{$key};
    }
    $log->info($error_string);
    return;
  }
  
  if ($protocol) {
    $params->{proto} = $protocol;
    $params->{ca_cert} = $ca_cert if ($ca_cert && $protocol eq 'https');
  }
  
  add_common_params($params);
  
  foreach my $address (@addresses) {
    $params->{address} = $address if $address;
    my $api_helper = NetMRI::HTTP::Client::Viptela->new(%$params);
    my $client     = NetMRI::SDN::Viptela->new(
      sql               => $sql,
      logger            => $log,
      api_helper        => $api_helper,
      network_interface => $network_interface || ''
    );

    if ($network_interface && !$client->{local_interface_conf}) {
      $log->error('Failed to determine the source IP address for the given interface. Please check your scan interface settings.');
      $log->info($error_string);
    } else {
      $log->info('Performing request'
          . ($address ? ' to ' . $api_helper->{args}->{proto} . "://$address" : '')
          . ($client->{local_interface_conf} ? ' using ' . $client->{local_interface_conf} : ''));
      my ($res, $error) = $client->getApiClient()->get_devices();
      if ($res) {
        $log->info($ok_string);
      } else {
        $log->error(ref($error) ? $error->{data}->{error}->{message} : $error);
        $log->info($error_string);
      }
    }
  }
}

sub test_mist_sdn {
  $log->info('Testing connection to Mist');
  unless ($api_key) {
    $log->error('api_key is required');
    $log->info($error_string);
    return;
  }
  my $params = {api_key => $api_key, fabric_id => 1};
  add_common_params($params);
  push @addresses, '' unless scalar(@addresses);
  foreach my $address (@addresses) {
    $params->{address} = $address if $address;
    my $api_helper = NetMRI::HTTP::Client::Mist->new(%$params);
    my $client     = NetMRI::SDN::Mist->new(
      sql               => $sql,
      logger            => $log,
      api_helper        => $api_helper,
      network_interface => $network_interface || ''
    );
   
    if ($network_interface && !$client->{local_interface_conf}) {
      $log->error('Failed to determine the source IP address for the given interface. Please check your scan interface settings.');
      $log->info($error_string);
    } else {
      $log->info('Performing request'
          . ($address ? " to $protocol://$address" : '')
          . ($client->{local_interface_conf} ? ' using ' . $client->{local_interface_conf} : ''));
      my ($res, $error) = $client->getApiClient()->get_self();
      $log->debug("Received from Mist API:");
      $log->debug(Dumper($res));
      if ($res) {
        $log->info($ok_string);
      } else {
        $log->error($error);
        $log->info($error_string);
      }
    }
  }
}

sub test_silverpeak_sdn {
  $log->info('Testing connection to SilverPeak');
  unless ($api_key) {
    $log->error('api_key is required');
    $log->info($error_string);
    return;
  }
  my $params = {api_key => $api_key, fabric_id => 1};
  add_common_params($params);
  push @addresses, '' unless scalar(@addresses);
  foreach my $address (@addresses) {
    $params->{address} = $address if $address;
    my $api_helper = NetMRI::HTTP::Client::SilverPeak->new(%$params);
    my $client     = NetMRI::SDN::SilverPeak->new(
      sql               => $sql,
      logger            => $log,
      api_helper        => $api_helper,
      network_interface => $network_interface || ''
    );
   
    if ($network_interface && !$client->{local_interface_conf}) {
      $log->error('Failed to determine the source IP address for the given interface. Please check your scan interface settings.');
      $log->info($error_string);
    } else {
      $log->info('Performing request'
          . ($address ? " to $protocol://$address" : '')
          . ($client->{local_interface_conf} ? ' using ' . $client->{local_interface_conf} : ''));
      my ($res, $error) = $client->getApiClient()->get_apiKey();
      $log->debug("Received from SilverPeak API:");
      $log->debug(Dumper($res));
      if ($res) {
        $log->info($ok_string);
      } else {
        $log->error($error);
        $log->info($error_string);
      }
    }
  }
}

sub add_common_params {
  my $params = shift;
  $params->{agent} = NetMRI::SDN::ApiHelperFactory::get_user_agent_string($cfg);
  if ($proxy_address) {
    $params->{proxy} = {host => $proxy_address};
    $params->{proxy}->{port}     = $proxy_port     if $proxy_port > 0;
    $params->{proxy}->{proto}    = 'http'          if $protocol eq 'http';
    $params->{proxy}->{username} = NetMRI::SDN::ApiHelperFactory::encode_proxy_credential($proxy_username) if $proxy_username;
    $params->{proxy}->{password} = NetMRI::SDN::ApiHelperFactory::encode_proxy_credential($proxy_password) if $proxy_password;
    $log->info("Use proxy $proxy_address" . ($params->{proxy}->{port} ? ':' . $params->{proxy}->{port} : ''));
  }
}
