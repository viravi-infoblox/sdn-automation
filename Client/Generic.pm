package NetMRI::HTTP::Client::Generic;

require 5.000;

use strict;
no warnings;
use Redis;
use Time::HiRes qw(usleep);
use LWP::UserAgent;
use HTTP::Request;
use MIME::Base64;
use NetMRI::LoggerShare;
use Data::Dumper;
use JSON;
use Carp;
use NetMRI::Util::HW;
use IO::Socket::SSL;

sub new {
  my ($type, %args) = @_;
  my $self = {args => \%args};
  my $requests_per_hour = defined $self->{args}->{requests_per_hour}
    ? $self->{args}->{requests_per_hour}
    : $ENV{NETMRI_SDN_MAX_REQUESTS_PER_HOUR};
  my $check_ssl_cert = '/var/local/netmri/sdn.no_ca.debug';
  if (NetMRI::Util::HW::isAutomationGridMember()) {
    $check_ssl_cert = '/storage/infoblox.var/netmri/sdn.no_ca.debug';
  }
  $self->{ua} = LWP::UserAgent->new(
    agent      => ($self->{args}->{agent}      || 'netmri_http_client'),
    timeout    => ($self->{args}->{timeout}    || 60),
    no_proxy   => ($self->{args}->{noproxy}    || []),
    cookie_jar => ($self->{args}->{cookie_jar} || undef));
  NetMRI::LoggerShare::logDebug("Checking SSL Certificate is " . ((-e $check_ssl_cert) ? "OFF" : "ON")); 
  NetMRI::LoggerShare::logDebug("Loaded IO::Socket::SSL version=${IO::Socket::SSL::VERSION}");
  $self->{ua}->ssl_opts( verify_hostname => 0, SSL_verify_mode => 0x00) if (-e $check_ssl_cert || (defined $self->{args}->{no_cert_check} && $self->{args}->{no_cert_check}));

  $self->{auth_token_response_header} = $self->{args}->{auth_token_response_header} || 'X-Auth-Token';
  $self->{auth_token_request_header}  = $self->{args}->{auth_token_request_header}  || 'Authentication';
  $self->{auth_token}                 = $self->{args}->{auth_token}                 || $self->{args}->{api_key} || '';
  $self->{requests_per_second}        = $self->_normalize_rate_limit($self->{args}->{requests_per_second});
  $self->{requests_per_hour}          = $self->_normalize_rate_limit($requests_per_hour);
  $self->{request_max_queue_time}     = $self->{args}->{request_max_queue_time} || 3600;
  $self->{too_many_requests_max_retry} = $self->{args}->{too_many_requests_max_retry} || 5;
  $self->{retry_if_auth_failed} = 1;

  $self->{port} = $self->{args}->{port};

  my $res = bless $self, $type;

  #handle proxy settings
  $res->proxy($self->{args}->{proxy});
  $res->base();

  return $res;
}

sub base {
  my ($self, $particular_api_version, $new_base) = @_;
  $self->{base} = '';
  $new_base = $self->{args}->{base} unless length($new_base);
  if ($new_base && $new_base =~/^(http|https|ftp)\:\/{2}/) {
    $self->{base} = $new_base;
    #handle variable substitution
    $particular_api_version = $self->supported_version() unless length($particular_api_version);
    $self->{base} =~ s/\%version\%/$particular_api_version/g;
  }
  return $self->{base};
}

sub server_version {
  my $self = shift;
  return $self->{server_version} || 0;
}

sub supported_version {
  my $self = shift;
  return $self->{supported_version} || 0;
}

sub no_proxy {
  my ($self, @noproxy) = @_;
  $self->{ua}->no_proxy(@noproxy);
}

sub proxy {
  my ($self, $proxy_settings) = @_;
  return unless defined $proxy_settings;

  $self->{proxy_setting_string} = undef;
  $self->{proxy_setting_proto}  = 'connect';
  if (!ref($proxy_settings)) {
    $self->{proxy_setting_string} = $proxy_settings;
  } elsif (ref($proxy_settings) eq 'HASH' && $proxy_settings->{host}) {
    if ($proxy_settings->{username}) {
      $self->{proxy_setting_string} .= $proxy_settings->{username};
      $self->{proxy_setting_string} .= ':' . $proxy_settings->{password} if $proxy_settings->{password};
      $self->{proxy_setting_string} .= '@';
    }
    $self->{proxy_setting_string} .= $proxy_settings->{host};
    $self->{proxy_setting_string} .= sprintf(':%d', $proxy_settings->{port}) if int($proxy_settings->{port}) > 0;
    $self->{proxy_setting_proto}  = $proxy_settings->{proto} if $proxy_settings->{proto};
  }
  if ($self->{proxy_setting_string}) {
    $self->{ua}->proxy(['http', 'ftp', 'https'], $self->{proxy_setting_proto} . '://' . $self->{proxy_setting_string});
  }
}

