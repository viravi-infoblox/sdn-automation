package NetMRI::HTTP::Client::GenericJson;

require 5.000;

use strict;
use NetMRI::HTTP::Client::Generic;
use JSON;

use vars qw(@ISA);
@ISA = qw(NetMRI::HTTP::Client::Generic);

sub request_has_body {
  return 1;
}

sub request_content {
  my ($self, $req, $params) = @_;
  my $body = encode_json($params);
  $req->header('Content-Type', 'application/json');
  if (length($body)) {
    $req->header('Content-Length' => length($body));
    $req->content($body);
  } else {
    $req->header('Content-Length' => 0);
  }
}

1;
