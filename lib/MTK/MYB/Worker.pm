package MTK::MYB::Worker;
# ABSTRACT: a MYB backup instance

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;

use Carp;
use English qw( -no_match_vars );
use Try::Tiny;
use File::Basename qw();
use File::Blarf;

use MTK::DB;
use MTK::MYB::Codes;
use MTK::MYB::Status;
use MTK::MYB::Packer;
use MTK::DB::Credentials;
use Sys::RotateBackup;
use Sys::CmdMod;
use Sys::FS;
use Sys::Run;

extends 'Job::Manager::Worker';

#
# Attributes
#

has 'status' => (
    'is'      => 'ro',
    'isa'     => 'MTK::MYB::Status',
    'lazy'    => 1,
    'builder' => '_init_status',
);

has 'bank' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'vault' => (
    'is'       => 'ro',
    'isa'      => 'Str',
    'required' => 1,
);

has 'sys' => (
    'is'      => 'rw',
    'isa'     => 'Sys::Run',
    'lazy'    => 1,
    'builder' => '_init_sys',
);

has 'name' => (
    'is'      => 'ro',
    'isa'     => 'Str',
    'lazy'    => 1,
    'builder' => '_init_name',
);

has 'fs' => (
    'is'      => 'rw',
    'isa'     => 'Sys::FS',
    'lazy'    => 1,
    'builder' => '_init_fs',
);

foreach my $dir (qw(daily progress last_rotation dumps structs tables binlogs)) {
    has 'dir_'
      . $dir => (
        'is'      => 'ro',
        'isa'     => 'Str',
        'lazy'    => 1,
        'builder' => '_init_dir_' . $dir,
      );
}

foreach my $key (qw(hostname username password)) {
    has $key => (
        'is'      => 'ro',
        'isa'     => 'Str',
        'lazy'    => 1,
        'builder' => '_init_' . $key,
    );
}

has 'port' => (
    'is'      => 'ro',
    'isa'     => 'Int',
    'lazy'    => 1,
    'builder' => '_init_port',
);

has 'dry' => (
    'is'      => 'ro',
    'isa'     => 'Bool',
    'lazy'    => 1,
    'builder' => '_init_dry',
);

has 'parent' => (
    'is'       => 'ro',
    'isa'      => 'MTK::MYB',
    'required' => 1,
);

has 'packer' => (
    'is'      => 'ro',
    'isa'     => 'MTK::MYB::Packer',
    'lazy'    => 1,
    'builder' => '_init_packer',
);

has 'cmdmod' => (
    'is'      => 'rw',
    'isa'     => 'Sys::CmdMod',
    'lazy'    => 1,
    'builder' => '_init_cmdmod',
);

has 'logfile' => (
    'is'      => 'rw',
    'isa'     => 'Str',
    'lazy'    => 1,
    'builder' => '_init_logfile',
);

#
# Builder Methods
#

sub _init_status {
    my $self = shift;
    return MTK::MYB::Status::->new();
}

sub _init_sys {
    my $self = shift;

    my $Sys = Sys::Run::->new( { 'logger' => $self->logger(), } );

    return $Sys;
}

