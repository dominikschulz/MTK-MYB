package MTK::MYB::Plugin;

# ABSTRACT: baseclass for any MYB plugin

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

# extends ...
# has ...
has 'parent' => (
  'is'       => 'rw',
  'isa'      => 'MTK::MYB',
  'required' => 1,
);

has 'priority' => (
  'is'      => 'ro',
  'isa'     => 'Int',
  'lazy'    => 1,
  'builder' => '_init_priority',
);

# with ...
with qw(Log::Tree::RequiredLogger Config::Yak::RequiredConfig);

# initializers ...

# your code here ...
sub run_config_hook         { return; }
sub run_prepare_hook        { return; }
sub run_worker_prepare_hook { return; }
sub run_cleanup_hook        { return; }
sub run_worker_cleanup_hook { return; }
sub _init_priority          { return 0; }

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

MTK::MYB::Plugin - baseclass for any MYB plugin

=attr parent

An instance of MTK::MYB (or any subclass).

=attr priority

This plugins priority. Plugins w/ prio 0 won't be loaded.

=method priority

This plugins priority relative to all other plugins.

=method run_cleanup_hook

Run after the backup was run.

=method run_config_hook

This hook allows plugins to contribute to the configuration.

=method run_prepare_hook

Run before the backup is run. But after the config hook.

=method run_worker_prepare_hook

Run before a worker starts to run.

=method run_worker_cleanup_hook

Run after a worker has run.

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
