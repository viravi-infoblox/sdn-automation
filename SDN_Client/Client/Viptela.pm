package NetMRI::HTTP::Client::Viptela;

use strict;
use NetMRI::HTTP::Client::Generic;
use base 'NetMRI::HTTP::Client::Generic';
use NetMRI::LoggerShare;
use Data::Dumper;

sub new {
    my $class = shift;
    my %args = @_;

    for my $option (qw(address username password)) {
        die "Required parameter $option is not provided" unless ($args{$option});
    }

    NetMRI::LoggerShare::logDebug("Creating Viptela HTTP Client");
    $args{proto} = lc($args{proto}) if $args{proto};
    $args{proto} ='https' unless ($args{proto} && $args{proto} eq 'http');
    $args{base} = "$args{proto}://$args{address}";
    $args{auth_token_request_header} = 'Set-Cookie';
    $args{auth_token_response_header} = 'Set-Cookie';
    $args{requests_per_second} //= 3;
    $args{auth_token} = [ '' ];
    $args{cookie_jar} = {};

    my $self = $class->SUPER::new(%args);
    $self->{fabric_id} = $args{fabric_id};
    return bless $self, $class;
}

# Viptela returns 200 OK even if autherication has errors. Wherein
# it returns html/text Content-Type instead of application/json
sub parse_response {
    my ($self, $response) = @_;
    $self->{response} = $response;
    $self->{success}  = $response->is_success;
    my $code          = $response->code;
    my $content       = $self->{response}->decoded_content;
    my $content_type  = $self->{response}->header('content-type');

    my %errors = (
        'Invalid User or Password' => 401,
        'Server is initializing. Please wait' => 503,
    );

    if ($self->{success} && $content_type =~ /text\/html/) {
        for my $err (keys %errors) {
            if ($content =~ /\Q$err\E/m) {
                $self->{success} = 0;
                $self->{request_data} = $self->make_error_data($errors{$err}, $err);
                return 0;            
            }
        }
    } 
    if (!$self->{success}) {
        $self->{request_data} = $self->make_error_data($code, $response->message);
        return 0;
    }

    my $method_name = "parse_content_" . $self->content_type_to_snake($response->header('content-type') || 'text/html');
    $self->$method_name(\$content) if $self->can($method_name);
    $self->{request_data} = $content;
    return 1;
}

sub viptela_request {
    my ($self, $method, $url, $params) = @_;
    
    unless ($self->{is_authenticated}) {
        my ($ok, $error) = $self->authenticate;
        return ($ok, $error) unless $ok;
    }
 
    return (undef, "Wrong method $method") unless $method =~ /(post|get)/i;
    $method = lc $method;
    NetMRI::LoggerShare::logDebug("Request url: dataservice/$url");
    NetMRI::LoggerShare::logDebug("Request parameters: " . Dumper($params)) if $params;

    my $res = $self->$method("dataservice/$url", undef, $params);

    if ($res->{success} && ref($res->{data}) eq 'HASH' && exists($res->{data}->{data})) {
        NetMRI::LoggerShare::logDebug("viptela_request result:");
        NetMRI::LoggerShare::logDebug(Dumper($res->{data}));
        $self->deauthenticate() if $self->{is_authenticated};
        return $res->{data}->{data} || {};
    } else {
        $self->deauthenticate() if $self->{is_authenticated};
    }

    NetMRI::LoggerShare::logDebug(Dumper($res));
    return (0, $res->{data}->{error});
}

sub authenticate {
    my ($self) = @_;

    return 1 if $self->{is_authenticated};

    NetMRI::LoggerShare::logDebug("Authenticating to $self->{base}");

    $self->{ua}->cookie_jar({});

    my $res = $self->post('j_security_check', undef, {
        'j_username' => $self->{args}->{username},
        'j_password' => $self->{args}->{password}
    });

    if ($res->{success}) {
        unless ($self->{XSRFtoken}) {
            my $uri = 'dataservice/client/token?json=true';
            $self->{XSRFtoken} = $self->get($uri)->{data}->{token} || '';
            unless ($self->{XSRFtoken}) {
                NetMRI::LoggerShare::logDebug(Dumper($self->{response}));
                NetMRI::LoggerShare::logWarn(sprintf("Failed to get XSRF token: request uri='%s' failed, code=%s message=%s", $uri, $self->{response}->{_rc} || '', $self->{response}->{_msg} || ''));
            }
        }
        $self->{is_authenticated} = 1;
        NetMRI::LoggerShare::logDebug("Auth successful");
        return $self->{is_authenticated};
    } else {
        $self->{is_authenticated} = undef;
        NetMRI::LoggerShare::logDebug("Auth failed " . Dumper($res));
        return (undef, $res); # ->{data}->{error}
    }
}

