package MTK::MYB::Cmd::Command::cleanup;
# ABSTRACT: Cleanup left over backups

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
use Sys::RotateBackup;
use MTK::MYB;

# extends ...
extends 'MTK::MYB::Cmd::Command';
# has ...
# with ...
# initializers ...
# your code here ...
sub execute {
    my $self = shift;

    my $MYB = MTK::MYB::->new({
        'config'    => $self->config(),
        'logger'    => $self->logger(),
    });

    if(!$MYB->configure()) {
        $self->logger()->log( message => 'Configure failed! Aborting!', level => 'debug', );
        return;
    }

    my $dbms_ref = $MYB->config()->get('MTK::MYB::DBMS');
    if($dbms_ref && ref($dbms_ref) eq 'HASH') {
        # check each DBMS if it is accessible
        foreach my $dbms (sort keys %{$dbms_ref}) {
            # rotate the backups
            my $Rotor = Sys::RotateBackup::->new(
                {
                    'logger'  => $self->logger(),
                    'sys'     => $MYB->sys(),
                    'vault'   => $MYB->fs()->filename( ( $MYB->bank(), $dbms ) ),
                    'daily'   => $self->config()->get( 'MTK::MYB::Rotations::Daily', { Default => 10, } ),
                    'weekly'  => $self->config()->get( 'MTK::MYB::Rotations::Weekly', { Default => 4, } ),
                    'monthly' => $self->config()->get( 'MTK::MYB::Rotations::Monthly', { Default => 12, } ),
                    'yearly'  => $self->config()->get( 'MTK::MYB::Rotations::Yearly', { Default => 10, } ),
                }
            );
            $Rotor->cleanup();
        }
    }

    return 1;
}

sub abstract {
    return 'Clean up old and/or broken backup dirs and files. Useful for migrations, otherwise seldomly useful.';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd::Command::cleanup - Cleanup left over backups

=method abstract

A descrition of this command.

=method execute

Run this command.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
