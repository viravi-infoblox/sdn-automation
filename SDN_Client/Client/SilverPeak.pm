package NetMRI::HTTP::Client::SilverPeak;

use strict;
use NetMRI::LoggerShare;
use NetMRI::HTTP::Client::Generic;
use Data::Dumper;
use JSON;
use URI;
use base 'NetMRI::HTTP::Client::Generic';

my %args;

sub new {
    my $class = shift;
    my %args = @_;
    
    for my $option (qw(address api_key fabric_id)) {
        die "Required parameter $option is not provided" unless ($args{$option});
    }
    $args{base} = "https://$args{address}/gms/rest/";
    $args{auth_token_request_header} = 'X-Auth-Token';
    $args{no_cert_check} = 1;
    my $self = $class->SUPER::new(%args);
    $self->{fabric_id} = $args{fabric_id};

    $self->{supported_version} = "";
    $self->base();
    
    return bless $self, $class;
}

sub silverpeak_request {
    my ($self, $uri, $api_version, $params) = @_;
    my $res = $self->get($uri, $api_version, $params);
    
    if ($res->{success} && exists($res->{data})) {
        return $res->{data};
    } elsif ($res->{data}->{error}->{code} == 404) {
        return (undef, $self->{response}->{_content} || "Bad Request");
    }
    
    return (undef, $res->{data}->{error}->{message});
}

sub silverpeak_post_request {
    my ($self, $uri,$api_version, $data) = @_;
    my $res = $self->post($uri,$api_version,$data);
    
    if ($res->{success} && exists($res->{data})) {
        return $res->{data};
    } elsif ($res->{data}->{error}->{code} == 404) {
        return (undef, $self->{response}->{_content} || "Bad Request");
    }

    return (undef, $res->{data}->{error}->{message});
}

sub get_apiKey {
    my $self = shift;
    my $params = shift;
    $params = {} unless ref($params) eq 'HASH';
    
    return $self->silverpeak_request("apiKey", undef, $params);
}

sub get_silverpeak_devices {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    
    return $self->silverpeak_request("appliance", undef, $params);
}

sub get_silverpeak_intf {
    my ($self, $deviceid, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    my $uri = "interfaceState/$deviceid";

    return $self->silverpeak_request($uri, undef, $params);
}

sub get_silverpeak_arp {
    my ($self, $deviceid, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';

    my $uri = "broadcastCli";
    my $data = {
        cmdList => ["show arp"],
        neList  => [$deviceid]
    };

    my $json_data = encode_json($data);

    my $arptoken = $self->silverpeak_post_request($uri, undef, $json_data);

    $uri = "action/status?key=$arptoken";

    my $timeout = 30;  # Timeout after 30 seconds
    my $interval = 2;  # Poll every 2 seconds
    my $elapsed = 0;
    my $res;

    while ($elapsed < $timeout) {
        $res = $self->silverpeak_request($uri, undef, $params);
        print "res value sunder get silver arp" .Dumper($res) ."\n". "elapsed time = $elapsed" ."\n";
        if ($res && ref($res) eq 'ARRAY' && @$res) {
            my $task = $res->[0];
            if ($task->{taskStatus} eq 'COMPLETED') {
                return $task->{result};
            } elsif ($task->{taskStatus} eq 'FAILED') {
                die "Task failed with message: " . $task->{result};
            }
        }

        sleep($interval);
        $elapsed += $interval;
    }
}

sub get_silverpeak_route {
    my ($self, $deviceid, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    my $uri = "subnets/true/$deviceid";

    return $self->silverpeak_request($uri, undef, $params);
}

1;
