package MTK::MYB::Checker::Plugin::Zabbix;
# ABSTRACT: a Zabbix Sender plugin for the MYB backup integrity checker

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
use Sys::Hostname::FQDN;

# extends ...
extends 'MTK::MYB::Checker::Plugin';
# has ...
# with ...
# initializers ...

# your code here ...

sub run_cleanup_hook {
    my $self = shift;
    my $ok = shift;

    my $hostname = Sys::Hostname::FQDN::fqdn();
    my $item = $self->config()->get( 'MTK::MYB::Check::ZabbixItem', { Default => 'mysqlbackup.p49.fileage', } );

    return $self->zabbix_report($ok,$hostname,$item);
}

sub zabbix_report {
    my $self     = shift;
    my $status   = shift;
    my $hostname = shift;
    my $item     = shift;

    if ( my $zabbix_server = $self->config()->get('Zabbix::Server') ) {
        $self->logger()->log( message => 'Using Zabbix Server at '.$zabbix_server, level => 'debug', );
        my $arg_ref = {
            'server' => $zabbix_server,
            'port'   => $self->config()->get('Zabbix::Port') || 10_051,
        };
        $arg_ref->{'hostname'} = $hostname if $hostname;
        try {
            my $Zabbix = Zabbix::Sender::->new($arg_ref);
            $Zabbix->send( $item, $status );
            $Zabbix = undef;
        }
        catch {
            $self->logger()->log( message => 'Zabbix::Sender failed w/ error: '.$_, level => 'error', );
        };
        return 1;
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

MTK::Slavecount::Plugin::Zabbix - a Zabbix Sender plugin for the MYB backup integrity checker

=method run_prepare_hook

Not implemented in this plugin.

=method run_cleanup_hook

Report fileage to zabbix.

=method zabbix_report

Send some item to zabbix.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
