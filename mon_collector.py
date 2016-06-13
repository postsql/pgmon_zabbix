#!/usr/bin/python

"""Fetches monitoring data from moninfo_2ndq.moninfo_full()

Run from cron once a minute

"""

import os, sys, glob, time, re, json

### configuration
LOGDIR_BASE = "/var/log/pgmon_2ndQ/"
### moninfo files will be kept in LOGDIR_BASE/PG_HOST/PG_PORT
### edit the folowing to connect to your database
MONDB = 'zbx_mondb' # recommendation to use dedicated database
PG_HOST = 'localhost' if (len(sys.argv) < 2 or sys.argv[1].startswith('--')) else sys.argv[1] # leave empty for peer connection
PG_PORT = '5432' if (len(sys.argv) < 3 or sys.argv[2].startswith('--')) else sys.argv[2]
PG_USER =  'zbx_monuser'
PG_PWD = 'zbx_monpwd'
##print PG_HOST,PG_PORT,PG_USER
### number of latest logs to keep, 0 - no cleanup
CLEANUP_OLD_LOGS = 5
### end of configuration

import psycopg2
import psycopg2.extras

if PG_HOST:
  con = psycopg2.connect('dbname=%(MONDB)s host=%(PG_HOST)s port=%(PG_PORT)s user=%(PG_USER)s password=%(PG_PWD)s' % globals())
else
  con = psycopg2.connect('port=%(PG_PORT)s' % globals())
#cur = con.cursor(cursor_factory=psycopg2.extras.DictCursor)
cur = con.cursor()

#open(os.path.join('LOGDIR_BASE','call.log'),'a').write('%t %s\n' % (time.time(), sys.argv))

before = time.time()

cur.execute('select * from  moninfo_2ndq.moninfo_full() order by 1')

res = cur.fetchall()

after = time.time()

runtime = int((after - before) * 1000) # runtime in milliseconds

res.append(('mon_collector.runtime',runtime))

LOGDIR = os.path.join(LOGDIR_BASE, PG_HOST, PG_PORT)           

if not os.path.exists(LOGDIR):
    os.makedirs(LOGDIR)

FILENAME = '%04d-%02d-%02dT%02d:%02d' % time.localtime(time.time())[:5]

LOGFILE = os.path.join(LOGDIR, FILENAME)

def get_discovery(res, what):
    discfmt = "UserParameter=pg2ndq.%%(param_name)s.discovery,/usr/local/bin/zabbix_2ndQ.py %(PG_HOST)s/%(PG_PORT)s %%(param_name)s.discovery" % globals()
    flexfmt = "UserParameter=pg2ndq.%%(param_name)s[*],/usr/local/bin/zabbix_2ndQ.py %(PG_HOST)s/%(PG_PORT)s %%(param_name)s %%(dollars)s" % globals()
    flexible_param_rx = re.compile(r'^([A-Za-z][A-Za-z0-9_.]+)\[(.+)\]$')
    flexy_max_argc_dict = {}
    flexy_item_dict = {}
    for param_name, value in res:
        if flexible_param_rx.match(param_name):
	    param, args = flexible_param_rx.match(param_name).groups()
	    args_list = args.split(',')
	    flexy_max_argc_dict[param] = max(flexy_max_argc_dict.get(param_name,0), len(args_list))
	    # create subtict for 'param'
	    flexy_item_dict[param] = flexy_item_dict.get(param,{})
	    # store item name
	    flexy_item_dict[param][args_list[0]] = True
    if what == 'discovery':
        for item in flexy_item_dict.keys():
	    a = '%s.discovery' % item
	    b = json.dumps({"data":[{('{#%s}' % item): name} for name in flexy_item_dict[item].keys()]})
	    yield '%s %s' % (a, b)
	return
    elif what == 'param_conf':
        for param_name, argc in flexy_max_argc_dict.items():
	    dollars = ' '.join(['$%d' % (i+1) for i in range(argc)])
            yield discfmt % locals()
	    yield flexfmt % locals()
    

f = open(LOGFILE, 'w')

for name, value in res:
    if value == None:
        value = ''
    f.write('%s %s\n' % (name, value))

for line in get_discovery(res, what='discovery'):
    f.write('%s\n' %  line)

f.close()

#os.symlink(LOGFILE, os.path.join(LOGDIR, 'latest'))
os.symlink(LOGFILE, os.path.join(LOGDIR, 'latest.tmp'))
os.rename(os.path.join(LOGDIR, 'latest.tmp'), os.path.join(LOGDIR, 'latest'))


simple_param_rx = re.compile('^[A-Za-z][A-Za-z0-9_.]+$')

flexible_param_rx = re.compile(r'^([A-Za-z][A-Za-z0-9_.]+)\[(.+)\]$')

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
    flexfmt = "UserParameter=pg2ndq.%(param_name)s[*],/usr/local/bin/zabbix_2ndQ.py %(PG_HOST)s/%(PG_PORT)s %(dollars)s"
    print '## 2ndQ Zabbix UserParameters START ##'
    flexy_dict = {}
    item_dict = {'DB': {}, 'TABLESPACE': {} }
    for param_name, value in res:
#        print (param_name, value)
        if simple_param_rx.match(param_name):
            print upfmt % locals()
#        elif flexible_param_rx.match(param_name):
#            param, args = flexible_param_rx.match(param_name).groups()
#            print '##', param,'[*]', args
#            args_list = args.split(',')
#            flexy_dict[param] = max(flexy_dict.get(param_name,0), len(args_list))
#            item_dict[param][args_list[0]] = True
        else:
            pass
#            print '##', param_name, value
    for line in get_discovery(res, what='param_conf'):
        print line
    print '## 2ndQ Zabbix UserParameters END ##'




