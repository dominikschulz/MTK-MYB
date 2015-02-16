package MTK::MYB::Cmd::Command::configcheck;

# ABSTRACT: Check the MYB config

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
use Try::Tiny;
use MTK::MYB;
use MTK::DB::Credentials;

# extends ...
extends 'MTK::MYB::Cmd::Command';

# has ...
has 'myb' => (
  'is'      => 'rw',
  'isa'     => 'MTK::MYB',
  'lazy'    => 1,
  'builder' => '_init_myb',
);

# with ...
# initializers ...
sub _init_myb {
  my $self = shift;

  my $MYB = MTK::MYB::->new(
    {
      'config' => $self->config(),
      'logger' => $self->logger(),
    }
  );

  return $MYB;
} ## end sub _init_myb

# your code here ...
sub _check_bank {
  my $self = shift;

  # do we have a bank?
  my $bank = $self->myb()->bank();
  if ($bank) {
    say 'OK - Bank directory configured: ' . $bank;

    # is the bank a directory?
    if ( -d $bank ) {
      say 'OK - Bank location is a directory';

      # is it writeable?
      if ( -w $bank ) {
        say 'OK - Bank location is writeable';
      }
      else {
        say 'ERROR - Bank directory is not writebale!';
        return;
      }
    } ## end if ( -d $bank )
    else {
      say 'ERROR - Configured Bank is no directory!';
      return;
    }
  } ## end if ($bank)
  else {
    say 'ERROR - No bank configured!';
    return;
  }

  return 1;
} ## end sub _check_bank

sub _check_basics {
  my $self = shift;

  # do we actually do some backups?
  my $dump_table  = $self->myb()->config()->get('MTK::MYB::DumpTable');
  my $dump_struct = $self->myb()->config()->get('MTK::MYB::DumpStruct');
  my $copy_table  = $self->myb()->config()->get('MTK::MYB::CopyTable');

  if ($dump_table) {
    say 'OK - DumpTable is enabled!';
  }
  if ($copy_table) {
    say 'OK - CopyTable is enabled!';
  }
  if ($dump_struct) {
    say 'INFO - DumpStruct is enabled';
  }
  if ( !$dump_table && !$copy_table ) {
    say 'ERROR - DumpTable and CopyTable set to false. Not doing any backups!';
    return;
  }

  return 1;
} ## end sub _check_basics

sub _dbms_list {
  my $self = shift;
  return $self->myb()->config()->get('MTK::MYB::DBMS');
}

sub _check_dbmss {
  my $self = shift;

  my $bank = $self->myb()->bank();

  # do we have at least one DBMS?
  my $dbms_ref = $self->_dbms_list();
  my $num_dbms = 0;
  my $status   = 1;
  if ( $dbms_ref && ref($dbms_ref) eq 'HASH' ) {

    # check each DBMS if it is accessible
    foreach my $dbms ( sort keys %{$dbms_ref} ) {
      say 'INFO - Checking ' . $dbms;

      # make sure the vault directory is writeable
      my $dbms_dir = $bank . q{/} . $dbms;
      if ( -e $dbms_dir && !-w $dbms_dir ) {
        say ' ERROR - Vault dir ' . $dbms_dir . 'not writeable! Make sure the directory exists and is writeable for ' . $UID . q{:} . $GID;
        $status = 0;
      }

      my $src_ip = $self->myb()->config()->get( 'MTK::MYB::DBMS::' . $dbms . '::ip' );

      # make sure the source is defined
      if ( !$src_ip ) {
        say ' WARNING - Source IP for ' . $dbms . ' not defined!';
      }
      $num_dbms++;

      # check access to the DBMS
      if ( $self->_check_dbms($dbms) ) {
        say 'OK - DBMS instance ' . $dbms . ' looks good';
      }
      else {
        say 'ERROR - DBMS instance ' . $dbms . ' failed. See above error and explaination.';
        $status = 0;
      }
    } ## end foreach my $dbms ( sort keys...)
  } ## end if ( $dbms_ref && ref(...))

  if ( $num_dbms > 0 && $status ) {
    say 'OK - Got ' . $num_dbms;
    return 1;
  }
  elsif ( !$status ) {
    say 'ERROR - At least one DBMS not ok.';
    return;
  }
  else {
    say 'ERROR - Got no DBMS';
    return;
  }
} ## end sub _check_dbmss

sub _check_dbms_dbh_connection {
  my $self = shift;
  my $dbms = shift;

  my $hostname = $self->config()->get( 'MTK::MYB::DBMS::' . $dbms . '::Hostname' );
  my $port = $self->config()->get( 'MTK::MYB::DBMS::' . $dbms . '::Port' ) || 3306;

  my $DBH;

  try {
    my $Creds = MTK::DB::Credentials::->new(
      {
        'hostname' => $hostname,
        'config'   => $self->config(),
        'keys'     => [ ( 'MTK::MYB::DBMS::' . $dbms ) ],
        'creds'    => { 'root' => 'root', },
        'port'     => $port,
        'logger'   => $self->logger(),
      }
    );
    my $username = $Creds->username();
    $self->{'username'} = $username;
    my $password = $Creds->password();
    $self->{'password'} = $password;
    $DBH                = $Creds->dbh();
    $Creds              = undef;
  };

  # Connection failed
  if ( $DBH && $DBH->valid() ) {
    return 1;
  }
  else {
    return;
  }
} ## end sub _check_dbms_dbh_connection

sub _check_dbms {
  my $self = shift;
  my $dbms = shift;

  # check db connection
  if ( $self->_check_dbms_dbh_connection($dbms) ) {
    say ' OK - DBH connection working for ' . $dbms;
  }
  else {
    say ' ERROR - DBH connection failed! Check connection credentials for ' . $dbms;
    return;
  }

  return 1;
} ## end sub _check_dbms

sub execute {
  my $self = shift;

  # check config and configured dirs
  if ( !$self->myb()->configure() ) {
    return;
  }

  my $status = 1;

  # check bank status
  if ( !$self->_check_bank() ) {
    $status = 0;
  }

  if ( !$self->_check_basics() ) {
    $status = 0;
  }

  if ( !$self->_check_dbmss() ) {
    $status = 0;
  }

  return $status;
} ## end sub execute

sub abstract {
  return 'Perform some santiy checks on your configuration.';
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::Cmd::Command::configcheck - Check the MYB config

=method abstract

A descrition of this command.

=method execute

Run this command.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
