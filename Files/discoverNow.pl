#!/usr/bin/perl

=head1 NAME

discoverNow.pl - A script to discovery and classification of a device.

=head1 SYNOPSIS

discoverNow.pl <ip address>

=head1 DESCRIPTION

This script is used by "discover now", and does each of the steps
of the discovery process as a 1 time through. The IP is required
the work is done by the launched scripts.

=cut

use strict;
use NetMRI::SDN::ApiHelperFactory;
use NetMRI::Util::Process;
use NetMRI::Util::Date;
use NetMRI::CollectorCommon;
use NetMRI::Config;
use NetMRI::Isl;
use NetMRI::MQ;
use NetMRI::Util::HW;		# NIOS-49097 : need to catch NetMRI vs NI running
use JSON;

use Getopt::Long;

# we need this to force a fetch of a config file
require "/tools/skipjack/app/WEB-INF/transaction/netmri/ccs/engine/CCS_Lib.pm";

our $skipjack       = "/tools/skipjack";

$| = 1;	# Turn on autoflush to not confuse the web pages

my %options;
# set command line defaults
$options{debug} = 0;           # no debug unless asked for
$options{targetIP} = '';       # we need one, but we can't assume any.
$options{cvsOwner} = 'netmri';  # currently all are owned by this user. 
$options{printHelp} = 0;       # flags that they want the help (only)
$options{skipIDReuse} = 0;     # if 1, and IP not in system, do not look for old device ID
$options{json} = 0;	       # if > 1, then JSON output will be sent to that file descriptor
$options{consolidate} = 0;     # force a consolidation
$options{source} = 'Discover Now'; # source can be also IF-MAP if
                                # discovery was initiated by getting IP from IF-MAP server 
$options{mqMode} = 0;		# flag for if we're doing a grid specific discovery (no CLI, suppress output, send info to MQ)

# Overriding the DBs isn't implemented yet, but we may need for future testing
$options{configDB} = 'config';
$options{reportDB} = 'report'; # to allow future testing by pointing at a different area
$options{netmriDB} = 'netmri';
$options{secondaryPID} = '';
$options{deviceMAC} = '';
$options{continue} = 0;
$options{debugSQL} = 0;
$options{vnid} = 1; # VirtualNetworkID, should be passed along with targetIP. 1 is standard net
$options{fabricid} = '';

NetMRI::LoggerShare::logOpen ( "STDOUT");
NetMRI::LoggerShare::logSetID ("discoverNow");

# used for JSON output
my %status = (initial => 0,
              fingerprint => 0,
              snmp_credentials => 0,
              identification => 0,
              system_info => 0,
              confirm_type => 0,
              cli_credentials => 0,
              config_collection => 0,
              contexts_info => 0);


# Note: I default them to off, but if the specify flag isn't given, they get turned on
# below. This lets me have a testing action to turn everything off expcept what I'm
# currently working

my %actions = (
	initialDiscovery => 0,
	doFingerPrint => 0,
	determineSNMPCredentials => 0,
	typeDiscovery => 0,
	pollSystemInfo => 0,
	confirmDiscovery => 0,
	determineCLICredentials => 0,
	getConfig => 0
);

my $optResult = GetOptions(
    "ip=s"			       => \$options{targetIP},
    "vnid=i"			       => \$options{vnid},
    "continue"                         => \$options{continue},
    "skipIDReuse"	       	       => \$options{skipIDReuse},
    "json=i"	 		       => \$options{json},
    "mq"                               => \$options{mqMode},
    "help"			       => \$options{printHelp},
    "specify"			       => \$options{specify},
    "debug"			       => \$options{debug},
    "dsql"			       => \$options{debugSQL},
    "determineSNMPCredentials"         => \$actions{determineSNMPCredentials},
    "initialDiscovery"		       => \$actions{initialDiscovery},
    "typeDiscovery"		       => \$actions{typeDiscovery},
    "pollSystemInfo"		       => \$actions{pollSystemInfo},
    "confirmDiscovery"		       => \$actions{confirmDiscovery},
    "doFingerPrint"		       => \$actions{doFingerPrint},
    "determineCLICredentials"	       => \$actions{determineCLICredentials},
    "getConfig"			       => \$actions{getConfig},
    "pollDeviceContext"		       => \$actions{pollDeviceContext},
    "secondaryPID=s"		       => \$options{secondaryPID},
    "deviceMAC=s"		       => \$options{deviceMAC},
    "sessionID=s"                      => \$options{sessionID},
    "source=s"                         => \$options{source},
    "fabricid=i"			       => \$options{fabricid},
);

$options{debug} ||= -e '/tmp/discovernow.debug';

NetMRI::LoggerShare::logSetDebug ($options{debug} ? 1 : 0);
NetMRI::LoggerShare::logSetLevel ($options{debug} ? 2 : 1);

foreach (@ARGV) {
    if ($options{targetIP} eq '') {
        $options{targetIP} = $_;
    } else {
        print "Unknown argument '$_' skipped\n";
	$options{printHelp} = 1; # problem, better to let them see it
    }
}

if ($options{printHelp}) {
    printHelp();
    exit 0;
}

foreach my $k (sort(keys %options)) {
    print ("\toptions{$k} = '$options{$k}'\n") if $options{debug};
}

my $mq;
# if we're in mqMode, make sure other options are set as needed (JSON off, etc)
if ($options{mqMode}) {
    $options{json} = 0;
    $mq = new NetMRI::MQ();
}
    
$status{ip_address} = $options{targetIP};

# If specify is ON, then we don't do this and only the ones they turn on will fire
if (!$options{specify}) {
    # we aren't specifying, so turn everything on
    foreach my $k (keys %actions) {
	$actions{$k} = 1;
    }
}

foreach my $k (sort(keys %actions)) {
    print ("\tactions{$k} = '$actions{$k}'\n") if $options{debug};
}

# make sure we're called correctly
die_with_error("invalid-params", "Usage: $0 <ipaddr>") if ($options{targetIP} !~ /^[[:xdigit:].:]+$/ && !$options{fabricid});

##
## Print a secondary PID so that I can be killed while waiting for the first process to finish
##
if ($options{secondaryPID}){
	NetMRI::Util::Process::createPidFile($options{secondaryPID});
}

