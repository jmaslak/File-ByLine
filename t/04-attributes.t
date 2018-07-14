#!/usr/bin/perl -T
# Yes, we want to make sure things work in taint mode

#
# Copyright (C) 2018 Joelle Maslak
# All Rights Reserved - See License
#

#
# Object Attribute Tests (this is a work in progress of seperating these
# out from 01-Basic.t)
#

use strict;
use warnings;
use autodie;

use v5.10;

use Carp;

use Test2::V0;

use File::ByLine;

subtest file_attribute => sub {
    my $byline = File::ByLine->new();
    ok( defined($byline), "Object created" );

    is( $byline->file(), undef, "File defaults to empty" );

    my @tests = (
        {
            test => 'Single file',
            list => ['file.txt'],
        },
        {
            test => 'Two files',
            list => [ 'file.txt', 'file2.txt' ],
        },
    );

    foreach my $test (@tests) {
        my $desc = $test->{test};
        my $list = $test->{list};

        if ( scalar(@$list) == 1 ) {
            is( $byline->file( $list->[0] ), $list->[0], "$desc - No List" );
            is( $byline->file($list),        $list,      "$desc - In List" );
        } else {
            is( $byline->file(@$list), $list, "$desc - List of Elements" );
            is( $byline->file($list),  $list, "$desc - Arrayref of Elements" );
        }
    }

    ok( dies { $byline->file(undef) }, "file() does not accept undef" );
};

subtest processes_attribute => sub {
    my $byline = File::ByLine->new();
    ok( defined($byline), "Object created" );

    is( $byline->processes(), 1, "processes defaults to 1" );

    ok( dies { $byline->processes(undef) }, "processes() does not accept undef" );
    ok( dies { $byline->processes(0) },     "processes() does not accept 0" );
    ok( dies { $byline->processes( 1, 2 ) }, "processes() does not accept list" );
    ok( dies { $byline->processes( [1] ) }, "processes() does not accept arrayref" );
};

subtest extended_info => sub {
    my $byline = File::ByLine->new();
    ok( defined($byline), "Object created" );

    ok( !$byline->extended_info(), "extended_info defaults to false" );

    ok( $byline->extended_info(1),      "extended_info set to true" );
    ok( $byline->extended_info(),       "extended_info contains true" );
    ok( !$byline->extended_info(undef), "extended_info set to false" );
    ok( !$byline->extended_info(),      "extended_info contains false" );
};

done_testing();