sub get {
  my ($self, $uri, $api_version, $params) = @_;
  return $self->perform_request('get', $uri, $api_version, $params);
}

sub post {
  my ($self, $uri, $api_version, $params) = @_;
  return $self->perform_request('post', $uri, $api_version, $params);
}

sub put {
  my ($self, $uri, $api_version, $params) = @_;
  return $self->perform_request('put', $uri, $api_version,  $params);
}

sub delete {
  my ($self, $uri, $api_version, $params) = @_;
  return $self->perform_request('delete', $uri, $api_version, $params);
}

sub perform_request {
  my ($self, $request_type, $uri, $api_version, $params) = @_;
  $api_version = '' unless defined $api_version;
  $self->_throttle();
  local $Data::Dumper::Indent = 0;
  NetMRI::LoggerShare::logDebug("Perform ${request_type} request uri=${uri}, api_version=${api_version}");
  NetMRI::LoggerShare::logDebug("Request parameters: " . Dumper($params)) if $params;
  my $res =  $self->request_params_valid($request_type, $uri, $api_version, $params) > 0
    ? $self->process_request($self->make_request_object($request_type, $uri, $params))
    : $self->error_response();

  my $retry_count = 0;
  while ($self->too_many_requests_response($res) && $retry_count < $self->{too_many_requests_max_retry}) {
    $retry_count++;
    NetMRI::LoggerShare::logWarn(sprintf(
      "Iteration %d, request uri=${uri} - too many connections detected, code=%s message=%s, sleeping for 1 sec and retry...", 
      $retry_count,
      $res->{data}->{error}->{code}||'', 
      $res->{data}->{error}->{message}||''
    ));
    sleep 1;
    $self->_throttle();
    $res = $self->process_request($self->make_request_object($request_type, $uri, $params));    
  }

  unless ($res->{success}) {
    NetMRI::LoggerShare::logWarn(sprintf("request uri=${uri} failed, code=%s message=%s", $res->{error}->{code}, $res->{error}->{message}||'')) if ($res->{error} && $res->{error}->{code}); 
  }
  NetMRI::LoggerShare::logDebug("Request result: " . Dumper($res));
  return $res;
}

sub request_params_valid {
  my ($self, $request_type, $url, $api_version, $params) = @_;
  $self->base($api_version) if ($api_version);
  if (length($self->{base}) == 0 && $url !~ /^(http|ftp|https)\:\/\//i) {
    $self->{request_data} =
      $self->make_error_data(500, 'request uri must be absolute in case of $self->{base} property is empty');
    $self->{success} = 0;
    return 0;
  }

  return 1;
}

sub error_response {
  my $self = shift;
  return {success => 0, data => $self->{request_data}};
}

sub make_error_data {
  my ($self, $error_code, $error_message) = @_;
  return {error => {code => $error_code, message => $error_message}};
}

sub extract_error_data {
    my $self = shift;
    my $response = $self->{response};

    return ($response->code, $response->message);
}

sub is_authenticated {
    my $self = shift;
    return $self->{is_authenticated};
}
# Generic version. Subclasses can terminate session on server side, throw away session data, etc.
sub deauthenticate {
    my $self = shift;
    $self->{is_authenticated} = undef;
}
sub authenticate {
    my $self = shift;
    return 1; # Generic implementation assumes all necessary data (e.g. API key) is already sent in the headers. Subclasses must override it
}
sub add_session_token {
    my $self = shift;
    my $request = shift;
    $self->add_headers($request);
}
sub check_session {
    my $self = shift;
    my $force = shift;

    return {success => 1 } if ($self->is_authenticated() && !$force);
    $self->{retry_if_auth_failed} = 0;
    $self->deauthenticate() if ($self->is_authenticated());
    my $res = $self->authenticate();
    $self->{retry_if_auth_failed} = 1;
    return $res;
}

sub process_request {
  my ($self, $request) = @_;
  #$self->{request} = $request;
  $self->add_session_token($request);
  my $response = $self->{ua}->request($request);
  $self->{response} = $response;
  if ($self->{retry_if_auth_failed} && $self->auth_required($response)) {
    #repeat the same request with username/password instead of auth token
    $self->check_session('force_refresh');
    # No point in retrying request if the user supplied wrong password. also, we return more useful
    # error message ('auth failed: that's why') instead of less useful ('invalid session')
    if ($self->{is_authenticated}) {
        $response = $self->{ua}->request($request);
    } else {
        # $self->{response} contains last response from check_session()
        $response = $self->{response};
    }
  }
  $self->find_auth_token($response);
  $self->parse_response($response);
  return {success => $self->{success} || 0, data => $self->{request_data}};
}

