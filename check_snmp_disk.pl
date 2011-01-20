#!/usr/bin/perl -w

use strict;
use lib   qw( /usr/local/nagios/libexec );
use utils qw( %ERRORS $TIMEOUT &print_revision &support &usage );
use Net::SNMP;
use Getopt::Long;
use Data::Dumper;

# globals
use vars qw(
  $PROGNAME $VERSION %disks $snmp $errstr @built_in_excludes
  $dskTable $dskIndex $dskPath $dskDevice $dskMinimum $dskMinPercent
  $dskTotal $dskAvail $dskUsed $dskPercent $dskPercentNode
  $exit @criticals @warnings @oks
  $opt_version $opt_help $opt_timeout $opt_verbose $opt_host $opt_community
  $opt_snmpver $opt_warn $opt_crit @opt_include @opt_exclude $opt_mountpoint
);

# config
$PROGNAME       = 'check_snmp_disk.pl';
$VERSION        = '0.1';
$dskTable       = '.1.3.6.1.4.1.2021.9';
$dskIndex       = '.1.3.6.1.4.1.2021.9.1.1';
$dskPath        = '.1.3.6.1.4.1.2021.9.1.2';
$dskDevice      = '.1.3.6.1.4.1.2021.9.1.3';
$dskMinimum     = '.1.3.6.1.4.1.2021.9.1.4';
$dskMinPercent  = '.1.3.6.1.4.1.2021.9.1.5';
$dskTotal       = '.1.3.6.1.4.1.2021.9.1.6';
$dskAvail       = '.1.3.6.1.4.1.2021.9.1.7';
$dskUsed        = '.1.3.6.1.4.1.2021.9.1.8';
$dskPercent     = '.1.3.6.1.4.1.2021.9.1.9';
$dskPercentNode = '.1.3.6.1.4.1.2021.9.1.10';
@built_in_excludes = qw(usbfs usbdevfs sysfs /proc /dev/pts);

# initialize
%disks  = ();
$snmp   = undef;
$errstr = undef;

# init options
$opt_version    = undef;
$opt_help       = undef;
$opt_timeout    = $TIMEOUT;
$opt_verbose    = undef;
$opt_host       = undef;
$opt_community  = 'public';
$opt_snmpver    = 1;
$opt_warn       = undef;
$opt_crit       = undef;
@opt_include    = ();
@opt_exclude    = ();
$opt_mountpoint = undef;

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
  'i|include=s'       => \@opt_include,
  'x|exclude=s'       => \@opt_exclude,
  'm|mountpoint'      => \$opt_mountpoint,
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

