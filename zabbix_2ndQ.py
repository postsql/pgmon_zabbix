#!/usr/bin/python

"""Extracts named data item from /var/log/pgmon_2ndQ/hostname/latest

Usage:
   .py hostname dataitem

"""

import os, sys, time

if len(sys.argv) == 1:
    print -1
    sys.exit()


LOGDIR_BASE = "/var/log/pgmon_2ndQ/"
LOGDIR = os.path.join(LOGDIR_BASE, sys.argv[1])
LOGFILE = os.path.join(LOGDIR, 'latest')

f = open(LOGFILE)

item = sys.argv[2] + ' '
ilen = len(item)

loglines = [line for line in f.readlines() if line.find(item)==0]

value = loglines[0].split(' ',1)[1].strip()

print value or '0'