# we do NOT limit the proc for mqMode
if(!$options{mqMode}) {
    ##
    ## Don't allow more than one of these at a time.
    ##
    my $pid = NetMRI::Util::Process::createPidFile("/var/run/netmri/discoverNow.pl");
    my $attempts = 0;
    while ( $pid != $$ ) {
        if ($attempts == 0) {
            print "\nWaiting for other discover now process to complete...\n";

            # another process already exists, try to get info by PID
            my $info_by_pid = `ps -p $pid -o args= --no-headers`;
            # search valid IP from command line
            my $octet = qr{\d{1,2}|[01]\d{2}|2[0-4]\d|25[0-5]};
            my $valid_ip = qr{(?:$octet\.){3}$octet};
            my $ip_addr = ($info_by_pid =~ /($valid_ip) /) ? $1 : "unknown";
            print "process id (PID): $pid , device address (IP): $ip_addr\n---\n";
        };
		if ( ++$attempts >= 60 ) {
			print "Lock-timeout: Gave up waiting for other process to finish ($pid).";
			exit 25;
		}
        sleep 2;
        $pid = NetMRI::Util::Process::createPidFile("/var/run/netmri/discoverNow.pl");
    }
}

END { 
	consolidate() if $options{consolidate} && $status{initial};
	sendJSON();
	NetMRI::Util::Process::removePidFile();
}

print " checking '$options{targetIP}'\n" if ($options{debug});

my $config = new NetMRI::Config();
die_with_error("file-not-found", "Unable to read config") if (!$config) ;

$main::CONFIG_DB = $options{configDB};
$main::NETMRI_DB = $options{netmriDB};
$main::REPORT_DB = $options{reportDB};

my $sql = new NetMRI::Sql (
			   DBType   => "mysql",
			   DBName   => "netmri",
			   DBUser   => "root",
			   DBPass   => $config->{mysqlPass},
			   DBHost   => $config->{mysqlHost},
			   DBPort   => $config->{mysqlPort},
			   Debug    => $options{debug},
			   DebugSQL => $options{debugSQL}, # Note: Debug needs to be on as well
			   ContinueOnError => 1);

# obtain DeviceID for given IP and VN, it is possible that it does not exist yet
my ($deviceID, $vendor, $type) = getDeviceInfo($sql, $options{targetIP}, $options{vnid});

if ( ($options{fabricid} || $type eq "SDN Controller" || $type eq "SDN Element") && $config->{SdnDiscovery} ne 'on' ) {
    my $what = ( $options{fabricid} ? "fabric ID $options{fabricid}" : "IP $options{targetIP}" );
    print "Skipping DiscoverNow for $what due to SDN/SD-WAN Polling is disabled\n";
    exit 11;
}

if ( $options{fabricid} ) {
	my %device_params = (
		fabric_id => $options{fabricid},
		sql => $sql,
		logger => NetMRI::LoggerShare::logGetLog(),
		cfg => $config,
		config_db => $options{configDB},
		netmri_db => $options{netmriDB},
		report_db => $options{reportDB},
		);
	my $info = $sql->record("SELECT start_blackout_schedule,blackout_duration FROM $options{configDB}.sdn_controller_settings " .
                            "WHERE id = $device_params{fabric_id}", RefWanted => 1, AllowNoRows => 1);
	if ($info->{start_blackout_schedule} && NetMRI::CollectorCommon::isBlackoutInEffect('skip', time(), $info->{start_blackout_schedule}, $info->{blackout_duration})) {
		print "Skipping DiscoverNow for fabric ID = $device_params{fabric_id} due to blackout period in effect\n";
		exit 10;
	}
	my $base = NetMRI::SDN::ApiHelperFactory::get_device_helper(%device_params); 
	my $type = $sql->record("SELECT sdn_type FROM $options{configDB}.sdn_controller_settings " .
                            "WHERE id = $device_params{fabric_id}", RefWanted => 1, AllowNoRows => 1);
	my $sdn_type = uc($type->{sdn_type} || '');
	if (!defined $base) {
		print "ERROR: Unable to create SDN helper for fabric_id=$device_params{fabric_id}, sdn_type='" . ($type->{sdn_type} || '') . "'\n";
		exit 1;
	}
	if ($sdn_type eq "MIST" || $sdn_type eq "VELOCLOUD") {
                print 'Device helper: ' . ref($base) . "\n";
                print "Run obtainEverything...\n";
                eval {  $base->obtainEverything() };
        } else {
                print 'Device helper: ' . ref($base) . "\n";
                print "Run obtainDevices...\n";
                eval {  $base->obtainDevices() };
        }
	print "ERROR: $@\n" if $@;
	exit $@ ? '0' : '1';
}

#############################################################################
##
## If the device was manually unlicensed or it is known to actually be over
## the device limit, don't allow discover now.  Other cases proceed as we
## need to allow discovery to determine if the device should become licensed.
##
my %notLicensed = $sql->record("
    select
        DeviceID
    from
        $options{configDB}.device_license_overrides
    where
        DeviceID=$deviceID and state = 0
    union select
            DeviceID
          from
            $options{netmriDB}.LicenseDetails
          where
            DeviceID=$deviceID and LimitExceeded = 1 ",

    AllowNoRows=>1);

if ( $notLicensed{DeviceID} ne "" ) {
	print "Device is not licensed.  Discover now will not be performed\n";
	exit 1;
}

# the checkMAC is only for Augusta at this time
if ($config->{AutomationGridMember}) {
    $actions{checkMACAddress} = 1;
} else {
    $actions{checkMACAddress} = 0;
}

my $SNMPCollection = $sql->single_value("select SNMPPolling from $options{netmriDB}.DeviceGroupSettings where DeviceID=$deviceID", AllowNoRows => 1);

if ($SNMPCollection eq '0' && $type ne "SDN Controller" && $type ne "SDN Element") {
	print "SNMP Collection is disabled for this device. Discover now will not be performed\n";
	exit 1;
}

#############################################################################
##
## These locals just clean up the commands below
my $discoveryEngine = "$skipjack/app/WEB-INF/transaction/netmri/processors/discovery/discoveryEngine.pl";
## This also WILL change the database, even though it's called "test"
my $snmpTester =  "$skipjack/app/WEB-INF/transaction/netmri/collectors/dataEngine/test ";
my $cliDoTest = ($config->{AutomationGridMember}) ? "/infoblox/netmri/DIS/bin/guessCLICredentials.pl" : "$skipjack/app/WEB-INF/transaction/netmri/tools/cli_credential/DoTest.pl";
my $fingerPrint = "$skipjack/app/WEB-INF/transaction/netmri/collectors/fingerprint/fingerprint.pl";
my $ret;

$cliDoTest .= " -debug" if $options{debug};

# vnid parameter for discoveryEngine, dataEngine, and cli_credential
my $engineParam = $options{vnid} ? "--vnid=$options{vnid}" : "";
my $snmpParam = $options{vnid} ? "-virtual_network_id $options{vnid}" : "";
my $cliParam = $options{vnid} ? "--virtualNetworkID=$options{vnid}" : "";

