package MTK::MYB;

# ABSTRACT: MySQL Backup

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;
use English qw( -no_match_vars );
use Try::Tiny;
use File::Temp qw();
use Format::Human::Bytes;

use Data::Persist;
use Job::Manager;
use MTK::MYB::Codes;
use MTK::MYB::Status;
use MTK::MYB::Packer;
use MTK::MYB::Job;
use Module::Pluggable::Object;
use Sys::Run;
use Sys::FS;

has 'cacher' => (
  'is'      => 'ro',
  'isa'     => 'Data::Persist',
  'lazy'    => 1,
  'builder' => '_init_cacher',
);

has 'status' => (
  'is'      => 'ro',
  'isa'     => 'MTK::MYB::Status',
  'lazy'    => 1,
  'builder' => '_init_status',
);

has 'sys' => (
  'is'      => 'rw',
  'isa'     => 'Sys::Run',
  'lazy'    => 1,
  'builder' => '_init_sys',
);

has 'fs' => (
  'is'      => 'rw',
  'isa'     => 'Sys::FS',
  'lazy'    => 1,
  'builder' => '_init_fs',
);

has 'bank' => (
  'is'      => 'ro',
  'isa'     => 'Str',
  'lazy'    => 1,
  'builder' => '_init_bank',
);

has 'status_cache_dir' => (
  'is'      => 'ro',
  'isa'     => 'Str',
  'lazy'    => 1,
  'builder' => '_init_status_cache_dir',
);

has 'debug' => (
  'is'      => 'rw',
  'isa'     => 'Bool',
  'default' => 0,
);

with 'Config::Yak::OrderedPlugins' => { -version => 0.18 };

############################################
# PRIVATE API
############################################

#############################
# Part 1: Helper methods
#############################
# Short, simple helper

sub _plugin_base_class { return 'MTK::MYB::Plugin'; }

sub BUILD {
  my $self = shift;

  # Important: Make sure to initialize the cache dir in the parent!
  my $dir = $self->status_cache_dir();

  return 1;
} ## end sub BUILD

sub _init_status_cache_dir {
  my $self = shift;

  my $dir = File::Temp::tempdir( CLEANUP => 1, );

  return $dir;
} ## end sub _init_status_cache_dir

sub _init_cacher {
  my $self = shift;

  my $Cacher = Data::Persist::->new(
    {
      'logger'   => $self->logger(),
      'filename' => $self->status_cache_dir() . '/parent.cache',
    }
  );

  return $Cacher;
} ## end sub _init_cacher

sub _init_bank {
  my $self = shift;

  return $self->config()->get( 'MTK::MYB::Bank', { Default => '/srv/backup/mysql', } );
}

sub _init_sys {
  my $self = shift;

  my $Sys = Sys::Run::->new( { 'logger' => $self->logger(), } );

  return $Sys;
} ## end sub _init_sys

sub _init_fs {
  my $self = shift;

  my $FS = Sys::FS::->new(
    {
      'logger' => $self->logger(),
      'sys'    => $self->sys(),
    }
  );

  return $FS;
} ## end sub _init_fs

sub _init_logger {
  my $self = shift;

  my $Log = Log::Tree::->new('mysqlbackup');

  return $Log;
} ## end sub _init_logger

sub _init_status {
  my $self = shift;
  return MTK::MYB::Status::->new();
}

#############################
# Part 2: Structural methods
#############################
# Those define the control flow

sub _prepare {
  my $self = shift;

  if ( !$self->configure() ) {
    $self->logger()->log( message => 'Configure step failed. Aborting!', level => 'error', );
    return;
  }

  foreach my $Plugin ( @{ $self->plugins() } ) {
    try {
      if ( $Plugin->run_prepare_hook() ) {
        $self->logger()->log( message => 'prepare hook of Plugin ' . ref($Plugin) . ' run successfully.', level => 'debug', );
      }
      else {
        $self->logger()->log( message => 'prepare hook of Plugin ' . ref($Plugin) . ' failed to run.', level => 'debug', );
      }
    } ## end try
    catch {
      $self->logger()->log( message => 'Failed to run prepare hook of ' . ref($Plugin) . ' w/ error: ' . $_, level => 'warning', );
    };
  } ## end foreach my $Plugin ( @{ $self...})

  return 1;
} ## end sub _prepare