sub _init_name {
    my $self = shift;

    return 'Backup DBMS ' . $self->vault();
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

sub _init_dry {
    my $self = shift;

    return $self->config()->get( 'MTK::MYB::Dry', { Default => 0, } );
}

sub _init_hostname {
    my $self = shift;

    return $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Hostname', { Default => 'localhost', } );
}

sub _init_username {
    my $self = shift;

    return $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Username', { Default => $self->dbms(), } );
}

sub _init_password {
    my $self = shift;

    return $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Password', { Default => 'root', } );
}

sub _init_port {
    my $self = shift;

    return $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Port', { Default => 3306, } );
}

sub _init_dir_daily {
    my $self = shift;

    return $self->fs()->makedir( $self->fs()->filename( ( $self->bank(), $self->vault(), 'daily', ) ), { Uid => $self->uid(), Gid => $self->gid(), } );
}

sub _init_dir_progress {
    my $self = shift;

    # remove old inprogress-dir, if any
    my $progressdir = $self->fs()->filename( ( $self->dir_daily(), 'inprogress' ) );
    if ( -d $progressdir ) {
        my $cmd = 'rm -rf "' . $progressdir . '"';
        $self->sys()->run_cmd($cmd);
    }
    $self->fs()->makedir( $progressdir, { Uid => $self->uid(), Gid => $self->gid(), } );

    return $progressdir;
}

sub _init_dir_last_rotation {
    my $self = shift;

    return $self->fs()->makedir( $self->fs()->filename( ( $self->dir_daily(), '0' ) ), { Uid => $self->uid(), Gid => $self->gid(), } );
}

sub _init_dir_dumps {
    my $self = shift;

    return $self->fs()->makedir( $self->fs()->filename( ( $self->dir_progress(), $self->_dirname_dumps() ) ), { Uid => $self->uid(), Gid => $self->gid(), } );
}

sub _dirname_dumps {
    my $self = shift;

    return 'dump';
}

sub _init_dir_structs {
    my $self = shift;

    return $self->fs()->makedir( $self->fs()->filename( ( $self->dir_progress(), $self->_dirname_structs() ) ), { Uid => $self->uid(), Gid => $self->gid(), } );
}

sub _dirname_structs {
    my $self = shift;

    return 'struct';
}

sub _init_dir_tables {
    my $self = shift;

    return $self->fs()->makedir( $self->fs()->filename( ( $self->dir_progress(), $self->_dirname_tables() ) ), { Uid => $self->uid(), Gid => $self->gid(), } );
}

sub _init_dir_binlogs {
    my $self = shift;

    return $self->fs()->makedir( $self->fs()->filename( ( $self->bank(), $self->vault(), 'binlogarchive', ) ), { Uid => $self->uid(), Gid => $self->gid(), } );
}

sub _init_logfile {
    my $self = shift;

    return $self->fs()->filename( ( $self->dir_progress(), 'binlogpos.log' ) );
}

sub _init_cmdmod {
    my $self = shift;

    my $Cmd = Sys::CmdMod::->new({
        'config'    => $self->config(),
        'logger'    => $self->logger(),
    });

    return $Cmd;
}

sub _init_packer {
    my $self = shift;

    return MTK::MYB::Packer::->new( {
        'config' => $self->config(),
        'logger' => $self->logger(),
    } );
}

#
# Private Methods
#

sub _dirname_tables {
    my $self = shift;

    return 'table';
}

# do any backup preparation, invoked in run
sub _prepare {
    my $self = shift;

    # Write timestamp to binlogpos file
    &File::Blarf::blarf( $self->logfile(), 'BACKUP-STARTING: ' . time(), { Append => 1, Flock => 1, Newline => 1, } );

    return 1;
}

# cleanup after the backup is finished, invoked in run
sub _cleanup {
    my $self = shift;

    # Write timestamp to binlogpos file
    my $status = q{};
    $status .= 'BACKUP-STATUS: ';
    if ( $self->status()->ok() ) {
        $status .= 'OK';
    }
    else {
        $status .= 'ERROR';
    }
    File::Blarf::blarf( $self->logfile(), $status . "\n" . 'BACKUP-FINISHED: ' . time(), { Append => 1, Flock => 1, Newline => 1, } );

    # Archive binlogs
    if ( $self->config()->get('MTK::MYB::BinlogArchive') ) {
        $self->logger()->log( message => 'Now archiving binlogs ...', level => 'debug', );
        $self->_binlog_archive();
    }
    else {
        $self->logger()->log( message => 'Not archiving binlogs. do_binlog = 0', level => 'debug', );
    }

    # rotate the backups
    my $Rotor = Sys::RotateBackup::->new(
        {
            'logger'  => $self->logger(),
            'sys'     => $self->sys(),
            'vault'   => $self->fs()->filename( ( $self->bank(), $self->vault() ) ),
            'daily'   => $self->config()->get( 'MTK::MYB::Rotations::Daily', { Default => 10, } ),
            'weekly'  => $self->config()->get( 'MTK::MYB::Rotations::Weekly', { Default => 4, } ),
            'monthly' => $self->config()->get( 'MTK::MYB::Rotations::Monthly', { Default => 12, } ),
            'yearly'  => $self->config()->get( 'MTK::MYB::Rotations::Yearly', { Default => 10, } ),
        }
    );
    $Rotor->rotate();

    # run any per-worker cleanup hooks
    foreach my $Plugin ( @{ $self->parent()->plugins() } ) {
        try {
            if($Plugin->run_worker_cleanup_hook($self)) {
                $self->logger()->log( message => 'worker cleanup hook of Plugin '.ref($Plugin).' run successfully.', level => 'debug', );
            } else {
                $self->logger()->log( message => 'worker cleanup hook of Plugin '.ref($Plugin).' failed to run.', level => 'notice', );
            }
        }
        catch {
            $self->logger()->log( message => 'Failed to run worker cleanup hook of ' . ref($Plugin) . ' w/ error: ' . $_, level => 'warning', );
        };
    }

    return 1;
}

# find the best suitetd local ip for connection to the mysqld
sub _get_local_ip {
    my $self = shift;

    my $cmd = 'ip addr';
    my @out = $self->sys()->run_cmd( $cmd, { CaptureOutput => 1, Chomp => 1, } );
    my %ips = ();
    foreach my $line (@out) {
        if ( $line =~ m/^\s*inet\s/ ) {
            my ( $inet, $ipwnet ) = split /\s+/, $line;
            if ( $ipwnet =~ m/(\d+\.\d+\.\d+\.\d+)/ ) {
                my $ip = $1;
                $ips{$ip} = 1;
            }
        }
    }

    if ( $ips{'127.0.0.1'} ) {
        return '127.0.0.1';
    }
    elsif ( scalar( keys %ips ) == 1 ) {
        return keys %ips;
    }
    else {

        # uhm, don't know what to do, return default
        return '127.0.0.1';
    }
}

# returns as string containing all successfull initialized command modifier
sub _get_cmd_prefix {
    my $self = shift;

    my $prefix = '';

    return $self->cmdmod()->cmd($prefix);
}

sub _get_cmd_suffix {
    my $self    = shift;
    my $db      = shift;
    my $table   = shift;
    my $type    = shift;
    my $destdir = shift;
    my $file    = shift;

    return q{ > } . $self->_get_local_destination( $db, $table, $type, $destdir, $file );
}

sub _get_local_destination {
    my $self    = shift;
    my $db      = shift;
    my $table   = shift;
    my $type    = shift;
    my $destdir = shift;
    my $file    = shift;

    return $destdir . q{/} . $file . $self->packer()->ext();
}

sub _get_excludes {
    my $self = shift;

    my @excludes = ();
    if ( my @e = $self->config()->get_array('MTK::MYB::Exclude') ) {
        foreach my $rule (@e) {
            next unless $rule;
            push( @excludes, '*.' . $rule );
        }
    }

    if ( my @e = $self->config()->get_array( 'MTK::MYB::DBMS::' . $self->dbms() . '::Exclude' ) ) {
        foreach my $rule (@e) {
            next unless $rule;
            push( @excludes, $self->dbms() . q{.} . $rule );
        }
    }
    return @excludes;
}

sub _get_backup_host {
    my $self = shift;

    my $hostname = '127.0.0.1';

    if ( my $h1 = $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Hostname' ) ) {
        $hostname = $h1;
    }
    elsif ( my $h2 = $self->config()->get('MTK::Mysql::DBA::Hostname') ) {
        $hostname = $h2;
    }

    return $hostname;
}

# inherited from Job::Manager::Worker, invoked when the Job is starting to run
sub run {
    my $self = shift;

    # 23h timeout to allow the next backup to run in case this one hangs
    my $timeout      = 23 * 60 * 60;
    my $prev_timeout = 0;
    my $success      = try {
        local $SIG{ALRM} = sub { die "alarm-mysqlbackup-cnc\n"; };

        $prev_timeout = alarm $timeout;
        $self->logger()->log( message => 'Set alarm to '.$timeout.'s. Previous timeout is '.$prev_timeout, level => 'debug' );

        # moved the meat of run() to it's own sub just to get nicer stacktraces
        $self->_run();

        # IMPORTANT: Make sure the last statement of this eval returns a true value!
    }
    catch {
        if ( $_ eq "alarm-mysqlbackup-cnc\n" ) {
            $self->logger()->log( message => 'Backup timed out after '.$timeout, level => 'warning', );
        }
        else {
            $self->logger()->log( message => 'Backup failed w/ error: ' . $_, level => 'error', );
        }
    }
    finally {

        # restore previous alarm, if any
        $self->logger()->log( message => 'Setting alarm to old value of '.$prev_timeout, level => 'debug', );

        # make sure the alarm is off
        alarm $prev_timeout;
    };

    if ($success) {
        $self->logger()->log( message => 'Backup finished successfull.', level => 'notice', );
        return 1;
    }
    else {
        $self->logger()->log( message => 'Backup of ' . $self->dbms() . ' failed somehow. See previous errors', level => 'error', );
        return;
    }
}

# extracted from run() to provide nicer stracktraces inside the eval
sub _run {
    my $self = shift;

    # per-loop initialisation for reporting
    my $secbehind_pre   = 0;
    my $secbehind_post  = 0;
    my $binlogpos_pre   = 0;
    my $binlogpos_post  = 0;
    my $binlogfile_pre  = "";
    my $binlogfile_post = "";

    #local $opts->{'IgnoreDry'} = 0;
    $self->logger()->log( message => 'Backup of instance ' . $self->dbms() . ' starting ...', level => 'debug' );

    # Database Variables
    my $query    = 0;                           # Hold query strings
    my $prepq    = 0;                           # Hold prepared query
    my $hostname = $self->_get_backup_host();
    if ( !$hostname ) {
        $self->logger()->log( message => 'No hostname found for DBMS ' . $self->dbms(), level => 'error', );
        croak('No hostname found for DBMS! Need Hostname! Aborting!');
    }
    my $port = $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Port' ) || 3306;

    my $Creds = MTK::DB::Credentials::->new(
        {
            'hostname' => $hostname,
            'config'   => $self->config(),
            'keys'     => [ ( 'MTK::MYB::DBMS::' . $self->dbms() ) ],
            'creds'    => { 'root' => 'root', },
            'port'     => $port,
            'logger'   => $self->logger(),
        }
    );
    my $username = $Creds->username();
    $self->{'username'} = $username;
    my $password = $Creds->password();
    $self->{'password'} = $password;
    my $DBH = $Creds->dbh();
    $Creds = undef;

    # make sure that mysql doesn't accidentially tries to use the default socket
    if ( $port != 3306 && $hostname eq 'localhost' ) {
        $hostname = $self->_get_local_ip();
    }
    $self->logger()->log( message => 'Host: ' . $self->dbms() . '.host: ' . $hostname,         level => 'debug' );
    $self->logger()->log( message => 'Port: ' . $self->dbms() . '.port: ' . $port,             level => 'debug' );
    $self->logger()->log( message => 'User: ' . $self->dbms() . '.username: ' . $username,     level => 'debug' );
    $self->logger()->log( message => 'Password: ' . $self->dbms() . '.password: ' . $password, level => 'debug' );

    # Connection failed
    if ( !$DBH || !$DBH->valid() ) {

        # report an error if we can't connect to an instance!
        my $msg = 'Database not available. Credentials ok? User: '.$username.', Host: '.$hostname.', Port: '.$port.', Error: ' . DBI->errstr;
        $self->logger()->log( message => $msg, level => 'alert', );
        $self->status()->global( MTK::MYB::Codes::get_status_code('CONNECT-ERROR') );
        $self->parent()->reporter()->report();
        die( $msg . "\n" );
    }

    if ( !$self->_prepare( $hostname, $self->dbms() ) ) {
        $self->logger()->log( message => '_prepare failed! Aborting.', level => 'debug', );
        croak('Could not prepare backup. Aborting!');
    }

    #
    # Lock the database
    #
    $DBH->flush_tables_with_read_lock();

    #
    # Flush the logs (start a new binlog, ...)
    #
    if ( $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::Flushlogs' ) || $self->config()->get('MTK::MYB::Flushlogs') ) {
        $DBH->flush_logs();
    }

    #
    # Record the binlog position
    #
    ( $binlogpos_pre, $binlogfile_pre ) = $self->_record_master_status( $DBH, $self->logfile() );
    if(!defined($binlogpos_pre)) {
        $self->logger()->log( message => 'Could not write master status. Is the bank writeable? Aborting!', level => 'error', );
        return;
    }

    #
    # Record the slave status
    #
    $secbehind_pre = $self->_record_slave_status( $DBH, $self->logfile() );
    if(!defined($secbehind_pre)) {
        $self->logger()->log( message => 'Could not write slave status. Is the bank writeable? Aborting!', level => 'error', );
        return;
    }

    # Get a list of all databases
    my $opts_ref = { 'ReturnHashRef' => 1, };
    @{ $opts_ref->{'Excludes'} } = $self->_get_excludes();
    my $table_ref = $DBH->list_tables($opts_ref);

    # need at least one table to assume success here
    if ( scalar( keys %{$table_ref} ) < 1 ) {
        $self->logger()->log( message => 'Found no tables on ' . $self->dbms(), level => 'error', );
        $self->status()->global( MTK::MYB::Codes::get_status_code('NO-TABLES') );
    }
    else {
        $self->logger()->log( message => 'Found at least on table on ' . $self->dbms(), level => 'debug', );
    }

    #
    # Iterate over all DATABASES inside this DBMS
    #
    # Iterate over each DB, get a list ot the tables and dump each table
    foreach my $db ( sort keys %{$table_ref} ) {
        $self->logger()->log( message => 'PROCESSING ' . $self->dbms() . q{.} . $db, level => 'debug' );

        #
        # Iterate over all TABLES inside this database
        #
        foreach my $table ( sort keys %{ $table_ref->{$db} } ) {
            my $engine      = $table_ref->{$db}{$table}{'engine'};
            my $update_time = $table_ref->{$db}{$table}{'update_time'};

            $self->logger()->log( message => 'PROCESSING ' . $self->dbms() . q{.} . $db . q{.} . $table . ' w/ engine: ' . $engine, level => 'debug' );

            # Try to get table_update_time for InnoDB Tables via stat ...
            if ( $engine eq 'INNODB' ) {
                $update_time = $self->_innodb_update_time( $self->type() eq 'cnc' ? $hostname : 'localhost', $db, $table );
            }

            # set default update time
            $update_time ||= 0;

            #
            # DUMP STRUCTURE
            #
            # Dump the structure of the DB to (uncompressed) SQL-Files
            #
            if (   $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::DumpStruct' )
                || $self->config()->get('MTK::MYB::DumpStruct') )
            {
                $self->logger()->log( message => 'Processing structure Dumps for DB: '.$db.' / Table: '.$table.' (Engine: '.$engine.')', level => 'debug' );

                my $status = $self->_table_dump(
                    {
                        'type'              => 'struct',
                        'db'                => $db,
                        'table'             => $table,
                        'engine'            => $engine,
                        'mysqld_host'       => $hostname,
                        'target_host'       => $self->type() eq 'cnc' ? $hostname : 'localhost',
                        'table_last_update' => $update_time,
                        'port'              => $port,
                        'hardlink' => $self->config()->get( 'MTK::MYB::LinkUnmodified', { Default => 0, } ),
                    }
                );

                my $status_set = $self->status()->set_table_status( $self->dbms(), $db, $table, $status, 'struct' );
            }
            else {
                $self->status()->set_table_status( $self->dbms(), $db, $table, -7, 'struct' );    # Status -7 => do_struct = 0
                $self->logger()->log( message => 'Not dumping structure of Table ' . $self->dbms() . q{.}.$db.q{.}.$table.' ('.$engine.'). DumpStruct = 0', level => 'notice' );
            }

            #
            # DUMP DATA
            #
            # Dump content of the DB to (compressed) SQL-files
            #
            if ( $self->config()->get('MTK::MYB::DumpTable')
                || $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::DumpTable')
                || ( $self->config()->get('MTK::MYB::CopyTable') && $engine ne 'MYISAM')
                )
            {

                $self->logger()->log( message => 'Processing Data-Dumps for DB: '.$db.' / Table: '.$table.' (Engine: '.$engine.')', level => 'debug', );

                my $status = $self->_table_dump(
                    {
                        'type'              => 'dump',
                        'db'                => $db,
                        'table'             => $table,
                        'engine'            => $engine,
                        'mysqld_host'       => $hostname,
                        'target_host'       => $self->type() eq 'cnc' ? $hostname : 'localhost',
                        'table_last_update' => $update_time,
                        'port'              => $port,
                        'hardlink'        => $self->config()->get( 'MTK::MYB::LinkUnmodified',       { Default => 0, } ),
                        'hardlink_innodb' => $self->config()->get( 'MTK::MYB::LinkUnmodifiedInnodb', { Default => 0, } ),
                    }
                );
                $self->status()->set_table_status( $self->dbms(), $db, $table, $status, 'dump' );
            }
            else {
                $self->status()->set_table_status( $self->dbms(), $db, $table, -2, 'dump' );    # Status -2 => do_dump = 0
                $self->logger()->log( message => 'Not dumping Table ' . $self->dbms() . q{.}.$db.q{.}.$table.' ('.$engine.'). DumpTable = 0', level => 'notice' );
            }

            #
            # COPY TABLEFILES
            #
            # Copy the RAW tablefiles, useful for fast restore
            #
            if ( $engine ne 'MYISAM' ) {
                $self->status()->set_table_status( $self->dbms(), $db, $table, -6, 'copy' );    # Status -6 => engine not MyISAM
                $self->logger()->log( message => 'Storage Engine of Table ' . $self->dbms() . q{.}.$db.q{.}.$table.' ('.$engine.') not MyISAM. Can not create tablefile backup.', level => 'debug', );
            }
            elsif (
                $engine eq 'MYISAM'
                && (   $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::CopyTable' )
                    || $self->config()->get('MTK::MYB::CopyTable') )
              )
            {
                $self->logger()->log( message => 'Processing Tablefiles for DB: '.$db.' / Table: '.$table.' (Engine: '.$engine.')', level => 'debug' );

                my $status = $self->_table_copy(
                    {
                        'dbms'        => $self->dbms(),
                        'db'          => $db,
                        'table'       => $table,
                        'engine'      => 'MYISAM',
                        'mysqld_host' => 'localhost',
                        'target_host' => $self->type() eq 'cnc' ? $hostname : 'localhost',
                        'hardlink'    => $self->config()->get( 'MTK::MYB::LinkUnmodified', { Default => 0, } ),
                    }
                );
                $self->status()->set_table_status( $self->dbms(), $db, $table, $status, 'tables' );
            }
            else {
                $self->status()->set_table_status( $self->dbms(), $db, $table, -5, 'tables' );    # Status -5 => do_tablefiles = 0
                $self->logger()->log( message => 'Not archiving tablefiles of ' . $self->dbms() . q{.}.$db.q{.}.$table.' ('.$engine.'). CopyTable = 0', level => 'notice', );
            }
            my $sleep_between_tables = $self->config()->get('MTK::MYB::SleepBetweenTables') || 0;
            if ($sleep_between_tables) {
                $self->logger()->log( message => 'Sleeping for '.$sleep_between_tables.'s due to ionice_sleep setting.', level => 'debug' );
                sleep $sleep_between_tables;
            }
            if ( !$DBH || !$DBH->valid() ) {
                my $msg =
                  'Lost mysql connection to '.$hostname.' during backup of ' . $self->dbms() . q{.}.$db.q{.}.$table.'. Backup is insconsistent due to broken locks!';
                $self->logger()->log( message => $msg, level => 'alert', );
            }
        }    # End of TWHILE
    }

    # Check if mysql connection is still alive
    if ( !$DBH || !$DBH->valid() ) {
        my $msg = 'Lost mysql connection to '.$hostname.' during backup. Backup is insconsistent due to broken locks! Aborting.';
        $self->logger()->log( message => $msg, level => 'alert', );

        # report an error if we lost the connection to mysql
        $self->status()->global( MTK::MYB::Codes::get_status_code('MYSQL-LOST') );
        $self->parent()->reporter()->report();
        die( $msg . "\n" );
    }

    # Executed during mysql instance(s) is/are stopped
    $self->parent()->_exec_main( $self->dbms() );

    # Unlock the tables and close connection
    $DBH->unlock_tables();

    # This master and slave status are only used for reporting!
    # The values related to the consistent backup set are
    # recorded above.

    # Record parameters after backup has ended
    # Record the binlog position
    if ( $self->dry() ) {
        ( $binlogpos_post, $binlogfile_post ) = $DBH->get_master_status();
    }

    # Record the slave status
    my $ss = $DBH->get_slave_status();
    if ( $ss && ref($ss) eq 'HASH' ) {
        $secbehind_post = $ss->{'Seconds_Behind_Master'};
    }

    # Append to log, for reporting
    $self->logger()->log( message => 'Seconds_Behind_Master before processing ' . $self->dbms() . ": " . $secbehind_pre, level => 'debug', );
    $self->logger()->log( message => 'Seconds_Behind_Master after processing ' . $self->dbms() . ": " . $secbehind_post, level => 'debug', );
    $self->logger()->log( message => 'Read_Master_Log_Pos before processing ' . $self->dbms() . ": " . $binlogpos_pre,   level => 'debug', );
    $self->logger()->log( message => 'Read_Master_Log_Pos after processing ' . $self->dbms() . ": " . $binlogpos_post,   level => 'debug', );
    $self->logger()->log( message => 'Read_Master_Log_File before processing ' . $self->dbms() . ": " . $binlogfile_pre, level => 'debug', );
    $self->logger()->log( message => 'Read_Master_Log_File after processing ' . $self->dbms() . ": " . $binlogfile_post, level => 'debug', );

    # Close the connection
    if ( !$DBH || !$DBH->valid() ) {
        $self->logger()->log( message => 'Connection to Database lost during backup. This is fatal!', level => 'error', );
        $self->status()->global( &MTK::MYB::Codes::get_status_code('MYSQL-LOST') );
    }
    else {
        $self->status()->global( &MTK::MYB::Codes::get_status_code('OK') );
    }

    $prepq->finish()   if $prepq;
    $DBH->disconnect() if $DBH;

    $self->_cleanup();

    return 1;
}

# Try to find out the last modify/update time for innodb tables
sub _innodb_update_time {
    my $self  = shift;
    my $host  = shift;
    my $db    = shift;
    my $table = shift;

    my $filename = '/var/lib/mysql/' . $db . '/' . $table . '.ibd';
    my $cmd      = 'stat -L -c"%Y" ' . $filename;

    my $out = $self->sys()->run(
        $host, $cmd,
        {
            CaptureOutput => 1,
            Chomp         => 1,
        }
    );
    if ( $out && $out =~ m/^\d+$/ ) {
        $self->logger()->log( message => 'Found the update time of '.$db.q{.}.$table.' via stat. Update time: '.$out.' / ' . localtime($out), level => 'debug', );
        return $out;
    }
    else {
        $out ||= '';
        $self->logger()->log( message => 'Could not do a stat. cmd: '.$cmd.'. Error: '.$out, level => 'notice', );
    }
    return;
}

# Compress binlogs and remove old ones
sub _binlog_archive {
    my $self = shift;

    # Create required directories
    my $archive_dir = $self->fs()->makedir( $self->fs()->filename( $self->dir_binlogs(), ), { Uid => $self->uid(), Gid => $self->gid() } );
    my $log_bin = $self->config()->get( 'MTK::MYB::DBMS::' . $self->dbms() . '::LogBin' );

    if(!$log_bin) {
        $self->logger()->log( message => 'LogBin not defined for '.$self->dbms().' - Aborting binlog archival.', level => 'warning', );
        return;
    }

    my $source_dir = File::Basename::dirname($log_bin);

    if ( $source_dir && -d $source_dir ) {
        $self->logger()->log( message => 'Binlog Source dir for ' . $self->dbms() . ' is ' . $source_dir, level => 'debug', );
    }
    else {
        $self->logger()
          ->log( message => 'Source dir for ' . $self->dbms() . ' is not defined or not a directory! Not archiving binlogs.', level => 'warning', );
        return;
    }

    # default = 10 years
    my $holdbacktime = $self->config()->get('MTK::MYB::Rotations::Binlogs') || 3650;

    my ( $sec, $min, $hour, $dayofmonth, $month, $year, $dayofweek, $dayofyear, $summertime ) = localtime();
    $month++;

    # Remove old (expired) archived binlogs
    foreach my $file ( glob($source_dir.'/mysql-bin.*') ) {
        $self->logger()->log( message => 'Binlogarchive-Expire - File '.$file.' is ' . sprintf( '%.2f', -M $file ) . ' days old.', level => 'debug' );
        if ( -M $file > $holdbacktime ) {
            $self->logger()->log( message => 'Binlogarchive-Expire - File ' . $file . ' is too ' . ( -M $file ) . ' old. Removing.', level => 'debug' );
            my $cmd = 'rm -f '.$file;
            $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );
            $self->sys()->run_cmd($cmd) unless $self->dry();
        }
    }

    # Archive new binlogs
    if ( !$source_dir || !-d $source_dir || $source_dir eq '/' ) {
        $self->logger()->log( message => "Invalid binlog search path: $source_dir", level => 'error', );
        return;
    }
    else {
        $self->logger()->log( message => "Continuing w/ binlog search path $source_dir", level => 'debug', );
    }

    my $cmd = $self->_get_cmd_prefix() . '/usr/bin/find '.$source_dir." -type f -name 'mysql-bin.*'";
    $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );
    my @out = $self->sys()->run_cmd( $cmd, { CaptureOutput => 1, Chomp => 1, } );

    foreach my $binlog_file (@out) {
        $self->logger()->log( message => "Binlog Source: " . $binlog_file, level => 'debug', );

        # Do not compress compressed files again
        my @srcpath = split /\//, $binlog_file;
        my $dst = $archive_dir . '/' . $srcpath[-1] . $self->packer()->ext();
        if ( !-e $dst || ( ( -M $binlog_file ) != ( -M $dst ) ) ) {
            $self->logger()->log( message => "$binlog_file not up-to-date, overwriting.", level => 'debug', );
            $cmd = $self->_get_cmd_prefix() . $self->packer()->cmd() . ' ' . $binlog_file . ' > ' . $dst;
            $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );
            $self->sys()->run_cmd($cmd) unless $self->dry();
            $cmd = "/usr/bin/touch --reference=" . $binlog_file . ' ' . $archive_dir . '/' . $srcpath[-1] . $self->packer()->ext();
            $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );
            $self->sys()->run_cmd($cmd) unless $self->dry();
        }
        else {
            $self->logger()->log( message => $binlog_file . $self->packer()->ext() . ' present and uptodate, skipping.', level => 'debug', );
        }
    }

    # remove old binlogs
    $cmd = $self->_get_cmd_prefix() . '/usr/bin/find '.$source_dir.' -type f -regex ".*mysql\-bin.[0-9].*" -mtime +10 -print0 | /usr/bin/xargs -0 rm -f';
    $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );
    $self->sys()->run_cmd($cmd) unless $self->dry();

    return 1;
}

