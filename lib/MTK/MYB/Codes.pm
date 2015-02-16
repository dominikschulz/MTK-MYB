package MTK::MYB::Codes;

# ABSTRACT: the MYB status codes

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use strict;
use warnings;

{
  my %status_code = (
    1   => 'UNDEF-ERROR',
    0   => 'OK',
    -1  => 'IGNORED',
    -2  => 'NO-DUMP',
    -3  => 'DRY-RUN',
    -4  => 'HARDLINK',
    -5  => 'NO-TABLEFILES',
    -6  => 'NOT-MYISAM',
    -7  => 'NO-STRUCT',
    95  => 'TOO-SMALL',        # only a gzip header
    96  => 'NO-INSTANCES',
    97  => 'PRE-EXEC-ERROR',
    98  => 'CONNECT-ERROR',
    99  => 'SSH-ERROR',
    100 => 'FTP-ERROR',
    101 => 'MYSQL-LOST',
    102 => 'NO-TABLES',
    255 => 'UNKNOWN-ERROR',
  );

  sub get_status_code {
    my $search = shift;
    foreach my $code ( keys %status_code ) {
      my $text = $status_code{$code};
      return $code if $text =~ m/^\Q$search\E$/i;
    }
    return 255;
  } ## end sub get_status_code

  sub get_status_text {
    my $search = shift;
    if ( $status_code{$search} ) {
      return $status_code{$search};
    }
    return 'UNK';
  } ## end sub get_status_text

  sub status_text {
    my $status = shift;
    if ( $status_code{$status} ) {
      return $status_code{$status};
    }
    elsif ( $status > 0 ) {
      return 'ERROR: ' . $status;
    }
    else {
      return 'WARN: ' . $status;
    }
  } ## end sub status_text
}

1;

__END__

=head1 NAME

MTK::MYB::Codes - mysqlbackup status codes

=method get_status_code

Get the numeric status code for the given search string.

=method get_status_text

Get the textual status for the given numberic status.

=method status_text

TODO DOC

=head1 ACKNOWLEDGEMENT

This module was originally developed for eGENTIC Systems. With approval from eGENTIC Systems,
this module was generalized and published, for which the authors would like to express their
gratitude.

=cut
