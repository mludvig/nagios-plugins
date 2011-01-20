#!/usr/bin/perl

# 
# check-slony-cluster.pl
# 
# Nagios script for checking the replication 
# status of PostgreSQL Slony Cluster. 
# 
# Michal Ludvig <michal@logix.cz> (c) 2009
# http://www.logix.cz/michal/devel/nagios
# 
# Run with --help to get some hints about usage or
# look at subroutine usage() near the end of this file.
# 

# Recommended Nagios configuration snippet:
#
# define command{
#         command_name    check_slony
#         command_line    $USER10$/check-slony-cluster.pl --host $HOSTADDRESS$ --user $ARG1$ --dbname $ARG2$ --cluster $ARG3$ --node $ARG4$
# }
# 
# define service{
#         use                             generic-service
#         host_name                       dbmaster
#         service_description             Slony - node 2 dbslave
#         check_command                   check_slony!nagios!mydb!mydbcluster!2
#         }

use strict;
use DBI;
use Getopt::Long;

my $db_host = "localhost";
my $db_port = "5432";
my $db_user = "";
my $db_pass = "";
my $db_name = "";
my $slony_cluster = "";
my $slony_node = "";
my $lag_warn = 10;
my $lag_err  = 30;

# Nagios codes
my %ERRORS=('OK'=>0, 'WARNING'=>1, 'CRITICAL'=>2, 'UNKNOWN'=>3, 'DEPENDENT'=>4);

GetOptions(
	'host=s' => \$db_host,
	'port=i' => \$db_port,
	'user=s' => \$db_user,
	'password=s' => \$db_pass,
	'db|dbname|database=s' => \$db_name,
	'cluster=s' => \$slony_cluster,
	'node-id=i' => \$slony_node,
	'warn-minutes=i' => \$lag_warn,
	'error-minutes=i' => \$lag_err,
	'help' => sub { &usage(); },
);

&nagios_return("UNKNOWN", "At least --dbname, --cluster and --node must be set!") if (! $db_name || ! $slony_cluster || ! $slony_node);

my $db_conn_string = "DBI:Pg:";
$db_conn_string .= "database=$db_name;";
$db_conn_string .= "host=$db_host;";
$db_conn_string .= "port=$db_port;";

## Connect to the database.
my $dbh = DBI->connect($db_conn_string, $db_user, $db_pass,
                       {'RaiseError' => 0, 'PrintError' => 0});

&nagios_return("CRITICAL", "Connect failed: $DBI::errstr") if (!$dbh);

## Now retrieve data from the table.
my $sth = $dbh->prepare("SELECT st_origin, st_received, DATE_TRUNC('second', st_lag_time) AS lag, st_lag_time>'$lag_warn min' AS warn, st_lag_time>'$lag_err min' AS err FROM _$slony_cluster.sl_status WHERE st_received = '$slony_node'");
&nagios_return("CRITICAL", "[1] $DBI::errstr") if (!$sth);

$sth->execute();

&nagios_return("CRITICAL", "[2] $DBI::errstr") if ($sth->err);
&nagios_return("CRITICAL", "Query returned ".scalar($sth->rows)." rows. Check $db_name._$slony_cluster.sl_status table.") if (scalar($sth->rows) < 1);

## Query should return one row only
my $result = $sth->fetchrow_hashref();

&nagios_return("UNKNOWN", "[3] $DBI::errstr") if (!$result);

## Print all results? No thanks.
#while (my ($key, $val) = each %$result) {
#	print "$key = $val\n";
#}

my $message = "Replication lag: ".$result->{'lag'};

$sth->finish();

# Disconnect from the database.
$dbh->disconnect();

## Check the returned values
&nagios_return("CRITICAL", $message) if ($result->{'err'} != 0);
&nagios_return("WARNING", $message) if ($result->{'warn'} != 0);
&nagios_return("OK", $message);
exit 0;

### 

sub nagios_return($$) {
	my ($ret, $message) = @_;
	my ($retval, $retstr);
	if (defined($ERRORS{$ret})) {
		$retval = $ERRORS{$ret};
		$retstr = $ret;
	} else {
		$retstr = 'UNKNOWN';
		$retval = $ERRORS{$retstr};
		$message = "WTF is return code '$ret'??? ($message)";
	}
	$message = "$retstr - $message\n";
	$! = $retval;
	print $message;
	exit $retval;
}

sub usage() {
	print("
Nagios script for checking the replication status 
of PostgreSQL Slony Cluster.

Michal Ludvig <michal\@logix.cz> (c) 2009
              http://www.logix.cz/michal

  --host=<host>	  Hostname or IP address to connect to.
  --port=<port>   TCP port where the server listens

  --user=<user>
  --password=<password>
                  Username and password of a user with
		  REPLICATION CLIENT privileges. See
		  below for details.

  --dbname=<dbname>
                  Name of the database to open on connect.

  --cluster=<cluster>
                  Name of the Slony Cluster to check.

  --node-id=<node#>
                  ID of replication node to check. Use its
                  number, not the '\@alias'

  --warn-minutes=NN
                  Return WARNING status if replication lag 
                  is more than NN minutes (default: $lag_warn)
		  
  --error-minutes=NN
                  Return ERROR status if replication lag 
                  is more than NN minutes (default: $lag_err)
		  
  --help          Guess what ;-)

To access the script over SNMP put the following line
into your /etc/snmpd.conf:

extend slony-node-2 /path/to/check-slony-cluster.pl \\
         --dbname myappdb --cluster mycluster --node 2

To check retrieve the status over SNMP use check_snmp_extend.sh
from http://www.logix.cz/michal/devel/nagios

Recommended Nagios configuration snippet:

define command{
        command_name    check_slony
        command_line    \$USER10\$/check-slony-cluster.pl --host \$HOSTADDRESS\$ --user \$ARG1\$ --dbname \$ARG2\$ --cluster \$ARG3\$ --node \$ARG4\$
}

define service{
        use                             generic-service
        host_name                       dbmaster
        service_description             Slony - node 2 dbslave
        check_command                   check_slony!nagios!mydb!mydbcluster!2
        }


");
	exit 0;
}
