


/*
CREATE DATABASE mondb_2ndq;

CREATE USER monuser_2ndq WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB PASSWORD 'abyD66jIu';

\c mondb_2ndq

CREATE LANGUAGE plpgsql;
CREATE LANGUAGE plpythonu;

check pg_hba.conf for connect info

Things to watch out for
=======================

dangerous:

all_databases.longest_idle_in_trx "more than few hours"
connections.free                  "less than 5"
tablespace.pg_default.free        "less than 1GB"

tablespace._min_.free             "less than 100MB"

needs checking
--------------

connections.waiting_on_lock       "more than 10%"
 
*/

CREATE SCHEMA moninfo_2ndq; 

CREATE TYPE moninfo_2ndq.mondata AS (name text, value bigint);

CREATE TYPE moninfo_2ndq.mondata_int AS (name text, value bigint);

CREATE TYPE moninfo_2ndq.mondata_float AS (name text, value float);

CREATE TYPE moninfo_2ndq.mondata_text AS (name text, value text);

GRANT USAGE ON SCHEMA moninfo_2ndq TO monuser_2ndq;

/* add missing pl/xx languages*/

CREATE /*OR REPLACE*/ LANGUAGE plpythonu;;
CREATE /*OR REPLACE*/ LANGUAGE plpgsql;


/*
connections:
    max_connections
    free_connections
    status IDLE
    status IDLE IN TRANSACTION
    status ACTIVE
    status ACTIVE waiting for LOCK
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.connections() RETURNS SETOF moninfo_2ndq.mondata_int AS
$$
DECLARE
  retval moninfo_2ndq.mondata_int;
BEGIN
    SELECT 'connections.max_available', current_setting('max_connections')::bigint INTO retval;
    RETURN NEXT retval ;
    SELECT 'connections.free', current_setting('max_connections')::bigint - count(*) from pg_stat_activity INTO retval;
    RETURN NEXT retval;
    SELECT 'connections.superuser_reserved', current_setting('superuser_reserved_connections')::bigint INTO retval;
    RETURN NEXT retval;
    FOR retval.name, retval.value IN
        SELECT sname, COALESCE(counts.count, 0)
        FROM (
                      SELECT 'connections.idle_in_transaction' as sname
            UNION ALL SELECT 'connections.idle' as sname
            UNION ALL SELECT 'connections.waiting_on_lock' as sname
            UNION ALL SELECT 'connections.running' as sname
        ) AS states LEFT JOIN 
        (SELECT (CASE WHEN current_query LIKE '<IDLE> in transaction%' THEN 'connections.idle_in_transaction'
                     WHEN current_query = '<IDLE>' THEN 'connections.idle'
                     WHEN waiting THEN 'connections.waiting_on_lock' 
                     ELSE 'connections.running' 
                END) AS cname, 
                count(*) as count 
          FROM pg_stat_activity
         GROUP BY 1 ) counts
        ON sname = cname
    LOOP
        RETURN NEXT retval;
    END LOOP;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

/*
database sizes
   sizes of each database
*/
   