sub make_request_object {
  my ($self, $method, $url, $params) = @_;

  my $request_has_body = $self->request_has_body($method, $params);
  if (!$request_has_body && $params && (lc($method) eq 'get' || lc($method) eq 'delete')) {
    $url = $self->add_parameters_to_url($url, $params);
  }
  my $request = HTTP::Request->new(uc($method), $self->process_url($url));
  $self->request_content($request, $params) if ($request_has_body && $params);
  $self->add_headers($request);
  return $request;
}

sub add_headers {
  my ($self, $request) = @_;
  my $headers = $self->request_header();
  while (my ($k, $v) = splice(@$headers, 0, 2)) {
    $request->header($k, $v);
  }
}

sub find_auth_token {
  my ($self, $response) = @_;
  #find auth token
  my $t = $response->header($self->{auth_token_response_header});
  $self->{auth_token} = $t if $t;
}

sub request_has_body {
  my ($self, $method, $params) = @_;
  return (lc($method) ne 'get' && lc($method) ne 'delete');
}

sub process_url {
  my ($self, $url) = @_;

  delete($self->{port}) if ($self->{port} && $self->{port} =~ /\D/);

  $url = URI->new_abs($url, $self->{base}) if $self->{base};
  my $uri = URI->new($url);
  my $ca_cert = $self->{args}->{ca_cert} || '';
  if (ref($self->{ua}) && $uri->scheme eq 'https' && $ca_cert) {
    my $host = $uri->host;
    $self->{ua}->ssl_opts(SSL_ca_file => $ca_cert, SSL_verifycn_name => $host) if $host;
  }
  return URI->new($uri->scheme . '://' . $uri->host . ':' . ($self->{port} || $uri->port) . $uri->path_query)->canonical . "";
}

sub parse_response {
  my ($self, $response) = @_;
  $self->{response} = $response;
  $self->{success}  = $response->is_success;
  unless ($self->{success}) {
    $self->{request_data} = $self->make_error_data($self->extract_error_data());
    return 0;
  }

  # convert request body using specific converter
  my $method_name = "parse_content_" . $self->content_type_to_snake($response->header('content-type') || 'text/html');
  my $result = $response->decoded_content;
  $self->$method_name(\$result) if $self->can($method_name);
  $self->{request_data} = $result;
  return 1;
}

sub add_parameters_to_url {
  my ($self, $url, $params) = @_;
  $url = URI->new($url);
  my @old_data = $url->query_form();
  $url->query_form(ref($params) eq "HASH" ? %$params : @$params);
  $url->query_form($url->query_form, @old_data);
  return $url->as_string;
}

sub request_header {
  my $self  = shift;
  my $res   = [];
  my $token = $self->auth_token_header_data();
  if (ref($token) eq 'ARRAY') {
    push @$res, @$token;
  } else {
    my $auth_string = $self->auth_header_data();
    push @$res, @$auth_string if ref($auth_string) eq 'ARRAY';
  }
  return $res;
}

sub request_content {
  my ($self, $req, $content) = @_;
  my $ct = $req->header('Content-Type');
  if ($req->method eq 'POST' && $req->uri->path =~ /broadcastCli/ && !$req->content) {
    $ct = 'application/json';
  }
  unless ($ct) {
    $ct = 'application/x-www-form-urlencoded';
  } elsif ($ct eq 'form-data') {
    $ct = 'multipart/form-data';
  }

  if (ref $content) {
    if ($ct =~ m,^multipart/form-data\s*(;|$),i) {
      require HTTP::Headers::Util;
      my @v = HTTP::Headers::Util::split_header_words($ct);
      Carp::carp("Multiple Content-Type headers") if @v > 1;
      @v = @{$v[0]};

      my $boundary;
      my $boundary_index;
      for (my @tmp = @v; @tmp;) {
        my ($k, $v) = splice(@tmp, 0, 2);
        if ($k eq "boundary") {
          $boundary       = $v;
          $boundary_index = @v - @tmp - 1;
          last;
        }
      }

      ($content, $boundary) = HTTP::Request::Common::form_data($content, $boundary, $req);

      if ($boundary_index) {
        $v[$boundary_index] = $boundary;
      } else {
        push(@v, boundary => $boundary);
      }
      $ct = HTTP::Headers::Util::join_header_words(@v);
    } else {
      require URI;
      my $url = URI->new('http:');
      $url->query_form(ref($content) eq "HASH" ? %$content : @$content);
      $content = $url->query;
    }
  }

  $req->header('Content-Type' => $ct);
  if (defined($content)) {
    $req->header('Content-Length' => length($content)) unless ref($content);
    $req->content($content);
  } else {
    $req->header('Content-Length' => 0);
  }
  return undef;
}

