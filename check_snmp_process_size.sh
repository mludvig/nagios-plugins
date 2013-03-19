#!/bin/sh

# Nagios "check" for finding a size (VSZ) of process
# running on the remote server, all over SNMP.
# 
# Author Michal Ludvig <michal@logix.cz> (c) 2009
#        http://www.logix.cz/michal/devel/nagios
# 

# Example configuration 
# =====================
# 
# Put the following lines into nagios' configuration:
# 
# ---- cut here ----
# $USER10$=/usr/local/nagios/libexec.local
# 
# define command{
# 	command_name	check_snmp_process_size
# 	command_line	$USER10$/check_snmp_process_size.sh $HOSTADDRESS$ $ARG1$ $ARG2$ $ARG3$
# 	}
# 
# define service{
# 	use			generic-service
# 	host_name		server.domain
# 	service_description	mem-leaker process size
# 	check_command		check_snmp_process_size!mem-leaker-size!20000!50000
# }
# ---- cut here ----
# 
# On the host server.domain configure SNMP extension
# with name "mem-leaker-size". 
# Configuration goes to /etc/snmp/snmpd.conf or similar.
# 
# ---- cut here ----
# extend mem-leaker-size /etc/snmp/process-size.sh /usr/bin/mem-leaker
# ---- cut here ----
# 
# That's all. Just note that older versions of 
# Net-SNMP package did not support "extend" keyword.
# 
# This script is based on check_snmp_exec.sh from
#    http://www.logix.cz/michal/devel/nagios
# 
# Enjoy!
# Michal Ludvig

. /usr/lib64/nagios/plugins/utils.sh || exit 3

SNMPGET=$(which snmpget)

test -x ${SNMPGET} || exit $STATE_UNKNOWN

HOST=$1
NAME=$2
WARN_SIZE=$3
CRIT_SIZE=$4

test "${HOST}" -a "${NAME}" -a "${WARN_SIZE}" -a "${CRIT_SIZE}" || exit $STATE_UNKNOWN

SELFDIRNAME=$(dirname $0)
test -n "${SELFDIRNAME}" && SELFDIRNAME="${SELFDIRNAME}/"
HOST_ARG=$(${SELFDIRNAME}resolve-v4v6.pl --host ${HOST} --wrap-v6)

RESULT=$(${SNMPGET} -v2c -c public -OvQ ${HOST_ARG} NET-SNMP-EXTEND-MIB::nsExtendOutputFull.\"${NAME}\" 2>&1)

STATUS="OK"
expr ${RESULT} '>' ${WARN_SIZE} > /dev/null && STATUS="WARNING"
expr ${RESULT} '>' ${CRIT_SIZE} > /dev/null && STATUS="CRITICAL"

case "$STATUS" in
	OK|WARNING|CRITICAL)
		RET=$(eval "echo \$STATE_$STATUS")
		RESULT="${STATUS} - ${NAME} VSZ is ${RESULT} kB"
		;;
	*)
		RET=$STATE_UNKNOWN
		RESULT="UNKNOWN - SNMP returned unparsable status: $RESULT"
		;;
esac

echo $RESULT
exit $RET
