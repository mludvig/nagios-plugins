#!/usr/bin/env perl

use strict;
use Getopt::Long;

my ($file, $run_apt);
my $critical = 0;
my ($filelist, $num_upg, $num_new, $num_del, $num_noupg);

GetOptions ('file=s' => \$file,
	'run-apt' => \$run_apt,
	'help' => sub { &usage() } );

if (defined($run_apt)) {
	open STDIN, "apt-get -q -s upgrade |" or die "UNKNOWN - apt-get upgrade : $!\n";
} elsif (defined($file)) {
	open STDIN, "< $file" or die "UNKNOWN - $file : $!\n";
}

while (<>) {
	if (/The following packages will be upgraded:/) {
		while (<>) {
			last if not /^\s+\w+.*/;
			chop($_);
			$filelist .= $_;
		}
		## Remove extra spaces
		$filelist =~ s/\s+/ /g;
		$filelist .= " ";
	}
	if (/^Inst ([^\s]+).*security.*\)$/) {
		$critical++;
		$filelist =~ s/ ($1) / $1\[S\] /g;
	}
	if (/(\d+) upgraded, (\d+) newly installed, (\d+) to remove and (\d+) not upgraded/) {
		($num_upg, $num_new, $num_del, $num_noupg) = ($1, $2, $3, $4);
	}
}

my $ret;
if (! defined($num_upg)) {
	print ("UNKNOWN - could not parse \"apt-get upgrade\" output\n");
	$ret = 3;
} elsif ($critical > 0) {
	print ("CRITICAL - $critical security updates available:$filelist\n");
	$ret = 2;
} elsif ($num_upg > 0) {
	print ("WARNING - $num_upg updates available:$filelist\n");
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

Author: Michal Ludvig <michal\@logix.cz> (c) 2006
        http://www.logix.cz/michal/devel/nagios

Usage: check-apt-upgrade.pl [options]

  --help          Guess what's it for ;-)

  --file=<file>   File with output of \"apt-get -s upgrade\"
  --run-apt       Run \"apt-get -s upgrade\" directly. 

Option --run-apt has precedence over --file, i.e. no file is
read if apt-get is run internally. If none of these options 
is given use standard input by default (e.g. to read from
external command through a pipe).

Return value (according to Nagios expectations):
  * If no updates are found, returns OK.
  * If there are only non-security updates, return WARNING.
  * If there are security updates, return CRITICAL.

");
	exit (1);
}
