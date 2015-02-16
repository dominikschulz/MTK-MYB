package MTK::MYB::Cmd::Command::backupcheck;

# ABSTRACT: Run the MYB backup checker

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
use MTK::MYB::Checker;

# extends ...
extends 'MTK::MYB::Cmd::Command';

# has ...
# with ...
# initializers ...

# your code here ...
sub execute {
  my $self = shift;

  # check backup
  my $Checker = MTK::MYB::Checker::->new(
    {
      'config'  => $self->config(),
      'logger'  => $self->logger(),
      'bank'    => $self->config()->get( 'MTK::MYB::Bank', { Default => '/srv/backup/mysql', } ),
      'min_pc'  => $self->config()->get( 'MTK::MYB::Check::MinPC', { Default => 85, } ),
      'max_age' => $self->config()->get( 'MTK::MYB::Check::MaxAge', { Default => 30, } ),
    }
  );
  return $Checker->run();
} ## end sub execute

sub abstract {
  return 'Check the integrity of your backups';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd::Command::backupcheck - Run the MYB backup checker

=method abstract

A descrition of this command.

=method execute

Run this command.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
