package MTK::MYB::Cmd;
# ABSTRACT: The MYB CLI

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

# extends ...
extends 'MooseX::App::Cmd';
# has ...
# with ...
# initializers ...

# your code here ...

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd - Command base class.

=head1 SYNOPSIS

    use MTK::Cmd;
    my $Cmd = MTK::MYB::Cmd::->new();
    $Cmd->run();

=head1 DESCRIPTION

This class is the base class for any command implemented by its subclasses.

It is a mere requirement by App::Cmd. Don't mess with it.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