sub run {
  my $self = shift;

  $self->logger()->log( message => 'Backup starting', level => 'debug', );

  # "preparatory" steps must succeed. if the backup was run
  # we don't care about the results anymore and just try to
  # clean up as much as possible
  if ( !$self->_exec_pre() ) {
    $self->_cleanup(0);
    return;
  }
  if ( !$self->_prepare() ) {
    $self->_cleanup(0);
    return;
  }
  my $global_status = $self->_run();

  # translate the (perlish) return code of the jobqueue to the (unixish) return
  # code of the status object
  if ($global_status) {

    # $global_status == true ~ 0
    $self->status()->global( MTK::MYB::Codes::get_status_code('OK') );
  }
  else {

    # $global_status != true ~ 1
    $self->status()->global( MTK::MYB::Codes::get_status_code('OK') );
  }

  if ( $self->_cleanup($global_status) ) {
    $self->logger()->log( message => '_cleanup OK', level => 'debug', );
  }
  else {
    $self->logger()->log( message => '_cleanup failed!', level => 'warning', );
  }
  $self->_exec_post();

  $self->logger()->log( message => 'Backup finished. Returning global status: ' . $global_status, level => 'debug', );

  return $global_status;
} ## end sub run

sub _run {
  my $self = shift;

  # Loop control
  my $concurrency     = $self->config()->get( 'MTK::MYB::Concurrency', { Default => 1, } );
  my @childs          = ();
  my $forks_running   = 0;
  my $childs_returned = 0;

  $self->logger()->prefix('[PARENT]');

  $self->logger()->log( message => 'Dispatching workers. Concurrency is ' . $concurrency, level => 'debug', );

  #
  # THIS IS THE MAIN LOOP
  # Backup each mysqld instance
  #
  my $JQ = Job::Manager::->new(
    {
      'logger'      => $self->logger(),
      'concurrency' => $concurrency,
    }
  );

  my $dbms_ref = $self->config()->get('MTK::MYB::DBMS');

  if ( !$dbms_ref ) {

    #print $self->config()->dump();
    $self->logger()->log( message => 'No DBMS defined. Aborting!', level => 'error', );
    return;
  } ## end if ( !$dbms_ref )

  foreach my $dbms ( sort keys %{$dbms_ref} ) {
    try {
      my $Job = $self->_get_job($dbms);
      if ( $JQ->add($Job) ) {
        $self->logger()->log( message => 'Added Job for DBMS ' . $dbms, level => 'debug', );
      }
    } ## end try
    catch {
      $self->logger()->log( message => 'Could not create Job for DBMS ' . $dbms . ', Error: ' . $_, level => 'error', );
    };
  } ## end foreach my $dbms ( sort keys...)

  # Job::Manager return values: undef - error, 1 - ok
  my $status = $JQ->run();

  $self->logger()->log( message => 'Collected all child stati. All Jobs have finished. Returning status: ' . $status, level => 'debug', );
  $self->logger()->prefix('');

  return $status;
} ## end sub _run

sub _get_job {
  my $self  = shift;
  my $vault = shift;

  my $Job = MTK::MYB::Job::->new(
    {
      'parent' => $self,
      'vault'  => $vault,
      'logger' => $self->logger(),
      'config' => $self->config(),
      'bank'   => $self->bank(),
    }
  );

  return $Job;
} ## end sub _get_job

sub _exec {
  my $self = shift;
  my $sec  = shift;
  my $type = shift;
  my $opts = shift || {};

  local $opts->{AppendLog}     = 0;
  local $opts->{CaptureOutput} = 0;
  local $opts->{Timeout}       = $self->config()->get('MTK::MYB::ExecTimeout') || 3600;

  my @exec = $self->config()->get_array( 'MTK::MYB::Exec' . $type );
  return 0 if !@exec;

  my $status = 1;
  foreach my $cmd (@exec) {
    if ( $opts->{CurrentDB} ) {
      $cmd =~ s/_DBNAME_/$opts->{CurrentDB}/g;
    }
    $cmd = $self->reporter()->fill_placeholder( [$cmd], 'myb', $self->status(), $self->logger() );

    # fill_placeholder will return an ARRAY_ref, so we have to assemble it again since run_cmd expects a SCALAR
    if ( ref($cmd) eq 'ARRAY' ) {
      $cmd = join( q{ }, @{$cmd} );
    }
    $self->logger()->log( message => '_exec(' . $sec . q{,} . $type . ') - Running CMD: ' . $cmd, level => 'debug', );
    if ( $self->sys()->run_cmd( $cmd, $opts ) ) {
      $self->logger()->log( message => '_exec(' . $sec . q{,} . $type . ') - Command successfull.', level => 'debug', );
    }
    else {
      $self->logger()->log( message => '_exec(' . $sec . q{,} . $type . ') - Command failed.', level => 'debug', );
      $status = 0;
    }
  } ## end foreach my $cmd (@exec)
  return $status;
} ## end sub _exec

