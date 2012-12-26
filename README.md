This is the README file for MTK-MYB, a MySQL Backup tool.

## Description

MTK-MYB provides a MySQL backup tool.

This application was written with a focus on logging and
monitoring. It comes with several addons for monitoring and
reporting as well as backup integrity checks.

There is also a centralized implementation available as
MTK-MYB-CNC.

## Installation

This package uses Dist::Zilla.

Use

dzil build

to create a release tarball which can be
unpacked and installed like any other EUMM
distribution.

perl Makefile.PL

make

make test

make install

## Documentation

Please see perldoc MTK::MYB.
