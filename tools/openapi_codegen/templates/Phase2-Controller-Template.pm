package NetMRI::SDN::__VENDOR__;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use NetMRI::SDN::Base;
use NetMRI::Util::Date;
use NetMRI::Util::Network qw(netmaskFromPrefix maskStringFromPrefix InetAddr);
use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{vendor_name} = '__VENDOR_DISPLAY_NAME__';
    $self->{SaveDevices_unique_fieldname} = 'Serial';
    return bless $self, $class;
}

sub getApiClient {
    my $self = shift;
    my $api_helper = $self->SUPER::getApiClient();
    unless (ref($api_helper)) {
        $self->{logger}->error('__VENDOR__[' . ($self->{fabric_id} // '') . '] getApiClient: Error getting the API Client');
        return undef;
    }
    return $api_helper;
}

sub loadSdnDevices {
    my $self = shift;

    $self->{logger}->info('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: started');

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveDevices');
    my $query;

    $self->{dn} = '' unless defined $self->{dn};

    if ($self->{dn} eq '') {
        $query = 'select * from ' . $device_plugin->target_table() . ' where SdnControllerId=' . $sql->escape($self->{fabric_id});
    }
    else {
        $query = 'select * from ' . $device_plugin->target_table() . ' where SdnDeviceDN = ' . $sql->escape($self->{dn}) . ' and SdnControllerId=' . $sql->escape($self->{fabric_id});
    }

    my $sdn_devices = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$sdn_devices) {
        $self->{logger}->error('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: No devices for FabricID');
        return;
    }

    $self->{logger}->info('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: ' . scalar(@$sdn_devices) . ' entries');
    $self->{logger}->debug(Dumper($sdn_devices)) if ($self->{logger}->{Debug} && scalar(@$sdn_devices));
    $self->{logger}->info('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: finished');

    return $sdn_devices;
}

__CONTEXT_HELPERS__

sub obtainEverything {
__OBTAIN_EVERYTHING_BODY__
}

__COLLECTION_METHODS__

__API_WRAPPER_METHODS__

sub handle_error {
    my ($self, $resp, $datapoint, $dataset) = @_;
    my $err_text = '__VENDOR__ ' . $datapoint . ' failed';
    $err_text .= ' for device ' . $self->{dn} if defined $self->{dn} && length $self->{dn};
    $err_text .= ": " . Dumper($resp) if defined $resp;
    $self->{logger}->warn($err_text) if $self->{logger};

    if ($dataset && $self->can('updateDataCollectionStatus')) {
        $self->updateDataCollectionStatus($dataset, 'Error');
    }
}

1;
