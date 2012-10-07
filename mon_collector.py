#!/usr/bin/python

"""Fetches monitoring data from moninfo_2ndq.moninfo_full()

Run from cron once a minute

"""

import os, sys, glob, time

### configuration
LOGDIR_BASE = "/var/log/pgmon_2ndQ/"
### moninfo files will be kept in LOGDIR_BASE/PG_HOST/PG_PORT
### edit the folowing to connect to your database
MONDB = 'zbx_mondb' # recommendation to use dedicated database
PG_HOST = 'localhost' if (len(sys.argv) < 2 or sys.argv[1].startswith('--')) else sys.argv[1]
PG_PORT = '5432' if (len(sys.argv) < 3 or sys.argv[2].startswith('--')) else sys.argv[2]
PG_USER =  'zbx_monuser'
PG_PWD = 'zbx_monpwd'
##print PG_HOST,PG_PORT,PG_USER
### number of latest logs to keep, 0 - no cleanup
CLEANUP_OLD_LOGS = 5
### end of configuration

import psycopg2
import psycopg2.extras

con = psycopg2.connect('dbname=%(MONDB)s host=%(PG_HOST)s port=%(PG_PORT)s user=%(PG_USER)s password=%(PG_PWD)s' % globals())
#cur = con.cursor(cursor_factory=psycopg2.extras.DictCursor)
cur = con.cursor()


before = time.time()

cur.execute('select * from  moninfo_2ndq.moninfo_full() order by 1')

res = cur.fetchall()

after = time.time()

runtime = int((after - before) * 1000) # runtime in milliseconds

res.append(('pg2ndq.mon_collector.runtime',runtime))

LOGDIR = os.path.join(LOGDIR_BASE, PG_HOST, PG_PORT)           

if not os.path.exists(LOGDIR):
    os.makedirs(LOGDIR)

FILENAME = '%04d-%02d-%02dT%02d:%02d' % time.localtime(time.time())[:5]

LOGFILE = os.path.join(LOGDIR, FILENAME)

f = open(LOGFILE, 'w')

for name, value in res:
    f.write('%s %s\n' % (name, value))

f.close()

#os.symlink(LOGFILE, os.path.join(LOGDIR, 'latest'))
os.symlink(LOGFILE, os.path.join(LOGDIR, 'latest.tmp'))
os.rename(os.path.join(LOGDIR, 'latest.tmp'), os.path.join(LOGDIR, 'latest'))


if CLEANUP_OLD_LOGS:
    files = glob.glob(LOGDIR + '/*:*') # get all timestamp-named files
    files.sort()
    files.reverse()
#    print files
    while len(files) > CLEANUP_OLD_LOGS:
        oldest_file = files.pop()
        os.remove(oldest_file)
#        print 'REMOVED', oldest_file

if sys.argv[-1] == '--UserParameter.conf':
    upfmt = "UserParameter=pg2ndq.%(param_name)s,/usr/local/bin/zabbix_2ndQ.py %(PG_HOST)s/%(PG_PORT)s %(param_name)s"
    print '## 2ndQ Zabbix UserParameters START ##'
    for param_name, value in res:
        print upfmt % locals()
    print '## 2ndQ Zabbix UserParameters END ##'

