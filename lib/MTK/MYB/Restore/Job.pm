package MTK::MYB::Restore::Job;
# ABSTRACT: a MYB restore job

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

use MTK::MYB::Restore::Worker;

extends 'Job::Manager::Job';

has 'filename' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

foreach my $key (qw(username password hostname)) {
    has $key => (
        'is'       => 'ro',
        'isa'      => 'Str',
        'required' => 1,
    );
}

has 'port' => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'default' => 3306,
);

sub _init_worker {
    my $self = shift;

    my $Worker = MTK::MYB::Restore::Worker::->new(
        {
            'config'   => $self->config(),
            'logger'   => $self->logger(),
            'filename' => $self->filename(),
            'username' => $self->username(),
            'password' => $self->password(),
            'hostname' => $self->hostname(),
            'port'     => $self->port(),
        }
    );

    return $Worker;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Restore::Job - an mysqlbackup restore job

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