sub add_session_token {
    my $self = shift;
    my $request = shift;
    return unless $self->{is_authenticated};
    if ($self->{XSRFtoken}) {
        NetMRI::LoggerShare::logDebug('Add XSRF token');
        $request->header('X-XSRF-TOKEN', $self->{XSRFtoken});
    }
}

sub DESTROY {
    my $self = shift;
    $self->deauthenticate() if $self->{is_authenticated};
}

sub deauthenticate {
    my $self = shift;
    NetMRI::LoggerShare::logDebug("Logout from $self->{base}");
    $self->{ua}->max_redirect(0);
    $self->get('logout');
    $self->{ua}->max_redirect(7);

    # If the http response code is 302 redirect with location header https://{vmanage-ip-address}/welcome.html?nocache=,
    # the session has been invalidated. https://developer.cisco.com/docs/sdwan/#!authentication/how-to-authenticate
    if ($self->{response}->{_rc} == 302 && ($self->{response}->{_headers}->{location} =~ /welcome.html/ || $self->{response}->{_content} =~ /welcome.html/)) {
        NetMRI::LoggerShare::logDebug('Logout successful');
        $self->{is_authenticated} = undef;
        $self->{XSRFtoken} = undef;        
    } else {
        NetMRI::LoggerShare::logDebug(Dumper($self->{response}));
        NetMRI::LoggerShare::logWarn(sprintf("Logout failed: request uri='logout' failed, code=%s message=%s", $self->{response}->{_rc} || '', $self->{response}->{_msg} || ''));
    }
}

=head1
    API call for monitoring of devices connected to vManage NMS:
    Display all Viptela devices in the overlay network that are connected to the vManage NMS.
    optional call params
        model

    $self->get_devices($deviceId, {model => $model})
=cut

sub get_devices {
    my ($self, $extra) = @_;
    return $self->viptela_request('get', 'device', $extra);
}

=head1
    API call to get information about particular device connected to vManage NMS:
    parameters:
        deviceId - required

    $self->get_device_info($deviceId)
=cut
sub get_device_info {
    my ($self, $deviceId) = @_;
    return (undef, "deviceId param required!") unless $deviceId;
    return $self->viptela_request('get', "device", {deviceId => $deviceId});
}

=head1
    API calls for real-time monitoring of interface information:
    parameters:
        deviceId - required
        vpn-id
        ifname
        af-type
    call:
        '' - Display information about IPv4 interfaces on a Viptela device.(default)
        arp_stats - Display the ARP statistics for each interface
        error_stats - Display error statistics for interfaces
        synced - Display information about IPv4 interfaces on a Viptela device (from vManage NMS only).
        pkt_size - Display packet size information for each interface (on vEdge routers only).
        port_stats - Display interface port statistics (on vEdge routers only).
        queue_stats - Display interface queue statistics (on vEdge routers only).
        stats - Display interface statistics (on vEdge routers only).

    $self->get_interfaces($deviceId, $call, {vpn-id => $vpnid})
=cut

sub get_interfaces {
    my ($self, $deviceId, $call, $extra) = @_;
    return (undef, "deviceId param required!") if !$deviceId;
    $call = ( $call && $call =~ /(arp_stats|error_stats|synced|pkt_size|port_stats|queue_stats|stats)/) ? "interface/$call" : 'interface';
    my $validate = ['vpn-id', 'ifname', 'af-type'];
    $extra = (ref $extra eq "HASH") ? $self->_check_extra($extra, $validate) : {};
    return $self->viptela_request('get', "device/$call", {deviceId => $deviceId, %$extra});
}

