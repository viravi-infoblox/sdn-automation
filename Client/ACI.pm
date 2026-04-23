package NetMRI::HTTP::Client::ACI;
use strict;
use warnings;
use NetMRI::HTTP::Client::Generic;
use base 'NetMRI::HTTP::Client::Generic';
use URI::Escape;
use JSON;
use Data::Dumper;
use NetMRI::LoggerShare;

# How often retry connection to failed host
my $DEAD_HOST_TIMEOUT = 600;

sub new {
    my $class = shift;
    my %args = @_;
    for my $option (qw(proto host username password)) {
        die "Required parameter $option is not provided" unless ($args{$option});
    }
    NetMRI::LoggerShare::logDebug("Creating ACI HTTP Client");

    # We always start with first controller
    $args{auth_token_request_header} = 'Set-Cookie';
    $args{auth_token_response_header} = 'Set-Cookie';
    $args{requests_per_second} //= 3;
    $args{auth_token} = [ '' ]; # APIC controller stores session information in cookies. No need to send it explicitly
    $args{cookie_jar} = {};
    my $self = $class->SUPER::new(%args);
    $self->{updated_at} = time();
    $self->{controllers} = [];
    foreach my $host (@{$args{host}}) {
        push @{$self->{controllers}}, {address => $host, is_alive => 1, ts => time(), is_authenticated => 0};
    }
    $self->current_controller($self->{controllers}[0]);
    $self->base('', $self->_construct_base_url($self->current_controller()->{address}, $args{proto}));

    return bless $self, $class;

}

sub DESTROY {
    my $self = shift;
    $self->deauthenticate() if $self->authenticated();
}

sub authenticate {
    my ($self, $force) = @_;
    return 1 if (!$force && $self->authenticated());
    NetMRI::LoggerShare::logDebug("Authenticating to $self->{base}");
    my $body = to_json({aaaUser => {attributes => {name => $self->{args}->{username}, pwd => $self->{args}->{password}}}});
    my $res = $self->post('aaaLogin.json', undef, $body);
    NetMRI::LoggerShare::logDebug( ref $res->{data} ne 'HASH' ? $res->{data} :
        Dumper($res->{data}{imdata}[0]{aaaLogin}{attributes}));
    if ($res->{success}) {
        NetMRI::LoggerShare::logDebug("Auth successful");
        return $self->authenticated(1);
    } else {
        NetMRI::LoggerShare::logDebug("Auth failed");
        $self->authenticated(0);
        return (undef, $res->{data}{error}{message});
    }
}

sub deauthenticate {
    my $self = shift;
    NetMRI::LoggerShare::logDebug("Deauthenticating from $self->{base}");
    my $body = to_json({aaaUser => {attributes => {name => $self->{args}->{username}}}});
    my $res = $self->post('aaaLogout.json', undef, $body);
    # Delete old session token as ACI won't do it for us
    $self->{ua}->cookie_jar({});
    $self->authenticated(0);
}

sub check_session {
    my $self = shift;
    return $self->authenticated();
}

sub add_session_token {
    my $self = shift;
    my $request = shift;
    return unless $self->authenticated();
    $request->header($self->{auth_token_request_header}, "APIC-Cookie=$self->{auth_token}");
}

sub aci_request {
    my $self = shift;
    my $target = shift;

    my $url = $self->_construct_aci_request($target);

    my ($res, $unrecoverable_error, $no_more_controllers, $authenticated, $error);
    do {
        my $controller = $self->_get_available_controller();
        if ($controller) {
            $self->current_controller($controller);
            my $new_base = $self->_construct_base_url($controller->{address});
            if ($self->{base} ne $new_base) {
                NetMRI::LoggerShare::logDebug("Preferred controller has changed. Resetting session");
            }
            $self->base('', $new_base);
            NetMRI::LoggerShare::logDebug("Base url is $self->{base}");
            $authenticated = $self->authenticated();
            ($authenticated, $error) = $self->authenticate(1) unless $authenticated;
            if ($authenticated) {
                # At the moment, all our requests a read-only and there are no plans for NetMRI
                # to configure ACI. We'll add support for POST and other methods if we actually need it
                NetMRI::LoggerShare::logDebug("Fetching data from $url...");
                $res = $self->get($url);
                if ( !$res->{success} && $res->{data}->{error}->{code} =~/^40[13]$/ ) {
                    NetMRI::LoggerShare::logDebug("Error: $res->{data}->{error}->{message}");
                    NetMRI::LoggerShare::logDebug("Try to authenticate again...");
                    $self->authenticate(1);
                    $res = $self->get($url);
                }
            } else {
                NetMRI::LoggerShare::logDebug("Authenticate failed on controller $url...");
                $res = {success => '', data =>{error =>{message => $error}} };
            }
        } else {
            $no_more_controllers = 1;
        }
        # response should be successful and have structures from ACI response
        if ($res->{success}) {
            if (ref($res->{data}) eq 'HASH' && exists($res->{data}->{imdata})) {
                NetMRI::LoggerShare::logDebug("...data fetched");
                $self->_set_controller_status($controller, 1);
                return $res->{data}->{imdata};
            } else {
                # If we got here, we got 200 OK with invalid response body (e.g. from polling something other than ACI controller)
                NetMRI::LoggerShare::logDebug("Got invalid response from controller $controller->{address}");
                $res->{success} = undef;
                $res->{data} = {error => {code => 500, message => "Invalid response from $controller->{address}"}};
                #$self->_set_controller_status($controller, undef);
            }
        }
        if (!$res->{success} && !$no_more_controllers) {
            # If server reports error in ACI format, the controller is OK, and there's something wrong with our query or our credentials
            if (ref($res->{data}) eq 'HASH' && $res->{data}->{error}->{is_aci_error}) {
                NetMRI::LoggerShare::logDebug("Request failed. Due to nature of error, controller $controller->{address} is still considered valid");
                $unrecoverable_error = 1;
                $self->_set_controller_status($controller, 1); # Error on one node (e.g. node is down) should not prevent the controller from being usable on another
            } else { # In all other cases controller is either down or isn't ACI controller
                NetMRI::LoggerShare::logDebug("Request failed. Controller $controller->{address} is marked as invalid");
                $self->_set_controller_status($controller, undef);
            }
        }
    } until ($res->{success} || $unrecoverable_error || $no_more_controllers);

    return (undef, $res->{data}->{error}->{message}) if ($unrecoverable_error);
    if ($no_more_controllers) {
        my $message = 'All controllers are down';
        $message .= ': ' . $res->{data}->{error}->{message} if ($res->{data}->{error}->{message});
        return (undef, $message);
    }
    return (undef, $res->{data}->{error}->{message});
}

