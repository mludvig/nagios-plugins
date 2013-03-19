#!/usr/bin/perl -w

use strict;
use lib   qw( /usr/local/nagios/libexec );
use utils qw( %ERRORS $TIMEOUT &print_revision &support &usage );
use Net::SNMP;
use Getopt::Long;
use Data::Dumper;

# globals
use vars qw(
  $PROGNAME $VERSION $snmp $errstr $laLoad
  $exit @criticals @warnings @oks
  $opt_version $opt_help $opt_timeout $opt_verbose $opt_host $opt_community
  $opt_snmpver $opt_warn $opt_crit @opt_warn @opt_crit
);

# config
$PROGNAME = 'check_snmp_load.pl';
$VERSION  = '0.1';
$laLoad   = '.1.3.6.1.4.1.2021.10.1.3';

# initialize
$snmp   = undef;
$errstr = undef;

# init options
$opt_version   = undef;
$opt_help      = undef;
$opt_timeout   = $TIMEOUT;
$opt_verbose   = undef;
$opt_host      = undef;
$opt_community = 'public';
$opt_snmpver   = 1;
$opt_warn      = undef;
$opt_crit      = undef;

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
  'w|warning=s'       => \$opt_warn,
  'c|critical=s'      => \$opt_crit,
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

if($opt_warn) {
  @opt_warn = split(/,/, $opt_warn);
} else {
  print "No warning levels given\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

if($opt_crit) {
  @opt_crit = split(/,/, $opt_crit);
} else {
  print "No critical levels given\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

# set alarm in case we hang
$SIG{ALRM} = sub {
  print "LOAD UNKNOWN - Timeout after $opt_timeout seconds\n";
  exit($ERRORS{'UNKNOWN'});
};
alarm($opt_timeout);

# connect to the snmp server
my ($snmp, $errstr);
foreach my $domain ("udp4", "udp6", "tcp4", "tcp6") {
	($snmp, $errstr) = Net::SNMP->session(
		-hostname  => $opt_host,
		-version   => $opt_snmpver,
		-community => $opt_community,
		-timeout   => $opt_timeout,
		-domain    => $domain,
		);
	last if (defined($snmp));
}
unless($snmp) {
	print("LOAD UNKNOWN - Could not create SNMP session: $errstr\n");
	exit($ERRORS{'UNKNOWN'});
}

my $result = $snmp->get_request(
  -varbindlist => [
    "$laLoad.1",
    "$laLoad.2",
    "$laLoad.3",
  ],
);
if($result) {
  my $la1  = $result->{"$laLoad.1"};
  my $la5  = $result->{"$laLoad.2"};
  my $la15 = $result->{"$laLoad.3"};

  if( ($opt_crit[0] && $la1  > $opt_crit[0]) ||
      ($opt_crit[1] && $la5  > $opt_crit[1]) ||
      ($opt_crit[2] && $la15 > $opt_crit[2]) )
  {

    print "LOAD CRITICAL - load average: $la1, $la5, $la15\n";
    exit($ERRORS{'CRITICAL'});

  } elsif( ($opt_warn[0] && $la1  > $opt_warn[0]) ||
           ($opt_warn[1] && $la5  > $opt_warn[1]) ||
           ($opt_warn[2] && $la15 > $opt_warn[2]) )
  {

    print "LOAD WARNING - load average: $la1, $la5, $la15\n";
    exit($ERRORS{'WARNING'});

  } else {

    print "LOAD OK - load average: $la1, $la5, $la15\n";
    exit($ERRORS{'OK'});

  }
} else {
  print "LOAD UNKNOWN - Could not retrieve load data from snmp server: " . $snmp->error() . "\n";
  exit($ERRORS{'UNKNOWN'});
}

sub print_usage {
  my $tab = ' ' x length($PROGNAME);
  print <<EOB
Usage:
 $PROGNAME -H <host> -w WLOAD1,WLOAD5,WLOAD15 -c CLOAD1,CLOAD5,CLOAD15
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

Check the load averages of a remote machine through SNMP.

EOB

  print_usage();
  print <<EOB;

Required Arguments:
 -H, --host=HOST
    The name or address of the host running SNMP.
 -w, --warning=WLOAD1,WLOAD5,WLOAD15
    Exit with WARNING status if load average exceeds WLOADn
 -c, --critical=CLOAD1,CLOAD5,CLOAD15
    Exit with CRITICAL status if load average exceed CLOADn


Optional Arguments:
 -C, --community=STRING
    The community string of the SNMP agent.  Default: public
 -S, --snmpver=STRING
    The version of snmp to use.  1 and 2 are supported.  Default: 1
 -t, --timeout=INTEGER
    Number of seconds to wait for a response.

EOB
}