# Executed before mysqld(s) is/are locked
sub _exec_pre {
  my $self = shift;

  my $status = 1;

  # exec_pre are MANDATORY pre-exec scripts which MUST NOT FAIL
  if ( $self->config()->get('MTK::MYB::ExecPre') ) {
    $status = $self->_exec( 'default', 'Pre' );
  }

  # exec_pre_opt are OPTIONAL pre-exec scripts which MAY FAIL
  # so the return code of these is just ignored
  if ( $self->config()->get('MTK::MYB::ExecPreOpt') ) {
    $self->_exec( 'default', 'PreOpt' );
  }

  if ($status) {
    return 1;
  }
  else {
    return;
  }
} ## end sub _exec_pre

# Executed while mysqld(s) is/are locked
sub _exec_main {
  my $self = shift;
  my $dbms = shift;

  my $opts = {};
  $opts->{CurrentDB} = $dbms;

  my $status = 1;

  # global exec_main
  if ( $self->config()->get('MTK::MYB::ExecMain') ) {
    $status = $self->_exec( 'default', 'Main', $opts );
  }

  # per-instance exec_main
  if ( $self->config()->get( 'MTK::MYB::DBMS::' . $dbms . '::ExecMain' ) ) {
    $status = $self->_exec( $dbms, 'Main', $opts );
  }

  return $status;
} ## end sub _exec_main

# Executed after mysqld(s) is/are unlocked
sub _exec_post {
  my $self = shift;

  if ( $self->config()->get('MTK::MYB::ExecPost') ) {
    return $self->_exec( 'default', 'Post' );
  }
  else {
    $self->logger()->log( message => 'Nothing to do for exec_post.', level => 'debug', );
    return;
  }
} ## end sub _exec_post

sub _merge_child_stati {
  my $self = shift;

  my $files_processed = 0;

  # merge cached information
  if ( -d $self->status_cache_dir() && opendir( my $DH, $self->status_cache_dir() ) ) {
    $self->logger()->log( message => 'Reading child stati from Status-Dir at ' . $self->status_cache_dir(), level => 'debug', );
  FILE: while ( my $dir_entry = readdir($DH) ) {
      next if $dir_entry =~ m/^\./;
      my $path = $self->status_cache_dir() . q{/} . $dir_entry;
      next unless -e $path;
      next unless $dir_entry =~ m/child-\d+\.cache$/;

      $self->logger()->log( message => 'Merging Child-Status from ' . $path, level => 'debug', );

      # dbms, status and logger
      my $child_ref = $self->cacher()->read($path);
      if ( !$child_ref || ref($child_ref) ne 'HASH' ) {
        $self->logger()->log( message => 'Could not read Child-Status from ' . $path, level => 'warning', );
        next FILE;
      }
      my $child_dbms   = $child_ref->{'dbms'};
      my $child_stati  = $child_ref->{'stati'};
      my $child_logbuf = $child_ref->{'logbuf'};

      # merge stati
      foreach my $dbms ( keys %{$child_stati} ) {
        foreach my $db ( keys %{ $child_stati->{$dbms} } ) {
          foreach my $table ( keys %{ $child_stati->{$dbms}->{$db} } ) {
            foreach my $type ( keys %{ $child_stati->{$dbms}->{$db}->{$table} } ) {
              my $status_code = $child_stati->{$dbms}->{$db}->{$table}->{$type};
              my $status_text = MTK::MYB::Codes::get_status_text($status_code);
              $self->status()->set_table_status( $dbms, $db, $table, $status_code, $type );
              $self->logger()->log(
                message => 'Set table status of ' . $dbms . q{.} . $db . q{.} . $table . q{.} . $type . ' to ' . $status_code . ' (' . $status_text . ')',
                level   => 'debug',
              );
            } ## end foreach my $type ( keys %{ ...})
          } ## end foreach my $table ( keys %{...})
        } ## end foreach my $db ( keys %{ $child_stati...})
      } ## end foreach my $dbms ( keys %{$child_stati...})

      # merge logger
      foreach my $entry ( @{$child_logbuf} ) {
        $self->logger()->add_to_buffer($entry);
      }

      # remove file after processing
      unlink($path);

      $files_processed++;
    } ## end FILE: while ( my $dir_entry = readdir...)
    closedir($DH);
  } ## end if ( -d $self->status_cache_dir...)
  else {
    $self->logger()->log( message => 'Status-Dir at ' . $self->status_cache_dir() . ' not found!', level => 'warning', );
  }
  return $files_processed;
} ## end sub _merge_child_stati