=head1
    API calls for real-time monitoring of IP information:
    deviceId required for all calls
    call (on vEdge routers only):
        fib - Display the IPv4 entries in the local forwarding table.(default)
        optional call params
            vpn-id
            address-family
            prefix
            tloc
            color
        mfiboil - Display the list of outgoing interfaces
                    from the Multicast Forwarding Information Base (MFIB).
        mfibstats - Display packet transmission and receipt statistics for active entries in
                    the Multicast Forwarding Information Base (MFIB).
        mfibsummary - Display a summary of all active entries in the Multicast Forwarding
                        Information Base (MFIB).
        nat/filter  - Display the NAT translational filters.
        optional call params
            nat-vpn-id
            nat-ifname
            private-source-address
            proto
        nat/interface - List the interfaces on which NAT is enabled and the NAT translational filters on those interfaces.
        nat/interfacestatistics - List the interfaces on which NAT is enabled and
                                    the NAT translational filters on those interfaces.
        routetable - Display the IPv4 entries in the local route table. On vSmart controllers,
                    the route table incorporates forwarding information.
        optional call params
            vpn-id
            address-family
            prefix
            protocol

    $self->get_ip($deviceId, $call, {foo => 'bar'})
=cut

sub get_ip {
    my ($self, $deviceId, $call, $extra) = @_;
    return (undef, "deviceId param required!") if !$deviceId;

    my %validate = (
        fib => ['vpn-id', 'address-family', 'prefix', 'tloc', 'color'],
        mfiboil => [],
        mfibstats => [],
        mfibsummary => [],
        'nat/filter' => ['nat-vpn-id', 'nat-ifname', 'private-source-address', 'proto'],
        'nat/interface' => [],
        'nat/interfacestatistics' => [],
        routetable => ['vpn-id', 'address-family', 'prefix', 'protocol']
    );

    $call = 'fib' unless ($call && exists $validate{$call});
    $extra = (ref $extra eq 'HASH') ? $self->_check_extra($extra, $validate{$call}) : {};
    return $self->viptela_request('get', "device/ip/$call", {deviceId => $deviceId, %$extra});
}

=head1
    API call for real-time monitoring of ARP information:
        Display the IPv4 entries in the Address Resolution Protocol table,
        which lists the mapping of IP addresses to device MAC addresses.

        $self->get_ip($deviceId, {call => 'summary'})
=cut

sub get_arp {
    my ($self, $deviceId) = @_;
    return (undef, "deviceId param required!") if !$deviceId;
    return $self->viptela_request('get', "device/arp", {deviceId => $deviceId});
}

=head1
    API calls for real-time monitoring of BGP information (on vEdge routers only):
        deviceId required for all calls
        neighbors - List the router's BGP neighbors.
            optional call params
                as
                peer-addr
                vpn-id
        routes - List the router's BGP routes.
            optional call params
                nexthop
                prefix
                vpn-id
        summary - Display the status of all BGP connections (default).

        $self->get_bgp($deviceId, $call, {foo => bar})
=cut

sub get_bgp {
    my ($self, $deviceId, $call, $extra) = @_;
    return (undef, "deviceId param required!") if !$deviceId;
    $call ||= 'summary';

    my %validate = (
        neighbors => ['as', 'peer-addr', 'vpn-id'],
        routes    => ['nexthop', 'prefix', 'vpn-id'],
        summary   => [],
    );

    $extra = (ref $extra eq 'HASH') ? $self->_check_extra($extra, $validate{$call}) : {};
    return $self->viptela_request('get', "device/bgp/$call", {deviceId => $deviceId, %$extra});
}

=head1
    API calls for real-time monitoring of a device:
        Display time and process information for the device, as well as CPU, memory, and disk usage data.
        Params:
            deviceId - required
            synced   - show data from vManage NMS only.

        $self->get_system($deviceId, $synced})
=cut

sub get_system {
    my ($self, $deviceId, $synced) = @_;
    return (undef, "deviceId param required!") if !$deviceId;

    my $call = ( $synced ? "synced/" : "" ) . 'status';
    return $self->viptela_request('get', "device/system/$call", {deviceId => $deviceId});
}