sub _can_hardlink {
    my $self                = shift;
    my $params              = shift;
    my $last_backup_modtime = shift;
    my $last_backup_size    = shift;

    if ( $params->{'type'} && $params->{'type'} ne 'dump' ) {
        $self->logger()->log( message => 'Skipping non-dump type.', level => 'debug', );
        return;
    }

    if ( !$last_backup_size || $last_backup_size < 21 ) {
        $self->logger()->log( message => 'Last Backup file is too small. Probably only a gzip header. Skipping.', level => 'debug', );
        return;
    }

    if ( !$params->{'hardlink'} ) {
        $self->logger()->log( message => 'Hardlink (link_unmodified=1) not set to a true value.', level => 'debug', );
        return;
    }

    if ( !$params->{'engine'} || $params->{'engine'} !~ m/^(?:MYISAM|INNODB|ARCHIVE)$/i ) {
        $self->logger()->log( message => 'Supported engines are MyISAM, InnoDB and Archive. Not ' . $params->{'engine'}, level => 'debug', );
        return;
    }

    if ( $params->{'engine'} && $params->{'engine'} eq 'INNODB' && !$params->{'hardlink_innodb'} ) {
        $self->logger()->log(
            message => 'Hardlinking InnoDB is experimental. Only used when link_unmodified_innodb is set to a true value which it is not.',
            level   => 'debug',
        );
        return;
    }

    if ( $last_backup_modtime && $params->{'table_last_update'} && $params->{'table_last_update'} <= ( $last_backup_modtime - 24 * 60 ) ) {
        $self->logger()->log(
            message => "Last Table Modification ("
              . $params->{'table_last_update'}
              . ') is less or eqal to the last modification to the last backup minus one day ('
              . ( $last_backup_modtime - 24 * 60 )
              . '). Hardlinking.',
            level => 'debug',
        );
        return 1;
    }
    else {
        $last_backup_modtime ||= 0;
        $self->logger()->log(
            message => 'Not hardlinking. Last modification of table: '
              . $params->{'table_last_update'}
              . ', Last modification of backup: '
              . ( $last_backup_modtime - 24 * 60 ),
            level => 'debug',
        );
        return;
    }
}

