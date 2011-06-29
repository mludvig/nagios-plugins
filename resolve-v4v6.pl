#!/usr/bin/env perl

# NET-SNMP utils are stupid in that they require either IPv4 _OR_ IPv6 address
# and don't just try whatever the hostname resolves to. For instance if
# host.example.com resolves to ::1 and 127.0.0.1 you can't just let "snmpget"
# to decide which one to try but must either specify "udp:host.example.com" or 
# "udp6:host.example.com". And that assumes you _know_ if it's v6 or v4 host.
# This script finds out just that...

# Usage: snmpwalk -v2c -c public $(resolve-v4v6.pl -h $hostname)

# Author: Michal Ludvig <mludvig@logix.net.nz>
#         http://logix.cz/michal/devel/nagios/

use strict;

use Net::SNMP;
use Getopt::Long;

my $opt_host = undef;
my $prefix_v4 = "";
my $prefix_v6 = "udp6:";
my $wrap_v6 = 0;

GetOptions(
	'h|host=s'	=> \$opt_host,
	'prefix-v4=s'	=> \$prefix_v4,
	'prefix-v6=s'	=> \$prefix_v6,
	'wrap-v6'	=> \$wrap_v6,
) or do {
	print STDERR "Usage: $0 -h <hostname> [--prefix-v4 '...'] [--prefix-v6 '...']\n";
	exit(1);
};
my $prefix = $prefix_v4;

my ($snmp, $errstr, $domain);
foreach $domain ("udp4", "udp6") {
	($snmp, $errstr) = Net::SNMP->session(
		-hostname  => $opt_host,
		-community => 'public',
		-domain    => $domain,
		);
	if (defined($snmp)) {
		if ($domain eq "udp6") {
			$prefix = $prefix_v6;
			if ($opt_host =~ /:/ and $wrap_v6) {
				$opt_host = "[$opt_host]";
			}
		}
		last;
	}
}

if (!defined($snmp)) {
	print STDERR "ERROR: $errstr\n";
	exit(1);
}

print "${prefix}${opt_host}\n";
exit(0);
