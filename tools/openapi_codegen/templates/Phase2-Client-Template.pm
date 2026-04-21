package NetMRI::HTTP::Client::__VENDOR__;

use strict;
use warnings;

use NetMRI::HTTP::Client::Generic;
use URI::Escape qw(uri_escape);
use base 'NetMRI::HTTP::Client::Generic';

# BEFORE FIRST USE (replace placeholders):
# 1) __VENDOR__
# 2) __API_VERSION__
# 3) __BASE_URI_TEMPLATE__ (must include %version% token if versioned API)
# 4) __AUTH_HEADER_NAME__
# 5) __AUTH_MODE__ (bearer | api_key | basic | cookie | none)
# 6) For each operation block: __operation_method_name__, __OPENAPI_PATH__, __HTTP_METHOD__
# 7) Add required path parameter substitutions in each operation method.

# Generic Phase-2 template for new SDN vendors.
# Replace placeholders and keep only the hooks required by the target API.
my $default_api_version = '__API_VERSION__';
my $default_base_uri = '__BASE_URI_TEMPLATE__';
my $auth_token_request_header = '__AUTH_HEADER_NAME__';
my $default_auth_mode = '__AUTH_MODE__'; # bearer | api_key | basic | cookie | none

sub new {
    my $class = shift;
    my %args = @_;

    # Keep required parameters minimal for broad reuse.
    $args{fabric_id} = defined $args{fabric_id} ? $args{fabric_id} : '';

    $args{base} ||= $args{address}
        ? "https://$args{address}/\%version\%/"
        : $default_base_uri;

    $args{auth_mode} ||= $default_auth_mode;
    $args{token_prefix} = 'Bearer' unless defined $args{token_prefix};

    $args{auth_token_request_header} ||= $args{auth_header} || $auth_token_request_header;
    $args{requests_per_second} //= 3;

    # Transport toggles can be injected from controller config.
    $args{timeout} = $args{timeout} if defined $args{timeout};
    $args{no_cert_check} = $args{no_cert_check} if defined $args{no_cert_check};

    # Normalize auth credentials without locking into a single vendor style.
    if ($args{auth_mode} eq 'bearer' && defined $args{api_key} && length $args{api_key}) {
        my $prefix = defined $args{token_prefix} ? $args{token_prefix} : '';
        $args{api_key} = $prefix ? "$prefix $args{api_key}" : $args{api_key};
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
sub __operation_method_name__ {
    my ($self, %args) = @_;
    my $uri = '__OPENAPI_PATH__';

    # Required path parameters (example placeholders):
    # die "Missing required path parameter: org_id\n" unless defined $args{org_id};
    # $uri =~ s/\Q{org_id}\E/uri_escape("$args{org_id}")/ge;

    my $params;
    if ('__HTTP_METHOD__' =~ /^(post|put|patch)$/i) {
        $params = $args{body} && ref($args{body}) eq 'HASH' ? $args{body} : {};
    } else {
        $params = $args{query} && ref($args{query}) eq 'HASH' ? $args{query} : {};
    }

    # Use perform_request to stay compatible with NetMRI::HTTP::Client::Generic.
    return $self->perform_request('__HTTP_METHOD__', $uri, $self->{supported_version}, $params);
}

1;
