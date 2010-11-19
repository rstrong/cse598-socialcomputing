#!/usr/bin/env perl

use strict; use warnings;

use Getopt::Long;
use Data::Dumper;
my (%opt);
GetOptions( \%opt, 'debug', 'map=s', 'file=s'); 

die "Can't read mapping file" unless -r $opt{map};
die "Can't read target file" unless -r $opt{file};

print "Using $opt{file}\n" if $opt{debug};

my $map;
my @s;
# load mapping
open(MAP, "<", $opt{map});
while(<MAP>)
{
	chomp($_);
  @s = split(/,/, $_);
	$map->{$s[1]} = $s[0]; # maps uid to anonymous int
}
close(MAP);

open(FILE, "<", $opt{file});
open(OUT, ">", 'anon.txt');
while(<FILE>)
{
	chomp($_);
	@s = split(/,/, $_);
	foreach my $f (@s)
	{
		if(defined $map->{$f})
		{
			print OUT $map->{$f} . ",";
		}
		else
		{
			print "WHY: $f\n";
		}

	}
	print OUT "\n";
}
close(OUT);
close(FILE);