sub _table_dump {
    my $self   = shift;
    my $params = shift;

    # Check given params
    foreach my $key (
        qw(
        db table engine mysqld_host target_host
        table_last_update hardlink
        )
      )
    {
        if ( !defined( $params->{$key} ) ) {
            $self->logger()->log( message => 'Missing a value for the required key '.$key.'! Aborting!', level => 'error', );
            return;
        }
    }

    if ( !$params->{'type'} && ( $params->{'type'} ne 'dump' && $params->{'type'} ne 'struct' ) ) {
        $self->logger()->log( message => 'Got no valid value for type! Must be one of {dump,struct}. Aborting!', level => 'error', );
        return;
    }

    $self->logger()->log(
        message => 'Processing Dumps (Type: '.$params->{'type'}.') for DB: '.$params->{'db'}.' / Table: '.$params->{'table'}.' (Engine: '.$params->{'engine'}.')',
        level   => 'debug'
    );

    # Create required directories
    my $destdir      = undef;
    my $destdir_prev = undef;
    if ( $params->{'type'} eq 'struct' ) {
        $destdir = $self->fs()->makedir( $self->fs()->filename( ( $self->dir_structs(), $params->{'db'} ) ), { Uid => $self->uid(), Gid => $self->gid() } );
        $destdir_prev = $self->fs()->makedir( $self->fs()->filename( ( $self->dir_last_rotation(), $self->_dirname_structs(), $params->{'db'} ) ),
            { Uid => $self->uid(), Gid => $self->gid() } );
    }
    else {
        $destdir = $self->fs()->makedir( $self->fs()->filename( ( $self->dir_dumps(), $params->{'db'} ) ), { Uid => $self->uid(), Gid => $self->gid() } );
        $destdir_prev = $self->fs()->makedir( $self->fs()->filename( ( $self->dir_last_rotation(), $self->_dirname_dumps(), $params->{'db'} ) ),
            { Uid => $self->uid(), Gid => $self->gid() } );
    }

    #
    # HARDLINK UNMODIFIED TABLES
    #
    # If a tables wasn't modified (as stated by INFORMATION_SCHEMA - only for MYISAM) we do no new dump but a hardlink instead.
    # The last modification time was already reported by list_tables above. Now we built the path to the last dumpfile and stat()
    # it for its last modification time.
    # If this feature is enabled (it's disabled by default) we check the modification time of the table against the create time
    # of the last backup and create a hardlink with link(), if feasible.
    my $last_backup_modtime;
    my $last_backup_size;
    my $last_backup_file = $self->fs()->filename( $destdir_prev, $params->{'table'} . '.sql' . $self->packer()->ext() );
    if ( $last_backup_file && -e $last_backup_file && $params->{'table_last_update'} ) {
        my @stat = stat($last_backup_file);
        $last_backup_size    = $stat[7];
        $last_backup_modtime = $stat[9];
        $self->logger()->log(
            message => 'Last Backup Modtime for '.$params->{'db'}.q{/}.$params->{'table'}.' is '
              . localtime($last_backup_modtime)
              . '. Last update time of table is '
              . localtime( $params->{'table_last_update'} ),
            level => 'debug'
        );
    }

    if ( $self->_can_hardlink( $params, $last_backup_modtime, $last_backup_size ) ) {

        # skip backup of this table, only create a hardlink
        my $linkdest = $destdir . q{/} . $params->{'table'} . '.sql' . $self->packer()->ext();
        link( $last_backup_file, $linkdest );
        $self->logger()->log( message => 'link_unmodified = 1. Linked '.$last_backup_file.' to '.$linkdest, level => 'debug', );
        return MTK::MYB::Codes::get_status_code('HARDLINK');
    }
    else {

        # Dump table structure
        my $pw_opt = "";
        if ( $self->password() ) {
            $pw_opt = " -p" . $self->password();
        }

        my $mysqldump_bin = '/usr/bin/mysqldump';

        my $cmd = $self->_get_cmd_prefix();
        $cmd .= $mysqldump_bin . ' --opt -u' . $self->username() . $pw_opt . ' -h' . $params->{'mysqld_host'};
        $cmd .= ' --port=' . $params->{'port'} . ' --single-transaction';
        $cmd .= ' --no-data' if $params->{'type'} eq 'struct';
        $cmd .= q{ } . $params->{'db'} . q{ } . $params->{'table'};
        $cmd .= ' | ';
        $cmd .= $self->_get_cmd_prefix();                                                                      # contains CmdMods (nice, ionice, eatmydata, ...)
        $cmd .= $self->packer()->cmd();                                                                        # contains gzip/bzip2/...
        $cmd .=
          $self->_get_cmd_suffix( $params->{'db'}, $params->{'table'}, $params->{'type'}, $destdir, $params->{'table'} . '.sql' )
          ;                                                                                                    # contains output redirection to file/ftp/...

        # Hide password in verbose output
        my $cmdp = $cmd;
        if ( $params->{'password'} ) {
            $cmdp =~ s/$params->{'password'}/xxxxxx/g;
        }
        $self->logger()->log( message => 'CMD: ' . $cmdp, level => 'debug', );
        if ( $self->dry() ) {
            return MTK::MYB::Codes::get_status_code('DRY-RUN');
        }
        else {
            my $status = 1;
            if ( $params->{'target_host'} eq 'localhost' ) {
                $status = $self->sys()->run_cmd( $cmd, { Timeout => 14400, Retry => 0, } );
            }
            else {
                $status = $self->sys()->run_remote_cmd( $params->{'target_host'}, $cmd, { Timeout => 14400, Retry => 0, } );
            }

            # verify that the resulting backup file is larger than 20bytes (gzip header)
            my $local_backup_file =
              $self->_get_local_destination( $params->{'db'}, $params->{'table'}, $params->{'type'}, $destdir, $params->{'table'} . '.sql' );
            my $local_backup_file_size = ( stat($local_backup_file) )[7];

            if ($status) {
                if ( $local_backup_file_size <= 20 ) {
                    $self->logger()->log( message => 'Command finished w/o error but file is too small (lte 20 bytes).', level => 'error', );
                    return &MTK::MYB::Codes::get_status_code('TOO-SMALL');
                }
                else {
                    $self->logger()->log( message => 'Command finished w/o error and file passed the filesize test.', level => 'debug', );
                }
                return &MTK::MYB::Codes::get_status_code('OK');
            }
            else {
                $self->logger()->log( message => 'Command failed.', level => 'error', );
                return MTK::MYB::Codes::get_status_code('UNDEF-ERROR');
            }
        }
    }
}

