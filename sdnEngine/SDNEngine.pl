#!/usr/bin/perl
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::Fork;
use AnyEvent::Fork::RPC;
use AnyEvent::Fork::Pool;
use POSIX;
use Redis;
use NetMRI::Config;
use NetMRI::LoggerShare qw(logOpen logSetID logGetLog logInfo logWarn logError);
use NetMRI::SdnEngine::Util qw(set_loglevel);
use NetMRI::SdnEngine::Scheduler;

use Data::Dumper;

$0 = 'SDNEngine:scheduler';
our $redis_path = '/SDNEngine';
our $skipjack = '/tools/skipjack';
logOpen("$skipjack/logs/SDNEngine.log", 'NetMRI.Discovery');
logSetID ("scheduler");
set_loglevel();

# SdnDiscovery (a.k.a. 'Enable SDN/SD-WAN polling' checkbox) is stored as advanced setting
$main::CONFIG = NetMRI::Config->new();
$main::NETMRI_DB = 'netmri';
$main::CONFIG_DB = 'config';
$main::REPORT_DB = 'report';
$main::redis_reconnect_timeout = 300;

my $finish = AE::cv;
my $sched;
# Redirect warnings to log
$SIG{__DIE__} = sub {
    my $message = shift;
    logError($message);
    return 1;
};
$SIG{__WARN__} = sub {
    my $message = shift;
    logWarn($message);
    return 1;
};
$SIG{QUIT} = $SIG{INT} = $SIG{TERM} = sub {
    logInfo("Caught signal, stopping...");
    $finish->send;
    return 1;
};
$SIG{CHLD} = 'IGNORE';

# NOTE: You cannot send signals to workers because it breaks their communication with parent. 
# Workers check for debug flags automatically every iteration
$SIG{HUP} = sub {
    set_loglevel();
    $main::CONFIG->load();
    $sched->monitor_schedule() if $sched;
    return 1;
};

# Clean up Redis share
my $redis =  Redis->new(reconnect => $main::redis_reconnect_timeout);
foreach my $key ($redis->keys("$redis_path/*")) {
    $redis->del($key);
}

$sched = NetMRI::SdnEngine::Scheduler->new(types => ['SDN'], log => NetMRI::LoggerShare::logGetLog());
$sched->init();
$sched->monitor_schedule();

my $config_refresh_interval = 600;
my $config_refresh_timer = AnyEvent->timer(after=> $config_refresh_interval, interval => $config_refresh_interval, cb => sub {set_loglevel(); $main::CONFIG->load(); $sched->monitor_schedule();});

# This is how the daemon can be shut down
#my $w = AnyEvent->timer(after => 120, cb => sub {$finish->send});

# Blocking on this condvar will keep event loop running
$finish->recv;
# Cleanup code beyond this point
$sched->_stop_monitoring_schedule() if $sched; 

logInfo("Main process exits");

exit(0);
