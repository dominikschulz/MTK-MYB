package MTK::MYB::Checker;
# ABSTRACT: the MYB backup integrity checker

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;
use Try::Tiny;
use English qw( -no_match_vars );

use Sys::FS;
use Sys::Run;

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

has 'min_pc' => (
    'is'       => 'rw',
    'isa'      => 'Int',
    'required' => 1,
);

has 'bank' => (
    'is'       => 'rw',
    'isa'      => 'Str',
    'required' => 1,
);

has 'max_age' => (
    'is'       => 'rw',
    'isa'      => 'Int',
    'required' => 1,
);

# instance dirs found
# db dirs found
# *.sql files found
# table dumps with "CREATE TABLE"
# errors - expected dirs not found
foreach my $var (qw(instances dbs tables valid failed)) {
    has 'num_'
      . $var => (
        'is'      => 'rw',
        'isa'     => 'Int',
        'default' => 0,
      );
}

with 'Config::Yak::OrderedPlugins' => { -version => 0.18 };

sub _plugin_base_class { return 'MTK::MYB::Checker::Plugin'; }

sub _init_sys {
    my $self = shift;

    my $Sys = Sys::Run::->new( { 'logger' => $self->logger(), } );

    return $Sys;
}

sub _init_fs {
    my $self = shift;

    my $FS = Sys::FS::->new(
        {
            'logger' => $self->logger(),
            'sys'    => $self->sys(),
        }
    );

    return $FS;
}

sub run {
    my $self = shift;

    foreach my $Plugin (@{$self->plugins()}) {
        try {
            $Plugin->run_prepare_hook();
        } catch {
            $self->logger()->log( message => 'Plugin '.ref($Plugin).' failed to run prepare hook w/ error: '.$_, level => 'warning', );
        };
    }

    my $status = $self->_check_dumps();

    foreach my $Plugin (@{$self->plugins()}) {
        try {
            $Plugin->run_cleanup_hook($status);
        } catch {
            $self->logger()->log( message => 'Plugin '.ref($Plugin).' failed to run cleanup hook w/ error: '.$_, level => 'warning', );
        };
    }

    return $status;
}

sub _find_instances {
    my $self    = shift;
    my $basedir = $self->{'bank'};

    my @insts = ();

    # collect instances
    opendir( my $DH, $basedir );
    while ( my $dir_entry = readdir($DH) ) {
        my $path = $basedir . '/' . $dir_entry;
        next if $dir_entry =~ m/^\./;
        next if !-d $path;
        next if $dir_entry =~ m/binlogarchive/;
        $self->num_instances( $self->num_instances() + 1 );
        push( @insts, $path );
        $self->logger()->log( message => 'Found instance dir: '.$path, level => 'debug', );
    }
    closedir($DH);
    return \@insts;
}

sub _find_dbs {
    my $self = shift;

    my @dbs = ();
    foreach my $inst ( @{ $self->_find_instances() } ) {
        my $dump_dir = $inst . '/daily/0/dumps';
        if ( -d $dump_dir && opendir( my $DH, $dump_dir ) ) {
            while ( my $dir_entry = readdir($DH) ) {
                my $path = $dump_dir . '/' . $dir_entry;
                next if $dir_entry =~ m/^\./;
                next if $dir_entry =~ m/^mysql$/;
                next if !-d $path;
                $self->num_dbs( $self->num_dbs() + 1 );
                push( @dbs, $path );
                $self->logger()->log( message => 'Found db dir: '.$path, level => 'debug', );
            }
            closedir($DH);
        }
        else {

            # Could not open an instance directory
            $self->num_failed( $self->num_failed() + 1 );
            $self->logger()->log( message => 'Not a directory: '.$dump_dir, level => 'warning', );
        }
    }
    return \@dbs;
}

sub _check_tables {
    my $self = shift;

    foreach my $db ( @{ $self->_find_dbs() } ) {
        if ( -d $db && opendir( my $DH, $db ) ) {
            while ( my $dir_entry = readdir($DH) ) {
                my $path = $db . '/' . $dir_entry;
                next if $dir_entry =~ m/^\./;
                if ( $dir_entry =~ m/\.sql(?:|\..*)$/ ) {
                    $self->num_tables( $self->num_tables() + 1 );
                    $self->logger()->log( message => 'Found table dump: '.$path, level => 'debug', );
                    my $modtime = ( stat($path) )[9];
                    if ( $modtime >= $self->{'max_age'} && $self->has_create_table($path) ) {
                        $self->num_valid( $self->num_valid() + 1 );
                        $self->logger()->log( message => 'Found valid table dump: '.$path, level => 'debug', );
                    }
                }
            }
            closedir($DH);
        }
        else {
            # Could not open a DB directory
            $self->num_failed( $self->num_failed() + 1 );
            $self->logger()->log( message => 'Not a directory: '.$db, level => 'warning', );
        }
    }
    return 1;
}

sub _check_dumps {
    my $self = shift;

    my $pc_new = 0;

    # /srv/backup/mysql/daily/0/<instance>/dump/<db>/table.sql*
    # |    basedir            | instance  |    | db | table

    my $basedir = $self->{'bank'};
    if ( -e $basedir ) {

        # check tables
        $self->_check_tables();

        if ( $self->num_tables() ) {
            $pc_new = int( ( $self->num_valid() / $self->num_tables() ) * 100 );
        }
        else {
            $pc_new = 100;
        }
    }
    else {
        $self->logger()->log( message => 'Basedir '.$basedir.' not found!', level => 'error', );
    }

    if ( $self->num_tables() < 1 || $pc_new < $self->min_pc() || $self->num_failed() > 0 ) {
        $self->logger()->log(
            message => 'Valid dumps modified within '
              . $self->max_age()
              . 'h: '.$pc_new.'% of '
              . $self->num_tables() . ' < '
              . $self->min_pc() . '%. '
              . $self->num_failed()
              . ' directory errors.',
            level => 'error',
        );
        return;
    }
    else {
        $self->logger()->log(
            message => 'OK. Valid dumps modified within '
              . $self->max_age()
              . 'h: '.$pc_new.'% of '
              . $self->num_tables() . ' >= '
              . $self->min_pc()
              . '%. No directory errors.',
            level => 'debug',
        );
        return 1;
    }
}

sub has_create_table {
    my $self = shift;
    my $file = shift;
    my $cmd  = '/bin/zcat ' . $file . ' 2>/dev/null | /usr/bin/head -50 2>/dev/null | /bin/grep -l "CREATE TABLE" >/dev/null 2>&1';

    if ( $self->sys()->run_cmd($cmd) ) {
        return 1;
    }
    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Checker - Mysqlbackup integrity checker

=method has_create_table

Return true if the given file contains a vaild CREATE TABLE statement.

=method run

Check all tables.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
