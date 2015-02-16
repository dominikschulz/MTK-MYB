package MTK::MYB::Restore;

# ABSTRACT: the MYB restore helper

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

use Job::Manager;
use MTK::MYB::Restore::Job;
use MTK::DB::Credentials;
use Sys::Run;
use Sys::CPU;

has 'config' => (
  'is'       => 'ro',
  'isa'      => 'Config::Yak',
  'required' => 1,
);

has 'logger' => (
  'is'       => 'ro',
  'isa'      => 'Log::Tree',
  'required' => 1,
);

has 'backupdir' => (
  'is'       => 'ro',
  'isa'      => 'Str',
  'required' => 1,
);

has 'concurrency' => (
  'is'      => 'ro',
  'isa'     => 'Int',
  'lazy'    => 1,
  'builder' => '_init_concurrency',
);

has 'sys' => (
  'is'      => 'rw',
  'isa'     => 'Sys::Run',
  'lazy'    => 1,
  'builder' => '_init_sys',
);

sub _init_concurrency {
  my $self = shift;

  my $cpu_factor = 1;

  if ( my $f = $self->config()->get('MTK:::Mysqlbackup::Restore::CpuFactor') ) {
    $cpu_factor = $f;
  }

  return Sys::CPU::cpu_count() * $cpu_factor;
} ## end sub _init_concurrency

sub _init_sys {
  my $self = shift;

  my $Sys = Sys::Run::->new( { 'logger' => $self->logger(), } );

  return $Sys;
} ## end sub _init_sys

sub _scan_dbs {
  my $self = shift;

  my @dbs = ();

  if ( -d $self->backupdir() && opendir( my $DH, $self->backupdir() ) ) {
    if ( -d $self->backupdir() . '/mysql' ) {
      push( @dbs, 'mysql' );
    }
    while ( my $dir_entry = readdir($DH) ) {
      next if $dir_entry =~ m/^\./;
      my $path = $self->backupdir() . q{/} . $dir_entry;
      next unless -d $path;

      # the db mysql is already handled above
      next if $dir_entry eq 'mysql';
      push( @dbs, $dir_entry );
    } ## end while ( my $dir_entry = readdir...)
    closedir($DH);
  } ## end if ( -d $self->backupdir...)

  return @dbs;
} ## end sub _scan_dbs

sub _scan_tables {
  my $self = shift;

  my @dbs   = $self->_scan_dbs();
  my @files = ();

  foreach my $db (@dbs) {
    if ( -d $self->backupdir() . q{/} . $db && opendir( my $DH, $self->backupdir() . q{/} . $db ) ) {
      while ( my $dir_entry = readdir($DH) ) {
        next if $dir_entry =~ m/^\./;
        my $path = $self->backupdir() . q{/} . $db . q{/} . $dir_entry;
        next unless -e $path;
        push( @files, $path );
      } ## end while ( my $dir_entry = readdir...)
      closedir($DH);
    } ## end if ( -d $self->backupdir...)
  } ## end foreach my $db (@dbs)

  return @files;
} ## end sub _scan_tables

sub run {
  my $self = shift;

  my $hostname = $self->config()->get( 'MTK::MYB::Restore::Hostname', { Default => 'localhost', } );
  my $port     = $self->config()->get( 'MTK::MYB::Restore::Port',     { Default => 3306, } );
  my $Creds    = MTK::DB::Credentials::->new(
    {
      'config'   => $self->config(),
      'hostname' => $hostname,
      'keys'     => [qw(MTK::MYB::Restore)],
      'logger'   => $self->logger(),
    }
  );
  my $username = $Creds->username();
  my $password = $Creds->password();
  $Creds = undef;

  my $JQ = Job::Manager::->new(
    {
      'logger'      => $self->logger(),
      'concurrency' => $self->concurrency(),
    }
  );

  foreach my $filename ( $self->_scan_tables() ) {
    my $Job = MTK::MYB::Restore::Job::->new(
      {
        'filename' => $filename,
        'username' => $username,
        'password' => $password,
        'hostname' => $hostname,
        'port'     => $port,
        'logger'   => $self->logger(),
      }
    );
    $JQ->add($Job);
  } ## end foreach my $filename ( $self...)

  return $JQ->run();
} ## end sub run

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Restore - the MYB restore helper

=method run

Restore all configured tables.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
