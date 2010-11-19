#!/usr/bin/env perl

use strict; use warnings;

use CSE598::Project2;


my $queue = ['68627', '234182', '1272'];
my $crawler = CSE598::Project2->new('debug' => 1, procs => 6, queue => $queue);
$crawler->start_crawling();
POE::Kernel->run();
