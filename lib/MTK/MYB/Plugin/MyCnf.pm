package MTK::MYB::Plugin::MyCnf;

# ABSTRACT: Plugin to parse the my.cnf

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
use Config::Tiny;

# extends ...
extends 'MTK::MYB::Plugin';

# has ...
# with ...
# initializers ...
sub _init_priority { return 1; }

# requires ...

# your code here ...
sub _set_mysqld_defaults {
  my $self           = shift;
  my $current_mysqld = shift;

  if ( $current_mysqld eq 'mysqld' && $self->config()->get('MTK::MYB::DBMS::localhost') ) {

    # copy everything from localhost to mysqld and delete localhost
    foreach my $prop ( $self->config()->get_array('MTK::MYB::DBMS::localhost') ) {
      my $val = $self->config()->get( 'MTK::MYB::DBMS::localhost::' . $prop );
      $self->config()->set( 'MTK::MYB::DBMS::mysqld::' . $prop, $val );
    }
    $self->config()->delete('MTK::MYB::DBMS::localhost');
  } ## end if ( $current_mysqld eq...)

  # set default bind-address to localhost, in case no bind-address is defined
  my $hostname = $self->config()->get('MTK::MYB::Hostname') || 'localhost';
  $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Hostname', $hostname )
    unless $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::Hostname' );

  # set default port to 3306, in case no port is defined
  my $port = $self->config()->get('MTK::MYB::Port') || 3306;
  $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Port', $port )
    unless $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::Port' );

  # set default user
  my $username = $self->config()->get('MTK::Mysql::User::DBA::Username') || $self->config()->get('MTK::Mysql::User::DebianSysMaint::Username');
  $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Username', $username )
    unless $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::Username' );

  # set default password
  my $password = $self->config()->get('MTK::Mysql::User::DBA::Password') || $self->config()->get('MTK::Mysql::User::DebianSysMaint::Password');
  $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Password', $password )
    unless $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::Password' );
  return 1;
} ## end sub _set_mysqld_defaults

sub run_config_hook {
  my $self = shift;
  my $mycnf_file = shift || '/etc/mysql/my.cnf';

  if ( !-e $mycnf_file ) {
    $self->logger()->log( message => "File my.cnf not found at $mycnf_file.", level => 'notice', );
    return;
  }

  my $cnf = Config::Tiny::->read($mycnf_file);

  foreach my $section ( sort keys %{$cnf} ) {
    if ( $section =~ m/^\[(mysqld\d*)\]/ ) {
      my $current_mysqld = $1;

      $self->_set_mysqld_defaults($current_mysqld);

      # process each key
      foreach my $key ( sort keys %{ $cnf->{$section} } ) {
        my $value = $cnf->{$section}->{$key};
        if ( $key =~ m/^\s*bind-address.*/ ) {

          # Important: a manual setting of mysql_host.mysqld overrides the value from the config!
          # This comes into play when we need to connect via the unix socket instead of 127.0.0.1, e.g.
          # in a vserver with broken networking
          $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Hostname', $value );
        } ## end if ( $key =~ m/^\s*bind-address.*/)
        elsif ( $key =~ m/^\s*port.*/ ) {
          $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Port', $value );
          if ( $value ne '3306' && $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::Hostname' ) eq 'localhost' ) {
            $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Hostname', '127.0.0.1' );
          }
        } ## end elsif ( $key =~ m/^\s*port.*/)
        elsif ( $key =~ m/^\s*datadir.*/ ) {
          $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::Datadir', $value )
            unless $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::Datadir' );
        }
        elsif ( $key =~ m/^\s*log[_-]bin/ ) {
          $self->config()->set( 'MTK::MYB::DBMS::' . $current_mysqld . '::LogBin', $value )
            unless $self->config()->get( 'MTK::MYB::DBMS::' . $current_mysqld . '::LogBin' );
        }
      } ## end foreach my $key ( sort keys...)
    } ## end if ( $section =~ m/^\[(mysqld\d*)\]/)
    elsif ( $section =~ m/^\[mysqld_multi\]/ ) {

      # if a multi mysqld is defined remove the single-mysqld configuration
      $self->config()->delete('MTK::MYB::DBMS::Mysqld');
    }
  } ## end foreach my $section ( sort ...)
  return 1;
} ## end sub run_config_hook

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin::MyCnf - Plugin to parse the my.cnf

=method priority

This plugins relative priority.

=method run

Execute this plugin.

=method run_config_hook

Read a global /etc/mysql/my.cnf and contribute to the config.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
