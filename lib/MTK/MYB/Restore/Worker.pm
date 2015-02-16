package MTK::MYB::Restore::Worker;

# ABSTRACT: a restore Worker

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

extends 'Job::Manager::Worker';

has 'filename' => (
  'is'       => 'ro',
  'isa'      => 'Str',
  'required' => 1,
);

foreach my $key (qw(username password hostname)) {
  has $key => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
  );
} ## end foreach my $key (qw(username password hostname))

has 'port' => (
  'is'      => 'ro',
  'isa'     => 'Int',
  'default' => 3306,
);

sub run {
  my $self = shift;

  if ( !-r $self->filename() ) {
    $self->logger()->log( message => 'Can not read dump at ' . $self->filename(), level => 'error', );
  }

  my $filesize = ( stat( $self->filename() ) )[7];
  $filesize = sprintf( '%.2f', $filesize / ( 1024 * 1024 ) );    # convert to MB

  my @path = split /\//, $self->filename();
  my $db = $path[-2];
  if ( $path[-1] =~ m/^([^.])\.sql(?:\.(gz|lzop|lzma|xz|bz2))?/ ) {
    my $table       = $1;
    my $compression = $2;

    # create db
    my $sql_create = 'CREATE DATABASE IF NOT EXISTS `' . $db . '`;';
    my $cmd_create = 'mysql -u' . $self->username() . ' -p' . $self->password() . ' -h' . $self->hostname() . " -e$sql_create";
    $self->sys()->run_cmd($cmd_create);

    # assemble command
    my $cmd_load = '';

    if ($compression) {
      if ( $compression eq 'gz' ) {
        $cmd_load .= 'gzip -d -c ';
      }
      elsif ( $compression eq 'lzo' ) {
        $cmd_load .= 'lzop -d -c ';
      }
      elsif ( $compression eq 'lzma' ) {
        $cmd_load .= 'lzma -d -c ';
      }
      elsif ( $compression eq 'xz' ) {
        $cmd_load .= 'xz -d -c ';
      }
      elsif ( $compression eq 'bz2' ) {
        $cmd_load .= 'bzip2 -d -c ';
      }
    } ## end if ($compression)
    else {
      $cmd_load .= 'cat ';
    }
    $cmd_load .= $self->filename();
    $cmd_load .= ' | ';
    $cmd_load .= 'mysql -u' . $self->username() . ' -p' . $self->password() . ' -h' . $self->hostname() . ' ' . $db;

    my $t0         = time();
    my $status     = $self->sys()->run_cmd($cmd_load);
    my $status_msg = 'FAILURE';
    $status_msg = 'OK' if ($status);
    my $d   = time() - $t0;
    my $msg = "Restored DB $db / Table $table - Status: $status_msg - Performance: ";
    $msg .= $filesize . ' MB in ' . $d . 's (' . sprintf( '%.2f', $filesize / $d ) . ' MB/s).';
    $self->logger()->log( message => $msg, level => ( $status ? 'notice' : 'error' ) );
    return 1;
  } ## end if ( $path[-1] =~ m/^([^.])\.sql(?:\.(gz|lzop|lzma|xz|bz2))?/)
  else {

    # invalid filename
    $self->logger()->log( message => 'Can not parse filename: ' . $self->filename(), level => 'error', );
    return;
  } ## end else [ if ( $path[-1] =~ m/^([^.])\.sql(?:\.(gz|lzop|lzma|xz|bz2))?/)]
} ## end sub run

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

	my $Worker = MTK::MYB::Restore::Worker::->new({
		'filename'	=> '/my/file',
		'username'	=> '123',
		'password'	=> '123',
		'hostname'	=> 'localhost',
	});
	$Worker->run();

=head1 NAME

MTK::MYB::Restore::Worker - an Mysqlbackup restore worker

=method run

run this worker.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