sub _table_copy {
    my $self   = shift;
    my $params = shift;

    # Check given params
    foreach my $key (
        qw(
        db table engine mysqld_host target_host
        )
      )
    {
        if ( !defined( $params->{$key} ) ) {
            $self->logger()->log( message => 'Missing a value for the required key '.$key.'! Aborting!', level => 'error', );
            return;
        }
    }

    $self->logger()
      ->log( message => 'Processing Tablefiles for DB: '.$params->{'db'}.' / Table: '.$params->{'table'}.' (Engine: '.$params->{'engine'}.')', level => 'debug', );

    my $dbdir = '/var/lib/mysql/' . $params->{'db'} . '/';
    my $cmd   = 'test -d "' . $dbdir . '"';
    if ( !$self->sys()->run( $params->{'target_host'}, $cmd, ) ) {
        $self->logger()
          ->log( message => 'Unable to access DB-Directory at ' . $dbdir . ' for Table ' . $params->{'table'} . '. Aborting.', level => 'warning' );
        return;
    }

    # Create required directories
    my $destdir = $self->fs()->makedir( $self->fs()->filename( ( $self->dir_tables(), $params->{'db'} ) ), { Uid => $self->uid(), Gid => $self->gid() } );
    my $destdir_prev = $self->fs()->makedir( $self->fs()->filename( ( $self->dir_last_rotation(), $self->_dirname_tables(), $params->{'db'} ) ),
        { Uid => $self->uid(), Gid => $self->gid() } );

    # Copy table files
    my $opts = {};
    $opts->{CaptureOutput} = 1;
    $opts->{Timeout}       = 1200;
    $opts->{Retry}         = 0;
    $opts->{Chomp}         = 1;

    my @valid_exts = qw(MYI MYD frm idb ARZ par);

    #$cmd = '/usr/bin/find ' . $dbdir . ' -name "' . $params->{'table'} . '.MYI" -o -name "' . $params->{'table'} . '.MYD" -o -name "' . $params->{'table'} . '.frm"';
    $cmd = '/usr/bin/find ' . $dbdir . ' -name "' .join('" -o -name "'.$params->{'table'}.'.',@valid_exts). '"';
    $self->logger()->log( message => 'CMD: '.$cmd, level => 'debug', );

    my $files = $self->sys()->run( $params->{'target_host'}, $cmd, $opts );
    if ($files) {
        my $status = 1;
        foreach my $file ( split /\n/, $files ) {
            $self->logger()->log( message => 'processing file: '.$file, level => 'debug', );
            my @path = split /\//, $file;
            my $filename = $path[-1];

            #
            # HARDLINK UNMODIFIED TABLES
            #
            # If a tables wasn't modified (as stated by INFORMATION_SCHEMA - only for MYISAM) we do no new dump but a hardlink instead.
            # The last modification time was already reported by list_tables above. Now we built the path to the last dumpfile and stat()
            # it for its last modification time.
            # If this feature is enabled (it's disabled by default) we check the modification time of the table against the create time
            # of the last backup and create a hardlink with link(), if feasible.
            my $last_backup_modtime;
            my $last_backup_size;
            my $last_backup_file = $self->fs()->filename( $destdir_prev, $filename . $self->packer()->ext() );
            if ( $last_backup_file && -e $last_backup_file && $params->{'table_last_update'} ) {
                my @stat = stat($last_backup_file);
                $last_backup_modtime = $stat[9];
                $last_backup_size    = $stat[7];
                $self->logger()->log(
                    message => 'Last Backup Modtime for '.$params->{'db'}.q{/}.$params->{'table'}.' is '
                      . localtime($last_backup_modtime)
                      . '. Last update time of table is '
                      . localtime( $params->{'table_last_update'} ),
                    level => 'debug'
                );
            }
            if (   $params->{'engine'} eq 'MYISAM'
                && $params->{'hardlink'}
                && $last_backup_modtime
                && $last_backup_size
                && $last_backup_size > 20
                && $params->{'table_last_update'}
                && $params->{'table_last_update'} <= ( $last_backup_modtime - 24 * 60 ) )
            {

                # skip backup of this table, only create a hardlink
                my $linkdest = $destdir . "/" . $filename . $self->packer()->ext();
                link( $last_backup_file, $linkdest );
                $self->logger()->log( message => 'link_unmodified = 1. Linked '.$last_backup_file.' to '.$linkdest, level => 'debug', );
                return MTK::MYB::Codes::get_status_code('HARDLINK');
            }
            else {
                $cmd = $self->_get_cmd_prefix();
                $cmd .= $self->packer()->cmd();
                $cmd .= ' ';
                $cmd .= $file;
                $cmd .= ' ';
                $cmd .=
                  $self->_get_cmd_suffix( $params->{'db'}, $params->{'table'}, 'table', $destdir, $filename );    # contains output redirection to file/ftp/...

                $self->logger()->log( message => 'CMD: ' . $cmd, level => 'debug', );
                if ( $self->dry() ) {
                    return MTK::MYB::Codes::get_status_code('DRY-RUN');
                }
                else {
                    $opts                  = {};
                    $opts->{Timeout}       = 14400;
                    $opts->{CaptureOutput} = 0;
                    $opts->{Retry}         = 0;
                    $status                = 1;
                    my $rv = undef;
                    if ( $params->{'target_host'} eq 'localhost' ) {
                        $rv = $self->sys()->run_cmd( $cmd, $opts );
                    }
                    else {
                        $rv = $self->sys()->run_remote_cmd( $params->{'target_host'}, $cmd, $opts );
                    }
                    if ( defined($rv) && $rv == 0 ) {
                        $status = &MTK::MYB::Codes::get_status_code('OK');
                    }
                    else {
                        $status = $rv;
                    }
                }
            }
        }
        return $status;
    }
    else {
        $self->logger()->log( message => 'Find found no files.', level => 'notice', );
        return;
    }
}

