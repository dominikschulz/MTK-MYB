package MTK::MYB::Checker::Plugin;
# ABSTRACT: the base class for any MYB checker plugin

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
# has ...
# with ...
with qw(Log::Tree::RequiredLogger Config::Yak::RequiredConfig);
# initializers ...

# your code here ...
sub priority { return 10; }

sub run_prepare_hook {
    my $self = shift;
    my $JQ = shift;

    return;
}

sub run_cleanup_hook {
    my $self = shift;
    my $status = shift;

    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Checker::Plugin - the base class for any MYB checker plugin

=method priority

This plugins relative priority.

=method run_cleanup_hook

Executed after the check script was run.

=method run_prepare_hook

Executed before the check script is run.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
