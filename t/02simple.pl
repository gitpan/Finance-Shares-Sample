#!/usr/bin/perl
use strict;
use warnings;
use Test;
BEGIN { plan tests => 5 };
use PostScript::File qw(check_file);
use Finance::Shares::MySQL;
use Finance::Shares::Sample;
ok(1);

my $db = new Finance::Shares::MySQL( 
    user => 'tester',
    password => '4tune81',
    database => 'stocks',
);
ok($db);

my $s = new Finance::Shares::Sample(
	source	    => $db,
	epic	    => 'gsk.l',
	start_date  => '2002-08-01',
	end_date    => '2002-08-31',
    );
ok($s);

my $name = "02simple";
$s->output( $name, "test-results" );
ok(1); # survived so far
my $file = check_file( "$name.ps", "test-results" );
ok($file);
