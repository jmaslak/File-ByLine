#!/usr/bin/perl -T
# Yes, we want to make sure things work in taint mode

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

use strict;
use warnings;
use autodie;

use v5.10;

use Carp;

use Test2::V0;

use File::ByLine;

my (@lines) = ( 'Line 1', 'Line 2', 'Line 3', );
my $lc = 0;
my @flret;

subtest forlines_inline => sub {
    my @result;
    my $lineno = 0;
    my $linecnt = forlines "t/data/3lines.txt", sub {
        $lineno++;
        my $line = shift;

        push @result, $line;

        is( $line, $_, "Line $lineno - Local \$_ and \$_[0] are the same" );
    };

    is( \@result, \@lines,        'Read 3 line file' );
    is( $linecnt, scalar(@lines), 'Return value is proper' );
};

sub flsub {
    $lc++;
    my $line = shift;

    is( $line, $_, "Line $lc - Local \$_ and \$_[0] are the same" );

    push @flret, $line;
    return;
}

subtest parallel_maplines_one_for_one => sub {
    my @result = parallel_maplines {
        my $line = shift;
        return lc($line);
    }
    "t/data/3lines.txt", 1;

    my (@lc) = map { lc } @lines;
    is( \@result, \@lc, 'Read 3 line file, 1 process' );

    @result = parallel_maplines {
        my $line = shift;
        return lc($line);
    }
    "t/data/3lines.txt", 4;

    is( \@result, \@lc, 'Read 3 line file, 4 processes' );
};

subtest parallel_maplines_none_and_two => sub {
    my @result = parallel_maplines {
        my $line = shift;

        if ( $line eq 'Line 1' ) { return; }
        if ( $line eq 'Line 2' ) { return $line, $line; }
        if ( $line eq 'Line 3' ) { return $line; }
    }
    "t/data/3lines.txt", 1;

    my (@expected) = ( $lines[1], $lines[1], $lines[2] );

    is( \@result, \@expected, 'Read 3 line file' );
};

subtest parallel_greplines => sub {
    my @result = parallel_greplines {
        my $line = shift;

        if ( $line eq 'Line 1' ) { return; }
        if ( $line eq 'Line 2' ) { return 1; }
        if ( $line eq 'Line 3' ) { return 1; }
    }
    "t/data/3lines.txt", 1;

    my (@expected) = grep { $_ ne 'Line 1' } @lines;
    is( \@result, \@expected, 'Read 3 line file, 1 process' );

    @result = parallel_greplines {
        my $line = shift;

        if ( $line eq 'Line 1' ) { return; }
        if ( $line eq 'Line 2' ) { return 1; }
        if ( $line eq 'Line 3' ) { return 1; }
    }
    "t/data/3lines.txt", 4;

    is( \@result, \@expected, 'Read 3 line file, 4 processes' );
};

subtest parallel_greplines_large => sub {
    my @result = parallel_greplines { 1; } "t/data/longer-text.txt", 4;
    my @expected = readlines "t/data/longer-text.txt";

    is( \@result, \@expected, "Grep on non-trivial file" );
};

subtest parallel_maplines_large => sub {
    my @result = parallel_maplines { lc($_) } "t/data/longer-text.txt", 4;
    my @expected = map { lc($_) } readlines "t/data/longer-text.txt";

    is( \@result, \@expected, "Map on non-trivial file" );
};

done_testing();

