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
  # Procedural Interface (Simple!)
  #

  # Execute a routine for each line of a file
  dolines { say "Line: $_" } "file.txt";
  forlines "file.txt", sub { say "Line: $_" };

  # Grep (match) lines of a file
  my (@result) = greplines { m/foo/ } "file.txt";

  # Apply a function to each line and return result
  my (@result) = maplines { lc($_) } "file.txt";

  # Parallelized forlines/dolines routines
  # (Note: Requires Parallel::WorkUnit to be installed)
  parallel_dolines { foo($_) } "file.txt", 10;
  parallel_forlines "file.txt", 10, sub { foo($_); };

  # Parallelized maplines and greplines
  my (@result) = parallel_greplines { m/foo/ } "file.txt", 10;
  my (@result) = parallel_maplines  { lc($_) } "file.txt", 10;

  # Read an entire file, split into lines
  my (@result) = readlines "file.txt";

  # Write out a file
  writefile "file.txt", @lines;  # Since version 2.182350

  #
  # Object Oriented Interface (More Powerful!)
  #

  # Execute a routine for each line of a file
  my $byline = File::ByLine->new();
  $byline->do( sub { say "Line: $_" }, "file.txt");

  # Grep (match) lines of a file
  my $byline = File::ByLine->new();
  my (@result) = $byline->grep( sub { m/foo/ }, "file.txt");

  # Apply a function to each line and return result
  my $byline = File::ByLine->new();
  my (@result) = $byline->map( sub { lc($_) }, "file.txt");

  # Parallelized routines
  # (Note: Requires Parallel::WorkUnit to be installed)
  my $byline = File::ByLine->new();
  $byline->processes(10);
  $byline->do( sub { foo($_) }, "file.txt");
  my (@grep_result) = $byline->grep( sub { m/foo/ }, "file.txt");
  my (@map_result)  = $byline->map( sub { lc($_) }, "file.txt");

  # Skip the header line
  my $byline = File::ByLine->new();
  $byline->skip_header(1);
  $byline->do( sub { foo($_) }, "file.txt");
  my (@grep_result) = $byline->grep( sub { m/foo/ }, "file.txt");
  my (@map_result)  = $byline->map( sub { lc($_) }, "file.txt");

  # Process the header line
  my $byline = File::ByLine->new();
  $byline->header_handler( sub { say $_; } );
  $byline->do( sub { foo($_) }, "file.txt");
  my (@grep_result) = $byline->grep( sub { m/foo/ }, "file.txt");
  my (@map_result)  = $byline->map( sub { lc($_) }, "file.txt");

  # Read an entire file, split into lines
  my (@result) = $byline->lines("file.txt");

  # Alternative way of specifying filenames
  my $byline = File::ByLine->new();
  $byline->file("file.txt")
  $byline->do( sub { foo($_) } );
  my (@grep_result) = $byline->grep( sub { m/foo/ } );
  my (@map_result)  = $byline->map( sub { lc($_) } );

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
  qw(dolines forlines greplines maplines parallel_dolines parallel_forlines parallel_greplines parallel_maplines readlines writefile);
## use critic

our @EXPORT_OK =
  qw(dolines forlines greplines maplines parallel_dolines parallel_forlines parallel_greplines parallel_maplines readlines writefile);

=func dolines

  dolines { say "Line: $_" } "file.txt";
  dolines \&func, "file.txt";

This function calls a coderef once for each line in the file.  The file is read
line-by-line, removes the newline character(s), and then executes the coderef.

Each line (without newline) is passed to the coderef as the only parameter to
the coderef.  It is also placed into C<$_>.

This function returns the number of lines in the file.

This is similar to C<forlines()>, except for order of arguments.  The author
recommends this form for short code blocks - I.E. a coderef that fits on
one line.  For longer, multi-line code blocks, the author recommends
the C<forlines()> syntax.

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

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

Each line (without newline) is passed to the coderef as the only parameter to
the coderef.  It is also placed into C<$_>.

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

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

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

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

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

Each line (without newline) is passed to the coderef as the only parameter to
the coderef.  It is also placed into C<$_>.

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

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

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

