#!/usr/bin/perl
use strict;
use warnings;
use POSIX;
use NetMRI::Util::Process;
use NetMRI::Config;
use File::Basename;
use Data::Dumper;

use NetMRI::SdnEngine::Scheduler;

our $skipjack = '/tools/skipjack';
my ($script_filename, $script_dirname, undef) = File::Basename::fileparse($0);
my $config = NetMRI::Config->new(SkipAdvanced => 1);
my $command =  lc(shift(@ARGV));
if ($command eq 'start') {
    if($$config{NetMRIMode} eq "master") {
		print "Not supported in master mode\n";
		exit(0);
	}
    start_daemon();
} elsif ($command eq 'stop') {
    stop_daemon();
} elsif ($command eq 'restart') {
    stop_daemon();
    start_daemon();
} else {
    print "Unknown command $command\nValid commands are start|stop|restart\n";
    exit(-1);
}

# Fork, detach and exec the daemon proper
sub start_daemon {
    my @procs = NetMRI::Util::Process::getProcessByTag("SDNEngine:scheduler");
    if (scalar(@procs)) {
        print "SDN Engine already running on PID ".join(',', @procs)."\n";
        exit(1);
    }
    my $pid = fork();
    die "can't fork: $!" unless (defined $pid);
    if ($pid) {
        # This happens in parent
        exit 0;
    } else {
        my @pwline = NetMRI::Util::Process::getNetMRIUserUID();
        my $uid = $pwline[2] || $>;
        my $gid = $pwline[3] || POSIX::getgid();
        if ( -e "$skipjack/logs/SDNEngine.log" ) {
            chown $uid, $gid, glob("$skipjack/logs/SDNEngine.log*");
        }

        # This happens in the child
        POSIX::setsid(); 
        setpgrp(0,0);
        NetMRI::Util::Process::runAsNetMRIUser();
        open (STDIN, "</dev/null");
        open (STDOUT, ">/dev/null");
        open (STDERR,">&STDOUT");
        exec($script_dirname."SDNEngine.pl");
    }
}

sub stop_daemon {
    NetMRI::Util::Process::killProc('SDNEngine:scheduler');
    NetMRI::Util::Process::killProc('SDNEngine:worker');
}
