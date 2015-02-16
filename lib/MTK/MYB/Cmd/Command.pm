package MTK::MYB::Cmd::Command;

# ABSTRACT: baseclass for any MYB command

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
use Config::Yak;
use Log::Tree;

# extends ...
extends 'MooseX::App::Cmd::Command';

# has ...
has '_config' => (
  'is'       => 'rw',
  'isa'      => 'Config::Yak',
  'lazy'     => 1,
  'builder'  => '_init_config',
  'accessor' => 'config',
);

has '_logger' => (
  'is'       => 'rw',
  'isa'      => 'Log::Tree',
  'lazy'     => 1,
  'builder'  => '_init_logger',
  'accessor' => 'logger',
);

# with ...
# initializers ...
sub _init_config {
  my $self = shift;

  my $Config = Config::Yak::->new(
    {
      'locations' => [qw(conf /etc/mtk)],
    }
  );

  return $Config;
} ## end sub _init_config

sub _init_logger {
  my $self = shift;

  my $Logger = Log::Tree::->new('mysqlbackup');

  return $Logger;
} ## end sub _init_logger

# your code here ...

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd::Command - baseclass for any MYB command

=head1 SYNOPSIS

    use MTK::App;
    my $App = MTK::App::->new();
    $App->run();

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
