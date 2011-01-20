#!/usr/bin/perl

# Disable use of embedded perl in Nagios for this script
# nagios: -epn

# check_snmp_uptime.pl
#
# Nagios script for monitoring system uptime
# and optionally triggering an alert when
# a monitored server had been restarted
# (i.e. its uptime is lower then it was on
# previous reading).
#
# Michal Ludvig <michal@logix.cz> (c) 2009
# http://www.logix.cz/michal/devel/nagios
#
# NOTE 1: net-snmp provides the snmpd daemon's uptime in
#         DISMAN-EVENT-MIB::sysUpTimeInstance (.1.3.6.1.2.1.1.3.0)
#         The real system uptime is available as
#         HOST-RESOURCES-MIB::hrSystemUptime.0 (.1.3.6.1.2.1.25.1.1.0)
#         Many other devices like switches provide
#         only the former OID.
#
#         This script can read either of them.
#         Use --sysUpTime or --hrSystemUptime to select
#         the appropriate OID for each device.
#
# NOTE 2: If --dbfile is not used the script will only
#         check and report the uptime and return OK.
#         No alerts will be generated at all.
#

use strict;

use Net::SNMP qw(ticks_to_time);
use DB_File;
use Getopt::Long;

my $host = 'localhost';
my $community = 'public';
my $port = 161;
my $dbfile;
my $rebootretval = 'WARNING';   # {'OK', 'WARNING', 'CRITICAL'}
my $oid = '1.3.6.1.2.1.1.3.0';
my $oid_name = 'sysUpTime';

GetOptions(
	"h|host=s" => \$host,
	"c|community=s" => \$community,
	"p|port=i" => \$port,
	"d|dbfile=s" => \$dbfile,
	"w|warning-on-reboot" => sub { $rebootretval = "WARNING"; },
	"c|critical-on-reboot" => sub { $rebootretval = "CRITICAL"; },
	"sysUpTime" => sub { $oid = '1.3.6.1.2.1.1.3.0'; $oid_name = 'sysUpTime'; },
	"hrSystemUptime" => sub { $oid = '1.3.6.1.2.1.25.1.1.0'; $oid_name = 'hrSystemUptime'; },
);

my %ERRORS=('OK'=>0, 'WARNING'=>1, 'CRITICAL'=>2, 'UNKNOWN'=>3, 'DEPENDENT'=>4);

my $retval = "OK";

my %dbuptime;
if (defined($dbfile)) {
	tie (%dbuptime, 'DB_File', $dbfile)
		or die("Can't open database file: $dbfile: $!\n");
}

my ($session, $error) = Net::SNMP->session(
	-hostname  => $host,
	-community => $community,
	-port      => $port,
	-translate => [
			-timeticks => 0x0   # Turn off so sysUpTime is numeric
		],
);

if (!defined($session)) {
	printf("ERROR: %s.\n", $error);
	exit(1);
}

my $result = $session->get_request(
	-varbindlist => [$oid]
);

if (!defined($result)) {
	printf("ERROR: %s.\n", $session->error);
	$session->close();
	exit(1);
}

my $retval;
my $extra_message = "";
if (not defined($dbuptime{$host}) or ($dbuptime{$host} < $result->{$oid})) {
	$retval = "OK";
} else {
	$retval = $rebootretval;
	$extra_message = " (was: ".ticks_to_time($dbuptime{$host}).")";
}

# Pointless but harmless when %dbuptime is not tie()'d to a db file
$dbuptime{$host} = $result->{$oid};

printf("%s - %s: %s is %s%s\n",
	$retval,
	$session->hostname,
	$oid_name,
	ticks_to_time($result->{$oid}),
	$extra_message,
);

$session->close();

exit $ERRORS{$retval};
