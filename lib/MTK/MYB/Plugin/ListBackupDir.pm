package MTK::MYB::Plugin::ListBackupDir;

# ABSTRACT: Plugin to list the backup directory

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;
# use Carp;
use English qw( -no_match_vars );

# use Try::Tiny;

# extends ...
extends 'MTK::MYB::Plugin';

# has ...
# with ...
# initializers ...
sub _init_priority { return 10; }

# your code here ...
# Used to add a list of the current dataset to the log
sub run_cleanup_hook {
  my $self = shift;
  my $ok   = shift;
  my $dir  = shift;

  if ( !$dir ) {
    $dir = $self->parent()->bank();
    $self->logger()->log( message => "No Backup Dir given. Using default: $dir", level => 'debug', );
  }

  if ( $dir && !-d $dir ) {
    $self->logger()->log( message => "Backup dir ($dir) is no directory. Aborting!", level => 4 );
    return;
  }

  local $INPUT_RECORD_SEPARATOR = "\n";

  my $cmd = '/usr/bin/find ' . $dir . ' -type f -exec ls -la {} \;';
  $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );

  my @out = $self->parent()->sys()->run_cmd( $cmd, { CaptureOutput => 1, Chmop => 1, } );

  if (@out) {
    foreach my $line (@out) {
      chomp($line);
      my ( $perms, $hls, $user, $group, $size, $day, $month, $hm, $file ) = split /\s+/, $line;
      $self->logger()->log( message => $file . q{ - } . Format::Human::Bytes::base2($size) . " - $day $month $hm - Links: $hls", level => 'debug', );
    }
    return 1;
  } ## end if (@out)
  else {
    $self->logger()->log( message => 'Failed to execute command. Error: ' . $OS_ERROR, level => 'error', );
    return;
  }
} ## end sub run_cleanup_hook

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin::ListBackupDir - Plugin to list the backup directory

=method priority

This plugins relative priority.

=method run

Execute this plugin.

=method run_cleanup_hook

Add content of the backup dir to the log buffer.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
