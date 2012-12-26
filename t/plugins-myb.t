#perl
use strict;
use warnings;
use feature ':5.10';

use Test::More;
use Config::Yak;
use Test::MockObject::Universal;

use MTK::MYB;

my $Config = Config::Yak::->new({ locations => [], });
my $Logger = Test::MockObject::Universal->new();

my $MYB = MTK::MYB::->new({
    'config'    => $Config,
    'logger'    => $Logger,
});
$Config->set('MTK::MYB::Plugin::Reporter::Disabled',1);

my @got_pnames = map { ref($_) } @{$MYB->plugins()};
my @expect_pnames = map { 'MTK::MYB::Plugin::'.$_ } qw(MyCnf ListBackupDir Zabbix DotMyCnf DebianCnf LegacyConfig);
is_deeply(\@got_pnames,\@expect_pnames,'Got ordered plugins');
$MYB = undef;

$MYB = MTK::MYB::->new({
    'config'    => $Config,
    'logger'    => $Logger,
});
$Config->set('MTK::MYB::Plugin::DebianCnf::Priority',9);
@expect_pnames = map { 'MTK::MYB::Plugin::'.$_ } qw(MyCnf DebianCnf ListBackupDir Zabbix DotMyCnf LegacyConfig);
@got_pnames = map { ref($_) } @{$MYB->plugins()};
is_deeply(\@got_pnames,\@expect_pnames,'Got ordered plugins');

done_testing();

1;
