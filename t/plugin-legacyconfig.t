#perl
use strict;
use warnings;
use feature ':5.10';

use Test::More;
use Config::Yak;

#use Log::Tree;
use Test::MockObject::Universal;

use MTK::MYB;
use MTK::MYB::Plugin::LegacyConfig;

my $Config  = Config::Yak::->new( { locations => [], } );
my $Logger  = Test::MockObject::Universal->new();
my $FakeMYB = $Logger;

$Config->set( 'MTK::Mysqlbackup::DBMS::localhost::Hostname',               'localhost' );
$Config->set( 'MTK::Mysqlbackup::DBMS::localhost::exec_pre_opt',           'true' );
$Config->set( 'MTK::Mysqlbackup::DBMS::localhost::link_unmodified_innodb', 'true' );

my $Lcfg = MTK::MYB::Plugin::LegacyConfig::->new(
  {
    'parent' => $FakeMYB,
    'config' => $Config,
    'logger' => $Logger,
  }
);

is( $Lcfg->run_config_hook(), 0, 'Not all ok' );

is( $Config->get('MTK::MYB::DBMS::localhost::hostname'), 'localhost' );
isnt( $Config->get('MTK::Mysqlbackup::DBMS::localhost::hostname'), 'localhost' );

is( $Config->get('MTK::MYB::DBMS::localhost::exec_pre_opt'), 'true' );
isnt( $Config->get('MTK::Mysqlbackup::DBMS::localhost::exec_pre_opt'), 'true' );

is( $Config->get('MTK::MYB::DBMS::localhost::link_unmodified_innodb'), 'true' );
isnt( $Config->get('MTK::Mysqlbackup::DBMS::localhost::link_unmodified_innodb'), 'true' );

done_testing();

1;
