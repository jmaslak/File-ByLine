#!/usr/bin/perl

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

package File::ByLine;

use v5.10;

# ABSTRACT: Line-by-line file access loops

use strict;
use warnings;
use autodie;

use Carp;
use Fcntl;
use File::ByLine::Object;
use Scalar::Util qw(reftype);

# Object with default options
our $OBJ = File::ByLine::Object->new();

=head1 SYNOPSIS

  use File::ByLine;

  #
  # Execute a routine for each line of a file
  #
  dolines { say "Line: $_" } "file.txt";
  forlines "file.txt", sub { say "Line: $_" };

  #
  # Grep (match) lines of a file
  #
  my (@result) = greplines { m/foo/ } "file.txt";

  #
  # Apply a function to each line and return result
  #
  my (@result) = maplines { lc($_) } "file.txt";

  #
  # Parallelized forlines/dolines routines
  # (Note: Requires Parallel::WorkUnit to be installed)
  #
  parallel_dolines { foo($_) } "file.txt", 10;
  parallel_forlines "file.txt", 10, sub { foo($_); };

  #
  # Parallelized maplines and greplines
  #
  my (@result) = parallel_greplines { m/foo/ } "file.txt", 10;
  my (@result) = parallel_maplines  { lc($_) } "file.txt", 10;

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
our @ISA = qw(Exporter);

## no critic (Modules::ProhibitAutomaticExportation)
our @EXPORT =
  qw(dolines forlines greplines maplines parallel_dolines parallel_forlines parallel_greplines parallel_maplines readlines);
## use critic

our @EXPORT_OK =
  qw(dolines forlines greplines maplines parallel_dolines parallel_forlines parallel_greplines parallel_maplines readlines);

=func dolines

  dolines { say "Line: $_" } "file.txt";
  dolines \&func, "file.txt";

This function calls a coderef once for each line in the file.  The file is read
line-by-line, removes the newline character(s), and then executes the coderef.

Each line (without newline) is passed to the coderef as the first parameter and
only parameter to the coderef.  It is also placed into C<$_>.

This function returns the number of lines in the file.

This is similar to C<forlines()>, except for order of arguments.  The author
recommends this form for short code blocks - I.E. a coderef that fits on
one line.  For longer, multi-line code blocks, the author recommends
the C<forlines()> syntax.

=cut

sub dolines (&$) {
    my ( $code, $file ) = @_;

    return $OBJ->do( $code, $file );
}

=func forlines

  forlines "file.txt", sub { say "Line: $_" };
  forlines "file.txt", \&func;

This function calls a coderef once for each line in the file.  The file is read
line-by-line, removes the newline character(s), and then executes the coderef.

Each line (without newline) is passed to the coderef as the first parameter and
only parameter to the coderef.  It is also placed into C<$_>.

This function returns the number of lines in the file.

This is similar to C<dolines()>, except for order of arguments.  The author
recommends this when using longer, multi-line code blocks, even though it is
not orthogonal with the C<maplines()>/C<greplines()> routines.

=cut

sub forlines ($&) {
    my ( $file, $code ) = @_;

    return $OBJ->do( $code, $file );
}

=func parallel_dolines

  my (@result) = parallel_dolines { foo($_) } "file.txt", 10;

Requires L<Parallel::WorkUnit> to be installed.

Three parameters are requied: a codref, a filename, and number of simultanious
child threads to use.

This function performs similar to C<dolines()>, except that it does its'
operations in parallel using C<fork()> and L<Parallel::WorkUnit>.  Because
the code in the coderef is executed in a child process, any changes it makes
to variables in high scopes will not be visible outside that single child.
In general, it will be safest to not modify anything that belongs outside
this scope.

Note that the file will be read in several chunks, with each chunk being
processed in a different thread.  This means that the child threads may be
operating on very different sections of the file simultaniously and no specific
order of execution of the coderef should be expected!

Because of the mechanism used to split the file into chunks for processing,
each thread may process a somewhat different number of lines.  This is
particularly true if there are a mix of very long and very short lines.  The
splitting routine splits the file into roughly equal size chunks by byte
count, not line count.

Otherwise, this function is identical to C<dolines()>.  See the documentation
for C<dolines()> or C<forlines()> for information about how this might differ
from C<parallel_forlines()>.

=cut

sub parallel_dolines (&$$) {
    my ( $code, $file, $procs ) = @_;

    if ( !defined($procs) ) {
        croak("Must include number of child processes");
    }

    if ( $procs <= 0 ) { croak("Number of processes must be >= 1"); }

    my $byline = File::ByLine::Object->new();
    $byline->processes($procs);

    return $byline->do( $code, $file );
}

=func parallel_forlines

  my (@result) = parallel_forlines "file.txt", 10, sub { foo($_) };

Requires L<Parallel::WorkUnit> to be installed.

Three parameters are requied: a filename, a codref, and number of simultanious
child threads to use.

This function performs similar to C<forlines()>, except that it does its'
operations in parallel using C<fork()> and L<Parallel::WorkUnit>.  Because
the code in the coderef is executed in a child process, any changes it makes
to variables in high scopes will not be visible outside that single child.
In general, it will be safest to not modify anything that belongs outside
this scope.

Note that the file will be read in several chunks, with each chunk being
processed in a different thread.  This means that the child threads may be
operating on very different sections of the file simultaniously and no specific
order of execution of the coderef should be expected!

