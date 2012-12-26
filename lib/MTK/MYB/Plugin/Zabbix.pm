package MTK::MYB::Plugin::Zabbix;
# ABSTRACT: Plugin to report success/failure via Zabbix::Sender

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;
# use Carp;
# use English qw( -no_match_vars );
use Try::Tiny;
use Zabbix::Sender;
use MTK::MYB::Codes;
use Sys::Hostname::FQDN ();

# extends ...
extends 'MTK::MYB::Plugin';
# has ...
# with ...
# initializers ...
sub _init_priority { return 11; }

# your code here ...
sub run_prepare_hook {
    my $self = shift;

    my $zabbix_item = $self->config()->get( 'MTK::MYB::ZabbixItemStartTime', { Default => 'mysqlbackup.start', } ); # to plugin
    return $self->zabbix_send( Sys::Hostname::FQDN::fqdn(), $zabbix_item, scalar( time() ) );
}

sub run_cleanup_hook {
    my $self = shift;
    my $ok = shift;

    # report to Zabbix
    my $zabbix_status = MTK::MYB::Codes::get_status_code('UNDEF-ERROR');    # Error by default
    if ( $self->parent->status()->ok() ) {
        $zabbix_status = MTK::MYB::Codes::get_status_code('OK');            # OK
    }

    my $fqdn = Sys::Hostname::FQDN::fqdn();

    my $zabbix_item = $self->config()->get( 'MTK::MYB::ZabbixItemStatus', { Default => 'mysqlbackup.status', } );
    $self->zabbix_send( $fqdn, $zabbix_item, $zabbix_status );
    $zabbix_item = $self->config()->get( 'MTK::MYB::ZabbixItemFinishTime', { Default => 'mysqlbackup.end', } );
    $self->zabbix_send( $fqdn, $zabbix_item, scalar( time() ) );

    return 1;
}

sub zabbix_send {
    my $self        = shift;
    my $hostname    = shift;
    my $zabbix_item = shift;
    my $item_value  = shift;

    if ( my $zabbix_server = $self->config()->get('Zabbix::Server') ) {
        $self->logger()->log( message => 'Using Zabbix Server at '.$zabbix_server, level => 'debug', );
        my $port = $self->config()->get( 'Zabbix::Port', { Default => 10051, } );
        my $arg_ref = {
            'server' => $zabbix_server,
            'port'   => $port,
        };
        $arg_ref->{'hostname'} = $hostname if $hostname;
        my $sent = undef;

        try {
            my $Zabbix = Zabbix::Sender::->new($arg_ref);
            $sent = $Zabbix->send( $zabbix_item, $item_value );
        }
        catch {
            $self->logger()->log( message => 'Zabbix::Sender failed w/ error: '.$_, level => 'error', );
        };

        if ($sent) {
            $self->logger()
              ->log( message => 'Successfully sent '.$zabbix_item.q{ = }.$item_value.' for '.$hostname.' to Zabbix Server '.$zabbix_server.q{:}.$port, level => 'debug', );
            return 1;
        }
        else {
            $self->logger()
              ->log( message => 'Could not send '.$zabbix_item.q{ = }.$item_value.' for '.$hostname.' to Zabbix Server '.$zabbix_server.q{:}.$port, level => 'error', );
            return;
        }
    }
    else {
        $self->logger()->log( message => 'No Zabbix Server configured.', level => 'debug', );
        return;
    }
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin::Zabbix - Plugin to report success/failure via Zabbix::Sender

=method priority

This plugins relative priority.

=method run

Execute this plugin.

=method run_prepare_hook

Send the start timestamp to zabbix.

=method run_cleanup_hook

Send the end timestamp to zabbix.

=method zabbix_send

Send some item to zabbix.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
