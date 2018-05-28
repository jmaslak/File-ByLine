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
use Fcntl;

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
  # Parallelized maplines and greplines
  #
  my (@result) = parallel_greplines { lc($_) } "file.txt";
  my (@result) = parallel_maplines  { lc($_) } "file.txt";

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
our @EXPORT = qw(forlines greplines maplines parallel_greplines parallel_maplines readlines);
## use critic

our @EXPORT_OK = qw(forlines greplines maplines parallel_greplines parallel_maplines readlines);

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

    my ( $fh, $end ) = _open_and_seek( $file, 1, 0 );    # Part[0] of one part

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

    my $lines = _grep_chunk( $code, $file, 1, 0 );
    return @$lines;
}

=func parallel_greplines

  my (@result) = parallel_greplines { m/foo/ } "file.txt", 4;

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
        croak("Must include number of child processes before filename - Ex: 4:file.txt");
    }

    if ( $procs <= 0 ) { croak("Number of processes must be >= 1"); }

    require Parallel::WorkUnit or croak("Parallel::WorkUnit must be installed");
    if ( $Parallel::WorkUnit::VERSION < 1.111 ) {
        croak("Parallel::WorkUnit must be version 1.111 or newer");
    }

    my $wu = Parallel::WorkUnit->new();
    for ( my $part = 0; $part < $procs; $part++ ) {
        $wu->async(
            sub {
                return _grep_chunk( $code, $file, $procs, $part );
            }
        );
    }

    return map { @$_ } $wu->waitall();
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

    my $mapped_lines = _map_chunk( $code, $file, 1, 0 );
    return @$mapped_lines;
}

=func parallel_maplines

  my (@result) = parallel_maplines { lc($_) } "file.txt", 4;

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
        croak("Must include number of child processes before filename - Ex: 4:file.txt");
    }

    if ( $procs <= 0 ) { croak("Number of processes must be >= 1"); }

    require Parallel::WorkUnit or croak("Parallel::WorkUnit must be installed");
    if ( $Parallel::WorkUnit::VERSION < 1.111 ) {
        croak("Parallel::WorkUnit must be version 1.111 or newer");
    }

    my $wu = Parallel::WorkUnit->new();
    for ( my $part = 0; $part < $procs; $part++ ) {
        $wu->async(
            sub {
                return _map_chunk( $code, $file, $procs, $part );
            }
        );
    }

    return map { @$_ } $wu->waitall();
}

=func readlines

  my (@result) = readlines "file.txt";

This function simply returns an array of lines (without newlines) read from
a file.

=cut

sub readlines ($) {
    my ($file) = @_;

    my @lines;

    open my $fh, '<', $file or die($!);

    while (<$fh>) {
        chomp;
        push @lines, $_;
    }

    close $fh;

    return @lines;
}

# Internal function to perform a grep on a single chunk of the file.
#
# Procs should be >= 1.  It represents the number of chunks the file
# has.
#
# Part should be >= 0 and < Procs.  It represents the zero-indexed chunk
# number this invocation is processing.
sub _grep_chunk {
    my ( $code, $file, $procs, $part ) = @_;

    my ( $fh, $end ) = _open_and_seek( $file, $procs, $part );

    my @lines;
    while (<$fh>) {
        chomp;

        if ( $code->($_) ) {
            push @lines, $_;
        }

        # If we're reading multi-parts, do we need to end the read?
        if ( ( $end > 0 ) && ( tell($fh) > $end ) ) { last; }
    }

    close $fh;
    return \@lines;
}

# Internal function to perform a map on a single chunk of the file.
#
# Procs should be >= 1.  It represents the number of chunks the file
# has.
#
# Part should be >= 0 and < Procs.  It represents the zero-indexed chunk
# number this invocation is processing.
sub _map_chunk {
    my ( $code, $file, $procs, $part ) = @_;

    my ( $fh, $end ) = _open_and_seek( $file, $procs, $part );

    my @mapped_lines;
    while (<$fh>) {
        chomp;
        push @mapped_lines, $code->($_);

        # If we're reading multi-parts, do we need to end the read?
        if ( ( $end > 0 ) && ( tell($fh) > $end ) ) { last; }
    }

    close $fh;
    return \@mapped_lines;
}

# Internal function to facilitate reading a file in chunks.
#
# If parts == 1, this basically just opens the file (and returns -1 for
# end, to be discussed later)
#
# If parts > 1, then this divides the file (by byte count) into that
# many parts, and then seeks to the first character at the start of a
# new line in that part (lines are attributed to the part in which they
# end).
#
# It also returns an end position - no line starting *after* the end
# position is in the relevant chunk.
#
# part_number is zero indexed.
#
# For part_number >= 1, the first valid character is actually start + 1
# If a line actually starts at the first position, we treat it as
# part of the previous chunk.
#
# If no lines would start in a given chunk, this seeks to the end of the
# file (so it gives an EOF on the first read)
sub _open_and_seek {
    my ( $file, $parts, $part_number ) = @_;

    if ( !defined($parts) )       { $parts       = 1; }
    if ( !defined($part_number) ) { $part_number = 0; }

    if ( $parts <= $part_number ) {
        croak("Part Number must be greater than number of parts");
    }
    if ( $parts <= 0 ) {
        croak("Number of parts must be > 0");
    }
    if ( $part_number < 0 ) {
        croak("Part Number must be greater or equal to 0");
    }

    open my $fh, '<', $file or die($!);

    # If this is a single part request, we are done here.
    # We use -1, not size, because it's possible the read is from a
    # terminal or pipe or something else that can grow.
    if ( $parts == 0 ) {
        return ( $fh, -1 );
    }

    # This is a request for part of a multi-part document.  How big is
    # it?
    seek( $fh, 0, Fcntl::SEEK_END );
    my $size = tell($fh);

    # Special case - more threads than needed.
    if ( $parts > $size ) {
        if ( $part_number > $size ) { return ( $fh, -1 ) }

        # We want each part to be one byte, basically.  Not fractiosn of
        # a byte.
        $parts = $size;
    }

    # Figure out start and end size
    my $start = int( $part_number * ( $size / $parts ) );
    my $end = int( $start + ( $size / $parts ) );

    # Seek to start position
    seek( $fh, $start, Fcntl::SEEK_SET );

    # Read and discard junk to the end of line.
    # But ONLY for parts other than the first one.  We basically assume
    # all parts > 1 are starting mid-line.
    if ( $part_number > 0 ) {
        scalar(<$fh>);
    }

    # Special case - allow file to have grown since first read to end
    if ( ( $parts - 1 ) == $part_number ) {
        return ( $fh, -1 );
    }

    # Another special case...  If we're already past the end, seek to
    # the end.
    if ( tell($fh) > $end ) {
        seek( $fh, 0, Fcntl::SEEK_END );
    }

    # We return the file at this position.
    return ( $fh, $end );
}

1;

