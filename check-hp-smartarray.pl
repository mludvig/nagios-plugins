#!/usr/bin/perl

#
# check-hp-smartarray.pl
#
# Nagios script for checking HP SmartArray status.
# Keywords: HP SmartArray, CCISS, hpacucli, RAID
#
# Michal Ludvig   <michal@logix.cz>    (c)  2013
#              http://www.logix.cz/michal/nagios
# for Enterprise IT -- http://enterpriseit.co.nz
#
# The "hpacucli" package must be installed (free to
# download from HP).
#

use strict;

my %ERRORS=("OK"=>0, "WARNING"=>1, "CRITICAL"=>2, "UNKNOWN"=>3, "DEPENDENT"=>4);

my $debug = 0;
my $displays_cnt = 0;

my $result = "OK";
my @output;
my $slots_cnt = 0;
my $arrays_cnt = 0;
my $lds_cnt = 0;
my $pds_cnt = 0;

sub debug($) {
	my $message = shift;
	if ($debug) {
		print($message . "\n");
	}
}

sub nagios_exit($$) {
	my $result = shift;
	my $message = shift;

	print("$result - $message\n");

	exit($ERRORS{$result});
}

sub hpacucli($) {
	my $command = shift;
	my @lines;
	debug(">> hpacucli $command <<");
	if ($#ARGV > -1) {
		open(HP, $ARGV[0]) or die("${ARGV[0]}: $!");
	} else {
		open(HP, "hpacucli $command |") or nagios_exit("UNKNOWN", "hpacucli: $!");
	}
	while (<HP>) {
		# trim whitespace
		$_ =~ s/^\s*(.*?)\s*$/$1/;
		debug("hpacucli: $_");
		push(@lines, $_);
	}
	return @lines;
}

sub update_result($)
{
	my $new_result = shift;
	if ($ERRORS{$result} < $ERRORS{$new_result}) {
		debug("Updating result $result -> $new_result");
		$result = $new_result;
	}
}

sub check_arrays() {
	my ($slot, $array, $ld, $pd_cnt);
	my $ok = 1;
	my @ld_show = hpacucli("controller all show config");
	foreach (@ld_show) {
		if (/^(.*) in Slot (\d+).*/) {
			$slots_cnt++;
			$slot = "slot=$2";
			debug("$slot ($1)");
			$array = undef;
			$ld = undef;
			next;
		}
		if (/^array ([A-Z]+)/) {
			$arrays_cnt++;
			$array = "array=$1";
			next;
		}
		if (/^unassigned/) {
			$array = "unassigned";
			next;
		}
		if (/^logicaldrive (\d+) \((.+)\)/) {
			$lds_cnt++;
			$ld = $1;
			my $ld_output = "$slot $array $_";
			if ($2 =~ /OK/) {
				debug("OK: $ld_output");
				push(@output, $ld_output) if ($displays_cnt);
			} elsif ($2 =~ /Fail/) {
				push(@output, $ld_output);
				debug("CRITICAL: $ld_output");
				update_result("CRITICAL");
			} else {
				push(@output, $ld_output);
				debug("WARNING: $ld_output");
				update_result("WARNING");
			}
			next;
		}
		if (/^physicaldrive/) {
			$pds_cnt++;
			if (/OK/) {
				debug("OK: $_");
			} elsif (/Fail/) {
				push(@output, $_);
				debug("CRITICAL: $_");
				update_result("CRITICAL");
			} else {
				push(@output, $_);
				debug("WARNING: $_");
				update_result("WARNING");
			}
		}
	}
}

check_arrays();

push(@output, "Checked: $slots_cnt slots, $arrays_cnt arrays, $lds_cnt LDs, $pds_cnt PDs");

nagios_exit($result, join(" / ", @output));
