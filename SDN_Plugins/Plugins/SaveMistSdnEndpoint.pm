package NetMRI::SDN::Plugins::SaveMistSdnEndpoint;

use base qw(NetMRI::SDN::Plugins::SaveSdnEndpoint);

sub required_fields {
  return {
    DeviceID       => '^\d+$',
    Name           => '',
    MAC            => ''
  };
}

1;