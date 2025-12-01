package NetMRI::HTTP::Client::Meraki;

use strict;
use NetMRI::LoggerShare;
use NetMRI::HTTP::Client::Generic;
use URI;
use base 'NetMRI::HTTP::Client::Generic';

# v1 API endpoints are taken from https://developer.cisco.com/meraki/api-v1/
my $default_api_version = 'v1';
my $base_uri = 'https://api.meraki.com/api/%version%/';
my $auth_token_request_header = 'X-Cisco-Meraki-API-Key';

sub new {
    my $class = shift;
    my %args = @_;
    for my $option (qw(api_key fabric_id)) {
        die "Required parameter $option is not provided" unless ($args{$option});
    }
    $args{base} = $args{address} ? "https://$args{address}/api/\%version\%/" : $base_uri;
    $args{auth_token_request_header} = $auth_token_request_header;
    $args{requests_per_second} //= 3;
    my $self = $class->SUPER::new(%args);
    $self->{fabric_id} = $args{fabric_id};
    $self->{org_id} = $args{org_id} || '';
    $self->{supported_version} = $default_api_version;
    $self->{max_iterations_for_paginated_data} ||= 100;
    # update base URI by calling base() once again
    $self->base();
    return bless $self, $class;
}

sub get_throttle_key {
  my $self = shift;
  return $self->{org_id} || 'Global';
}

sub too_many_requests_response {
    my ($self, $res) = @_;
    #{'success' => 0,'data' => {'error' => {'message' => 'Too Many Requests','code' => 429}}}
    my $flg = (!$res->{success} && $res->{data}->{error}->{code} && $res->{data}->{error}->{code} == 429);
    return $flg;
}

