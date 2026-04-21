package NetMRI::HTTP::Client::VeloCloud;

use strict;
use warnings;
use NetMRI::HTTP::Client::Generic;
use URI::Escape qw(uri_escape);
use base 'NetMRI::HTTP::Client::Generic';

# VeloCloud SD-WAN Orchestrator v2 REST API client.
#
# Authentication: Authorization: Token <api_token>
# Generate tokens in:  Orchestrator UI -> Administration -> API Tokens
#
# API base: https://<vco-hostname>/api/sdwan/v2/
#
# Reference: VMware VeloCloud SD-WAN 6.4 Orchestrator OpenAPI Guide

my $default_api_version = 'sdwan/v2';
my $default_base_uri    = 'https://example.invalid/api/%version%/';

sub new {
    my $class = shift;
    my %args  = @_;

    for my $required (qw(api_key fabric_id)) {
        die "NetMRI::HTTP::Client::VeloCloud: required parameter '$required' is missing\n"
            unless defined $args{$required} && length $args{$required};
    }

    # Build base URL: accept explicit `address` (hostname or IP) or a fully-formed `base`.
    $args{base} ||= $args{address}
        ? "https://$args{address}/api/\%version\%/"
        : $default_base_uri;

    # VeloCloud uses "Authorization: Token <token>" — not Bearer.
    $args{auth_token_request_header} = 'Authorization';
    $args{api_key}                   = "Token $args{api_key}"
        unless $args{api_key} =~ /^Token /i;

    $args{requests_per_second} //= 3;

    my $self = $class->SUPER::new(%args);
    $self->{fabric_id}                        = $args{fabric_id};
    $self->{supported_version}                = $default_api_version;
    $self->{max_iterations_for_paginated_data} ||= 100;

    $self->base();   # resolve %version% placeholder in base URL
    return bless $self, $class;
}

sub get_throttle_key {
    my $self = shift;
    return $self->{fabric_id} || 'Global';
}

# Return true when the API signals rate-limiting (HTTP 429).
sub too_many_requests_response {
    my ($self, $res) = @_;
    return (
        !$res->{success}
        && defined $res->{data}{error}{code}
        && $res->{data}{error}{code} == 429
    ) ? 1 : 0;
}

# -----------------------------------------------------------------------
# Private helpers
# -----------------------------------------------------------------------

# Low-level GET.  Returns ($data, undef) on success or (undef, $message) on error.
sub _velocloud_get {
    my ($self, $uri, $params) = @_;
    $params //= {};
    my $res = $self->get($uri, $self->{supported_version}, $params);
    if ($res->{success} && exists $res->{data}) {
        return $res->{data};
    }
    my $msg = $res->{data}{error}{message}
           // $self->{response}{_content}
           // 'Unknown error';
    return (undef, $msg);
}

# GET with Link-header pagination (rel=next style used by VeloCloud v2).
# Returns (\@all_items, undef) on success or (undef, $message) on error.
sub _velocloud_get_pages {
    my ($self, $uri, $params) = @_;
    $params //= {};
    my @all;
    my $max  = $self->{max_iterations_for_paginated_data};
    my $iter = 0;

    while (1) {
        my ($pool, $err) = $self->_velocloud_get($uri, $params);
        return (undef, $err) if defined $err;

        push @all, ref($pool) eq 'ARRAY' ? @$pool : $pool;

        # VeloCloud v2 paginates via Link: <url>; rel="next"
        my $next;
        if (ref($self->{response}) && $self->{response}->can('header')) {
            my $link = $self->{response}->header('link') // '';
            ($next) = $link =~ m{\<([^>]+)\>\s*;\s*rel=["']?next["']?};
        }
        last unless $next;

        $uri    = $next;
        $params = {};   # next-page URL already encodes all query params
        last if ++$iter >= $max;
    }

    return \@all;
}

# -----------------------------------------------------------------------
# Public API Operations
# -----------------------------------------------------------------------

# GET /api/sdwan/v2/enterprises/
# Returns an array-ref of enterprise objects.
# Each enterprise includes: logicalId, name, domain, accountNumber, timezone, ...
sub get_enterprises {
    my ($self, $params) = @_;
    return $self->_velocloud_get_pages('enterprises/', $params);
}

# GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/clientDevices
# Returns an array-ref of client (non-edge) endpoint device objects.
# Each device includes: id, logicalId, name, ipAddress, macAddress, vendor, model,
#                       serialNumber, softwareVersion, status.
sub get_enterprise_client_devices {
    my ($self, $enterprise_logical_id, $params) = @_;
    die "get_enterprise_client_devices: enterpriseLogicalId is required\n"
        unless defined $enterprise_logical_id && length $enterprise_logical_id;

    my $uri = 'enterprises/' . uri_escape($enterprise_logical_id) . '/clientDevices';
    return $self->_velocloud_get_pages($uri, $params);
}

# GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges
# Returns an array-ref of VeloCloud Edge objects for an enterprise.
# Each edge includes: logicalId, name, model, serialNumber, softwareVersion,
#                     ipAddress (management IP), interfaces[], gatewayLogicalId.
sub get_enterprise_edges {
    my ($self, $enterprise_logical_id, $params) = @_;
    die "get_enterprise_edges: enterpriseLogicalId is required\n"
        unless defined $enterprise_logical_id && length $enterprise_logical_id;

    my $uri = 'enterprises/' . uri_escape($enterprise_logical_id) . '/edges';
    return $self->_velocloud_get_pages($uri, $params);
}

# GET /api/sdwan/v2/gateways/{gatewayLogicalId}/
# Returns a single gateway/edge detail object including:
#   interfaces[]   — interface configs with ipAddress, subnetMask, name, status
#   bgpPeers[]     — BGP peer table: peerIp, asn, state, routesAdvertised, routesReceived
#   ipRoutes[]     — IP routing table: destination, nextHop, metric, protocol
#   cpuUsage, memoryUsage, uptime — performance counters
sub get_gateway_details {
    my ($self, $gateway_logical_id) = @_;
    die "get_gateway_details: gatewayLogicalId is required\n"
        unless defined $gateway_logical_id && length $gateway_logical_id;

    my $uri = 'gateways/' . uri_escape($gateway_logical_id) . '/';
    return $self->_velocloud_get($uri);
}

1;
