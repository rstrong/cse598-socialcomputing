#!/usr/bin/env perl

use strict; use warnings;

use Getopt::Long;
my (%opt);
GetOptions( \%opt, 'debug', 'files=s'); 

my @files = split(/,/,$opt{files});
my @t;
my $map;

my $i = 1;
foreach my $file(@files)
{
	print "Now working on $file\n";
	if(-r $file)
	{
		open(NODE, "<", $file);
		open(OUT, ">>", 'mapping.txt');
		while(<NODE>)
		{
			chomp($_);
			@t = split(/,/,$_);			
			foreach my $user (@t)
			{
				if(not defined $map->{$user} && (length($user) > 2))
				{
					$map->{$user} = $i++;
					print OUT "$map->{$user},$user\n";
				}
			}
		}
		close(NODE);
		close(OUT);
	}
}
