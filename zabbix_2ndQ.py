#!/usr/bin/python

"""Extracts named data item from /var/log/pgmon_2ndQ/hostname/latest

Usage:
   .py host/port dataitem

"""

import os, sys, time

if len(sys.argv) == 1:
    print -1
    sys.exit()


LOGDIR_BASE = "/var/log/pgmon_2ndQ/"
LOGDIR = os.path.join(LOGDIR_BASE, sys.argv[1])
LOGFILE = os.path.join(LOGDIR, 'latest')

open(os.path.join(LOGDIR_BASE,'call.log'),'a').write('%s %s\n' % (time.time(), sys.argv))


f = open(LOGFILE)

args = sys.argv[2:]

if len(args) == 3:
    item = '%s[%s,%s]' % tuple(args)
else:
    item = sys.argv[2] + ' '
    ilen = len(item)

loglines = [line for line in f.readlines() if line.find(item)==0]

try:
    value = loglines[0].split(' ',1)[1].strip()
except:
    value = sys.argv[1:]

print value or '0'