sub auth_required {
    my $self = shift;
    my $response = shift;
    return 1 if ($response->code == 401);
    return undef;
}

sub auth_token_header_data {
  my $self = shift;
  return $self->{auth_token} ? [$self->{auth_token_request_header}, $self->{auth_token}] : undef;
}

sub auth_header_data {
  my $self = shift;
  my $res  = undef;
  if ($self->{args}->{username} && $self->{args}->{password}) {
    $res = [
      'Authorization',
      'Basic ' . MIME::Base64::encode_base64url($self->{args}->{username} . ':' . $self->{args}->{password}) . '='
    ];
  }
  return $res;
}

sub content_type_to_snake {
  my ($self, $string) = @_;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  $string =~ s/\;.*$//;
  $string =~ s/\W/\_/g;
  return lc($string);
}

sub parse_content_application_json {
  my ($self, $content) = @_;
  eval {
      $$content = decode_json($$content);
  };
  if ($@) {
    $$content = $self->make_error_data(500, "JSON parsing error: $@");
  }
}

sub too_many_requests_response {
  my ($self, $res) = @_;
  return undef;
}

sub get_throttle_key {
  my $self = shift;
  return $self->{fabric_id} || 'Global';
}

sub _normalize_rate_limit {
  my ($self, $value) = @_;
  return 0 unless defined $value;
  return int($value) if ($value =~ /^\d+$/);
  return 0;
}

sub _throttle {
  my $self = shift;
  return if ($self->{requests_per_second} < 1 && $self->{requests_per_hour} < 1);
  my $redis = Redis->new();
  return unless ref $redis;

  $self->_throttle_window($redis, 1, $self->{requests_per_second}, 'requests per second');
  $self->_throttle_window($redis, 3600, $self->{requests_per_hour}, 'requests per hour');
}

sub _throttle_window {
  my ($self, $redis, $window_seconds, $limit, $metric_name) = @_;
  return if $limit < 1;

  my $call_cnt = $self->_incr_window($redis, $window_seconds);
  my $start_time = time();
  while (($call_cnt > $limit) && ((time()-$start_time) < $self->{request_max_queue_time})) {
    # For large windows (e.g. per-hour), sleep until the Redis key expires
    # (i.e. until the window resets) rather than polling every ~0.6s.
    # For sub-second or very short windows, fall back to the original short sleep.
    my $sleep_seconds = $self->_sleep_until_window_reset($redis, $window_seconds);
    NetMRI::LoggerShare::logDebug("_throttle: ${metric_name} limit exceeded for key ["
                                  . $self->get_throttle_key()
                                  . "] (${metric_name} count: ${call_cnt}, max: ${limit}), sleeping for ${sleep_seconds}s");
    sleep($sleep_seconds);
    $call_cnt = $self->_incr_window($redis, $window_seconds);
  }

  NetMRI::LoggerShare::logDebug("_throttle: exit cycle ["
                                  . $self->get_throttle_key()
                                  . "] ${metric_name} count: ${call_cnt}, max: ${limit}");
}

# Returns how many seconds to sleep before the current window resets.
# Uses Redis TTL of the active key so sleep is aligned to the exact window expiry.
# Falls back to time-based calculation if TTL is unavailable.
sub _sleep_until_window_reset {
  my ($self, $redis, $window_seconds) = @_;

  my $window_start = int(time() / $window_seconds) * $window_seconds;
  my $key = $self->get_throttle_key() . "/${window_seconds}/${window_start}";

  # Ask Redis how many seconds remain on this key's TTL
  my $ttl = eval { $redis->ttl($key) } // -1;

  if ($ttl > 0) {
    # Sleep exactly as long as Redis says the key will live,
    # plus a small buffer so the new window key is ready.
    return $ttl + 1;
  }

  # Fallback: compute remaining seconds in the current window from wall clock.
  my $seconds_elapsed_in_window = time() % $window_seconds;
  my $remaining = $window_seconds - $seconds_elapsed_in_window;
  return $remaining > 0 ? $remaining : 1;
}

sub _incr {
  my ($self, $redis) = @_;
  return $self->_incr_window($redis, 1);
}

sub _incr_window {
  my ($self, $redis, $window_seconds) = @_;
  # Bucketize time so all requests in the same window share one Redis key.
  my $window_start = int(time() / $window_seconds) * $window_seconds;
  my $key = $self->get_throttle_key() . "/${window_seconds}/${window_start}";
  my $res = $redis->incr($key);
  $redis->expire($key, $window_seconds + 1);
  return $res;
}

1;
