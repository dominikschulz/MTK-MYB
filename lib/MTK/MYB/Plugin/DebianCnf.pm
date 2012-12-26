package MTK::MYB::Plugin::DebianCnf;
# ABSTRACT: Plugin to read credentials from a debian.cnf

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
# use Try::Tiny;
use Config::Tiny;

# extends ...
extends 'MTK::MYB::Plugin';
# has ...
# with ...
# initializers ...
sub _init_priority { return 20; }

# your code here ...
sub run_config_hook {
    my $self = shift;
    my $debcnf = shift || '/etc/mysql/debian.cnf';

    if ( !-e $debcnf ) {
        $self->logger()->log( message => "File debian.cnf not found at $debcnf", level => 'notice', );
        return;
    }

    my $Config = Config::Tiny::->read($debcnf);
    if(!$Config) {
        # could not read file
        $self->logger()->log( message => 'Could not parse '.$debcnf, level => 'warning', );
        return;
    }

    my $c = $Config->{'client'};
    if($c && $c->{'user'} && $c->{'password'}) {
        $self->config()->set('MTK::Mysql::User::DebianSysMaint::Username',$c->{'user'});
        $self->config()->set('MTK::Mysql::User::DebianSysMaint::Password',$c->{'password'});
    }

    return 1;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin::DebianCnf - Plugin to read credentials from a debian.cnf

=method priority

This plugins relative priority.

=method run

Execute this plugin.

=method run_config_hook

Read a /etc/mysql/debian.cnf and contribute to the config.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
