package MTK::MYB::Status;
# ABSTRACT: a MYB backup status object

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

# global status, used for misc. purposes. the default value of '1' means error
has 'global' => (
    'is'      => 'rw',
    'isa'     => 'Num',
    'default' => 1,
);

has 'dbms' => (
    'is'      => 'rw',
    'isa'     => 'HashRef',
    'default' => sub { {} },
);

has 'exec' => (
    'is'      => 'rw',
    'isa'     => 'ArrayRef',
    'default' => sub { [] },
);

sub set_table_status {
    my $self   = shift;
    my $dbms   = shift;
    my $db     = shift;
    my $table  = shift;
    my $status = shift;
    my $type   = shift;

    $self->dbms()->{$dbms}->{$db}->{$table}->{$type} = $status;

    # return the value set
    return $self->dbms()->{$dbms}->{$db}->{$table}->{$type};
}

sub tables {
    my $self = shift;

    return $self->_get_type('table');
}

sub dumps {
    my $self = shift;

    return $self->_get_type('dump');
}

sub structs {
    my $self = shift;

    return $self->_get_type('struct');
}

sub _get_type {
    my $self = shift;
    my $type = shift;

    my $data_ref = {};
    foreach my $dbms ( keys %{ $self->dbms() } ) {
        foreach my $db ( keys %{ $self->dbms()->{$dbms} } ) {
            foreach my $table ( keys %{ $self->dbms()->{$dbms}->{$db} } ) {
                if ( defined( $self->dbms()->{$dbms}->{$db}->{$table}->{$type} ) ) {
                    my $status = $self->dbms()->{$dbms}->{$db}->{$table}->{$type};
                    $data_ref->{$dbms}->{$db}->{$table} = $status;
                }
            }
        }
    }

    return $data_ref;
}

sub ok {
    my $self = shift;

    my $sum = $self->global();

    foreach my $rv ( @{ $self->exec() } ) {
        $sum += $rv;
    }

    foreach my $dbms ( keys %{ $self->dbms() } ) {
        foreach my $db ( keys %{ $self->dbms()->{$dbms} } ) {
            foreach my $table ( keys %{ $self->dbms()->{$dbms}->{$db} } ) {
                foreach my $type ( keys %{ $self->dbms()->{$dbms}->{$db}->{$table} } ) {
                    my $object_status = $self->dbms()->{$dbms}->{$db}->{$table}->{$type};
                    $sum += $object_status if $object_status >= 0;
                }
            }
        }
    }

    if ( !$sum ) {
        return 1;    # everything ok
    }
    else {
        return;      # some error
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Status - an Mysqlbackup status object

=method dumps

TODO DOC

=method ok

TODO DOC

=method set_table_status

TODO DOC

=method structs

TODO DOC

=method tables

TODO DOC

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