if(!$opt_warn) {
  print "No warning level given\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

if(!$opt_crit) {
  print "No critical level given\n";
  print_usage();
  exit($ERRORS{'UNKNOWN'});
}

push(@opt_exclude, @built_in_excludes);

# set alarm in case we hang
$SIG{ALRM} = sub {
  print "DISK CRITICAL - Timeout after $opt_timeout seconds\n";
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

# grab the table
my $result = $snmp->get_table(-baseoid => $dskTable);

# parse into the disks hash
foreach my $key (keys(%$result)) {
  my($base, $index) = ($key =~ /($dskTable\.1\.\d+)\.(\d+)/);
  #print "base: [$base] index: [$index]\n";

  if($base eq $dskPath)     { $disks{$index}{path}    = $result->{$key}; }
  if($base eq $dskDevice)   { $disks{$index}{device}  = $result->{$key}; }
  if($base eq $dskTotal)    { $disks{$index}{total}   = $result->{$key}; }
  if($base eq $dskAvail)    { $disks{$index}{avail}   = $result->{$key}; }
  if($base eq $dskUsed)     { $disks{$index}{used}    = $result->{$key}; }
  if($base eq $dskPercent)  { $disks{$index}{percent} = $result->{$key}; }
}

# modify the disks hash to only include those devices/paths to check
# based on the include and exlude options
foreach my $key (keys(%disks)) {
  my($path, $device) = ($disks{$key}{path}, $disks{$key}{device});
  if(@opt_include) {
    my $is_included = 0;
    foreach my $include (@opt_include) {
      if($include eq $path || $include eq $device) {
        #print "including $key [$path] [$device]: in includes ($include)\n";
        $is_included = 1;
        last;
      }
    }

    if(!$is_included) {
      #print "excluding $key [$path] [$device]: not in includes\n";
      delete($disks{$key});
    }
  }

  if(@opt_exclude) {
    foreach my $exclude (@opt_exclude) {
      if($exclude eq $path || $exclude eq $device) {
        #print "excluding $key [$path] [$device]: in excludes ($exclude)\n";
        delete($disks{$key});
      }
    }
  }
}

# Check the devices if their type is in the %types hash
@criticals = ();
@warnings  = ();
@oks       = ();

foreach my $key (keys(%disks)) {
  my($path, $device, $percent, $avail)
    = ( $disks{$key}{path},  $disks{$key}{device},
        $disks{$key}{percent}, $disks{$key}{avail} );

  my $pcntavail = 100 - $percent;

  #print "path [$path] device [$device] percent [$percent] avail [$avail] pcntavail: [$pcntavail]\n";

  my $output = "$avail kB ($pcntavail%) free on "
             . ($opt_mountpoint ? $path : $device);

  if(!check_disk($opt_crit, $pcntavail, $avail)) {
    push(@criticals, $output);
  } elsif(!check_disk($opt_warn, $pcntavail, $avail)) {
    push(@warnings, $output);
  } else {
    push(@oks, $output);
  }
}

if(!keys(%disks)) {
  push(@criticals, "No disks found!");
}

if(@criticals) {
  print "DISK CRITICAL - " . join(', ', @criticals) . "\n";
  exit($ERRORS{'CRITICAL'});
} elsif(@warnings) {
  print "DISK WARNING - " . join(', ', @warnings) . "\n";
  exit($ERRORS{'WARNING'});
} elsif(@oks) {
  print "DISK OK - " . join(', ', @oks) . "\n";
  exit($ERRORS{'OK'});
}

sub check_disk {
  my($limit, $pcntavail, $avail) = @_;

  #print "check_disk($limit, $pcntavail, $avail)\n";

  if($limit =~ /^(\d+)%$/) {
    $limit = $1;
    if($pcntavail <= 0) {
      return(0);
    } elsif($pcntavail <= $limit) {
      return(0);
    } else {
      return(1);
    }
  } elsif($limit =~ /^\d+$/) {
    if($avail <= $limit) {
      return(0);
    } else {
      return(1);
    }
  } else {
    die("Invalid limit: $limit\n");
  }
}

sub print_usage {
  my $tab = ' ' x length($PROGNAME);
  print <<EOB
Usage:
 $PROGNAME -H host -w limit -c limit [-i include] [-x exclude] [-m]
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

Check disk space on the remote machine through SNMP.  You must configure the
SNMP daemon on the target machine to check the disks, with either the option
"includeAllDisks 5%" or "disk / 5%".  The percentages you set there are 
required for the SNMP daemon to work, but this plugin completely ignores them.

EOB

  print_usage();
  print <<EOB;

Required Arguments:
 -H, --host=HOST
    The name or address of the host running SNMP.
 -w, --warning=INTEGER
    Exit with WARNING status if less than INTEGER kilobytes of disk are free
 -w, --warning=PERCENT%
    Exit with WARNING status if less than PERCENT of disk space is free
 -c, --critical=INTEGER
    Exit with CRITICAL status if less than INTEGER kilobytes of disk are free
 -c, --critical=PERCENT%
    Exit with CRITICAL status if less than PERCENT of disk space is free
 -i, --include=PATH or DEVICE
    Check only the included paths or devices.
 -e, --exclude=PATH or DEVICE
    Do not check the given paths or devices.
 -m, --mountpoint
    Display the mountpoint (path) instead of device name.


Optional Arguments:
 -C, --community=STRING
    The community string of the SNMP agent. Default: public
 -S, --snmpver=STRING
    The version of snmp to use.  1 and 2 are supported. Default: 1
 -t, --timeout=INTEGER
    Number of seconds to wait for a response.

EOB
}