Each line (without newline) is passed to the coderef as the only parameter to
the coderef.  It is also placed into C<$_>.

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

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

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

=func writefile

  writefile "file.txt", @lines;

This was added in version 2.181850.

This function creates a file (overwriting existing files) and writes each
line to the file.  Each line (array element) is terminated with a newline,
except the last line IF the last line ends in a newline itself.

I.E. the following will write a file with three lines, each terminated by
a newline:

  writefile "file.txt", "a", "b", "c";

So will this:

  writefile "file.txt", "a\nb", "c\n";

There is no object-oriented equivilent to this function.

This does not return any value.

=cut

sub writefile ($@) {
    my ( $file, @lines ) = @_;
    if ( !defined($file) ) { die("Must define the filename"); }

    # Last line should have it's newline removed, if applicable
    if (@lines) { $lines[-1] =~ s/\n$//s; }

    open my $fh, '>', $file;
    foreach my $line (@lines) {
        say $fh $line;
    }
    close $fh;

    return;
}

#
# Object Oriented Interface
#

sub new {
    shift;    # Remove the first parameter because we want to specify the class.

    return File::ByLine::Object->new(@_);
}

=head1 OBJECT ORIENTED INTERFACE

The object oriented interface was implemented in version 1.181860.

=head2 new

  my $byline = File::ByLine->new();

Constructs a new object, suitable for the object oriented calls below.

=head2 ATTRIBUTES

=head3 extended_info

  $extended = $byline->extended_info();
  $byline->extended_info(1);

This was added in version 1.181951.

Gets and sets the "extended information" flag.  This defaults to false, but
if set to a true value this will pass a second parameter to all user-defined
code (such as the per-line code function in C<dolines> and C<do> and the
C<header_handler> function.

For all code, this information will be passed as the second argument to the
user defined code.  It will be a hashref with the following keys defined:

=over 4

=item C<filename> - The filename currently being processed

=item C<object> - An object corresponding to either the current explicit or implicit C<File::ByLine> object

=item C<process_number> - Which child process (first process is zero)

=back

This object should not be modified by user code.  In addition, no attributes
of the explict or implicit File::ByLine object passed as part of this hashref
should be modified within user code.

=head3 file

  my $file = $byline->file();
  $byline->file("abc.txt");
  $byline->file( [ "abc.txt", "def.txt" ] );
  $byline->file( "$abc.txt", "def.txt" );

Gets and sets the default filename used by the methods in the object oriented
interface.  The default value is C<undef> which indicates that no default
filename is provided.

Instead of a single filename, a list or arrayref can be passed in, in which
case the files are read in turn as if they are all one file. Note that if the
file doesn't end in a newline, a newline is inserted before processing the next
file.

=head3 header_all_files

  my $all_files = $byline->header_all_files();
  $byline->header_all_files(1);

Gets and sets whether the object oriented methods will call C<header_handler>
for every file if multiple files are passed into the C<file> attribute.

The anticipated usage of this would be with C<extended_info> set to true, with
the C<header_handler> function examining the C<filename> attribute of the
extended info hashref.  Note that all headers may be read before any line in
any file is read, to better accommodate parallel code execution.  I.E. the
headers of all files may be read at once before any data line is read.

=head3 header_handler

  my $handler = $byline->header_handler();
  $byline->header_handler( sub { ... } );

Specifies code that should be executed on the header row of the input file.
This defaults to C<undef>, which indicates no header handler is specified.
When a header handler is specified, the first row of the file is sent to this
handler, and is not sent to the code provided to the various do/grep/map/lines
methods in the object oriented interface.

The code is called with one or two parameters, the header line, and, if the
C<extended_info> attribute is set, the extended information hashref.  The
header line is also stored in C<$_>.

When set, this is always executed in the parent process, not in the child
processes that are spawned (in the case of C<processes> being greater than
one).

You cannot set this to true while a C<header_skip> value is set.

=head3 processes

  my $procs = $byline->processes();
  $byline->processes(10);

This gets and sets the degree of parallelism most methods will use.  The
default degree is C<1>, which indicates all tasks should only use a single
process.  Specifying C<2> or greater will use multiple processes to operate
on the file (see documentation for the parallel_* functions described above
for more details).

=head3 skip_unreadable

  my $unreadable = $byline->skip_unreadable();
  $byline->skip_unreadable(10);

This was added in version 1.181980.

If this attribute is true, unreadable files are treated as empty files during
processing.  The default is false, in which case an exception is thrown when
an access attempt is made to an unreadable file.

=head3 Short Name Aliases for Attributes

  $byline->f();     # Alias for file
  $byline->ei();    # Alias for extended_info
  $byline->haf();   # Alias for header_all_files
  $byline->hh();    # Alias for header_handler
  $byline->hs();    # Alias for header_skip
  $byline->p();     # Alias for processes
  $byline->su();    # Alias for skip_unreadable

Short name aliases were added in version 1.181980.

Each attribute listed above has a corresponding short name.  This short name
can also be used as a constructor argument.

=head2 METHODS

=head3 do

  $byline->do( sub { ... }, "file.txt" );

This performs the C<dolines> functionality, calling the code provided.  If
the filename is not provided, the C<file> attribute is used for this.  See the
C<dolines> and C<parallel_dolines> functions for more information on how this
functions.

Each line (without newline) is passed to the coderef as the first parameter to
the coderef.  It is also placed into C<$_>.  If the C<extended_info> attribute
is true, the extended information hashref will be passed as the second
parameter.

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

=head3 grep

  my (@output) = $byline->grep( sub { ... }, "file.txt" );

This performs the C<greplines> functionality, calling the code provided.  If
the filename is not provided, the C<file> attribute is used for this.  See the
C<greplines> and C<parallel_greplines> functions for more information on how
this functions.

Each line (without newline) is passed to the coderef as the first parameter to
the coderef.  It is also placed into C<$_>.  If the C<extended_info> attribute
is true, the extended information hashref will be passed as the second
parameter.

The output is a list of all input lines where the code reference produces a
true result.

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

=head3 map

  my (@output) = $byline->map( sub { ... }, "file.txt" );

This performs the C<maplines> functionality, calling the code provided.  If
the filename is not provided, the C<file> attribute is used for this.  See the
C<maplines> and C<parallel_maplines> functions for more information on how
this functions.

Each line (without newline) is passed to the coderef as the first parameter to
the coderef.  It is also placed into C<$_>.  If the C<extended_info> attribute
is true, the extended information hashref will be passed as the second
parameter.

The output is the list produced by calling the passed-in code repeatively
for each line of input.

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

=head3 lines

  my (@output) = $byline->lines( "file.txt" );

This performs the C<readlines> functionality.  If the filename is not provided,
the C<file> attribute is used for this.  See the C<readlines> function for more
information on how this functions.

The output is a list of all input lines.

Note that this function is unaffected by the value of the C<processes>
attribute - it always executes in the parent process.

Instead of a single filename, an arrayref can be passed in, in which case the
files are read in turn as if they are all one file. Note that if the file
doesn't end in a newline, a newline is inserted before processing the next
file.

=head1 SUGGESTED DEPENDENCY

The L<Parallel::WorkUnit> module is a recommended dependency.  It is required
to use the C<parallel_*> functions - all other functionality works fine without
it.

Some CPAN clients will automatically try to install recommended dependency, but
others won't (L<cpan> often, but not always, will; L<cpanm> will not by
default).  In the cases where it is not automatically installed, you need to
install L<Parallel::WorkUnit> to get this functionality.

=head1 EXPRESSING APPRECIATION

If this module makes your life easier, or helps make you (or your workplace)
a ton of money, I always enjoy hearing about it!  My response when I hear that
someone uses my module is to go back to that module and spend a little time on
it if I think there's something to improve - it's motivating when you hear
someone appreciates your work!

I don't seek any money for this - I do this work because I enjoy it.  That
said, should you want to show appreciation financially, few things would make
me smile more than knowing that you sent a donation to the Gender Identity
Center of Colorado (See L<http://giccolorado.org/> and donation page
at L<https://tinyurl.com/giccodonation>).  This organization understands
TIMTOWTDI in life and, in line with that understanding, provides life-saving
support to the transgender community.

=cut

1;

