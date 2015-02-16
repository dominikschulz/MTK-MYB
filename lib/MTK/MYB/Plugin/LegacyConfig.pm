package MTK::MYB::Plugin::LegacyConfig;

# ABSTRACT: Plugin to convert any legacy config stanzas to the new layout

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
extends 'MTK::MYB::Plugin';

# has ...
# with ...
# initializers ...
sub _init_priority { return 50; }

# your code here ...
# check the config for deprecated variables
sub run_config_hook {
  my $self = shift;

  # conversion table from old key to new key
  my %conv = (
    'mysql_host'             => 'Hostname',
    'do_binlog'              => 'BinlogArchive',
    'do_tables'              => 'CopyTable',
    'do_struct'              => 'DumpStruct',
    'do_dump'                => 'DumpTable',
    'exec_main'              => 'ExecMain',
    'exec_post'              => 'ExecPost',
    'exec_post_opt'          => 'ExecPostOpt',
    'exec_pre'               => 'ExecPre',
    'exec_pre_opt'           => 'ExecPreOpt',
    'exec_timeout'           => 'ExecTimeout',
    'holdbacktime_binlog'    => 'Rotations::Binlogs',
    'ionice_sleep'           => 'SleepBetweenTables',
    'link_unmodified'        => 'LinkUnmodified',
    'link_unmodified_innodb' => 'LinkUnmodifiedInnodb',
    'do_flushlogs'           => 'FlushLogs',
  );

  my $all_ok = 1;
  foreach my $old_key ( keys %conv ) {
    my $new_key = $conv{$old_key};
    if ( $self->config()->get( 'MTK::Mysqlbackup::' . $old_key ) ) {
      $self->logger()->log( message => 'DEPRECATED CONFIGURATION VARIABLE DETECTED: ' . $old_key . ' replace by ' . $new_key, level => 'warning', );

      # set the appropriate new key to the value of the old key
      $self->config()->set( 'MTK::Mysqlbackup::' . $new_key, $self->config()->get( 'MTK::Mysqlbackup::' . $old_key ) );
      $all_ok = 0;
    } ## end if ( $self->config()->...)
  } ## end foreach my $old_key ( keys ...)

  # convert namespace MTK::Mysqlbackup to MTK::MYB
  foreach my $key ( keys %{ $self->config()->get('MTK::Mysqlbackup') } ) {
    my $new_key = 'MTK::MYB::' . $key;
    my $old_key = 'MTK::Mysqlbackup::' . $key;
    $self->config()->set( $new_key, $self->config()->get($old_key) );
    $self->config()->delete($old_key);
    $all_ok = 0;
  } ## end foreach my $key ( keys %{ $self...})

  return $all_ok;
} ## end sub run_config_hook

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin::LegacyConfig - Plugin to convert any legacy config stanzas to the new layout

=method priority

This plugins relative priority.

=method run

Execute this plugin.

=method run_config_hook

Check the config for deprecated keys and translate those to their

recent counterparts if possible.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