Because of the mechanism used to split the file into chunks for processing,
each thread may process a somewhat different number of lines.  This is
particularly true if there are a mix of very long and very short lines.  The
splitting routine splits the file into roughly equal size chunks by byte
count, not line count.

Otherwise, this function is identical to C<forlines()>.  See the documentation
for C<forlines()> or C<dolines()> for information about how this might differ
from C<parallel_dolines()>.

=cut

sub parallel_forlines ($$&) {
    my ( $file, $procs, $code ) = @_;

    if ( !defined($procs) ) {
        croak("Must include number of child processes");
    }

    if ( $procs <= 0 ) { croak("Number of processes must be >= 1"); }

    my $byline = File::ByLine::Object->new();
    $byline->processes($procs);

    return $byline->do( $code, $file );
}

=func greplines

  my (@result) = greplines { m/foo/ } "file.txt";

Requires L<Parallel::WorkUnit> to be installed.

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

    return $OBJ->grep( $code, $file );
}

=func parallel_greplines

  my (@result) = parallel_greplines { m/foo/ } "file.txt", 10;

Three parameters are requied: a coderef, filename, and number of simultanious
child threads to use.

This function performs similar to C<greplines()>, except that it does its'
operations in parallel using C<fork()> and L<Parallel::WorkUnit>.  Because
the code in the coderef is executed in a child process, any changes it makes
to variables in high scopes will not be visible outside that single child.
In general, it will be safest to not modify anything that belongs outside
this scope.

If a large amount of data is returned, the overhead of passing the data
from child to parents may exceed the benefit of parallelization.  However,
if there is substantial line-by-line processing, there likely will be a speedup,
but trivial loops will not speed up.

Note that the file will be read in several chunks, with each chunk being
processed in a different thread.  This means that the child threads may be
operating on very different sections of the file simultaniously and no specific
order of execution of the coderef should be expected!  However, the results
will be returned in the same order as C<greplines()> would return them.

Because of the mechanism used to split the file into chunks for processing,
each thread may process a somewhat different number of lines.  This is
particularly true if there are a mix of very long and very short lines.  The
splitting routine splits the file into roughly equal size chunks by byte
count, not line count.

Otherwise, this function is identical to C<greplines()>.

=cut

sub parallel_greplines (&$$) {
    my ( $code, $file, $procs ) = @_;

    if ( !defined($procs) ) {
        croak("Must include number of child processes");
    }

    if ( $procs <= 0 ) { croak("Number of processes must be >= 1"); }

    my $byline = File::ByLine::Object->new();
    $byline->processes($procs);

    return $byline->grep( $code, $file );
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

Because of the mechanism used to split the file into chunks for processing,
each thread may process a somewhat different number of lines.  This is
particularly true if there are a mix of very long and very short lines.  The
splitting routine splits the file into roughly equal size chunks by byte
count, not line count.

This function returns the lines for which the coderef evaluates as true.

=cut

sub maplines (&$) {
    my ( $code, $file ) = @_;

    return $OBJ->map( $code, $file );
}

=func parallel_maplines

  my (@result) = parallel_maplines { lc($_) } "file.txt", 10;

Three parameters are requied: a coderef, filename, and number of simultanious
child threads to use.

This function performs similar to C<maplines()>, except that it does its'
operations in parallel using C<fork()> and L<Parallel::WorkUnit>.  Because
the code in the coderef is executed in a child process, any changes it makes
to variables in high scopes will not be visible outside that single child.
In general, it will be safest to not modify anything that belongs outside
this scope.

If a large amount of data is returned, the overhead of passing the data
from child to parents may exceed the benefit of parallelization.  However,
if there is substantial line-by-line processing, there likely will be a speedup,
but trivial loops will not speed up.

Note that the file will be read in several chunks, with each chunk being
processed in a different thread.  This means that the child threads may be
operating on very different sections of the file simultaniously and no specific
order of execution of the coderef should be expected!  However, the results
will be returned in the same order as C<maplines()> would return them.

Otherwise, this function is identical to C<maplines()>.

=cut

sub parallel_maplines (&$$) {
    my ( $code, $file, $procs ) = @_;

    if ( !defined($procs) ) {
        croak("Must include number of child processes");
    }

    if ( $procs <= 0 ) { croak("Number of processes must be >= 1"); }

    my $byline = File::ByLine::Object->new();
    $byline->processes($procs);

    return $byline->map( $code, $file );
}

=func readlines

  my (@result) = readlines "file.txt";

This function simply returns an array of lines (without newlines) read from
a file.

=cut

sub readlines ($) {
    my ($file) = @_;

    return $OBJ->lines($file);
}

#
# Object Oriented Interface
#

sub new {
    shift;    # Remove the first parameter because we want to specify the class.

    return File::ByLine::Object->new(@_);
}

=head1 SUGGESTED DEPENDENCY

The L<Parallel::WorkUnit> module is a recommended dependency.  It is required
to use the C<parallel_*> functions - all other functionality works fine without
it.

Some CPAN clients will automatically try to install recommended dependency, but
others won't (L<cpan> often, but not always, will; L<cpanm> will not by
default).  In the cases where it is not automatically installed, you need to
install L<Parallel::WorkUnit> to get this functionality.

=cut

1;