sub meraki_collect_pages_request {
    my ($self, $uri, $version, $params) = @_;
    my $res = []; 
    my $error = undef;
    my $finished = 0;
    my $max_iterations = $self->{max_iterations_for_paginated_data};
    my $cur_iteration = 1;
    while (!$error && !$finished) {
        my ($pool, $error) = $self->meraki_request($uri, $version, $params);
        $finished = 1;
        unless ($error) {
            push @$res, (ref($pool) eq 'ARRAY' ? @$pool : $pool);
            # find the "next" link in the header
            if (ref($self->{response}) && $self->{response}->header('link') =~ /\<([^>]+)\>\;\s+rel\=[\"\']?next[\"\']?/) {
                $finished = 0;
                my $uri   = URI->new($1);
                my %query = $uri->query_form;
                $params->{$_} = $query{$_} foreach keys %query;
            }
        }
        $cur_iteration++;
        if ($cur_iteration > $max_iterations) {
            $finished = 1;
            NetMRI::LoggerShare::logWarn("URI: ${uri} - iteration limit (${max_iterations}) is reached, forced completion of the page collection");
        }
    }
    return $error ? (undef, $error) : $res;
}

sub meraki_request {
    my ($self, $uri, $api_version, $params) = @_;
    my $res = $self->get($uri, $api_version || $default_api_version, $params);
    if ($res->{success} && exists($res->{data})) {
        return $res->{data};
    } elsif ($res->{data}->{error}->{code} == 400) {
        # Meraki may return useful error message in $client->{response}->{_content} when replying "Bad Request"
        return (undef, $self->{response}->{_content} || "Bad Request");
    }
    return (undef, $res->{data}->{error}->{message});
}

# List the organizations that the user has privileges on
# No GET parameters
sub get_organizations {
    my $self = shift;
    return $self->meraki_request("organizations");
}

# List the networks in an organization
# Parameters:
# * configTemplateId
# * perPage
# * startingAfter
# * endingBefore
sub get_networks {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{perPage} //= 1000;
    my $uri = "organizations/$organization_id/networks";
    return $self->meraki_collect_pages_request($uri, undef, $params);
}

# List the devices in a network
# No GET parameters
sub get_network_devices {
    my ($self, $network_id) = @_;
    my $uri = "networks/$network_id/devices";
    return $self->meraki_request($uri);
}

# List the devices in an organization
# Parameters:
# * perPage
# * startingAfter
# * endingBefore
sub get_organization_devices {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{perPage} //= 1000;
    return $self->meraki_collect_pages_request("organizations/$organization_id/devices", undef, $params);
}

# Return the device inventory for an organization
# Parameters:
# * perPage
# * startingAfter
# * endingBefore
sub get_organization_inventory {
    my ($self, $organization_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{perPage} //= 1000;
    my $uri = "organizations/$organization_id/inventoryDevices";
    return $self->meraki_collect_pages_request($uri, undef, $params);
}

# List the status of every Meraki device in the organization
# No GET parameters
sub get_device_statuses {
    my ($self, $organization_id) = @_;
    my $uri = "organizations/$organization_id/devices/statuses";
    return $self->meraki_request($uri);
}

sub get_all_devices_statuses {
    my ($self, $organizations) = @_;
    my %devices_statuses;
    foreach my $org (@$organizations) {
       my ($dev_statuses, $msg) = $self->get_device_statuses($org->{id});
       next unless $dev_statuses;
       foreach my $ds (@$dev_statuses) {
          $devices_statuses{"$org->{id}/$ds->{networkId}/$ds->{serial}"} = $ds->{status};
       }
    }
    return \%devices_statuses;
}

# Return a single device
# No GET parameters
sub get_device {
    my ($self, $serial) = @_;
    my $uri = "devices/$serial";
    return $self->meraki_request($uri);
}

# Get Organization Uplinks Statuses
# Parameters:
# * perPage
# * startingAfter
# * endingBefore
# * networkIds
# * serials
sub get_device_uplinks {
    my ($self, $organization_id, $serial) = @_;
    my $uri = "organizations/$organization_id/uplinks/statuses";
    return $self->meraki_collect_pages_request($uri, undef,  {perPage => 1000, 'serials[]' => $serial});
}


# List LLDP and CDP information for a device
# Parameters:
# * timespan < 2592000 (seconds in a month), REQUIRED
sub get_device_lldp_cdp {
    my ($self, $serial, $params) = @_;
    my $uri = "devices/$serial/lldpCdp";
    return $self->meraki_request($uri, undef, $params);
}

# List the Bluetooth clients seen by APs in this network
# Parameters:
# * perPage
# * startingAfter
# * endingBefore
# * timespan
# * includeConnectivityHistory
sub get_bluetooth_clients {
    my ($self, $network_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{perPage} //= 1000;
    return $self->meraki_collect_pages_request("networks/$network_id/bluetoothClients", undef, $params);
}

# List the clients of a device, up to a maximum of a month ago.
# The usage of each client is returned in kilobytes.
# If the device is a switch, the switchport is returned; otherwise the switchport field is null.
# Parameters:
# * t0
# * timespan
sub get_clients {
    my ($self, $serial, $params) = @_;
    my $uri = "devices/$serial/clients";
    return $self->meraki_request($uri, undef, $params);
}

# Return the client associated with the given identifier
# No GET parameters
sub get_client {
    my ($self, $network_id, $client_id) = @_;
    my $uri = "networks/$network_id/clients/$client_id";
    return $self->meraki_request($uri);
}

# List the clients that have used this network in the timespan
# Parameters:
# * t0
# * timespan
# * perPage (from 3 to 1000, 10 by default)
# Header of the response contains information like this:
# 'link' => '<https://n176.meraki.com/api/v0/networks/L_662029145223466424/clients?perPage=3&startingAfter=a000000>; rel=first, <https://n176.meraki.com/api/v0/networks/L_662029145223466424/clients?perPage=3&startingAfter=k6dfc89>; rel=next',
# Sometimes can return empty array or {"errors":["Invalid device type"]}, meaning there's no clients in current network or "not applicable"
sub get_network_clients {
    my ($self, $network_id, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    $params->{perPage} //= 1000;
    return $self->meraki_collect_pages_request("networks/$network_id/clients", undef, $params);
}

# List the SSIDs in a network
# No GET parameters
sub get_ssids {
    my ($self, $network_id) = @_;
    my $uri = "networks/$network_id/wireless/ssids";
    return $self->meraki_request($uri);
}

# Return the SSID statuses of an access point
# No GET parameters
sub get_wireless_bss {
    my ($self, $serial) = @_;
    my $uri = "devices/$serial/wireless/status";
    return $self->meraki_request($uri);
}

# List the static routes for this network
# No GET parameters
sub get_static_routes {
    my ($self, $network_id) = @_;
    my $uri = "networks/$network_id/appliance/staticRoutes";
    return $self->meraki_request($uri);
}

# List the switch ports for a switch
# Parameters:
# * t0       - The beginning of the timespan for the data. The maximum lookback
#               period is 31 days from today.
# * timespan - The timespan for which the information will be fetched. If 
#               specifying timespan, do not specify parameter t0. The value
#               must be in seconds and be less than or equal to 31 days.
#               The default is 1 day.
sub get_switch_port_statuses {
    my ($self, $serial, $params) = @_;
    $params = {} unless ref($params) eq 'HASH';
    my $uri = "devices/$serial/switch/ports/statuses";
    return $self->meraki_request($uri, undef, $params);
}

# List the switch ports for a switch
# No GET parameters
sub get_switch_ports {
    my ($self, $serial) = @_;
    my $uri = "devices/$serial/switch/ports";
    return $self->meraki_request($uri);
}

# List per-port VLAN settings for all ports of a MX
# No GET parameters
sub get_mx_ports {
    my ($self, $network_id) = @_;
    my $uri = "networks/$network_id/appliance/ports";
    return $self->meraki_request($uri);
}

# List the VLANs for an MX network
# No GET parameters
# Can throw "VLANs are not enabled for this network"
sub get_vlans {
    my ($self, $network_id) = @_;
    my $uri = "networks/$network_id/appliance/vlans";
    return $self->meraki_request($uri);
}

# Return the management interface settings for a device
# No GET parameters
# Can throw "Cameras are not supported by this endpoint"
sub get_mgmt_interface_settings {
    my ($self, $serial) = @_;
    my $uri = "devices/$serial/managementInterface";
    return $self->meraki_request($uri);
}

sub get_all_devices {
    my $self = shift;
    my @devices;
    my ($organizations, $msg) = $self->get_organizations();
    return (undef, $msg) unless ($organizations);

    foreach my $org (@$organizations) {
        (my $org_devices, $msg) = $self->get_organization_devices($org->{id});
        next unless ($org_devices);
        (my $inventory, $msg) = $self->get_organization_inventory($org->{id});
        my %inventory = map { $_->{serial} => $_ } @$inventory;  # transform array to hash for quick lookup by device serial
        foreach my $dev (@$org_devices) {
            $dev->{publicIp} = $inventory{$dev->{serial}}{publicIp};
            $dev->{claimedAt} = $inventory{$dev->{serial}}{claimedAt};
            $dev->{orgId} = $org->{id};
            push @devices, $dev;
        }
    }
    return \@devices;
}

1;