sub _set_controller_status {
    my ($self, $controller, $is_available) = @_;
    NetMRI::LoggerShare::logDebug("Marking controller $controller->{address} as " . ($is_available ? "valid" : "invalid"));
    $controller->{is_alive} = $is_available ? 1 : 0;
    $controller->{ts} = time();
}

sub _get_available_controller {
    my $self = shift;
    NetMRI::LoggerShare::logDebug("Current state of controllers: " . Dumper($self->{controllers}));

    # We want to recheck dead controllers periodically. This way we can go back
    # to polling preferred controller when it's brought online
    my $controller = (grep {$_->{is_alive} || ($_->{ts} < time() - $DEAD_HOST_TIMEOUT)} @{$self->{controllers}})[0];
    return defined($controller) ? $controller : undef;
}

sub _construct_aci_request {
    my $self = shift;
    my $target = shift;

    die "aci_request: target not defined" unless($target);
    return $target unless (ref($target)); # If the target is string, return it as is

    my $url = $self->_construct_target($target) . '.json';

    return $url . $self->_construct_param_string($target);

}

sub _construct_target {
    my $self = shift;
    my $target = shift;

    my $target_string;
    if ($target->{class}) {
        $target_string ='/api/node/class/';
        $target_string .= $target->{dn} . '/' if ($target->{dn});
        $target_string .= $target->{class};
    } elsif ($target->{dn}) {
        $target_string = '/api/node/mo/' . $target->{dn};
        $target_string .= '/'.$target->{subpath} if ($target->{subpath});
    }
    return $target_string;
}

sub _construct_param_string {
    my $self = shift;
    my $target = shift;

    # filter out target device params
    my $params = {map {$_ => $target->{$_}} (grep {!($_ =~ /^(dn|subpath|class)$/)} keys(%$target))};
    return '' unless (keys(%$params));

    # Taken from https://www.cisco.com/c/en/us/td/docs/switches/datacenter/aci/apic/sw/2-x/rest_cfg/2_1_x/b_Cisco_APIC_REST_API_Configuration_Guide/b_Cisco_APIC_REST_API_Configuration_Guide_chapter_01.html
    my @valid_params = qw(query-target target-subtree-class rsp-subtree rsp-subtree-class rsp-subtree-include query-target-filter rsp-subtree-filter order-by rsp-prop-include page-size page target-node target-path);
    foreach my $param (keys(%$params)) {
        die "aci_request: invalid parameter $param" unless (grep (/^$param$/, @valid_params)); 
    }

    my @query_array;
    for my $param (@valid_params) {
        next unless (exists($params->{$param}));
        my $val = uri_escape(ref($params->{$param}) eq 'ARRAY' ? join(',', @{$params->{$param}}) : $params->{$param});
        push @query_array, "$param=$val";
    }
    my $query_string = join('&', @query_array);
    return '?' . $query_string;
}

sub auth_required {
    my $self = shift;
    my $request = shift;
    return 1 if ($request->code == 401 || $request->code == 403);
    return undef; 
}

sub extract_error_data {
    my $self = shift;
    my $error_data = {};
    eval {
        $error_data = from_json($self->{response}->decoded_content()) if ($self->{response}->header('content-type') eq 'application/json');
    };
    my $error = $error_data->{imdata}[0]{error}{attributes};
    return $self->SUPER::extract_error_data() if ($@ || !$error); # Use generic version if server returns invalid json
    return ($error->{code}, $error->{text}, 'is_aci_error');
}

sub make_error_data {
    my ($self, $error_code, $error_message, $is_aci_error) = @_; 
    return {error => {code => $error_code, message => $error_message, is_aci_error => $is_aci_error ? 1 : undef}};
}

sub authenticated {
    my ($self, $flag) = @_;
    my $controller = $self->current_controller();
    $controller->{is_authenticated} = ($flag ? 1 : 0) if defined $flag;
    return $controller->{is_authenticated} || 0;
}

sub current_controller {
    my ($self, $new_controller) = @_;
    $self->{current_controller} = $new_controller if ($new_controller && ref($new_controller) eq 'HASH');
    return $self->{current_controller} || {};
}

sub _construct_base_url {
    my $self = shift;
    my $address = shift;
    my $proto = shift || $self->{args}{proto};

    my $base = "$proto://$address/api/";
    return $base;
}

1;
