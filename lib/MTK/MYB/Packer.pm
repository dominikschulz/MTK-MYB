package MTK::MYB::Packer;
# ABSTRACT: a wrapper around different compression binaries

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

use Sys::Run;
use Test::MockObject::Universal;

has 'config_prefix' => (
    'is'      => 'rw',
    'isa'     => 'Str',
    'default' => 'MTK::MYB',
);

has '_exe' => (
    'is'  => 'rw',
    'isa' => 'Str',
);

has '_opts' => (
    'is'  => 'rw',
    'isa' => 'ArrayRef[Str]',
);

has '_ext' => (
    'is'  => 'rw',
    'isa' => 'Str',
);

has 'sys' => (
    'is'      => 'ro',
    'isa'     => 'Sys::Run',
    'lazy'    => 1,
    'builder' => '_init_sys',
);

with qw(Config::Yak::RequiredConfig Log::Tree::RequiredLogger);

sub _init_sys {
    my $self = shift;

    my $Sys = Sys::Run::->new( { 'logger' => $self->logger(), } );

    return $Sys;
}

sub _init {
    my $self = shift;

    # see if we can fullfill the requested packer or
    # choose the best alternative if not
    my $req = $self->config()->get( $self->config_prefix() . '::Packer', { Default => 'gzip', } );
    my $pack_ref = $self->packers();

    if ( $pack_ref->{$req} && $self->sys()->check_binary($req) ) {

        # ok, requested packer available
        $self->_exe( $self->sys()->check_binary($req) );
        $self->_opts( $pack_ref->{$req}->{'opts'} );
        $self->_ext( '.' . $pack_ref->{$req}->{'ext'} );
        return 1;
    }
    else {

        # nope, requested one not found. find another one
        foreach my $key ( sort { $pack_ref->{$b}->{'prio'} <=> $pack_ref->{$a}->{'prio'} } keys %{$pack_ref} ) {
            if ( my $exe = $self->sys()->check_binary( $pack_ref->{$key}->{'exe'} ) ) {
                $self->_exe($exe);
                $self->_opts( $pack_ref->{$key}->{'opts'} );
                $self->_ext( '.' . $pack_ref->{$key}->{'ext'} );
                return 1;
            }
        }
        return;
    }
}

sub packers {
    my $self = shift;

    # a List of available packers, order by preference, most prefereable one first
    my %packer = (
        'pigz' => {
            exe  => 'pigz',
            opts => [qw(-c --fast -f --no-name)],
            desc => 'Parallel gzip',
            ext  => 'gz',
            prio => 10,
        },
        'gzip' => {
            exe  => 'gzip',
            opts => [qw(-c --fast -f --rsyncable --no-name)],
            desc => 'Regular gzip',
            ext  => 'gz',
            prio => 9,
        },
        'pbzip2' => {
            exe  => 'pbzip2',
            opts => [qw(-c --fast)],
            desc => 'Parallel bzip2',
            ext  => 'bz2',
            prio => 8,
        },
        'lbzip2' => {
            exe  => 'lbzip2',
            opts => [qw(-c --fast)],
            desc => 'Parallel bzip2',
            ext  => 'bz2',
            prio => 8,
        },
        'lzo' => {
            exe  => 'lzop',
            opts => [qw(-c --fast)],
            desc => 'Blazingly fast. Poor compression.',
            ext  => 'lzo',
            prio => 7,
        },
        'xz' => {
            exe  => 'xz',
            opts => [qw(-c --fast)],
            desc => 'Successor of LZMA',
            ext  => 'xz',
            prio => 6,
        },
        'lzma' => {
            exe  => 'lzma',
            opts => [qw(-c --fast)],
            desc => 'lzma implements an improved version of the LZ77 algorithm',
            ext  => 'lzma',
            prio => 5,
        },
        'cat' => {
            exe  => 'cat',
            opts => [qw()],
            desc => 'No compression.',
            ext  => '',
            prio => 1,
        },
    );
    return \%packer;
}

sub ext {
    my $self = shift;

    if ( !$self->_ext() ) {
        $self->_init();
    }

    return $self->_ext();
}

sub exe {
    my $self = shift;

    if ( !$self->_exe() ) {
        $self->_init();
    }

    return $self->_exe();
}

sub opts {
    my $self = shift;

    if ( !$self->_opts() ) {
        $self->_init();
    }

    return $self->_opts();
}

sub cmd {
    my $self = shift;
    return $self->exe() . q{ } . join( q{ }, @{ $self->opts() } );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Packer - a wrapper around different compression binaries

=method cmd

TODO DOC

=method exe

TODO DOC

=method ext

TODO DOC

=method opts

TODO DOC

=method packers

TODO DOC

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
