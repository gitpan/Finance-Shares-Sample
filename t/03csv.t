#!/usr/bin/perl
use strict;
use warnings;
use Test;
BEGIN { plan tests => 4 };
use PostScript::File qw(check_file);
use Finance::Shares::Sample;
ok(1);

my $s = new Finance::Shares::Sample(
	source	    => 'shell.csv',
	directory   => 't',
	epic	    => 'shel.l',
    );
ok($s);

my $name = "02simple";
$s->output( $name, "test-results" );
ok(1); # survived so far
my $file = check_file( "$name.ps", "test-results" );
ok($file);
