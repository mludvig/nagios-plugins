#!/usr/bin/env perl

use strict;
use Getopt::Long;

my ($file, $run_yum);
my $critical = 0;
my $num_upg = 0;
my $filelist;

GetOptions ('file=s' => \$file,
	'run-yum' => \$run_yum,
	'help' => sub { &usage() } );

if (defined($run_yum)) {
	open STDIN, "yum check-update |" or die "UNKNOWN - yum check-update : $!\n";
} elsif (defined($file)) {
	open STDIN, "< $file" or die "UNKNOWN - $file : $!\n";
}

my $pkglist_switch = 0;
while (<>) {
	if ($pkglist_switch == 0) {
		$pkglist_switch = 1 if (/^\s*$/);
		next;
	}
	if (/^([^\s]+)\s+([^\s]+)\s+([^\s]+)/) {
		my $package = $1;
		my $version = $2;
		my $repository = $3;
		$package =~ s/\.[^\.]+$//;
		$filelist .= $package." ";
		$num_upg ++;
	}
}

my $ret;
if ($num_upg == 0 and $pkglist_switch == 1) {
	print ("UNKNOWN - could not parse \"yum check-update\" output\n");
	$ret = 3;
} elsif ($critical > 0) {
	## Unused - don't know how to decide if there are security updates or not
	print ("CRITICAL - $critical security updates available: $filelist\n");
	$ret = 2;
} elsif ($num_upg > 0) {
	print ("WARNING - $num_upg updates available: $filelist\n");
	$ret = 1;
} else {
	print ("OK - system is up to date\n");
	$ret = 0;
}
exit $ret;

# ===========

sub usage() {
	printf("
Nagios SNMP check for Debian / Ubuntu package updates

Author: Michal Ludvig <michal\@logix.cz> (c) 2007
        http://www.logix.cz/michal/devel/nagios

Usage: check-yum-update.pl [options]

  --help          Guess what's it for ;-)

  --file=<file>   File with output of \"yum check-update\"
  --run-yum       Run \"yum check-update\" directly. 

Option --run-yum has precedence over --file, i.e. no file is
read if yum is run internally. If none of these options 
is given use standard input by default (e.g. to read from
external command through a pipe).

Return value (according to Nagios expectations):
  * If no updates are found, returns OK.
  * If there are only non-security updates, return WARNING.
  * If there are security updates, return CRITICAL.

");
	exit (1);
}
