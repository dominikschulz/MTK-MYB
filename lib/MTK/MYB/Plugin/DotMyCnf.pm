package MTK::MYB::Plugin::DotMyCnf;
# ABSTRACT: Plugin to read credentials from a users .my.cnf

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
sub _init_priority { return 15; }
# requires ...

# your code here ...
sub run_config_hook {
    my $self = shift;

    my $mycnf_file = $ENV{'HOME'}.'/.my.cnf';

    if ( !-e $mycnf_file ) {
        $self->logger()->log( message => "File .my.cnf not found at $mycnf_file.", level => 'notice', );
        return;
    }
    my $Config = Config::Tiny::->read($mycnf_file);
    if(!$Config) {
        # could not read file
        return;
    }

    my $c = $Config->{'client'};
    if($c && $c->{'user'} && $c->{'password'}) {
        if($c->{'user'} eq 'root') {
            $self->config()->set('MTK::Mysql::User::DBA::Username','root');
            $self->config()->set('MTK::Mysql::User::DBA::Password',$c->{'password'});
        } else {
            $self->config()->set('MTK::Mysql::User::User::Username',$c->{'user'});
            $self->config()->set('MTK::Mysql::User::User::Password',$c->{'password'});
        }
    }

    return 1;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin::MyCnf - Plugin to read credentials from a users .my.cnf

=method priority

This plugins relative priority.

=method run

Execute this plugin.

=method run_config_hook

Read a ~/.my.cnf and contribute to config.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
