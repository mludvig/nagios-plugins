#!/usr/bin/perl

# check-timestamp.pl - Nagios file timestamp checker
#
# The script reports warning or critical when a
# monitored file is older (or newer) then the specified
# treshold.
#
# Written by Michal Ludvig - http://logix.cz/michal/devel/nagios/
#    for Enterprise IT Ltd - http://enterpriseit.co.nz

use strict;
use Getopt::Long;
use File::stat;

my %ERRORS=("OK"=>0, "WARNING"=>1, "CRITICAL"=>2, "UNKNOWN"=>3, "DEPENDENT"=>4);
my $result = "OK";
my @output;

my $file;
my $warn_age = 25 * 3600; # 25 hours
my $crit_age = 50 * 3600; # 50 hours
my $mtime = 0;
my $ctime = 0;

sub nagios_exit($$) {
	my $result = shift;
	my $message = shift;

	print("$result - $message\n");

	exit($ERRORS{$result});
}

sub update_result($)
{
	my $new_result = shift;
	if ($ERRORS{$result} < $ERRORS{$new_result}) {
		$result = $new_result;
	}
}

sub check_timestamp($$$)
{
	my $timestamp = shift;
	my $warn_age = shift;
	my $crit_age = shift;
	my $now = time();

	if ($crit_age > 0) {
		return ("CRITICAL", $now - $timestamp, $crit_age) if ($now - $timestamp > $crit_age);
	} elsif ($crit_age < 0) {
		return ("CRITICAL", $now - $timestamp, -$crit_age) if ($now - $timestamp < -$crit_age);
	} # if ($crit_age == 0) do nothing

	if ($warn_age > 0) {
		return ("WARNING", $now - $timestamp, $warn_age) if ($now - $timestamp > $warn_age);
	} elsif ($warn_age < 0) {
		return ("WARNING", $now - $timestamp, -$warn_age) if ($now - $timestamp < -$warn_age);
	} # if ($warn_age == 0) do nothing
	
	return ("OK", $now - $timestamp, abs($warn_age));
}

sub usage() {
	print ("
check-timestamp.pl - Nagios file timestamp checker

The script reports warning or critical when a
monitored file is older (or newer) then the specified
treshold.

  --file=FILE     File to check

  --warn-age=SEC  Warning if FILE is older than SEC.
                  If SEC is negative alert if FILE
                  is newer then -SEC. Default: $warn_age

  --crit-age=SEC  Critical if FILE is older than SEC.
                  If SEC is negative alert if FILE
                  is newer then -SEC. Default: $crit_age

  --mtime         Check FILE's \"mtime\" timestamp.
                  That's when the file's content was
                  last modified. This is the default.

  --ctime         Check FILE's \"ctime\" timestamp.
                  That's when the file's metadata were
                  last modified.

  --help          Guess what.

Written by Michal Ludvig (http://logix.cz/michal/devel/)
");
	exit(1);
}

GetOptions(
	"file=s" => \$file,
	"warn-age=i" => \$warn_age,
	"crit-age=i" => \$crit_age,
	"mtime" => sub{ $mtime = 1; },
	"ctime" => sub{ $ctime = 1; },
	"help" => sub{ &usage(); },
);

if (not defined($file)) {
	nagios_exit("UNKNOWN", "No file specified, use --file=FILE");
}

if ($mtime + $ctime == 0) {
	$mtime = 1;
}

my $st = stat($file) or nagios_exit("UNKNOWN", "$file: $!");

if ($mtime) {
	my ($res, $ts_diff, $ts_exp) = check_timestamp($st->mtime, $warn_age, $crit_age) if $mtime;
	if ($res ne "OK") {
		update_result($res);
		push(@output, "$file: mtime is too ".($ts_diff > $ts_exp ? "old" : "new").": $ts_diff (treshold: $ts_exp)");
	} else {
		push(@output, "$file: mtime is OK: $ts_diff (treshold $ts_exp)");
	}
}

if ($ctime) {
	my ($res, $ts_diff, $ts_exp) = check_timestamp($st->ctime, $warn_age, $crit_age) if $ctime;
	if ($res ne "OK") {
		update_result($res);
		push(@output, "$file: ctime is too ".($ts_diff > $ts_exp ? "old" : "new").": $ts_diff (treshold: $ts_exp)");
	} else {
		push(@output, "$file: ctime is OK: $ts_diff (treshold $ts_exp)");
	}
}

nagios_exit($result, join(" / ", @output));