sub _record_master_status {
    my $self     = shift;
    my $dbh      = shift;
    my $filename = shift;

    my ( $file, $pos ) = $dbh->get_master_status();
    $file ||= 'none';
    $pos = -1 unless defined($pos);
    my $master_status = "SHOW MASTER STATUS\n";
    $master_status .= "File: $file\nPosition: $pos\n";
    $master_status .= "-----\n";
    if ( &File::Blarf::blarf( $filename, $master_status, { Append => 1, Flock => 1, Newline => 1, } ) ) {
        $self->logger()->log( message => 'Wrote master status to '.$filename, level => 'debug', );
        return ( $pos, $file );
    }
    else {
        $self->logger()->log( message => 'Can not write master status to '.$filename.' w/ error: '.$OS_ERROR, level => 'alert', );
        return;
    }
}

sub _record_slave_status {
    my $self     = shift;
    my $dbh      = shift;
    my $filename = shift;

    my $secbehind    = -1;
    my $ss           = $dbh->get_slave_status($dbh);
    my $slave_status = "SHOW SLAVE STATUS\n";
    if ( $ss && ref($ss) eq 'HASH' ) {
        foreach my $key ( keys %{$ss} ) {
            my $value = $ss->{$key};
            $value = 'n/a' unless defined($value);
            $slave_status .= "$key = $value\n";
        }
        $secbehind = $ss->{'Seconds_Behind_Master'};
    }
    else {
        $slave_status .= "No Slave Status.\n";
        $secbehind = -1;
    }
    if ( File::Blarf::blarf( $filename, $slave_status, { Append => 1, Flock => 1, Newline => 1, } ) ) {
        $self->logger()->log( message => 'Wrote slave status to '.$filename, level => 'debug', );
        return $secbehind;
    }
    else {
        $self->logger()->log( message => 'Can not write slave status to '.$filename.' w/ error: '.$OS_ERROR, level => 'alert', );
        return;
    }
}

