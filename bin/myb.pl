#!/usr/bin/perl
# ABSTRACT: The MySQL Backup commandline interface
# PODNAME: myb.pl
use strict;
use warnings;

use MTK::MYB::Cmd;

# All the magic is done using MooseX::App::Cmd, App::Cmd and MooseX::Getopt
my $Cmd = MTK::MYB::Cmd::->new();
$Cmd->run();

__END__

=head1 NAME

myb - MySQL Backup

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