# NETMRI-23491 : Verify the IP is OK to try discovery on
#                NOTE: this could flag blackout on an IP before we've verified
#                the device, but that's valid for not doing this.
#                This currently happens for any and all actions
# We want a different behavior in the logging of the isBlackout, so we change the
# logging flag based on which system we're on
# if we ever add a debug flag, we should probably NOT skip the log here
my $blackoutLog = 'skip';	# flags to utility to NOT log
if (NetMRI::Util::HW::isAutomationGridMember()) {
    $blackoutLog = '';	# forces log to stdout for NI
}
# Check the IP
if (NetMRI::CollectorCommon::isBlackoutInEffectForIp($sql, 
						     $blackoutLog,
						     $options{targetIP},
						     $options{vnid},
						     time())) {
    print "Skipping DiscoverNow for IP $options{targetIP} due to blackout period in effect\n";   
    exit 10;
}

##
## If the device doesn't exist yet, run the discovery engine once
## to see if it appears due to configuration changes.  If still
## not found, exit.
##
if ($actions{initialDiscovery}) {
	my $did = getDeviceID($sql, $options{targetIP}, $options{vnid});
	if (!$did) {
	    printProgress("Performing initial discovery (this may take a few minutes)\n");
	    my $skip = "";
	    $skip = "--skipIDReuse" if $options{skipIDReuse};
	    if (!myDoCommand("$discoveryEngine $skip --now $engineParam --source=\'$options{source}\' $options{targetIP}")) {
		print "Unable to perform device discovery\n";
		exit 1;
	    }
	    $did = getDeviceID($sql, $options{targetIP}, $options{vnid});
	    if ( !$did ) {

		print "Unable to discover device\n";
		my $query = "select d.Name as Device, d.IPAddress from $options{netmriDB}.Device d left join $options{netmriDB}.ifAddr i on (d.DeviceID=i.DeviceID) where i.IPAddressDotted='$options{targetIP}'";
		my @rows = $sql->table($query);
		if (@rows) {
			print "Reason: the entered ip address belongs to one of these existing devices:\n";
			foreach my $row (@rows) {
                        	foreach my $col (keys %{$row}) {
                        		print "$col=$row->{$col}     ";
                        	}
                        	print "\n";
                         }
		}
		exit 2;
	    }
	    printProgress("Done performing initial discovery\n");
	} else {
	  # NIOS-49097
	  # If we're running as a AutomationGridMember, we need to force the next
	  # IpamIP consolidation to update the record_timestamp and sequence number
	  # By setting the record_timestamp to 0, the tests within the IpamIP will
	  # force that to happen.
	  # Note: the network view ID == virtual network ID
	  if (NetMRI::Util::HW::isAutomationGridMember()) {
	    $sql->execute("update $options{reportDB}.IpamIP ".
			  " set record_timestamp = 0 ".
			  " where network_view_id = '$options{vnid}' AND " .
			  "  ip_address = '$options{targetIP}'" );
	    print ("=discoverNow, have cleared record_timestamp\n") if ($options{debug}); # DWV DEBUG REMOVE
	  }
	}

	# TODO: move device query out of the if blocks and 
	# make %device available to the entire script
	$status{DeviceID} = $did;
	$status{initial} = 1;
    
	# this case will be fine if $sctions{initialDiscovery} is on which is the default
	# if specify is on, then this check may not be called

	# We seem to be re-querying for no reason
	# NETMRI-23491 : as part of adding blackout to NetMRI, cleaned up 
	#                the mechanism to not log unless debug is on
	
	if (NetMRI::CollectorCommon::isBlackoutInEffectForDevice($sql, 
								 $blackoutLog,
								 $status{DeviceID},
								 time())) {
	    print "Skipping DiscoverNow for target IP $options{targetIP} id:$status{DeviceID} due to blackout period in effect\n";   
	    exit 10;
	}
    
	if ( $did && $options{deviceMAC} ne "" ) {
	    ## If provided the MAC put it in DeviceProperty to help pre-seed the DeviceMac in DeviceConfig.
	    $sql->execute("
			replace $options{netmriDB}.DeviceProperty
			(DeviceID,PropertyName,PropertyIndex,Value,Source,Timestamp)
			values 
			($did,'DeviceMAC','','$options{deviceMAC}','$options{source}',now())
		");
	}
}

## We need to check if discovered device is SDN Controller or SDN Element
## DeviceType will be available even after initial discovery
## If it is SDN Controller/Element we need to perform SDN-specific actions and disable irrelevant actions like credential guessing, etc.
if ($type eq "SDN Controller" || $type eq "SDN Element") {
  my $info = $sql->record("SELECT start_blackout_schedule,blackout_duration 
                           FROM $options{configDB}.sdn_controller_settings join $options{netmriDB}.SdnFabricDevice on (id = SdnControllerId) 
                           where DeviceID='$deviceID';", RefWanted => 1, AllowNoRows => 1);
        if ($info->{start_blackout_schedule} && NetMRI::CollectorCommon::isBlackoutInEffect('skip', time(), $info->{start_blackout_schedule}, $info->{blackout_duration})) {
            print "Skipping DiscoverNow for device ID = $deviceID due to blackout period in effect\n";
            exit 10;
        }
  foreach my $k (keys %actions) {
    $actions{$k} = 0;
    # We need to nofity user that we are skipping action he specified if it is not supported
    print "Skipping $k action is disabled for $type\n" if !$actions{$k} && $options{specify};
  }

  my ($fabric_id, $dn) = $sql->record("select SdnControllerId, SdnDeviceDN from netmri.SdnFabricDevice where DeviceID='$deviceID'", Array => 1);
  my %device_params = (
      fabric_id => $fabric_id,
      sql => $sql,
      logger => NetMRI::LoggerShare::logGetLog(),
      cfg => $config,
      config_db => $options{configDB},
      netmri_db => $options{netmriDB},
      report_db => $options{reportDB},
      dn => $dn
      );

  my $device = NetMRI::SDN::ApiHelperFactory::get_device_helper(%device_params);
  print 'Device helper: ' . ref($device) . "\n";

  foreach my $property ($sql->table("select pgd.PropertyName from netmri.SdnFabricDevice d join netmri.PropertyGroup pg on d.NodeRole = pg.DeviceType join netmri.PropertyGroupDef pgd using (PropertyGroup) where DeviceID='$deviceID'")){
    my $datapoint = $property->{PropertyName};
    eval {
      if ($device->can($datapoint)) {
        print "Run $datapoint\n";
        $device->$datapoint();
      }
      else {
        print 'Device helper: ' . ref($device) . " doesn't know what to do with $datapoint\n";
      }
    };
    print "ERROR: $@\n" if $@;
  }

  my %aci_device = $sql->record("select SdnDeviceDN, NodeRole from $options{netmriDB}.SdnFabricDevice where DeviceID = $deviceID", AllowNoRows => 1);
  if (%aci_device) {
    print "Successfully identified device as $aci_device{NodeRole} with DN $aci_device{SdnDeviceDN}\n";
  } else {
    print "Unable to find information about this device in fabric data collected by SDN\n";
    exit 1;
  }

  $status{snmp_credentials} = 1;
}



##
## Collect the fingerprint information
##
if ( $actions{doFingerPrint} && $config->{PortScanFingerPrintEnabled} eq "on") {
    printProgress("Collecting fingerprint information\n");
    my ($deviceID, $vendor, $type) = getDeviceInfo($sql, $options{targetIP}, $options{vnid});
    if (!myDoCommand("$fingerPrint --IPAddress=$options{targetIP} --DeviceID=$deviceID ")) {
	print "Unable to collect fingerprint info \n";
	if (!$options{continue}) { # This may not be fatal
	    exit 5;
	}
    }
    printProgress("Done collecting fingerprint\n");
    $status{fingerprint} = 1;
}

my $snmpTestCmd = "$snmpTester $options{targetIP} $snmpParam";
$snmpTestCmd .= " --quiet --human" unless ($options{debug});

##
## Determine SNMP credentials
##
if ($actions{determineSNMPCredentials}) {
    printProgress("Determining SNMP credentials for device\n");
    my $successString = ($options{debug}) ? "Discovered working credential" : "Credential passed" ;
    $ret = myDoCommand("$snmpTestCmd CredentialObject",$successString);
    if (($ret != 1) && (!$options{continue})) { # This may not be fatal
	print "Unable to determine SNMP credentials\n";
	exit 3;
    }
    if ($ret == 1) {
	printProgress("Done determining SNMP credentials for device\n");
	$status{snmp_credentials} = 1;
    } else {
	print "Continuing without determining SNMP credentials\n";
    }
}

##
## First run of discovery engine to populate device type
##
if ($actions{typeDiscovery} && $status{snmp_credentials}) {
    printProgress("Performing device identification discovery\n");
    if (!myDoCommand("$discoveryEngine --now $engineParam $options{targetIP}")) {
	print "Unable to perform device identification discovery\n";
	if (!$options{continue}) { # This may not be fatal
	    exit 4;
	}
    }
    printProgress("Done performing device identification discovery\n");
    $status{identification} = 1;
}

##
## Collect the SNMP system information
##
if ($actions{pollSystemInfo} && $status{snmp_credentials}) {
    printProgress("Collecting system information\n");
    if (!myDoCommand("$snmpTestCmd SystemInfo")) {
	print "Unable to collect basic SystemInfo info via SNMP\n";
	if (!$options{continue}) { # This may not be fatal
	    exit 5;
	}
    }
    printProgress("Done collecting system information\n");
    $status{system_info} = 1;
    getDeviceInfo($sql, $options{targetIP}, $options{vnid}) if $options{json} > 0; # refresh status info
}

##
## Run discovery a second time now that everything that can affect it should have been collected
##
if ($actions{confirmDiscovery} && $status{snmp_credentials}) {
    printProgress("Performing next stage discovery\n");
    if (!myDoCommand("$discoveryEngine --now $engineParam $options{targetIP}")) {
	print "Unable to discover second time to confirm device type\n";
	if (!$options{continue}) { # This may not be fatal
	    exit 6;
	}
    }
    getDeviceInfo($sql, $options{targetIP}, $options{vnid}) if $options{json} > 0; # refresh status info
    
    ## Once again poll system info in case type changed so correct device support
    ## indicators are set
    if (!myDoCommand("$snmpTestCmd SystemInfo")) {
	print "Unable to recollect basic SystemInfo info via SNMP\n";
	if (!$options{continue}) { # This may not be fatal
	    exit 7;
	}
    }
    getDeviceInfo($sql, $options{targetIP}, $options{vnid}) if $options{json} > 0; # refresh status info
    
    $status{confirm_type} = 1;
    printProgress("Done performing next stage discovery\n");
}

# This is a special action only done for non network devices on discovery grid. 
# We do it because getting the device IP may indicate that the NIOS just handed 
# it out and our MAC may be out of date. We will go to a router that's in the same
# subnet and get the MAC from it
if ($actions{checkMACAddress}) {
    printProgress("checking MAC address\n");
    checkMACAddress($sql, $options{targetIP}, $options{vnid});
}

# These actions should only be done if we are allowed to try, so check feature set
if ($actions{determineCLICredentials} && (NetMRI::Isl::isl("Collection_Device_CLI_Tables") ||
                                          NetMRI::Isl::isl("Collection_Device_CLI_Credentials") ||
                                          NetMRI::Isl::isl("Collection_Device_Config"))) {

    printProgress("Determining CLI credentials for device\n");
    if (deviceSupportsCLI($sql,$options{targetIP})) {
	if (!myDoCommand("$cliDoTest -resultsOnly -update -with-history $options{targetIP} $cliParam",
			 "Credentials Successful")) {
		print  "Unable to determine CLI credentials\n";
		$status{cli_credentials} = -1;
		# will exit later after the pollDeviceContext to allow it for devices that do not need CLI for it
	} else {
		$status{cli_credentials} = 1;
	}
    } else {
	# we reach here if this is not a CLI device
	print "   CLI data collection not supported for $options{targetIP} - skipping CLI credential determination\n";
	$status{cli_credentials} = 2;
    }
    printProgress("Done determining CLI credentials for device\n");
}

##
## Collect the Device Contexts
##
if ($actions{pollDeviceContext} && ($status{snmp_credentials} || $status{cli_credentials} != 2)) {
	printProgress("Collecting Device Contexts information\n");
	if (!myDoCommand("$snmpTestCmd --skipResetCredGuess devicecontext")) {
		print "Unable to collect DeviceContexts\n";
	}
	printProgress("Done collecting Device Contexts information\n");
	$status{contexts_info} = 1;
}

if ($status{cli_credentials} == -1) {
	exit 8;	# all CLI after, so we fail for sure here
}

##
## Collect the Device Configuration
##
if ($status{cli_credentials} != 2 && $actions{getConfig} && NetMRI::Isl::isl("Collection_Device_Config")) {
    printProgress("Collecting configs from device\n");
    if (!dispatchGetConfig($sql,$options{targetIP}, $config, $options{vnid})) {
	print  "Unable to collect config file\n";
	exit 9;
    } 
    $status{config_collection} = 1;
    printProgress("\nDone collecting configs\n");
}

printProgress( "Discovery complete\n");

# Let the master daemon know we're done
if($options{mqMode}) {
    $mq->channel->inform({
	key => "local.discover-immediately.status",
	body => { id=> $options{sessionID}, 
		  status=>"Completed",
		  type=>"IP",
		  detail=>"$options{targetIP}"
	},
		      exchange => "netmri-inform"
			 });
}

exit 0;                         # return valid status,we're done

########################################################################################

# prints a help message based on our calling syntax 
sub printHelp
{

    print "Usage: $^X [-ip=<ip address>] [-vnid=number][-debug] [-help] [-specify] "
	   . "[--determineSNMPCredentials] [--intialDiscovery] [--pollSystemInfo] "
	   . "[-confirmDiscovery] [--determineCLICredentials] [--getConfig] [--pollDeviceContext] "
	   . "[--doFingerPrint] <ip address>\n";
    print " where\n";
    print "   <ip address> is the IP to force discovery on. can be used\n";
    print "   as a positional paramter or with -i. internal calling from GUI\n";
    print "   uses positional paramter\n";
    print "   <vnid> is the VirtualNetwork ID the device is attached.\n";
    print "   -debug turns on prints that show additional info\n";
    print "   -help prints this message and exits\n";
    print "   -specify indicates that the actions to take should be limited\n";
    print "    to the actions given in the command line. By default (no -specify)\n";
    print "    all actions are done. This is intended for development to focus on\n";
    print "    a given action or actions.\n";
    print "   --determineSNMPCredentails (action) - attempt to guess the SNMP \n";
    print "     community string for a device\n";
    print "   --initialDiscovery (action) - run discoveryEngine on IP, 1 time to \n";
    print "     determine initial information\n";
    print "   --typeDiscovery (action) - run discoveryEngine on IP, 1 time to \n";
    print "     determine device type information\n";
    print "   --pollSystemInfo (action) - get system table from device via SNMP to\n";
    print "     determine device type and get initial key information\n";
    print "   --confirmDiscovery (action) - run discoveryEngine on IP 1 time to \n";
    print "     lock device type at correct level for additional actions\n";
    print "   --determineCLICredentials (action) - attempt to guess SSH or Telnet \n";
    print "     credentials needed from master list to use scripts on device\n";
    print "   --getConfig (action) - force getting of current configuration and \n";
    print "     loading into correct areas of netmri for configuration tools to work\n";
    print "   --pollDeviceContext (action) - get device contexts if relevant\n";
    print "   --doFingerPrint (action) - run fingerprint.pl on IP 1 time to \n";
    print "   collect info about OS and open ports\n";
}

# This prints a message as long as we're NOT in mqMode. For mq, we do NOT watch the
# progress
sub printProgress {
    my $msg = shift;

    if (!$options{mqMode}) {
	print $msg;
    }
}

# This fires off the command and will return 0 if any problems seen or the optional
# testString is not seen in the output. There's other DoCommands out there, so we use
# a slightly unique name

sub myDoCommand
{
    my $cmd = shift;
    my $testString = shift;

    print ("+doCommand, cmd '$cmd'\n") if ($options{debug});

    # if there is no testString passed, we don't need to test
    my $stringFound = 0;
    if ($testString eq '') {
        $stringFound = 1;
    }

    my $pipe_cmd = "$cmd 2>&1";
    if ($options{debug}) {
	my $timestamp = NetMRI::Util::Date::formatTimestamp(time(), undef, '_');
	my $dbg_file = '/tmp/discovernow_' . $options{targetIP} . '_' . ($timestamp) . '.log';
	open DBG_FILE, ">$dbg_file" || print "Unable to open $dbg_file: $!";
	print DBG_FILE "$pipe_cmd\n\n";
	close DBG_FILE;
        $pipe_cmd .= " | tee -a $dbg_file";
    }

    # we use open so we keep writing the output
    if (open (CMD_PIPE, "$pipe_cmd |")) {
	print ("=doCommand: have started command '$cmd'\n")  if ($options{debug});
        while (<CMD_PIPE>) {
	    my $curLine = $_;
	    $curLine =~ s/&nbsp;/ /g;
#	    $curLine =~ s/^\d{4}\-\d{2}\-\d{2} \d{2}\:\d{2}\:\d{2} \[(info|warning|error|debug)\] \d+ \([\w\s]+\)// ;
	    $curLine =~ s/^\d{4}\-\d{2}\-\d{2} \d{2}\:\d{2}\:\d{2}\s+\[(info|warn|error|debug)\]\s+\d+\s+\([\w\s]+\)// ;
	    $curLine =~ s/^\[(info|warn|error|debug)\]\s+// ;

		## Clean-up some SNMP output
		$curLine =~ s/getScalars: //;	
		chomp($curLine) if ( $curLine =~ /\+\+\+ Checking / );
		next if ( $curLine =~ /No Device Record Found/ );
		next if ( $curLine =~ /IssueClient::/ );
		next if ( $curLine =~ /EventClient::/ );

		## Getting LLDP may result in this message on some devices but it's not the LLDP data
		## but the data that follows since it's a getnext kind of thing.  And that data doesn't
		## fit.
		next if ( $curLine =~ /getTable: Message size exceeded buffer maxMsgSize/ ||
		        #NETMRI-19653 : Removal of message displayed during discover now
		        $curLine =~ /getTable: The message size exceeded the buffer maxMsgSize/ ||
			$curLine =~ /getTable: Invalid number of OIDs returned/ ||
			$curLine =~ /Received tooBig/ );

		next if ( $cmd =~ /fingerprint/ && $curLine !~ /^\+\+\+/ );

		if ( $curLine =~ /No response from / ) {
			$curLine = " No response\n";
		}
		if ( $curLine =~ /Received ([\w\.]+)/ ) {
			$curLine = " Received $1\n";
		}

            printProgress $curLine;
            
		if ( $curLine =~ /$testString/ ) {
                	$stringFound = 1;
		}
        }
	print("=doCommand,loop finished, stringFound = '$stringFound'\n")  if ($options{debug});
        if (close CMD_PIPE) {
       
            if ($stringFound) {
		print ("-doCommand: command closed, stringFound is '$stringFound'\n")  if ($options{debug});
                return 1;       # everything looks OK
            } else {
		print("-doCommand: command closed, failure due to stringFound\n")  if ($options{debug});
	    }
        }  elsif ( $!) {
	    print ( "Error closing sort pipe: $!\n");
	}  else {
	    print ("-doCommand: exit status $? from '$cmd'\n") if ($options{debug});
            return 0;
        }
	
	
    } else {
	print ("-doCommand: couldn't invoke command '$cmd'\n")  if ($options{debug});
        return 0;
    }
    
    print("-doCommand: fallthrough case, returning failure\n")  if ($options{debug});
    return 0;
}

sub dispatchGetConfig 
{
    my $sqlHandle = shift;
    my $ipAddress = shift;
    my $config = shift;	# we need some of this information to save files
    my $vnid = shift;

    # This is required to be done before getConfig, it uses it.
    sqlOpen ("root", $config->{mysqlPass});

    my ($deviceID, $vendor, $type, $model, $os_version) = getDeviceInfo($sqlHandle, $ipAddress, $vnid);
    
    my $scriptToUse = lookupConfigScript($vendor);
    if ($scriptToUse ne '') {
		print("=dispatchGetConfig, script $scriptToUse, id '$deviceID'\n") if $options{debug};	
		# we need to pass device related data to getConfig
		# to be able to generate vendor/model specific input file
		# for getting the configs
		my %specParams = (
			vendor => $vendor,
			model => $model
		);
		my $c = getConfigs($scriptToUse, $deviceID, \%specParams);
		print("=dispatchGetConfigs, return from getConfigs = '$c'\n") if $options{debug};
		# we need to verify everything worked by also verifying the 
		# config file itself is present. There are errors where the return
		# can be 1, but nothing happened
		if (($c == 1) && (-f "/tmp/getConfigs-$deviceID/$deviceID-1.log")){
		    # success, so we need to record the info
	    	if (saveConfigFiles($deviceID,$vendor,$type,$model,$os_version,$config)!= -1) {
				printProgress("=dispatchGetConfig, config collection successful, and successfully saved config files\n") if $options{debug};
	    		return 1;
		    } else {
				printProgress("=dispatchGetConfig, config collection successful, but failed to save config files\n") if $options{debug};
				return 0;
		    }
		} elsif ($c != 1) {
	    	printProgress("=dispatchGetConfig, there's a config error during collection, calling captureConfigError() and getting logs\n") if $options{debug};
	    	captureConfigError($c,$deviceID,$vendor,$type,$config, $ipAddress);
	    	return 0;
		} else {
		    # file was missing, error should have been printed by getConfigs, but we need
	    	# to fail
		    if ($options{debug}) {
				printProgress("=dispatchGetConfig, config file missing, try to get logs\n");
				my $path = (-w "/home/admin/chroot-home/mnt/Backup/") ? "/home/admin/chroot-home/mnt/Backup" : "/tmp";
				my $res = system("/bin/tar -czvf $path/DiscoverNowConfigDebug-$deviceID.tgz /tmp/getConfigs-$deviceID/*");
				printProgress('=dispatchGetConfig, ' . $res == 0 ? "logs are saved at $path\n" : "unable to save logs at $path: $@\n");
		    }
	    return 0;
		}
    }
    # get here if we don't have script, hence failure
    return 0;
}

sub getDeviceID{
	my ($sql, $ipAddress, $vnid) = @_;
	my $query = "select DeviceID from $options{netmriDB}.Device where IPAddress = '$ipAddress'";
	if($vnid){
		$query = $query." and VirtualNetworkID=$vnid";
	}
	my %result = $sql->record($query, AllowNoRows => 1);
	return  $result{DeviceID} eq "" ? 0 : $result{DeviceID};
}

sub getDeviceInfo
{
	my $sqlHandle = shift;
	my $ipAddress = shift;
	my $vnid = shift;

	my $sqlCmd = "select DeviceID,Vendor,Type,Model,SWVersion from $options{netmriDB}.Device where IPAddress = '$ipAddress'";
	if($vnid){
		$sqlCmd = $sqlCmd." and VirtualNetworkID=$vnid";
	}
    	print ("=getDeviceInfo, about to sql '$sqlCmd'\n") if $options{debug};
    	my %row = $sqlHandle->record($sqlCmd,AllowNoRows=>1);

	$status{DeviceVendor} = $row{Vendor} if $row{Vendor};
	$status{DeviceType} = $row{Type} if $row{Type};

    # If the device doesn't exist yet, then returns 0 as the DeviceID
    # implementation like as subroutime 'getDeviceID'
	return ($row{DeviceID} || 0, $row{Vendor}, $row{Type}, $row{Model}, $row{SWVersion});
}

# If we are a non-network device and we don't have SNMP credentials, 
# we need to check a router that might have this IP in the 
# ARP table to make sure we've got the correct MAC.

sub checkMACAddress
{
    my $sqlHandle = shift;
    my $ipAddress = shift;
    my $vnid = shift;

    # simply check if the box has SNMP creds and, if we've got them, grab the type
    # in case we need to lock this down to only non-network (end host) checks
    
    my $sqlCmd = "select DeviceID,Type,SNMPReadSecure from $options{netmriDB}.Device where IPAddress = '$ipAddress'";
    if($vnid){
		$sqlCmd = $sqlCmd." and VirtualNetworkID=$vnid";
    }
    my %row = $sqlHandle->record($sqlCmd,AllowNoRows=>1);
    # Note: we don't need to decrypt the commstring/username(V3), we just care if it's set
    if ($row{SNMPReadSecure} eq '') {
	# No credentials found, so we're assuming this one's one we need
	# Now we need to get a router that should have this in the 
	# ARP table
	$sqlCmd = "select d.DeviceID, d.IPAddress as RouterIP, d.Name, d.Type, d.LastTimestamp, ifa.ifIndex,ifa.IPAddressDotted from $options{netmriDB}.Device d, $options{netmriDB}.ifAddr ifa where d.DeviceID=ifa.DeviceID and $options{reportDB}.subnet_has_ip(ifa.SubnetIPNumeric,ifa.NetMask,$options{reportDB}.inet_pton('$ipAddress')) order by NetMask desc limit 1;";
	my %routerRow = $sqlHandle->record($sqlCmd,AllowNoRows=>1);
	if ($routerRow{DeviceID} ne '') {
	    # We need a time check to make sure we don't get a router that's
	    # already refreshed. 
	    # now we need to force a retrieve of the MAC address. The test utility will do that via SNMP
	    # request to the same subnet router. The assumption is that that router is up to date
	    doCommand("$skipjack/app/transaction/netmri/collectors/dataEngine/test $routerRow{RouterIP} --arpIfIndex $routerRow{ifIndex} "
		      . " --arpIP $ipAddress --arpDevID $row{DeviceID} macFromArp"
		      .($vnid? " -virtual_network_id $vnid" : ""));

	} else {
	    print("No router found for IP $ipAddress, no MAC correction needed\n");
	}
    } else {
	print("IP $ipAddress has valid credentials, no MAC probe needed\n");
    }
	
    
#
}

# uses the database flag to see if we support CLI. We assume that we're 
# being run on the netmri collector that's responsible for a given device.

sub deviceSupportsCLI
{
	my $sqlHandle = shift;
	my $ipAddress = shift;

	# technically, we may want to get teh device ID and stash it away, we
	# need it for one of the actions, but I don't want to disrupt more
	# code for the NETMRI-8674 fix than I need to.

	# The change below will not break the fix for NETMRI-8674 because ConfigGroup 
	# will only contain the list of devices for which NetMRI provides config collection support
	my $sqlCmd = "select cg.LoginCmd from "
	    . "$options{netmriDB}.Device d, "
	    . "$options{netmriDB}.ConfigGroup cg "
	    . " where d.IPAddress = '$ipAddress' "
	    . " and (d.Vendor = cg.Vendor) "
	    . " and (d.Type = cg.Type or cg.Type is null) "
	    . " and (d.Model = cg.Model or cg.Model is null) "
	    . " and (d.SWVersion = cg.SWVersion or cg.SWVersion is null) "
            . " order by cg.SWVersion desc, cg.Model desc, cg.Type desc "
            . " limit 1 "
	;

    	print ("=deviceSupportsCLI, about to sql '$sqlCmd'\n") if $options{debug};
    	my %row = $sqlHandle->record($sqlCmd,AllowNoRows=>1);
	if ($row{LoginCmd} ne '' && $row{LoginCmd} ne 'DISABLED') {
	    return 1;		# we support
	}

	return 0;		# we reach here, we don't support
}

sub lookupConfigScript 
{
	my $vendor = shift;

	my $scriptName = `/tools/skipjack/app/WEB-INF/transaction/netmri/collectors/config/getCCSFile.pl '$vendor'`;
	chomp $scriptName;

	$scriptName =~ s/^FILE://;

	return $scriptName if (-e $scriptName);

	print "We do not currently support vendor '$vendor' for config collection\n";
	return "";
}

# This sub is a wrapper to set up the data for the ConfigSuccessHandler.pl

sub saveConfigFiles 
{
    my ($deviceID, $vendor, $type, $model, $os_version, $config) = @_;

    print("+saveConfigFiles, deviceID '$deviceID' vendor '$vendor' type '$type'\n") if $options{debug};

    my $configScriptDir = $config->{skipjack}
       . "/app/WEB-INF/transaction/netmri/collectors/config/";
    my $tmpRunningFile = "/tmp/getConfigs-$deviceID/$deviceID-1.log";
    my $tmpSavedFile = "/tmp/getConfigs-$deviceID/$deviceID-2.log";
    my $tmpSessionFile = "/tmp/getConfigs-$deviceID/session.log";
    my $sessionLocation = "/tmp/$deviceID-session.log";
    my $tmpHistoryFile = '';	# no history file known
    my $runningFile = $config->{CvsConfigClientRoot} .
	"/".$config->{CvsRunningConfigDir}."/".$deviceID;
    my $savedFile = $config->{CvsConfigClientRoot} .
	"/".$config->{CvsSavedConfigDir}."/".$deviceID;
    my $historyFile = '';
    my $cvsServerRoot = $config->{CvsServerRoot};
    my $cvsTimestamp = NetMRI::Util::Date::resolveDate('now'); # format we need
    my $accessProtocol = getAccessProtocol();

    my $sqlStmt = "select * from ((select group_concat(SectionName, ':', MD5Checksum) as md5sums, 
                                        group_concat(SectionName, ':', MD5ChecksumComparison) as md5sumsComparison,
                                        group_concat(SectionName, ':', MD5ChecksumRunToSaved) as md5sumsRunToSaved,
                                        'Running' as type
                                     from $options{reportDB}.ConfigRevisionMD5
                                    where DeviceID='$deviceID'
                                      and ConfigType='Running'
                                      and ConfigTimestamp=(select max(ConfigTimestamp)
                                                             from $options{reportDB}.ConfigRevisionMD5
                                                            where DeviceID='$deviceID'
                                                              and ConfigType='Running')
                                    group by DeviceID,ConfigType,ConfigTimestamp
                            ) union (
                                     select group_concat(SectionName, ':', MD5Checksum) as md5sums, 
                                    group_concat(SectionName, ':', MD5ChecksumComparison) as md5sumsComparison,
                                    group_concat(SectionName, ':', MD5ChecksumRunToSaved) as md5sumsRunToSaved,
                                    'Saved' as type
                                       from $options{reportDB}.ConfigRevisionMD5
                                      where DeviceID='$deviceID'
                                        and ConfigType='Saved'
                                        and ConfigTimestamp=(select max(ConfigTimestamp)
                                                               from $options{reportDB}.ConfigRevisionMD5
                                                              where DeviceID = '$deviceID'
                                                                and ConfigType = 'Saved' )
                                      group by DeviceID,ConfigType,ConfigTimestamp
                            )) as abc";

    my @rows = $sql->table($sqlStmt);
    my $md5s = { map {$_->{type} => {'noise' => $_->{md5sums}, 'comparison' => $_->{md5sumsComparison}, 'runtosaved' => $_->{md5sumsRunToSaved}, }} @rows };

	my $sys_descr = {$sql->record("select DeviceSysDescr from $options{reportDB}.InfraDevice where DeviceID = '$deviceID'",
								  AllowNoRows => 1)}->{DeviceSysDescr};
	my $accessSupport = {$sql->record("select Value from $options{netmriDB}.DeviceProperty " .
									  "where DeviceID = '$deviceID' and PropertyName = 'VendorSupportTag_Access'",
									  AllowNoRows => 1)}->{Value};

	if ($options{debug}) {
		my $debug_ts = NetMRI::Util::Date::resolveDate('now');
		$debug_ts =~ s/ /_/g;
		my $path = (-w "/home/admin/chroot-home/mnt/Backup/") ? "/home/admin/chroot-home/mnt/Backup" : "/tmp";
		my $res = system("/bin/tar -czvf $path/DiscoverNowConfigDebug-$deviceID-$debug_ts.tgz /tmp/getConfigs-$deviceID/*");
		if($res == 0){
			printProgress("=dispatchGetConfig, logs are saved at $path\n");
		}else{
			printProgress("=dispatchGetConfig, unable to save logs at $path: $@\n");
		}
	}
    # we need to makes sure that the files are owned properly so
    # we don't cause a problem for the normal channel
    if (-e "/tmp/getConfigs-$deviceID") {
	doCommand("/bin/chown -R netmri.users /tmp/getConfigs-$deviceID");
    }
    my $cmd = $configScriptDir . "ConfigSuccessHandler.pl";

    if ( !open(PIPE, "| $cmd") ) {
	die "Unable to run command ($cmd): $!\n";
    }
    else {
    	print PIPE "DeviceID\t$deviceID\n";
    	print PIPE "Vendor\t$vendor\n";
    	print PIPE "Type\t$type\n";
        print PIPE "Model\t$model\n";
        print PIPE "OSVersion\t$os_version\n";
        print PIPE "SysDescription\t$sys_descr\n";
    	print PIPE "TempSessionFile\t$tmpSessionFile\n";
    	print PIPE "CurrentSessionFile\t$sessionLocation\n";
    	print PIPE "TempRunningFile\t$tmpRunningFile\n";
    	print PIPE "RunningFile\t$runningFile\n";
    	print PIPE "RunningMD5\t$$md5s{Running}{noise}\n" if $md5s->{Running};
    	print PIPE "RunningMD5Comparison\t$$md5s{Running}{comparison}\n" if $md5s->{Running};
    	print PIPE "TempSavedFile\t$tmpSavedFile\n";
    	print PIPE "SavedFile\t$savedFile\n";
    	print PIPE "SavedMD5\t$$md5s{Saved}{noise}\n" if $md5s->{Saved};
    	print PIPE "SavedMD5Comparison\t$$md5s{Saved}{comparison}\n" if $md5s->{Saved};
    	print PIPE "SavedMD5RunToSaved\t$$md5s{Saved}{runtosaved}\n" if $md5s->{Saved};
    	print PIPE "TempHistoryFile\t$tmpHistoryFile\n";
    	print PIPE "HistoryFile\t$historyFile\n";
    	print PIPE "CvsServerRoot\t$cvsServerRoot\n";
    	print PIPE "CvsTimestamp\t$cvsTimestamp\n";
    	print PIPE "AccessProtocol\t$accessProtocol\n";
    	print PIPE "DeviceAccessSupportTag\t$accessSupport\n";
    	print PIPE "TrackingID\t0\n";
    	close (PIPE);
    }
    my $ret = $?;

    # change the new file owners to make sure nothing gets broken
    if (-f "/var/local/netmri/cvsclient/config/running/$deviceID") {
	doCommand("/bin/chown  netmri.users /var/local/netmri/cvsclient/config/running/$deviceID");
    }
    if (-f "/var/local/netmri/cvsclient/config/saved/$deviceID") {
	doCommand("/bin/chown  netmri.users /var/local/netmri/cvsclient/config/saved/$deviceID");
    }
    return $ret;
}

