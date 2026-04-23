package NetMRI::HTTP::Client::VeloCloud;

use strict;
use warnings;

use NetMRI::HTTP::Client::Generic;
use URI::Escape qw(uri_escape);
use base 'NetMRI::HTTP::Client::Generic';

# BEFORE FIRST USE (replace placeholders):
# 1) VeloCloud
# 2) sdwan/v2
# 3) https://example.invalid/api/\%version\%/ (must include %version% token if versioned API)
# 4) Authorization
# 5) token (bearer | api_key | basic | cookie | none)
# 6) For each operation block: __operation_method_name__, __OPENAPI_PATH__, __HTTP_METHOD__
# 7) Add required path parameter substitutions in each operation method.

# Generic Phase-2 template for new SDN vendors.
# Replace placeholders and keep only the hooks required by the target API.
my $default_api_version = 'sdwan/v2';
my $default_base_uri = 'https://example.invalid/api/\%version\%/';
my $auth_token_request_header = 'Authorization';
my $default_auth_mode = 'token'; # bearer | api_key | basic | cookie | none

sub new {
    my $class = shift;
    my %args = @_;

    for my $required (qw(api_key fabric_id)) {
        die "NetMRI::HTTP::Client::VeloCloud: required parameter '$required' is missing\n"
            unless defined $args{$required} && length $args{$required};
    }

    $args{base} ||= $args{address}
        ? "https://$args{address}/\%version\%/"
        : $default_base_uri;

    $args{auth_token_request_header} ||= $args{auth_header} || $auth_token_request_header;
    $args{requests_per_second} //= 3;

    # Transport toggles can be injected from controller config.
    $args{timeout} = $args{timeout} if defined $args{timeout};
    $args{no_cert_check} = $args{no_cert_check} if defined $args{no_cert_check};

    # Vendor authentication format: Token <token>
    $args{auth_token_request_header} = 'Authorization';
    if (defined $args{api_key} && length $args{api_key}) {
        $args{api_key} = "Token $args{api_key}"
            unless $args{api_key} =~ /^Token /i;
    }

    my $self = $class->SUPER::new(%args);
    $self->{fabric_id} = $args{fabric_id};
    $self->{supported_version} = $default_api_version;
    $self->{max_iterations_for_paginated_data} ||= 100;

    $self->base();
    return bless $self, $class;
}

sub get_throttle_key {
    my $self = shift;
    return $self->{fabric_id} || 'Global';
}

sub too_many_requests_response {
    my ($self, $res) = @_;
    my $flg = (!$res->{success} && $res->{data}->{error}->{code} && $res->{data}->{error}->{code} == 429);
    return $flg;
}

sub api_request {
    my ($self, $method, $uri, $params, $api_version) = @_;
    $method ||= 'get';
    my $version = $api_version || $self->{supported_version};

    my $res;
    if (lc($method) eq 'post') {
        $res = $self->post($uri, $version, $params || {});
    } elsif (lc($method) eq 'put') {
        $res = $self->put($uri, $version, $params || {});
    } elsif (lc($method) eq 'patch') {
        $res = $self->patch($uri, $version, $params || {});
    } elsif (lc($method) eq 'delete') {
        $res = $self->delete($uri, $version, $params || {});
    } else {
        $res = $self->get($uri, $version, $params || {});
    }

    if ($res->{success} && exists($res->{data})) {
        return $res->{data};
    }

    if ($res->{data}->{error}->{code} == 400) {
        return (undef, $self->{response}->{_content} || 'Bad Request');
    }

    return (undef, $res->{data}->{error}->{message});
}

sub collect_paginated {
    my ($self, $method, $uri, $api_version, $params) = @_;
    my @all;
    my $max_pages = 100;
    my $page = 0;

    while (1) {
        my ($body, $err) = $self->api_request($method, $uri, $params, $api_version);
        return (undef, $err) if $err;

        # Extract data array from response body
        my $items = ref($body) eq 'HASH' ? $body->{'data'} : $body;
        push @all, ref($items) eq 'ARRAY' ? @$items : $items if defined $items;

        # Check for next-page cursor in response body
        my $next_cursor;
        if (ref($body) eq 'HASH') {
            $next_cursor = $body->{'metaData'}{'nextPageLink'};
        }
        last unless defined $next_cursor && length $next_cursor;

        # Append cursor to query params for next request
        $params = ref($params) eq 'HASH' ? { %$params } : {};
        $params->{'nextPageLink'} = $next_cursor;

        last if ++$page >= $max_pages;
    }

    return \@all;
}

# Generated/OpenAPI operation method template.
# Copy this block per operationId mapped in the reviewed Phase-1 payload.
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