=head1
    API calls for real-time monitoring of software:
        Retrieve interface list.
        Params:
            deviceId - required
            synced   - show data from vManage NMS only.

    $self->get_software($deviceId, $synced)
=cut

sub get_software {
    my ($self, $deviceId, $synced) = @_;
    return (undef, "deviceId param required!") if !$deviceId;

    my $call = $synced ? "/synced" : "";
    return $self->viptela_request('get', "device/software$call", {deviceId => $deviceId});
}

=head1
    API calls for real-time monitoring of hardware information:
    deviceId required for all calls
    calls:
        alarms(default)    - Display information about currently active hardware alarms.
        environment        - Display status information about the router components, including component temperature.
        inventory          - Display an inventory of the hardware components in the router, including serial numbers.
        threshold          - Display temperature thresholds at which green, yellow, and red alarms are generated (on vEdge routers only).

        Params:
            deviceId - required
            synced - if enable "from vManage NMS only", else "on vEdge routers only" (unavailible for threshold)

    $self->get_hardware($deviceId, $call, $synced);
=cut

sub get_hardware {
    my ($self, $deviceId,  $call, $synced) = @_;
    return (undef, "deviceId param required!") if !$deviceId;

    $call = "alarms" unless ( $call && $call =~ /(alarms|environment|inventory|threshold)/ );
    $call = "synced/$call" if ( $synced && $call ne 'threshold');

    return $self->viptela_request('get', "device/hardware/$call", {deviceId => $deviceId});
}

=head1
    API call for real-time monitoring of IPv6 neighbors:
        Display the entries in the Address Resolution Protocol (ARP) table for IPv6 neighbors,
        which lists the mapping of IPv6 addresses to device MAC addresses
        (on vEdge routers and vSmart controllers only).
        Params:
            deviceId - required
            if-name
            mac
            vpn-id

    $self->get_ndv6($deviceId, {foo => bar});
=cut

sub get_ndv6 {
    my ($self, $deviceId, $extra) = @_;
    return (undef, "deviceId param required!") if !$deviceId;

    my $validate = ['if-name', 'mac', 'vpn-id'];
    $extra = (ref $extra eq 'HASH') ? $self->_check_extra($extra, $validate) : {};

    return $self->viptela_request('get', "device/ndv6", {deviceId => $deviceId, %$extra});
}

=head1
    API call for real-time monitoring of VPNs:
    Display VPN instance list.
    Params:
        deviceId - required

    $self->get_vpn($deviceId);
=cut

sub get_vpn {
    my ($self, $deviceId) = @_;
    return (undef, "deviceId param required!") if !$deviceId;
    return $self->viptela_request('get', "device/vpn", {deviceId => $deviceId});
}

=head1
    API calls for real-time monitoring of bridging information:
    deviceId required for all calls
    calls:
        interface - List information about the interfaces on which bridging is running (on vEdge routers only).
        mac       - List the MAC addresses that this vEdge router has learned (on vEdge routers only).
            Params(optional):
                bridge-id
                if-name
                mac-address
        table     - List the information in the bridge forwarding table.

    $self->get_bridge($deviceId, $call, {foo => bar});
=cut

sub get_bridge {
    my ($self, $deviceId, $call, $extra) = @_;
    return (undef, "deviceId param required!") if !$deviceId;

    my %validate = (
        interface => [],
        table     => [],
        mac       => ['bridge-id', 'if-name', 'mac-address']
    );

    $call = 'table' unless ($call && exists $validate{$call});
    $extra = (ref $extra eq 'HASH') ? $self->_check_extra($extra, $validate{$call}) : {};
    return $self->viptela_request('get', "device/bridge/$call", {deviceId => $deviceId, %$extra});
}

sub _check_extra {
    my ($self, $extra, $fields) = @_;
    my $ok = (ref $extra eq 'HASH' && %$extra) ? 1 : undef;

    if ($ok && ref $fields eq 'ARRAY') {
        my %checklist;
        $checklist{$_} = 1 for @$fields;
        %$extra = map { $_ => $extra->{$_} } grep { $checklist{$_} } keys %$extra;
    } else {
        $extra = {};
    }

    return $extra;
}

1;
