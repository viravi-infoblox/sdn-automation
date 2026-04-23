package NetMRI::HTTP::Client::Mist;

use strict;
use warnings;

use NetMRI::HTTP::Client::Generic;
use URI::Escape qw(uri_escape);
use base 'NetMRI::HTTP::Client::Generic';

# BEFORE FIRST USE (replace placeholders):
# 1) Mist
# 2) v1/installer
# 3) https://example.invalid/api/\%version\%/ (must include %version% token if versioned API)
# 4) Authorization
# 5) bearer (bearer | api_key | basic | cookie | none)
# 6) For each operation block: __operation_method_name__, __OPENAPI_PATH__, __HTTP_METHOD__
# 7) Add required path parameter substitutions in each operation method.

# Generic Phase-2 template for new SDN vendors.
# Replace placeholders and keep only the hooks required by the target API.
my $default_api_version = 'v1/installer';
my $default_base_uri = 'https://example.invalid/api/\%version\%/';
my $auth_token_request_header = 'Authorization';
my $default_auth_mode = 'bearer'; # bearer | api_key | basic | cookie | none

sub new {
    my $class = shift;
    my %args = @_;

    for my $required (qw(api_key fabric_id)) {
        die "NetMRI::HTTP::Client::Mist: required parameter '$required' is missing\n"
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

    # Vendor authentication format: Bearer <token>
    $args{auth_token_request_header} = 'Authorization';
    if (defined $args{api_key} && length $args{api_key}) {
        $args{api_key} = "Bearer $args{api_key}"
            unless $args{api_key} =~ /^Bearer /i;
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
    my $res = [];
    my $error = undef;
    my $finished = 0;
    my $max_iterations = $self->{max_iterations_for_paginated_data};
    my $cur_iteration = 1;

    while (!$error && !$finished) {
        my ($pool, $err) = $self->api_request($method, $uri, $params, $api_version);
        $error = $err if $err;
        $finished = 1;

        unless ($error) {
            push @$res, (ref($pool) eq 'ARRAY' ? @$pool : $pool);

            # Replace or extend this block with API-specific pagination strategy.
            # Common patterns:
            # - HTTP Link header rel=next
            # - x-page-* headers
            # - response body cursor/next URL
            my $next = undef;
            if (ref($self->{response}) && $self->{response}->can('header')) {
                my $link = $self->{response}->header('link') || '';
                if ($link =~ /\<([^>]+)\>\;\s+rel\=[\"\']?next[\"\']?/) {
                    $next = $1;
                }
            }
            if ($next) {
                $uri = $next;
                $params = {};
                $finished = 0;
            }
        }

        $cur_iteration++;
        if ($max_iterations && $cur_iteration > $max_iterations) {
            $finished = 1;
        }
    }

    return $error ? (undef, $error) : $res;
}

# Generated/OpenAPI operation method template.
# Copy this block per operationId mapped in the reviewed Phase-1 payload.
sub _mist_get {
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

sub _mist_get_pages {
    my ($self, $uri, $params) = @_;
    $params //= {};
    my @all;
    my $max  = $self->{max_iterations_for_paginated_data};
    my $iter = 0;

    while (1) {
        my ($pool, $err) = $self->_mist_get($uri, $params);
        return (undef, $err) if defined $err;

        push @all, ref($pool) eq 'ARRAY' ? @$pool : $pool;

        my $next;
        if (ref($self->{response}) && $self->{response}->can('header')) {
            my $link = $self->{response}->header('link') // '';
            ($next) = $link =~ m{\<([^>]+)\>\s*;\s*rel=["']?next["']?};
        }
        last unless $next;

        $uri    = $next;
        $params = {};
        last if ++$iter >= $max;
    }

    return \@all;
}

sub listinstallersites {
    my ($self, $org_id, $params) = @_;
    die "listinstallersites: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = 'orgs/' . uri_escape($org_id) . '/sites';
    return $self->_mist_get_pages($uri, $params);
}

sub getsitewirelessclientstats {
    my ($self, $site_id, $client_mac, $params) = @_;
    die "getsitewirelessclientstats: site_id is required\n"
        unless defined $site_id && length $site_id;
    die "getsitewirelessclientstats: client_mac is required\n"
        unless defined $client_mac && length $client_mac;

    my $uri = '/api/v1/sites/' . uri_escape($site_id) . '/stats/clients/' . uri_escape($client_mac) . '';
    return $self->_mist_get($uri, $params);
}

sub countorgsworgwports {
    my ($self, $org_id, $params) = @_;
    die "countorgsworgwports: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/stats/ports/count';
    return $self->_mist_get($uri, $params);
}

sub getorgnetworktemplate {
    my ($self, $org_id, $networktemplate_id, $params) = @_;
    die "getorgnetworktemplate: org_id is required\n"
        unless defined $org_id && length $org_id;
    die "getorgnetworktemplate: networktemplate_id is required\n"
        unless defined $networktemplate_id && length $networktemplate_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/networktemplates/' . uri_escape($networktemplate_id) . '';
    return $self->_mist_get($uri, $params);
}

sub listorgavailabledeviceversions {
    my ($self, $org_id, $params) = @_;
    die "listorgavailabledeviceversions: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/devices/versions';
    return $self->_mist_get_pages($uri, $params);
}

sub getorgsettings {
    my ($self, $org_id, $params) = @_;
    die "getorgsettings: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/setting';
    return $self->_mist_get($uri, $params);
}

sub countorgwirelessclientssessions {
    my ($self, $org_id, $params) = @_;
    die "countorgwirelessclientssessions: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/clients/sessions/count';
    return $self->_mist_get($uri, $params);
}

sub getorginventory {
    my ($self, $org_id, $params) = @_;
    die "getorginventory: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/inventory';
    return $self->_mist_get($uri, $params);
}

sub downloadorgnacportalsamlmetadata {
    my ($self, $org_id, $nacportal_id, $params) = @_;
    die "downloadorgnacportalsamlmetadata: org_id is required\n"
        unless defined $org_id && length $org_id;
    die "downloadorgnacportalsamlmetadata: nacportal_id is required\n"
        unless defined $nacportal_id && length $nacportal_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/nacportals/' . uri_escape($nacportal_id) . '/saml_metadata.xml';
    return $self->_mist_get($uri, $params);
}

sub getsiteallclientsstatsbydevice {
    my ($self, $site_id, $device_id, $params) = @_;
    die "getsiteallclientsstatsbydevice: site_id is required\n"
        unless defined $site_id && length $site_id;
    die "getsiteallclientsstatsbydevice: device_id is required\n"
        unless defined $device_id && length $device_id;

    my $uri = '/api/v1/sites/' . uri_escape($site_id) . '/stats/devices/' . uri_escape($device_id) . '/clients';
    return $self->_mist_get($uri, $params);
}

sub getsitestats {
    my ($self, $site_id, $params) = @_;
    die "getsitestats: site_id is required\n"
        unless defined $site_id && length $site_id;

    my $uri = '/api/v1/sites/' . uri_escape($site_id) . '/stats';
    return $self->_mist_get($uri, $params);
}

sub listsiteunconnectedclientstats {
    my ($self, $site_id, $map_id, $params) = @_;
    die "listsiteunconnectedclientstats: site_id is required\n"
        unless defined $site_id && length $site_id;
    die "listsiteunconnectedclientstats: map_id is required\n"
        unless defined $map_id && length $map_id;

    my $uri = '/api/v1/sites/' . uri_escape($site_id) . '/stats/maps/' . uri_escape($map_id) . '/unconnected_clients';
    return $self->_mist_get_pages($uri, $params);
}

sub showsitedeviceforwardingtable {
    my ($self, %args) = @_;
    my $uri = '/api/v1/sites/{site_id}/devices/{device_id}/show_forwarding_table';
    die "Missing required path parameter: site_id\n" unless defined $args{site_id};
    $uri =~ s/\Q{site_id}\E/uri_escape("$args{site_id}")/ge;
    die "Missing required path parameter: device_id\n" unless defined $args{device_id};
    $uri =~ s/\Q{device_id}\E/uri_escape("$args{device_id}")/ge;
    my $params = $args{body} && ref($args{body}) eq 'HASH' ? $args{body} : {};
    return $self->perform_request('post', $uri, $self->{supported_version}, $params);
}

sub getapiv1self {
    my ($self, $params) = @_;
    return $self->_mist_get_pages('/api/v1/self', $params);
}

sub listorgstatsdevices {
    my ($self, $org_id, $params) = @_;
    die "listorgstatsdevices: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/stats/devices';
    return $self->_mist_get_pages($uri, $params);
}

sub listorgstatsmxedges {
    my ($self, $org_id, $params) = @_;
    die "listorgstatsmxedges: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/stats/mxedges';
    return $self->_mist_get_pages($uri, $params);
}

sub searchorgsworgwports {
    my ($self, $org_id, $params) = @_;
    die "searchorgsworgwports: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/stats/ports/search';
    return $self->_mist_get($uri, $params);
}

sub searchorgdevices {
    my ($self, $org_id, $params) = @_;
    die "searchorgdevices: org_id is required\n"
        unless defined $org_id && length $org_id;

    my $uri = '/api/v1/orgs/' . uri_escape($org_id) . '/devices/search';
    return $self->_mist_get($uri, $params);
}

sub getsiteclientsstats {
    my ($self, $site_id, $params) = @_;
    die "getsiteclientsstats: site_id is required\n"
        unless defined $site_id && length $site_id;

    my $uri = '/api/v1/sites/' . uri_escape($site_id) . '/stats/clients';
    return $self->_mist_get($uri, $params);
}



1;
