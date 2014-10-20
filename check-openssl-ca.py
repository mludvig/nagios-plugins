#!/usr/bin/env python26

# Reports expiring/expired certificates from OpenSSL CA index.txt file
# Usage (/etc/snmp/snmpd.conf):
#     extend cert-check /usr/local/bin/checkcert.py /var/lib/YourCA/index.txt

# By Michal Ludvig @ 2014-07-31

import sys
import re
from datetime import datetime

nagios_states = {"OK": 0, "WARNING": 1, "CRITICAL": 2, "UNKNOWN": 3}
warning = ""
critical = ""

if __name__ == "__main__":
    try:
        certfile = open(sys.argv[1], "r")
    except Exception, e:
        if len(sys.argv) > 1:
            sys.stderr.write("%s: %s\n" % (sys.argv[1], e))
        else:
            sys.stderr.write("Usage: %s /path/to/CA/index.txt\n" % (sys.argv[0]))
	sys.exit(nagios_states["UNKNOWN"])

    suspects = {}
    now = datetime.now()
    for line in certfile:
        (status, raw_expire, raw_revoke, raw_serial, unknown, raw_dn) = line.split("\t")
        if status == "R":
            continue
        expire = datetime.strptime(raw_expire, "%y%m%d%H%M%SZ")
        diff = expire - now
        if diff.days < -30:
            ## Ignore too old certs
            continue
        try:
            cn = re.search("/CN=([^/]+)/", raw_dn).group(1)
        except:
            cn = raw_dn.strip()
        suspects[cn] = diff.days

    for cn in suspects:
        days = suspects[cn]
        if days >= 0 and days < 30:
            warning += "(EXPIRES in %d days) %s " % (days, cn)
        elif days < 0 and days > -30:
            critical += "(EXPIRED %d days ago) %s " % (-days, cn)

    if critical:
        print "CRITICAL - " + critical + warning
        sys.exit(nagios_states["CRITICAL"])
    elif warning:
        print "WARNING - " + warning
        sys.exit(nagios_states["WARNING"])
    else:
        print "OK"
        sys.exit(nagios_states["OK"])
