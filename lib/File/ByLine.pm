#!/usr/bin/perl

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

package File::ByLine;

use v5.8;

# ABSTRACT: Line-by-line file access loops

use strict;
use warnings;
use autodie;

use Carp;

=head1 SYNOPSIS

  use File::ByLine;

  #
  # Execute a routine for each line of a file
  #
  forlines "file.txt", { say "Line: $_" };

  #
  # Grep (match) lines of a file
  #
  my (@result) = greplines { m/foo/ } "file.txt";

  #
  # Apply a function to each line and return result
  #
  my (@result) = maplines { lc($_) } "file.txt";

  #
  # Read an entire file, split into lines
  #
  my (@result) = readlines "file.txt";

=head1 DESCRIPTION

Finding myself writing the same trivial loops to read files, or relying on
modules like C<Perl6::Slurp> that didn't quite do what I needed (abstracting
the loop), it was clear something easy, simple, and sufficiently Perl-ish was
needed.

=cut

#
# Exports
#
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(forlines greplines maplines readlines);  ## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT_OK = qw(forlines greplines maplines);

=func forlines

  forlines "file.txt", { say "Line: $_" };
  forlines "file.txt", \&func;

This function calls a coderef once for each line in the file.  The file is read
line-by-line, removes the newline character(s), and then executes the coderef.

Each line (without newline) is passed to the coderef as the first parameter and
only parameter to the coderef.  It is also placed into C<$_>.

This function returns the number of lines in the file.

=cut

sub forlines ($&) {
    my ( $file, $code ) = @_;

    open my $fh, '<', $file or die($!);

    my $lineno = 0;
    while (<$fh>) {
        $lineno++;

        chomp;
        $code->($_);
    }

    close $fh;

    return $lineno;
}

=func greplines

  my (@result) = greplines { m/foo/ } "file.txt";

This function calls a coderef once for each line in the file, and, based on
the return value of that coderef, returns only the lines where the coderef
evaluates to true.  This is similar to the C<grep> built-in function, except
operating on file input rather than array input.

Each line (without newline) is passed to the coderef as the first parameter and
only parameter to the coderef.  It is also placed into C<$_>.

This function returns the lines for which the coderef evaluates as true.

=cut

sub greplines (&$) {
    my ( $code, $file ) = @_;

    my @return;

    open my $fh, '<', $file or die($!);

    my $lineno = 0;
    while (<$fh>) {
        $lineno++;

        chomp;
        if ( $code->($_) ) {
            push @return, $_;
        }
    }

    close $fh;

    return @return;
}

=func maplines

  my (@result) = maplines { lc($_) } "file.txt";

This function calls a coderef once for each line in the file, and, returns
an array of return values from those calls.  This follows normal Perl rules -
basically if the coderef returns a list, all elements of that list are added
as distinct elements to the return value array.  If the coderef returns an
empty list, no elements are added.

Each line (without newline) is passed to the coderef as the first parameter and
only parameter to the coderef.  It is also placed into C<$_>.

This is meant to be similar to the built-in C<map> function.

This function returns the lines for which the coderef evaluates as true.

=cut

sub maplines (&$) {
    my ( $code, $file ) = @_;

    my @return;

    open my $fh, '<', $file or die($!);

    my $lineno = 0;
    while (<$fh>) {
        $lineno++;

        chomp;
        push @return, $code->($_);
    }

    close $fh;

    return @return;
}

=func readlines

  my (@result) = readlines "file.txt";

This function simply returns an array of lines (without newlines) read from
a file.

=cut

sub readlines ($) {
    my ( $file ) = @_;

    my @return;

    open my $fh, '<', $file or die($!);

    my $lineno = 0;
    while (<$fh>) {
        $lineno++;

        chomp;
        push @return, $_;
    }

    close $fh;

    return @return;
}

1;

