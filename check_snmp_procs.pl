#!/usr/bin/perl -w

use strict;
use lib   qw( /usr/local/nagios/libexec );
use utils qw( %ERRORS $TIMEOUT &print_revision &support &usage );
use Net::SNMP 4.1.0;
use Getopt::Long;
use Data::Dumper;

# globals
use vars qw(
  $PROGNAME $VERSION %procs $snmp $errstr $hrSWRunName $oid
  $prTable $prIndex $prNames $prCount
  $exit @criticals @warnings @oks
  $opt_version $opt_help $opt_timeout $opt_verbose $opt_host $opt_community
  $opt_snmpver @opt_procs $opt_fullscan
);

# config
$PROGNAME    = 'check_snmp_procs.pl';
$VERSION     = '0.1';
$hrSWRunName = '.1.3.6.1.2.1.25.4.2.1.2';

$prTable     = '.1.3.6.1.4.1.2021.2';
$prIndex     = '.1.3.6.1.4.1.2021.2.1.1';
$prNames     = '.1.3.6.1.4.1.2021.2.1.2';
$prCount     = '.1.3.6.1.4.1.2021.2.1.5';

# initialize
%procs  = ();
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
@opt_procs     = ();
$opt_fullscan  = 0;

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
  'p|process=s'       => \@opt_procs,
  'f|fullscan'        => \$opt_fullscan,
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

if(!@opt_procs) {
  print "No processes given to check\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

foreach my $proc (@opt_procs) {
  my($name, $warn, $crit) = split(/,/, $proc);

  if(!$name) {
    print "Invalid process name given in $proc\n";
    print_usage();
    exit($ERRORS{'UNKNOWN'});
  }

  if(!$warn) { $warn = '1:' };
  if(!$crit) { $crit = '1:' };

  $proc = {
    'name' => $name,
    'warn' => parse_range($warn),
    'crit' => parse_range($crit),
  };
}

# set alarm in case we hang
$SIG{ALRM} = sub {
  print "PROCS CRITICAL - Timeout after $opt_timeout seconds\n";
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

if($opt_fullscan) {
  # traverse the list
  $oid = $hrSWRunName;
  while(my $result = $snmp->get_next_request(-varbindlist => [$oid])) {
    #print "result: [" . Dumper($result) . "]\n";

       $oid = (keys(%$result))[0];
    my $val = $result->{$oid};

    if($oid =~ /^$hrSWRunName/) {
      #print "$oid => $val\n";
      $procs{$val}++;
    } else {
      last;
    }
  }
} else {
  my $result = $snmp->get_entries(-columns => [$prNames, $prCount]);

  if(not defined($result)) {
    print "PROCS CRITICAL - snmp error: " . $snmp->error() . "\n";
    exit($ERRORS{'CRITICAL'});
  }

  #print "result: [" . Dumper($result) . "]\n";
  
  my %tmpprocs = ();
  # parse into the tmpprocs hash
  foreach my $key (keys(%$result)) {
    my($base, $index) = ($key =~ /($prTable\.1\.\d+)\.(\d+)/);
    #print "base: [$base] index: [$index]\n";

    if($base eq $prNames) { $tmpprocs{$index}{name}  = $result->{$key}; }
    if($base eq $prCount) { $tmpprocs{$index}{count} = $result->{$key}; }
  }

  #print "tmpprocs: [" . Dumper(\%tmpprocs) . "]\n";

  # add these results to the procs hash
  foreach my $key (keys(%tmpprocs)) {
    if($tmpprocs{$key}{count}) {
      $procs{$tmpprocs{$key}{name}} += $tmpprocs{$key}{count};
    }
  }

}

#print "procs: [" . Dumper(\%procs) . "]\n";

# do the checking
@criticals = ();
@warnings  = ();
@oks       = ();

foreach my $proc (@opt_procs) {
  my($name, $warn, $crit) = ($proc->{name}, $proc->{warn}, $proc->{crit});
  my @output  = ();
  my $running = 0;
  
  foreach my $key (keys(%procs)) {
    if($key =~ /$name/) {
      push(@output, "$procs{$key} $key");
      $running += $procs{$key};
    }
  }

  if(!$running) {
    push(@output, "$running $name");
  }

  if(!in_range($running, @$crit)) {
    push(@criticals, @output);
  } elsif(!in_range($running, @$warn)) {
    push(@warnings, @output);
  } else {
    push(@oks, @output);
  }
}

if(@criticals) {
  print "PROCS CRITICAL - " . join(', ', @criticals) . " processes running\n";
  exit($ERRORS{'CRITICAL'});
} elsif(@warnings) {
  print "PROCS WARNING - " . join(', ', @warnings) . " processes running\n";
  exit($ERRORS{'WARNING'});
} elsif(@oks) {
  print "PROCS OK - " . join(', ', @oks) . " processes running\n";
  exit($ERRORS{'OK'});
}

sub in_range {
  my($val, $min, $max) = @_;
  #print "in_range($val, $min, $max)\n";

  if(not defined($val)) {
    return(0);
  }
  
  if(defined($min) && $min && $val < $min) {
    #print "in_range: $val < $min\n";
    return(0);
  } elsif(defined($max) && $max && $val > $max) {
    #print "in_range: $val > $max\n";
    return(0);
  } else {
    #print "in_range: true\n";
    return(1);
  }
}

sub parse_range {
  my($range) = @_;
  my($min, $max);

  if($range =~ /:/) {
    ($min, $max) = split(/:/, $range);
    if($min eq '') { $min = undef; }
    if($max eq '') { $max = undef; }
  } else {
    ($min, $max) = ($range, undef);
  }

  return([$min, $max]);
}

sub print_usage {
  my $tab = ' ' x length($PROGNAME);
  print <<EOB
Usage:
 $PROGNAME -H host -p proc_name,[warn_range],[crit_range]
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

Check the number of processes running on the remote host through SNMP. Multiple
processes can be checked by specifying more than one -p option.

EOB

  print_usage();
  print <<EOB;

Required Arguments:
 -H, --host=HOST
    The name or address of the host running SNMP.
 -p, --process=proc_name,[warn_range],[crit_range]
    The process to check.  Multiple -p options can be specified.
    
    proc_name   A string to match against the process names, i.e. 'crond'.
                Regular expression syntax is supported, i.e. 'crond?'.
    warn_range  If the number of processes that match fall outside of this
                RANGE (see below) then a warning is returned.
                Default: 1:
    crit_range  If the number of processes that match fall outside of this
                RANGE (see below) then a critical is returned.
                Default: 1:

Optional Arguments:
 -C, --community=STRING
    The community string of the SNMP agent. Default: public
 -S, --snmpver=STRING
    The version of snmp to use.  1 and 2 are supported. Default: 1
 -t, --timeout=INTEGER
    Number of seconds to wait for a response.

RANGES:
 RANGES are given in the following format: min:[max]
 if max is not given, infinity is assumed.

EOB
}