sub _cleanup {
  my $self = shift;
  my $ok   = shift;

  $self->_merge_child_stati();

  foreach my $Plugin ( @{ $self->plugins() } ) {
    try {
      if ( $Plugin->run_cleanup_hook($ok) ) {
        $self->logger()->log( message => 'cleanup hook of Plugin ' . ref($Plugin) . ' run successfully.', level => 'debug', );
      }
      else {
        $self->logger()->log( message => 'cleanup hook of Plugin ' . ref($Plugin) . ' failed to run.', level => 'notice', );
      }
    } ## end try
    catch {
      $self->logger()->log( message => 'Failed to run cleanup hook of ' . ref($Plugin) . ' w/ error: ' . $_, level => 'warning', );
    };
  } ## end foreach my $Plugin ( @{ $self...})

  return 1;
} ## end sub _cleanup

sub configure {
  my $self = shift;

  foreach my $Plugin ( @{ $self->plugins() } ) {
    try {
      if ( $Plugin->run_config_hook() ) {
        $self->logger()->log( message => 'config hook of Plugin ' . ref($Plugin) . ' run successfully.', level => 'debug', );
      }
      else {
        $self->logger()->log( message => 'config hook of Plugin ' . ref($Plugin) . ' failed to run.', level => 'notice', );
      }
    } ## end try
    catch {
      $self->logger()->log( message => 'Failed to run config hook of ' . ref($Plugin) . ' w/ error: ' . $_, level => 'warning', );
    };
  } ## end foreach my $Plugin ( @{ $self...})

  return 1;
} ## end sub configure

############################################
# PUBLIC API
############################################

sub type {
  return 'myb';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB - MySQL Backup

=head1 SYNOPSIS

    use MTK::MYB;
    my $MYB = MTK::MYB::->new({
        'config'    => Config::Yak::->new(),
        'logger'    => Log::Tree::->new('mysqlbackup'),
    });
    $MYB->start();
    
=head1 RISKS

This section is included to help users of this tool to assess the risk associated
with using it. The two main categories adressed are those created the idea
implemented and those created by bugs. There may be other risks as well.

B<myb> is mostly a read-only tool that will, however, lock your database server
for the duration of the backup. This will cause service interruptions as long as
you don't take precautions. Either point the script to an dedicated slave or
chose an idle time for running it.

=head1 SEE ALSO

L<Percona XtraBackup|http://www.percona.com/software/percona-xtrabackup> is an
advanced approach for backing up InnoDB and XtraDB tables. It does provide little
advantage in terms of MyISAM backups.

L<Holland Backup|http://wiki.hollandbackup.org/> is an multi-db backup application
written in Python.
    
=head1 DESCRIPTION

This class implements a sophisticated MySQL Backup tool. It is cappable of
performing fully automated backups using credentials detected from common
configuration files. This class is extendable so that different backup strategies
can by implemented by subclassing this class.

=method type

This method is primarily usefull for subclassing this class. It is used to
dynamically determine the exact subtype of itself. Of course this
could as well be done by using ISA and/or ref. Howevery this way is more
straight forward and easier to implement.

=method BUILD

Initializes the cache dir. Must be done in the parent.

=method configure

Run the configure hook on all plugins.

=method run

Once the class has been set up call this method to start the backup process.

=head1 HACKING

=head2 USING MOOSE

Moose crashcourse:
- 'has' is an ordinary perl method (i.e. a sub)
- it creates a hash entry with the name after 'has', i.e. $self->{'config'}
- it defined accessors (setter and getter) with this name, i.e. $self->config() [getter], and $self->config($value) [setter]
- it adds type checking to the setter
- required means that this attribute must be defined in the constructor or
  this instantication of this class will fail
- lazy means that this attribute will be initialized on first access
- lazy requires some kind of builder
- builder defines the name of a sub that is resolved via name resolution
- builder doesn't take a coderef, i.e. it does dynamic method resolution at runtime
- why would you use lazy and builders? to defer work until it is really needed and to
  help with subclassing, i.e. the builders can easily be overridden (or even defined) in subclasses
- extends is roughly equiv. to 'use base' or 'use parent'
- there is neither a 'new' nor a 'DESTROY' method. those are generated by Moose
- if you need to do work during new or DESTROY you'd use BUILD or DEMOLISH

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