# This should be called if the config threw an error (similar to the ConfigCollector.tdf)
sub captureConfigError
{
    my $errorID = shift;
    my $deviceID = shift;
    my $vendor = shift;
    my $type = shift;   
    my $config = shift;		# needed for looking up stuff.
	my $ipAddress = shift;
	my $message = shift;
    my $accessProtocol = getAccessProtocol();

    print("+captureConfigError, deviceID '$deviceID' vendor '$vendor' type $type error $errorID config $config proto $accessProtocol\n") if $options{debug};	

    my $configScriptDir = $config->{skipjack}
       . "/app/WEB-INF/transaction/netmri/collectors/config/";
    my $tmpRunningFile = "/tmp/getConfigs-$deviceID/$deviceID-1.log";
    my $tmpSavedFile = "/tmp/getConfigs-$deviceID/$deviceID-2.log";
    my $tmpSessionFile = "/tmp/getConfigs-$deviceID/session.log";
    my $tmpHistoryFile = '';	# no history file known
    my $errorDir = $config->{ConfigErrorDir};
	my $port = $accessProtocol eq 'ssh' ? 22 : $accessProtocol eq 'http' ? 80 : 23;

	my $error_message = 'Check Device Viewer for Details.'; # For legacy mode
	unless (lc($vendor) eq 'cisco' && (lc($type) eq 'comm server' ||
						lc($type) eq 'voip gateway' || 
	 					lc($type) eq 'vpn' || 
						lc($type) eq 'wireless ap'))
	{
		# Getting error message populated in CCS Engine
		$error_message = {$sql->record("select Value as ErrMsg from $options{netmriDB}.DeviceProperty 
						where DeviceID = '$deviceID' and PropertyName = 'ConfigErrorMsg'",AllowNoRows => 1)}->{ErrMsg};
		printProgress("+captureConfigError, error_message = '$error_message'\n") if $options{debug};
	}
	my $accessSupport = {$sql->record("select Value from $options{netmriDB}.DeviceProperty 
					   where DeviceID = '$deviceID' and PropertyName = 'VendorSupportTag_Access'", AllowNoRows => 1)}->{Value};

	if ($options{debug}) {
		my $debug_ts = NetMRI::Util::Date::resolveDate('now');
		$debug_ts =~ s/ /_/g;
		my $path = (-w "/home/admin/chroot-home/mnt/Backup/") ? "/home/admin/chroot-home/mnt/Backup" : "/tmp";
		my $res = system("/bin/tar -czvf $path/DiscoverNowConfigDebug-$deviceID-$debug_ts.tgz /tmp/getConfigs-$deviceID/*");
		if($res == 0){
			printProgress("=dispatchGetConfig, logs are saved at $path\n");
		}else{
			printProgress("=dispatchGetConfig, unable to save logs at $path: $@\n");
		}
	}

    # we need to makes sure that the files are owned properly so
    # we don't cause a problem for the normal channel
    if (-e "/tmp/getConfigs-$deviceID") {
        doCommand("/bin/chown -R netmri.users /tmp/getConfigs-$deviceID");
    }
    if ( !open(PIPE, "| ${configScriptDir}ConfigErrorHandler.pl") ) {
	die "Unable to run ConfigErrorHandler: $!\n";
    }
    else {
	print PIPE "ErrorDir\t$errorDir\n";
	print PIPE "ErrorID\t$errorID\n";
	print PIPE "DeviceID\t$deviceID\n";
	print PIPE "Vendor\t$vendor\n";
	print PIPE "Type\t$type\n";
	print PIPE "TempSessionFile\t$tmpSessionFile\n";
	print PIPE "TempRunningFile\t$tmpRunningFile\n";
	print PIPE "TempSavedFile\t$tmpSavedFile\n";
	print PIPE "TempHistoryFile\t$tmpHistoryFile\n";
	print PIPE "CollectProtocol\t$accessProtocol\n";
	print PIPE "CollectTimestamp\t" . NetMRI::Util::Date::resolveDate('now') . "\n";
	print PIPE "CollectIPDotted\t$ipAddress\n";
	print PIPE "SourceIPDotted\t\n";
	print PIPE "ErrorMessage\t$error_message\n";
	print PIPE "CollectPort\t$port\n";
	print PIPE "DeviceAccessSupportTag\t$accessSupport\n";
	print PIPE "TrackingID\t0\n";

	close (PIPE);
    }
}

sub die_with_error
{
	my $e = shift;
	my $m = shift;

	$status{error} = $e;
	$status{message} = $m;
	die "$m\n";
}

sub sendJSON
{
	return unless $options{json} > 0;
	$status{returncode} = $?;
	if (open(my $fh, ">>&=", $options{json})) {
		print $fh to_json(\%status),"\n";
		close($fh);
	}
}

sub consolidate
{
    system("/tools/skipjack/app/WEB-INF/transaction/netmri/maintenance/consolidate.pl -w 120 -type Normal 2>&1 >/dev/null");
    $status{"consolidate"} = $?;
}