sub _velocloud_get_pages {
    my ($self, $uri, $params) = @_;
    $params //= {};
    my @all;
    my $max  = $self->{max_iterations_for_paginated_data};
    my $iter = 0;

    while (1) {
        my ($body, $err) = $self->_velocloud_get($uri, $params);
        return (undef, $err) if defined $err;

        my $items = ref($body) eq 'HASH' ? $body->{'data'} : $body;
        push @all, ref($items) eq 'ARRAY' ? @$items : $items if defined $items;

        my $next;
        if (ref($body) eq 'HASH') {
            $next = $body->{'metaData'}{'nextPageLink'};
        }
        # Also check Link header as fallback
        unless ($next) {
            if (ref($self->{response}) && $self->{response}->can('header')) {
                my $link = $self->{response}->header('link') // '';
                ($next) = $link =~ m{\<([^>]+)\>\s*;\s*rel=["']?next["']?};
            }
        }
        last unless $next;

        if ($next =~ m{^https?://}) {
            $uri = $next;
            $params = {};
        } else {
            $params = ref($params) eq 'HASH' ? { %$params } : {};
            $params->{nextPageLink} = $next;
        }
        last if ++$iter >= $max;
    }

    return \@all;
}

sub v2_list_enterprises {
    my ($self, $params) = @_;
    return $self->_velocloud_get_pages('enterprises/', $params);
}

sub v2_get_edge_flowstats {
    my ($self, $enterpriseLogicalId, $edgeLogicalId, $params) = @_;
    die "v2_get_edge_flowstats: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;
    die "v2_get_edge_flowstats: edgeLogicalId is required\n"
        unless defined $edgeLogicalId && length $edgeLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/edges/' . uri_escape($edgeLogicalId) . '/flowStats';
    return $self->_velocloud_get($uri, $params);
}

sub v2_get_edge_non_sdwan_tunnel_status {
    my ($self, $enterpriseLogicalId, $edgeLogicalId, $params) = @_;
    die "v2_get_edge_non_sdwan_tunnel_status: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;
    die "v2_get_edge_non_sdwan_tunnel_status: edgeLogicalId is required\n"
        unless defined $edgeLogicalId && length $edgeLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/edges/' . uri_escape($edgeLogicalId) . '/nonSdWanTunnelStatus';
    return $self->_velocloud_get($uri, $params);
}

sub v2_get_edge_qos {
    my ($self, $enterpriseLogicalId, $edgeLogicalId, $params) = @_;
    die "v2_get_edge_qos: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;
    die "v2_get_edge_qos: edgeLogicalId is required\n"
        unless defined $edgeLogicalId && length $edgeLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/edges/' . uri_escape($edgeLogicalId) . '/qos';
    return $self->_velocloud_get($uri, $params);
}

sub v2_get_edge_linkqualitystats {
    my ($self, $enterpriseLogicalId, $edgeLogicalId, $params) = @_;
    die "v2_get_edge_linkqualitystats: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;
    die "v2_get_edge_linkqualitystats: edgeLogicalId is required\n"
        unless defined $edgeLogicalId && length $edgeLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/edges/' . uri_escape($edgeLogicalId) . '/linkQualityStats';
    return $self->_velocloud_get($uri, $params);
}

sub v2_list_enterprise_client_devices {
    my ($self, $enterpriseLogicalId, $params) = @_;
    die "v2_list_enterprise_client_devices: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/clientDevices';
    return $self->_velocloud_get_pages($uri, $params);
}

sub v2_get_edge_healthstats {
    my ($self, $enterpriseLogicalId, $edgeLogicalId, $params) = @_;
    die "v2_get_edge_healthstats: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;
    die "v2_get_edge_healthstats: edgeLogicalId is required\n"
        unless defined $edgeLogicalId && length $edgeLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/edges/' . uri_escape($edgeLogicalId) . '/healthStats';
    return $self->_velocloud_get($uri, $params);
}

sub v2_get_enterprise_bgp_sessions {
    my ($self, $enterpriseLogicalId, $params) = @_;
    die "v2_get_enterprise_bgp_sessions: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/bgpSessions';
    return $self->_velocloud_get($uri, $params);
}

sub v2_get_edge_firewallidpsstats {
    my ($self, $enterpriseLogicalId, $edgeLogicalId, $params) = @_;
    die "v2_get_edge_firewallidpsstats: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;
    die "v2_get_edge_firewallidpsstats: edgeLogicalId is required\n"
        unless defined $edgeLogicalId && length $edgeLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/edges/' . uri_escape($edgeLogicalId) . '/firewallIdpsStats';
    return $self->_velocloud_get($uri, $params);
}

sub v2_get_enterprise_flowstats {
    my ($self, $enterpriseLogicalId, $params) = @_;
    die "v2_get_enterprise_flowstats: enterpriseLogicalId is required\n"
        unless defined $enterpriseLogicalId && length $enterpriseLogicalId;

    my $uri = 'enterprises/' . uri_escape($enterpriseLogicalId) . '/flowStats';
    return $self->_velocloud_get($uri, $params);
}



1;
