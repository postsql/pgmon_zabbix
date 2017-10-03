==========================
pgmon_2ndQ
==========================


.. contents::


Overview
========

`pgmon_2ndq` is a set of postgresql monitoring functions implemented in the server.

The functions are installed in their own database and connect back to all databases in the
server to get database specific info

A cronjob gets the monitoring info from these functions in a single database call
and saves it to a file

Then zabbix user parameters are used to get the data from this file.

This architecture was chosen to make it easy to control number of connections to database

Setting up the monitoring database and and user
===============================================

create monitoring database and user :: 

    CREATE USER zbx_monuser
      WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB
      PASSWORD 'zbx_monpwd';

    CREATE DATABASE zbx_mondb WITH OWNER 'zbx_monuser';
    
    CREATE SCHEMA IF NOT EXISTS moninfo_2ndq;
    -- needed if zbx_monuser is not superuser
    GRANT USAGE ON SCHEMA moninfo_2ndq TO zbx_monuser;

connect to monitoring database ::

    \c zbx_mondb

    CREATE EXTENSION plpythonu;

and load the function definitions::

    \i mondb_functions.sql

your database host must have `pl/python` language installed.
It is usually either in its own package called something like
`postgresql-python` or `postgresql-plpython`.

`pl/python` makes use of pythons postgresql module `psycopg2`
to connect to all monitored databases in this server, so
the following needs to succeed when run on the database server::

    user@host:~/pgmon_zabbix$ python
    Python 2.7.3 (default, Aug  1 2012, 05:14:39) 
    [GCC 4.6.3] on linux2
    Type "help", "copyright", "credits" or "license" for more information.
    >>> import psycopg2
    >>> 

If it does not work, you need to install `psycopg2`.
Usually it is in a package `python-psycopg2` or similar.

Next, check `pg_hba.conf` to make sure that the monitoring
user can connect to the monitoring database. ( It may be a good idea
to let it connect to _only_ the monitoring database ).


Test it from the host you are going to run the zabbix
monitoring info collector from ::

    psql -h <database host> zbx_mondb zbx_monuser

if connecting succeeds, run::

    select * from moninfo_2ndq.moninfo_full();
    
if this also succeeds, you have successfully configured the
database side of zabbix monitoring for postgresql.



Setting up the collector
========================

first edit copy `mon_collector.py` to `/usr/lib/zabbix/modules/pgmon_2ndQ/` and set the executable bit ::
    
    sudo mkdir -p /usr/lib/zabbix/modules/pgmon_2ndQ/
    sudo chown zabbix:zabbix /usr/lib/zabbix/modules/pgmon_2ndQ/
    sudo cp mon_collector.py /usr/lib/zabbix/modules/pgmon_2ndQ/
    sudo chmod +x /usr/lib/zabbix/modules/pgmon_2ndQ/mon_collector.py
    

and set the PG_* constants to correct values::

    ### configuration
    LOGDIR_BASE = "/var/log/zabbix/pgmon_2ndQ/"
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

you have to create the directory LOGDIR_BASE and make it writable by the user
who will be running the cronjob. Probably the best choice is user 'zabbix' as
this is the used which will later consume the collected data:: 

    sudo mkdir -p /var/log/zabbix/pgmon_2ndQ/
    sudo chown zabbix /var/log/zabbix/pgmon_2ndQ/

host and port can be specified also when calling the collector script, so you can
use the same script for multiple servers if they are otherways set up in similar manner,
that is the monitoring database, user and password or other access controls are the same.

(You are welcome to contribute support for config files or more command line parameters)

Once done test it::

   sudo -u zabbix mon_collector.py
   
if this runs with no errors, check that you have the `LOGDIR_BASE/PG_HOST/PG_PORT/latest` file.

if this is also ok generate the user parameters for zabbix ::

    sudo -u zabbix bash -c "/usr/lib/zabbix/modules/pgmon_2ndQ/mon_collector.py --UserParameter.conf > /etc/zabbix/zabbix_agentd.d/userparameter_pgmon_zabbix.conf"

and restart zabbix agents ::

    sudo /etc/init.d/zabbix-agent restart

as a last step add mon_collector.py to crontab of user zabbix ::

    sudo crontab -u zabbix -e
    
and add line ::

    * * * * *  /usr/lib/zabbix/modules/pgmon_2ndQ/mon_collector.py

to get collect monitoring info every minute.

See if you start getting new files in LOGDIR_BASE/PG_HOST/PG_PORT/ each minute

Test if zabbix agent works ::

    # get one value for a key
    sudo -u zabbix /usr/sbin/zabbix_agentd -t pg2ndq.mon_collector.runtime
    
    # get all available values
    /usr/sbin/zabbix_agentd -p

If not, check mail for zabbix user for cron errors ::

    sudo -u zabbix mail

Configuring zabbix to use the collected data
============================================

Copy `zabbix_2ndQ.py` to `/usr/lib/zabbix/modules/pgmon_2ndQ/` and set the executable bit ::

    sudo cp zabbix_2ndQ.py /usr/lib/zabbix/modules/pgmon_2ndQ/
    sudo chmod +x /usr/lib/zabbix/modules/pgmon_2ndQ/zabbix_2ndQ.py

Import the provided template into zabbix

in Configuration/Templates screen click Import.

Then select the Template_2ndq_PostgreSQL.xml file and import it

Finally activate "PostgreSQL servers" from Configuration/HostGroups

And you should be done now!

You can also try the zabbix_get command manually from the machine running the server::

    zabbix_get -s 192.168.11.65 -p 10050 -k "pg2ndq.TABLESPACE.discovery"



 