CREATE OR REPLACE FUNCTION moninfo_2ndq.database_sizes(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
  retval RECORD;
BEGIN
    FOR name, value IN
        select 'database.'||datname||'.size', pg_database_size(datname) from pg_stat_database ORDER BY 1
    LOOP
        RETURN NEXT;
    END LOOP;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION moninfo_2ndq.database_sizes_py() RETURNS SETOF moninfo_2ndq.mondata AS
$$
    for rec in plpy.execute("select datname as name, pg_database_size(datname) as value from pg_stat_database ORDER BY 1"):
        yield rec
$$
LANGUAGE plpythonu SECURITY DEFINER;


/*
transactions
   transaction committed
   transactions aborted
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.transactions(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
  retval RECORD;
BEGIN
    SELECT 'all_databases.xact_commit', sum(xact_commit) from pg_stat_database INTO name, value;
    RETURN NEXT;
    SELECT 'all_databases.xact_rollback', sum(xact_rollback) from pg_stat_database INTO name, value;
    RETURN NEXT;

END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

/*
longest transactions
   longest running transaction length
   longest running statement length
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.longest_running_backend_states_ms(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
  retval RECORD;
BEGIN
    SELECT 'all_databases.longest_transaction',  round(extract('epoch' from max(current_timestamp - xact_start))*1000)::bigint as longest_transaction
      FROM pg_stat_activity INTO name, value;
    RETURN NEXT;
    SELECT 'all_databases.longest_statement', round(extract('epoch' from max(current_timestamp - query_start))*1000)::bigint as longest_statement
      FROM pg_stat_activity WHERE current_query NOT like '<IDLE>%' INTO name, value;
    RETURN NEXT;
    SELECT 'all_databases.longest_idle_in_trx', coalesce(round(extract('epoch' from max(current_timestamp - query_start))*1000)::bigint, 0) as longest_statement
      FROM pg_stat_activity WHERE current_query like '<IDLE> in transactio%' INTO name, value;
    RETURN NEXT;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;


/*
tablespace sizes
  size and free for all tablespaces
  +min free space
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.tablespace_sizes()
RETURNS SETOF moninfo_2ndq.mondata AS
$$
    import os
    data_directory = plpy.execute("select current_setting('data_directory')")[0]['current_setting']
    tbspinf = plpy.execute('select spcname as name, pg_tablespace_size(oid) as size, spclocation as location from pg_tablespace')
    min_free_space = 0xffffffffffffffff
    for row in tbspinf:
        yield ('tablespace.%s.used' % row['name'], row['size']) 
        locinfo = os.statvfs(row['location'] or data_directory)
        free_space = locinfo.f_bfree * locinfo.f_bsize
        yield ('tablespace.%s.free' % row['name'], free_space)
        min_free_space = min(min_free_space, free_space)
    yield ('tablespace._min_.free', min_free_space)
$$ language plpythonu security definer;

/*
pg_stat_functions total
  number of function calls
  average length of function call
  
#track_functions = none                 # none, pl, all
track_functions = all
  
*/

/*
CREATE OR REPLACE FUNCTION moninfo_2ndq.functions_total(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
  total_calls bigint;
  avg_time_ms float;
  retval RECORD;
BEGIN
    SELECT sum(calls) AS total_calls,
          (sum(total_time)/sum(calls)) AS avg_time
      FROM pg_stat_user_functions
      INTO total_calls, avg_time_ms; 
    SELECT 'number_of_calls', total_calls INTO name, value;
    RETURN NEXT;
    SELECT 'avg_duration_mks', (avg_time_ms * 1000)::bigint INTO name, value;
    RETURN NEXT;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.usr_function_totals_per_db()
RETURNS SETOF moninfo_2ndq.mondata AS
$$
    import psycopg2
    import psycopg2.extras
    db_port = plpy.execute("select current_setting('port')")[0]['current_setting']
    for dbrow in plpy.execute("select datname from pg_database where not datistemplate"):
        database = dbrow['datname']
#        con = psycopg2.connect('dbname=%s' % database)
        con = psycopg2.connect('dbname=%s port=%s' % (database, db_port))
        cur = con.cursor(cursor_factory=psycopg2.extras.DictCursor)
        cur.execute("""
        SELECT sum(calls)::bigint AS total_calls,
              (sum(total_time)/sum(calls)*1000)::float::bigint AS avg_time
          FROM pg_stat_user_functions
        """)
        for row in cur.fetchall():
            yield ('database.%s.functions.user_totals.number_of_calls' % database, row['total_calls']) 
            yield ('database.%s.functions.user_totals.avg_time_mks' % database, row['avg_time'])
        con.close()
$$ LANGUAGE plpythonu SECURITY DEFINER;

-- select * from moninfo_2ndq.usr_function_totals_per_db();

/*
pg_stat_functions top N by total time spent
   for each in top N
      total time
      number of calls
      average time
*/


/* TODO */

/*
pg_stat_user_tables total
   seq scans
   seq tuples fetched
   index scans
   index tuples fetched
   tuples inserted
   tuples updated
   tuples deleted 
   tuples hot-updated
*/

/*
pg_statio_user_tables total
   pages hit
   pages read
   index pages hit
   index pages read
*/
    
/*
same as above for index pages
   .. as above
*/

/*
pg_stat_user_xxx for selected tables and indexes
   .. as above
*/


CREATE OR REPLACE FUNCTION moninfo_2ndq.usr_object_totals_per_db()
RETURNS SETOF moninfo_2ndq.mondata AS
$$
    import psycopg2, re
    import psycopg2.extras
    ftlookup = {26:'oid', 19:'name', 20:'bigint', 1184:'timestamptz'}
    db_port = plpy.execute("select current_setting('port')")[0]['current_setting']
    for dbrow in plpy.execute("select datname from pg_database where not datistemplate"):
        database = dbrow['datname']
#        plpy.notice("connecting to %s" % database)
        con = psycopg2.connect('dbname=%s port=%s' % (database, db_port))
#        plpy.notice('dbname=%s port=%s' % (database, db_port))
        cur = con.cursor(cursor_factory=psycopg2.extras.DictCursor)
        for table_name in ['pg_stat_user_tables', 'pg_statio_user_tables', 'pg_stat_user_indexes', 'pg_statio_user_indexes']:
            try:
                cur.execute('select * from %s limit 1' % table_name)
                ftypes =  [(fname, ftlookup[ftype]) for (fname, ftype) in [row[:2] for row in cur.description]]
                stotals_query = 'SELECT %s FROM %s' % (
                    ','.join(['sum(%(fname)s)::bigint as %(fname)s' % locals() for (fname,ftype) in ftypes if ftype == 'bigint']),
                    table_name
                    )
                cur.execute(stotals_query)
                for row in cur.fetchall():
                    tname = re.sub(r'pg_stat(io)?_user_', '', table_name)
                    row = dict(row)
                    for (key, value) in row.items():
                        yield 'database.%s.%s.user_totals.%s' % (database,tname,key),  value or 0
            except:
                yield ('error: %s' % sys.exc_info()), -1

$$ LANGUAGE plpythonu SECURITY DEFINER;

-- select count(*) from moninfo_2ndq.usr_object_totals_per_db();


/*
item counts (per database)
   number of tables
   number of indexes
   number of functions
   number of temp tables
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.object_counts()
RETURNS SETOF moninfo_2ndq.mondata AS
$$
    import psycopg2
    db_port = plpy.execute("select current_setting('port')")[0]['current_setting']
    for row in plpy.execute("select datname from pg_database where not datistemplate"):
        database = row['datname']
#        con = psycopg2.connect('dbname=%s' % database)
        con = psycopg2.connect('dbname=%s port=%s' % (database, db_port))
        cur = con.cursor()
        cur.execute('select count(*) from pg_stat_user_tables')
        yield 'database.%s.tables.user_total.count' % database, cur.fetchone()[0]
        cur.execute('select count(*) from pg_stat_user_indexes')
        yield 'database.%s.indexes.user_total.count' % database, cur.fetchone()[0]
        # cout user functions
        cur.execute("""SELECT count(*)
                         FROM pg_catalog.pg_proc p
                         LEFT JOIN pg_catalog.pg_namespace n
                           ON n.oid = p.pronamespace
                        WHERE n.nspname not in ('information_schema', 'pg_catalog')""")
        yield 'database.%s.functions.user_total.count' % database, cur.fetchone()[0]
        con.close()
$$ language plpythonu security definer;

/*
item sizes per user
   size of tables
   size of indexes
   size of temp tables
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.object_sizes()
RETURNS SETOF moninfo_2ndq.mondata AS
$$
    import psycopg2
    db_port = plpy.execute("select current_setting('port')")[0]['current_setting']
    for row in plpy.execute("select datname from pg_database where not datistemplate"):
        database = row['datname']
#        con = psycopg2.connect('dbname=%s' % database)
        con = psycopg2.connect('dbname=%s port=%s' % (database, db_port))
        cur = con.cursor()
        cur.execute('select sum(pg_relation_size(relid)), sum(pg_total_relation_size(relid)) from pg_stat_user_tables')
        rel_size, total_rel_size = cur.fetchone() 
        yield 'database.%s.tables.total.rel_size' % database, rel_size
        yield 'database.%s.tables.total.total_size' % database, total_rel_size
        cur.execute('select sum(pg_relation_size(relid)) from pg_stat_user_indexes')
        yield 'database.%s.indexes.total.rel_size' % database, cur.fetchone()[0]
        con.close()
$$ language plpythonu security definer;


/*
temp space usage:
   number of temp files
   size of temp files
*/

/*
buffer cache usage (port from munin)
   how much buffer cache is used
*/

/*
checkpoint activity
   length of checkpoint (from munin)
*/

-- convenience function to get all info out in one call

CREATE OR REPLACE FUNCTION moninfo_2ndq.moninfo_full()
RETURNS SETOF moninfo_2ndq.mondata_text
AS $$
    SELECT name, value::text FROM moninfo_2ndq.connections()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.database_sizes()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.transactions()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.longest_running_backend_states_ms()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.tablespaces()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.tablespace_sizes()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.usr_function_totals_per_db()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.usr_object_totals_per_db()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.object_counts()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.object_sizes()
$$ LANGUAGE SQL SECURITY DEFINER;

\timing

SELECT count(*) FROM moninfo_2ndq.moninfo_full();

/*
>>> import psycopg2
>>> con = psycopg2.connect('')
>>> import psycopg2.extras
>>> cur = con.cursor(cursor_factory=psycopg2.extras.DictCursor)
>>> cur.execute('select * from pg_stat_user_tables limit 3')
>>> for row in cur.fetchall():
...     print json.dumps(row)
... 
[42007, "hannu", "ti", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, null, null, null, null]
[33220, "hannu", "tt2", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, null, null, null, null]
[33215, "public", "TTT", 0, 0, null, null, 0, 0, 0, 0, 0, 0, null, null, null, null]
>>> cur.execute('select * from pg_stat_user_tables limit 3')
>>> for row in cur.fetchall():
...     print json.dumps(dict(row))
... 
{"relid": 42007, "last_vacuum": null, "n_tup_ins": 0, "n_tup_hot_upd": 0, "idx_scan": 0, "n_tup_del": 0, "n_dead_tup": 0, "relname": "ti", "last_autovacuum": null, "last_analyze": null, "n_live_tup": 0, "idx_tup_fetch": 0, "n_tup_upd": 0, "last_autoanalyze": null, "seq_scan": 0, "seq_tup_read": 0, "schemaname": "hannu"}
{"relid": 33220, "last_vacuum": null, "n_tup_ins": 0, "n_tup_hot_upd": 0, "idx_scan": 0, "n_tup_del": 0, "n_dead_tup": 0, "relname": "tt2", "last_autovacuum": null, "last_analyze": null, "n_live_tup": 0, "idx_tup_fetch": 0, "n_tup_upd": 0, "last_autoanalyze": null, "seq_scan": 0, "seq_tup_read": 0, "schemaname": "hannu"}
{"relid": 33215, "last_vacuum": null, "n_tup_ins": 0, "n_tup_hot_upd": 0, "idx_scan": null, "n_tup_del": 0, "n_dead_tup": 0, "relname": "TTT", "last_autovacuum": null, "last_analyze": null, "n_live_tup": 0, "idx_tup_fetch": null, "n_tup_upd": 0, "last_autoanalyze": null, "seq_scan": 0, "seq_tup_read": 0, "schemaname": "public"}
*/

