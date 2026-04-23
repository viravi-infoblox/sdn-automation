#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use NetMRI::Config;
use NetMRI::SDN::ApiHelperFactory;
use NetMRI::LoggerShare;

NetMRI::LoggerShare::logOpen ( "STDOUT");
NetMRI::LoggerShare::logSetID ("test_sdn");

my @options = (
  'ipaddr=s',
  'device_id=i',
  'virtual_network_id=i',
  'datapoint=s@',
  'debug',
  'configDB=s',
  'reportDB=s',
  'netmriDB=s'
);

my %opt = (
  configDB  => 'config',
  reportDB  => 'report',
  netmriDB  => 'netmri',
  device_id => 0,
  ipaddr    => ''
);

my $usage =  "Usage: $0 -ipaddr=<ipaddr>|-device_id=<device_id> [-debug] [-virtual_network_id <VirtualNetworkID>] [-datapoint=[all|obtainSystemInfo,obtainInterfaces,obtain...]] )";

mydie($usage) unless @ARGV;

GetOptions( \%opt, @options );
$opt{datapoints} = [ split(/,/, join(',', @{$opt{datapoint}})) ] if $opt{datapoint};

if($opt{debug}) {
  NetMRI::LoggerShare::logSetLevel(2);
  NetMRI::LoggerShare::logSetDebug(1);
} else {
  NetMRI::LoggerShare::logSetLevel(1);
  NetMRI::LoggerShare::logSetDebug(0);
}

my $config = new NetMRI::Config();
my $sql = new NetMRI::Sql (
  DBType   => "mysql",
  DBName   => $opt{netmriDB},
  DBUser   => "root",
  DBPass   => $config->{mysqlPass},
  DBHost   => $config->{mysqlHost},
  DBPort   => $config->{mysqlPort},
  Debug    => $opt{debug},
  ContinueOnError => 1);

my $device_info = getDeviceInfo();
NetMRI::LoggerShare::logInfo('---------------------------');
foreach(sort(keys(%{$device_info}))) {
  NetMRI::LoggerShare::logInfo("$_: '$device_info->{$_}'");
}
mydie("Device '$device_info->{find_by}' is not found") unless $device_info->{DeviceID};
mydie("Device '$device_info->{find_by}' is not 'SDN' device") unless $device_info->{SdnDeviceDN};

my @datapoints = $sql->table(
  "select pg.DeviceType,pgd.PropertyGroup,PropertyName "
  . "from netmri.PropertyGroupDef as pgd join netmri.PropertyGroup as pg "
  . "using(PropertyGroup) where Source='SDN' order by PropertyName");
my %device_types = ();
foreach my $r (@datapoints) {
  $device_types{$r->{DeviceType}}->{datapoints}->{$r->{PropertyName}} = 1;
}
mydie("'SDN' datapoints are not defined for device '$device_info->{Type}/$device_info->{NodeRole}'") unless defined($device_types{$device_info->{NodeRole}} || $device_types{Global}->{datapoints}->{obtainEverything});

$main::CONFIG_DB = $opt{configDB};
$main::NETMRI_DB = $opt{netmriDB};
$main::REPORT_DB = $opt{reportDB};

my %device_params = (
    fabric_id => $device_info->{SdnControllerId},
    sql => $sql,
    logger => NetMRI::LoggerShare::logGetLog(),
    cfg => $config,
    config_db => $opt{configDB},
    netmri_db => $opt{netmriDB},
    report_db => $opt{reportDB},
    dn => $device_info->{SdnDeviceDN}
    );

my $device = NetMRI::SDN::ApiHelperFactory::get_device_helper(%device_params);
NetMRI::LoggerShare::logInfo('Helper: ' . ref($device) . "'");
NetMRI::LoggerShare::logInfo('---------------------------');
@datapoints = sort(keys(%{$device_types{$device_info->{NodeRole}}->{datapoints}}));
NetMRI::LoggerShare::logInfo("Known datapoins for the device:\n   ".join("\n   ", @datapoints));

@datapoints = @{$opt{datapoints}} unless grep(/^all$/, @{$opt{datapoints}});
NetMRI::LoggerShare::logInfo('---------------------------');
NetMRI::LoggerShare::logInfo("Perform data collection:");
foreach my $datapoint (@datapoints){
  eval {
    if ($device->can($datapoint)) {
      NetMRI::LoggerShare::logInfo("+ Run $datapoint ...");
      $device->$datapoint();
      NetMRI::LoggerShare::logInfo("- Done $datapoint");
    }
    else {
      NetMRI::LoggerShare::logInfo('Device helper: ' . ref($device) . " doesn't know what to do with $datapoint");
    }
  };
  NetMRI::LoggerShare::logError("ERROR: $@") if $@;
}
NetMRI::LoggerShare::logInfo("Done.");


sub getDeviceInfo
{
  my %row;

  my $sqlCmd = "select d.DeviceID,d.Vendor,d.Type,d.Model,d.SWVersion,"
  . "f.NodeRole,f.SdnControllerId,f.SdnDeviceDN "
  . "from $opt{netmriDB}.Device as d left join $opt{netmriDB}.SdnFabricDevice as f using (DeviceID) where ";
  if($opt{ipaddr}) {
    $sqlCmd .= "d.IPAddress='$opt{ipaddr}'";
    $row{find_by} = "ipaddr=$opt{ipaddr}";
  }
  elsif($opt{device_id}) {
    $sqlCmd .= 'd.DeviceID=' . $opt{device_id};
    $row{find_by} = $row{find_by} = "device_id=$opt{device_id}";
  }
  else {
    mydie("Mised required parameter\n$usage");
  }
  if($opt{virtual_network_id}){
    $sqlCmd .= ' and VirtualNetworkID=' . $opt{virtual_network_id};
  }
  NetMRI::LoggerShare::logDebug("-> getDeviceInfo, about to sql '$sqlCmd'\n");
  %row = (%row,$sql->record($sqlCmd, AllowNoRows=>1));

  return (\%row);
}

sub mydie {
  my ($message) = @_;
  NetMRI::LoggerShare::logError($message);
  exit 1;
}
