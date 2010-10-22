#!/usr/bin/perl -w

use strict;
use lib   qw( /usr/local/nagios/libexec );
use utils qw( %ERRORS $TIMEOUT &print_revision &support &usage );
use Net::SNMP;
use Getopt::Long;
use Data::Dumper;

# globals
use vars qw(
  $PROGNAME $VERSION $snmp $errstr $sysName
  $exit @criticals @warnings @oks
  $opt_version $opt_help $opt_timeout $opt_verbose $opt_host $opt_community
  $opt_snmpver $opt_warn $opt_crit @opt_warn @opt_crit $opt_expected $opt_nocheck
);

# config
$PROGNAME = 'check_snmp_hostname.pl';
$VERSION  = '0.1';
$sysName  = '.1.3.6.1.2.1.1.5.0';

# initialize
$snmp   = undef;
$errstr = undef;

# init options
$opt_version	= undef;
$opt_help	= undef;
$opt_timeout	= $TIMEOUT;
$opt_verbose	= undef;
$opt_host	= undef;
$opt_community	= 'public';
$opt_snmpver	= 2;
$opt_warn	= undef;
$opt_crit	= undef;
$opt_nocheck	= undef;
$opt_expected	= undef;

# get options
Getopt::Long::Configure('bundling');
GetOptions(
  'V|version'         => \$opt_version,
  'h|help'            => \$opt_help,
  't|timeout=i'       => \$opt_timeout,
  'v|verbose+'        => \$opt_verbose,
  'H|host=s'          => \$opt_host,
  'C|community=s'     => \$opt_community,
  'S|snmpver=s'       => \$opt_snmpver,
  'n|no-check'        => \$opt_nocheck,
  'e|expected=s'      => \$opt_expected,
) or do {
  print_usage();
  exit($ERRORS{'UNKNOWN'});
};

if($opt_version) {
  print_version();
  exit($ERRORS{'UNKNOWN'});
}

if($opt_help) {
  print_help();
  exit($ERRORS{'UNKNOWN'});
}

if(!$opt_host) {
  print "Host option not given\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

if($opt_expected && $opt_nocheck) {
  print "Both -e and -n given. That doesn't make sense.\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

if(!$opt_expected) {
  $opt_expected = $opt_host;
}

# set alarm in case we hang
$SIG{ALRM} = sub {
  print "LOAD CRITICAL - Timeout after $opt_timeout seconds\n";
  exit($ERRORS{'CRITICAL'});
};
alarm($opt_timeout);

# connect to the snmp server
($snmp, $errstr) = Net::SNMP->session(
  -hostname  => $opt_host,
  -version   => $opt_snmpver,
  -community => $opt_community,
  -timeout   => $opt_timeout,
);
die("Could not create SNMP session: $errstr\n") unless($snmp);

my $result = $snmp->get_request(
  -varbindlist => [
    "$sysName",
  ],
);
if($result) {
  my $r_sysName = $result->{"$sysName"};

  if (not $opt_nocheck and not (($opt_expected eq $r_sysName) or ($opt_expected =~ /^$r_sysName\./) or ($r_sysName =~ /^$opt_expected\./))) {
    print "HOSTNAME CRITICAL - got: $r_sysName, expected: $opt_expected\n";
    exit($ERRORS{'CRITICAL'});
  }
  print "HOSTNAME OK - $r_sysName\n";
  exit($ERRORS{'OK'});
} else {
  print "HOSTNAME CRITICAL - Could not retrieve data from snmp server: " . $snmp->error() . "\n";
  exit($ERRORS{'CRITICAL'});
}

sub print_usage {
  my $tab = ' ' x length($PROGNAME);
  print <<EOB
Usage:
 $PROGNAME -H <host> [ -e expected_hostname ] [-n]
 $tab [-C snmp_community] [-S snmp_version] [-t timeout]
 $PROGNAME --version
 $PROGNAME --help
EOB
}

sub print_version {
  print_revision($PROGNAME, $VERSION);
}

sub print_help {
  print_version();
  print <<EOB;

Check the hostname of a remote machine through SNMP.

EOB

  print_usage();
  print <<EOB;

Required Arguments:
 -H, --host=HOST
    The name or address of the host running SNMP.
 -e, --expected=EXP_HOSTNAME
    Exit with CRITICAL status if retrieved EXP_HOSTNAME 
    doesn't match EXP_HOSTNAME. If not set the hostname 
    given in -H will be used instead.
 -n, --no-check
    Don't check the validity of retrieved HOSTNAME. 
    Will return with OK status and print the retrieved value.

Optional Arguments:
 -C, --community=STRING
    The community string of the SNMP agent.  Default: public
 -S, --snmpver=STRING
    The version of snmp to use.  1 and 2 are supported.  Default: 1
 -t, --timeout=INTEGER
    Number of seconds to wait for a response.

EOB
}

