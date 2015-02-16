#!perl -T

use Test::More tests => 26;

BEGIN {
  use_ok('MTK::MYB::Checker::Plugin::Zabbix') || print "Bail out!
";
  use_ok('MTK::MYB::Checker::Plugin') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd::Command::backupcheck') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd::Command::cleanup') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd::Command::configcheck') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd::Command::restore') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd::Command::run') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd::Command') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin::DebianCnf') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin::DotMyCnf') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin::LegacyConfig') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin::ListBackupDir') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin::MyCnf') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin::Zabbix') || print "Bail out!
";
  use_ok('MTK::MYB::Restore::Job') || print "Bail out!
";
  use_ok('MTK::MYB::Restore::Worker') || print "Bail out!
";
  use_ok('MTK::MYB::Checker') || print "Bail out!
";
  use_ok('MTK::MYB::Cmd') || print "Bail out!
";
  use_ok('MTK::MYB::Codes') || print "Bail out!
";
  use_ok('MTK::MYB::Job') || print "Bail out!
";
  use_ok('MTK::MYB::Packer') || print "Bail out!
";
  use_ok('MTK::MYB::Plugin') || print "Bail out!
";
  use_ok('MTK::MYB::Restore') || print "Bail out!
";
  use_ok('MTK::MYB::Status') || print "Bail out!
";
  use_ok('MTK::MYB::Worker') || print "Bail out!
";
  use_ok('MTK::MYB') || print "Bail out!
";
} ## end BEGIN

diag("Testing MTK::MYB $MTK::MYB::VERSION, Perl $], $^X");
