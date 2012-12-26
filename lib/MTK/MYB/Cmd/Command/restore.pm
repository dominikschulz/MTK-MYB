package MTK::MYB::Cmd::Command::restore;
# ABSTRACT: Restore command for MYB

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
use MTK::MYB::Restore;

# extends ...
extends 'MTK::MYB::Cmd::Command';
# has ...
has 'dumpdir' => (
    'is'    => 'ro',
    'isa'   => 'Str',
    'required' => 1,
    'traits' => [qw(Getopt)],
    'cmd_aliases' => 'd',
    'documentation' => 'The source directory for restoring the backup',
);

# with ...
# initializers ...

# your code here ...
sub execute {
    my $self = shift;

    # TODO restore backup
    my $dumpdir = $self->dumpdir();
    if ( !$dumpdir ) {
        print "Error. Dumpdir not defined. Aborting.\n";
        return;
    }

    # remove trailing slash from dumpdir, if given
    $dumpdir =~ s#/$##;

    # test for existance of dumpdir
    if ( !-d $dumpdir ) {
        print "Error. Dir $dumpdir not found.\n";
        return;
    }

    print "RESTORING FROM $dumpdir ...\n";

    my $Restore = MTK::MYB::Restore::->new(
        {
            'config'    => $self->config(),
            'logger'    => $self->logger(),
            'backupdir' => $dumpdir,
        }
    );

    return $Restore->run();
}

sub abstract {
    return 'Restore some backups!';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd::Command::restore - Restore command for MYB

=method abstract

A descrition of this command.

=method execute

Run this command.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
