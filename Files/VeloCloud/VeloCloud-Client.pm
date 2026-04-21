package NetMRI::HTTP::Client::VeloCloud;

use strict;
use warnings;

use NetMRI::HTTP::Client::Generic;
use URI::Escape qw(uri_escape);
use base 'NetMRI::HTTP::Client::Generic';

# VeloCloud SD-WAN Orchestrator API client.
#
# Authentication: Cookie-based session via POST /portal/rest/login/enterpriseLogin
# The same session cookie is valid for both v1 portal and v2 REST calls.
#
# Required constructor args: username, password, fabric_id
# Optional: address (VCO hostname)

my $default_api_version = 'v1';
my $default_base_uri    = 'https://example.invalid/api/\%version\%/';
my $login_uri           = '/portal/rest/login/enterpriseLogin';

sub new {
    my $class = shift;
    my %args = @_;

    $args{fabric_id} = defined $args{fabric_id} ? $args{fabric_id} : '';

    $args{base} ||= $args{address}
        ? "https://$args{address}/\%version\%/"
        : $default_base_uri;

    $args{requests_per_second} //= 3;

    my $self = $class->SUPER::new(%args);
    $self->{fabric_id} = $args{fabric_id};
    $self->{supported_version} = $default_api_version;
    $self->{max_iterations_for_paginated_data} ||= 100;

    # Credentials for cookie-based session auth (used by both v1 and v2).
    $self->{username} = $args{username} || '';
    $self->{password} = $args{password} || '';
    $self->{is_authenticated} = 0;

    # Enable cookie jar so LWP persists the session cookie across requests.
    if ($self->{ua} && !$self->{ua}->cookie_jar) {
        $self->{ua}->cookie_jar({});
    }

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

# -----------------------------------------------------------------------
# Session management — single cookie-based login for all API versions
# -----------------------------------------------------------------------

sub authenticate {
    my ($self) = @_;

    unless (length $self->{username} && length $self->{password}) {
        return (undef, 'VeloCloud credentials (username/password) not configured');
    }

    my $body = {
        username => $self->{username},
        password => $self->{password},
    };

    # POST login — the orchestrator sets a session cookie that LWP's cookie jar retains.
    my $res = $self->post($login_uri, undef, $body);

    if ($res->{success}) {
        $self->{is_authenticated} = 1;
        return (1, undef);
    }

    my $msg = $res->{data}{error}{message}
           // $self->{response}{_content}
           // 'VeloCloud login failed';
    return (undef, $msg);
}

sub ensure_session {
    my ($self) = @_;
    return (1, undef) if $self->{is_authenticated};
    return $self->authenticate();
}

# -----------------------------------------------------------------------
# API request — ensures session before every call
# -----------------------------------------------------------------------

sub api_request {
    my ($self, $method, $uri, $params, $api_version) = @_;
    $method ||= 'get';
    my $version = $api_version || $self->{supported_version};

    # Establish cookie session if not already authenticated.
    my ($ok, $auth_err) = $self->ensure_session();
    return (undef, $auth_err) unless $ok;

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
sub v2_get_enterprises {
    my ($self, %args) = @_;
    my ($ok, $auth_err) = $self->ensure_session();
    return (undef, $auth_err) unless $ok;
    my $uri = '/api/sdwan/v2/enterprises/';
    my $params = $args{query} && ref($args{query}) eq 'HASH' ? $args{query} : {};
    my $res = $self->perform_request('get', $uri, $self->{supported_version}, $params);
    if ($res->{success} && exists $res->{data}) {
        return ($res->{data}, undef);
    }
    my $err = ($res->{data} && ref($res->{data}) eq 'HASH' && $res->{data}{error})
            ? $res->{data}{error}{message}
            : ($res->{error} ? $res->{error}{message} : 'v2 enterprises request failed');
    return (undef, $err);
}

sub v2_get_enterprise_edges {
    my ($self, %args) = @_;
    my ($ok, $auth_err) = $self->ensure_session();
    return (undef, $auth_err) unless $ok;
    my $uri = '/api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges/';
    die "Missing required path parameter: enterpriseLogicalId\n" unless defined $args{enterpriseLogicalId};
    $uri =~ s/\Q{enterpriseLogicalId}\E/uri_escape("$args{enterpriseLogicalId}")/ge;
    my $params = $args{query} && ref($args{query}) eq 'HASH' ? $args{query} : {};
    my $res = $self->perform_request('get', $uri, $self->{supported_version}, $params);
    if ($res->{success} && exists $res->{data}) {
        return ($res->{data}, undef);
    }
    my $err = ($res->{data} && ref($res->{data}) eq 'HASH' && $res->{data}{error})
            ? $res->{data}{error}{message}
            : ($res->{error} ? $res->{error}{message} : 'v2 edges request failed');
    return (undef, $err);
}

sub v1_get_edge_interface_metrics {
    my ($self, %args) = @_;
    die "Missing required parameter: edgeId\n" unless defined $args{edgeId};
    my $uri = '/portal/';
    my $body = {
        method => 'metrics/getEdgeNetworkInterfaceMetrics',
        params => {
            edgeId => $args{edgeId},
            (defined $args{enterpriseId} ? (enterpriseId => $args{enterpriseId}) : ()),
        },
    };
    return $self->api_request('post', $uri, $body, 'v1');
}

sub v1_get_enterprise_edge_status {
    my ($self, %args) = @_;
    die "Missing required parameter: enterpriseId\n" unless defined $args{enterpriseId};
    my $uri = '/portal/';
    my $body = {
        method => 'enterprise/getEnterpriseEdgeStatus',
        params => {
            enterpriseId => $args{enterpriseId},
        },
    };
    return $self->api_request('post', $uri, $body, 'v1');
}

# -----------------------------------------------------------------------
# Session cleanup — logout on object destruction (ACI pattern)
# -----------------------------------------------------------------------

sub deauthenticate {
    my ($self) = @_;
    return unless $self->{is_authenticated};

    my $res = $self->post('/portal/rest/logout/logout', undef, {});

    $self->{is_authenticated} = 0;
    $self->{ua}->cookie_jar({}) if $self->{ua};
}

sub DESTROY {
    my $self = shift;
    $self->deauthenticate() if $self->{is_authenticated};
}

1;
