package MTK::MYB::Cmd::Command::run;

# ABSTRACT: Run the MYB

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
use Linux::Pidfile;
use MTK::MYB;

# extends ...
extends 'MTK::MYB::Cmd::Command';

# has ...
has '_pidfile' => (
  'is'      => 'ro',
  'isa'     => 'Linux::Pidfile',
  'lazy'    => 1,
  'builder' => '_init_pidfile',
);

# with ...
# initializers ...
sub _init_pidfile {
  my $self = shift;

  my $PID = Linux::Pidfile::->new(
    {
      'pidfile' => $self->config()->get( 'MTK::MYB::Pidfile', { Default => '/var/run/myb.pid', } ),
      'logger'  => $self->logger(),
    }
  );

  return $PID;
} ## end sub _init_pidfile

# your code here ...

sub execute {
  my $self = shift;

  $self->_pidfile()->create() or die('Script already running.');

  my $MYB = MTK::MYB::->new(
    {
      'config' => $self->config(),
      'logger' => $self->logger(),
    }
  );

  my $status = $MYB->run();

  $self->_pidfile()->remove();

  return $status;
} ## end sub execute

sub abstract {
  return 'Make some backups^!°';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd::Command::run - Run the MYB

=method abstract

A descrition of this command.

=method execute

Run this command.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