sub uid {
    my $self = shift;

    return $EFFECTIVE_USER_ID;
}

sub gid {
    my $self = shift;

    return $EFFECTIVE_GROUP_ID;
}

sub type {
    return 'myb';
}

sub dbms {
    my $self = shift;

    # for MYB dbms is identical to the vault
    return $self->vault();
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

        my $Worker = MTK::MYB::Worker::->new({
                # TODO ...
        });

=head1 DIRECTORIES

/srv/backup/mysql/{dbms1,dbms3,..,dbmsn}/{daily,weekly,monthly,yearly,binlogarchive}/{inprogress,0,1,..,n}/{binlogpos.log,dumps,structs,tables}/"db"/"table".sql."ext"
\---- bank -----/\-- vault ------------/\-------- dir_daily -----------------------/\--- dir_progress ---/\----- type ------------------------/\-db/\-table-/\---ext-/

=head1 NAME

MTK::MYB::Worker - a MYB backup instance

=method dbms

Returns the DBMS that will be/is processed by this worker.

=method gid

The group id for file/directory creation or chown. Usefull for sublcasses which need to overwrite this.

=method run

Run the backup of the given DBMS.

=method type

The type of this worker. Usefull for subclasses.

=method uid

The user id for file/directory creation or chown. Usefull for sublcasses which need to overwrite this.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
