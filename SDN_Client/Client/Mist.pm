package NetMRI::HTTP::Client::Mist;

use strict;
use NetMRI::LoggerShare;
use NetMRI::HTTP::Client::Generic;
use URI;
use Data::Dumper;

use base 'NetMRI::HTTP::Client::Generic';

my $default_api_version = 'v1';
my $auth_token_request_header = 'Authorization';

sub new {
    my $class = shift;
    my %args = @_;
    for my $option (qw(address api_key fabric_id)) {
        die "Required parameter $option is not provided" unless ($args{$option});
    }
    $args{base} = "https://$args{address}/api/\%version\%/";
    $args{timeout} = 180;
    $args{auth_token_request_header} = $auth_token_request_header;
    $args{api_key} = "Token $args{api_key}";
    $args{requests_per_second} //= 100;
    my $self = $class->SUPER::new(%args);
    $self->{fabric_id} = $args{fabric_id};
    $self->{supported_version} = $default_api_version;
    $self->{max_iterations_for_paginated_data} = 0; # default is 0, which means no limit
    # update base URI by calling base() once again
    $self->base();
    return bless $self, $class;
}

sub too_many_requests_response {
    my ($self, $res) = @_;
    #{'success' => 0,'data' => {'error' => {'message' => 'Too Many Requests','code' => 429}}}
    my $flg = (!$res->{success} && $res->{data}->{error}->{code} && $res->{data}->{error}->{code} == 429);
    return $flg;
}

sub mist_collect_pages_request {
    my ($self, $uri, $version, $params) = @_;
	
    my $res = [];
    my $error = undef;
    my $finished = 0;
    my $max_iterations = $self->{max_iterations_for_paginated_data};
    my $cur_iteration = 1;

    while (!$error && !$finished) {
        my ($data, $err) = $self->mist_request($uri, $version, $params);
        $error = $err if $err;
        $finished = 1;

        unless ($error) {
            if (exists $data->[0]->{results} && ref($data->[0]->{results}) eq 'ARRAY') {
                push @$res, @{$data->[0]->{results}};

                if ($data->[0]->{next}) {
                    $uri     = $data->[0]->{next};
                    $params  = {};
                    $finished = 0;
                }

            } elsif (ref($data) eq 'ARRAY') {
                push @$res, @$data;

            } elsif (ref($data) eq 'HASH') {
                push @$res, $data;

            } else {
                NetMRI::LoggerShare::logWarn("Unexpected response format: " . Dumper($data));
            }
        }

        $cur_iteration++;
        if ($max_iterations && ($cur_iteration > $max_iterations)) {
            $finished = 1;
            NetMRI::LoggerShare::logWarn("URI: ${uri} - iteration limit (${max_iterations}) is reached, forced completion of the page collection");
        }
    }

    return $error ? (undef, $error) : $res;
}

sub mist_request {
    my ($self, $uri, $api_version, $params) = @_;

    my $version = $api_version || $default_api_version;
    my @all_data;

    my $res = $self->get($uri, $version, $params);

    unless ($res->{success} && exists $res->{data}) {
        if ($res->{data}->{error}->{code} == 400) {
            return (undef, $self->{response}->{_content} || "Bad Request");
        }
        return (undef, $res->{data}->{error}->{message});
    }

    if (ref $res->{data} eq 'ARRAY') {
        push @all_data, @{$res->{data}};
    } else {
        push @all_data, $res->{data};
    }

    my $headers = $self->{response}->{_headers};
    my $limit   = $headers->{'x-page-limit'}  || 0;
    my $total   = $headers->{'x-page-total'}  || 0;
    my $page    = $headers->{'x-page-page'}   || 1;

    if ($limit && $total) {
        my $pages = int(($total + $limit - 1) / $limit);

        for my $p ($page+1 .. $pages) {
            my %new_params = (%{$params || {}}, page => $p);
            my $r = $self->get($uri, $version, \%new_params);

            unless ($r->{success} && exists $r->{data}) {
                if ($r->{data}->{error}->{code} == 400) {
                    return (undef, $self->{response}->{_content} || "Bad Request");
                }
                return (undef, $r->{data}->{error}->{message});
            }

            if (ref $r->{data} eq 'ARRAY') {
                push @all_data, @{$r->{data}};
            } else {
                push @all_data, $r->{data};
            }
        }
    }

    return \@all_data;
}

sub get_self {
    my $self = shift;
    my $params = shift;
    $params = {} unless ref($params) eq 'HASH';
    return $self->mist_collect_pages_request("self", undef, $params);
}

sub get_sites {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{limit} //= 1000;
    my $uri = "orgs/$organization_id/sites";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

sub get_organization_devices {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{type} //= 'all';
    $params->{limit} //= 1000;
    my $uri = "orgs/$organization_id/stats/devices";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

sub get_edges_stats {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{for_site} //= 'any';
    $params->{limit} //= 1000;
    my $uri = "orgs/$organization_id/stats/mxedges";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

sub get_mist_intf {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{limit} //= 1000;
    my $uri = "orgs/$organization_id/stats/ports/search";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

sub get_device_lldp {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{perPage} //= 1000;
    my $uri = "orgs/$organization_id/devices/search";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

sub get_ipaddr {
    my ($self, $site_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{type} //='all';
    $params->{limit} //= 1000;
    my $uri = "sites/$site_id/stats/devices";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

sub get_endhosts {
    my ($self, $site_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    my $uri = "sites/$site_id/stats/clients";
    return $self->mist_collect_pages_request($uri, undef, $params);
}

1;