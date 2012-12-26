package MTK::MYB::Job;
# ABSTRACT: an MYB Job

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

use MTK::MYB::Worker;

extends 'Job::Manager::Job';

has 'parent' => (
    'is'       => 'ro',
    'isa'      => 'MTK::MYB',
    'required' => 1,
);

has 'verbose' => (
    'is'      => 'rw',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'dry' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'default' => 0,
);

has 'bank' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'vault' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

sub _init_worker {
    my $self = shift;

    my $Worker = MTK::MYB::Worker::->new(
        {
            'config'  => $self->config(),
            'logger'  => $self->logger(),
            'parent'  => $self->parent(),
            'verbose' => $self->verbose(),
            'dry'     => $self->dry(),
            'bank'    => $self->bank(),
            'vault'   => $self->vault(),
        }
    );

    return $Worker;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Job - an Mysqlbackup Job

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
