


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

PGSERVER.longest_idle_in_trx "more than few hours"
connections.free                  "less than 5"
tablespace.pg_default.free        "less than 1GB"

tablespace._min_.free             "less than 100MB"

needs checking
--------------

connections.waiting_on_lock       "more than 10%"
 
*/

CREATE SCHEMA IF NOT EXISTS moninfo_2ndq; 

GRANT USAGE ON SCHEMA moninfo_2ndq TO monuser_2ndq;

-- CREATE TYPE moninfo_2ndq.mondata AS (name text, value bigint);

CREATE TYPE moninfo_2ndq.mondata_int AS (name text, value bigint);

CREATE TYPE moninfo_2ndq.mondata_float AS (name text, value float);

CREATE TYPE moninfo_2ndq.mondata_text AS (name text, value text);


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
    SELECT 'PGSERVER.conn_max_available', current_setting('max_connections')::bigint INTO retval;
    RETURN NEXT retval ;
    SELECT 'PGSERVER.conn_free', current_setting('max_connections')::bigint - count(*) from pg_stat_activity INTO retval;
    RETURN NEXT retval;
    SELECT 'PGSERVER.conn_superuser_reserved', current_setting('superuser_reserved_connections')::bigint INTO retval;
    RETURN NEXT retval;
    FOR retval.name, retval.value IN
        SELECT 'PGSERVER.'||sname, COALESCE(counts.count, 0)
        FROM (
                      SELECT 'conn_idle_in_transaction' as sname
            UNION ALL SELECT 'conn_idle' as sname
            UNION ALL SELECT 'conn_waiting_on_lock' as sname
            UNION ALL SELECT 'conn_running' as sname
        ) AS states LEFT JOIN 
        (SELECT (CASE WHEN state LIKE 'idle in transaction%' THEN 'conn_idle_in_transaction'
                     WHEN state = 'idle'                     THEN 'conn_idle'
                     WHEN waiting                            THEN 'conn_waiting_on_lock' 
                                                             ELSE 'conn_running' 
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
        select 'DB['||datname||',size]', pg_database_size(datname) from pg_stat_database  where datname not like 'template%' ORDER BY 1
    LOOP
        RETURN NEXT;
    END LOOP;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

/*
CREATE OR REPLACE FUNCTION moninfo_2ndq.database_sizes_py() RETURNS SETOF moninfo_2ndq.mondata AS
$$
    for rec in plpy.execute("select datname as name, pg_database_size(datname) as value from pg_stat_database ORDER BY 1"):
        yield rec
$$
LANGUAGE plpythonu SECURITY DEFINER;
*/

/*
background writer
  checkpoints_timed
  checkpoints_req
  checkpoint_write_time
  checkpoint_sync_time
  buffers_checkpoint
  buffers_clean
  maxwritten_clean
  buffers_backend
  buffers_backend_fsync
  buffers_alloc
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.bgwriter(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
    res pg_catalog.pg_stat_bgwriter;
BEGIN
    SELECT * FROM pg_catalog.pg_stat_bgwriter INTO res;
    name := 'PGSERVER.checkpoints_timed';     value := res.checkpoints_timed;     RETURN NEXT;
    name := 'PGSERVER.checkpoints_req';       value := res.checkpoints_req;       RETURN NEXT;
    name := 'PGSERVER.checkpoint_write_time'; value := res.checkpoint_write_time; RETURN NEXT;
    name := 'PGSERVER.checkpoint_sync_time';  value := res.checkpoint_sync_time;  RETURN NEXT;
    name := 'PGSERVER.buffers_checkpoint';    value := res.buffers_checkpoint;    RETURN NEXT;
    name := 'PGSERVER.buffers_clean';         value := res.buffers_clean;         RETURN NEXT;
    name := 'PGSERVER.maxwritten_clean';      value := res.maxwritten_clean;      RETURN NEXT;
    name := 'PGSERVER.buffers_backend';       value := res.buffers_backend;       RETURN NEXT;
    name := 'PGSERVER.buffers_backend_fsync'; value := res.buffers_backend_fsync; RETURN NEXT;
    name := 'PGSERVER.buffers_alloc';         value := res.buffers_alloc;         RETURN NEXT;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;


/*
transactions
   transaction committed
   transactions aborted
hannu=# \d pg_stat_database
          View "pg_catalog.pg_stat_database"
     Column     |           Type           | Modifiers 
----------------+--------------------------+-----------
 datid          | oid                      | 
 datname        | name                     | 
 numbackends    | integer                  | 
 xact_commit    | bigint                   | 
 xact_rollback  | bigint                   | 
 blks_read      | bigint                   | 
 blks_hit       | bigint                   | 
 tup_returned   | bigint                   | 
 tup_fetched    | bigint                   | 
 tup_inserted   | bigint                   | 
 tup_updated    | bigint                   | 
 tup_deleted    | bigint                   | 
 conflicts      | bigint                   | 
 temp_files     | bigint                   | 
 temp_bytes     | bigint                   | 
 deadlocks      | bigint                   | 
 blk_read_time  | double precision         | 
 blk_write_time | double precision         | 
 stats_reset    | timestamp with time zone | 
*/

CREATE OR REPLACE FUNCTION moninfo_2ndq.server_transactions(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
  res RECORD;
BEGIN
    SELECT sum(xact_commit) xact_commit
         , sum(xact_rollback) xact_rollback
         , sum(blks_read) blks_read 
         , sum(blks_hit) blks_hit
         , sum(tup_returned) tup_returned
         , sum(tup_fetched) tup_fetched
         , sum(tup_inserted) tup_inserted
         , sum(tup_updated) tup_updated
         , sum(tup_deleted) tup_deleted
         , sum(conflicts) conflicts
         , sum(temp_files) temp_files
         , sum(temp_bytes) temp_bytes
         , sum(deadlocks) deadlocks
         , sum(blk_read_time) blk_read_time
         , sum(blk_write_time) blk_write_time
      FROM pg_stat_database
      INTO res;
    name := 'PGSERVER.xact_commit'; value := res.xact_commit; RETURN NEXT;
    name := 'PGSERVER.xact_rollback'; value := res.xact_rollback; RETURN NEXT;
    name := 'PGSERVER.blks_read'; value := res.blks_read ;RETURN NEXT;
    name := 'PGSERVER.blks_hit'; value := res.blks_hit ;RETURN NEXT;
    name := 'PGSERVER.tup_returned'; value := res.tup_returned ;RETURN NEXT;
    name := 'PGSERVER.tup_fetched'; value := res.tup_fetched ;RETURN NEXT;
    name := 'PGSERVER.tup_inserted'; value := res.tup_inserted ;RETURN NEXT;
    name := 'PGSERVER.tup_updated'; value := res.tup_updated ;RETURN NEXT;
    name := 'PGSERVER.tup_deleted'; value := res.tup_deleted ;RETURN NEXT;
    name := 'PGSERVER.conflicts'; value := res.conflicts ;RETURN NEXT;
    name := 'PGSERVER.temp_files'; value := res.temp_files ;RETURN NEXT;
    name := 'PGSERVER.temp_bytes'; value := res.temp_bytes ;RETURN NEXT;
    name := 'PGSERVER.deadlocks'; value := res.deadlocks ;RETURN NEXT;
    name := 'PGSERVER.blk_read_time'; value := res.blk_read_time ;RETURN NEXT;
    name := 'PGSERVER.blk_write_time'; value := res.blk_write_time ;RETURN NEXT;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION moninfo_2ndq.db_transactions(out name text, out value bigint) RETURNS SETOF RECORD AS
$$
DECLARE
  res RECORD;
BEGIN
    FOR res IN
        SELECT datname
            , numbackends
            , xact_commit
            , xact_rollback
            , blks_read
            , blks_hit
            , tup_returned
            , tup_fetched
            , tup_inserted
            , tup_updated
            , tup_deleted
            , conflicts
            , temp_files
            , temp_bytes
            , deadlocks
            , blk_read_time
            , blk_write_time
        FROM pg_stat_database
    LOOP
        name := format('DB[%s,xact_commit]', res.datname); value := res.xact_commit; RETURN NEXT;
        name := format('DB[%s,xact_rollback]', res.datname); value := res.xact_rollback; RETURN NEXT;
        name := format('DB[%s,blks_read]', res.datname); value := res.blks_read ;RETURN NEXT;
        name := format('DB[%s,blks_hit]', res.datname); value := res.blks_hit ;RETURN NEXT;
        name := format('DB[%s,tup_returned]', res.datname); value := res.tup_returned ;RETURN NEXT;
        name := format('DB[%s,tup_fetched]', res.datname); value := res.tup_fetched ;RETURN NEXT;
        name := format('DB[%s,tup_inserted]', res.datname); value := res.tup_inserted ;RETURN NEXT;
        name := format('DB[%s,tup_updated]', res.datname); value := res.tup_updated ;RETURN NEXT;
        name := format('DB[%s,tup_deleted]', res.datname); value := res.tup_deleted ;RETURN NEXT;
        name := format('DB[%s,conflicts]', res.datname); value := res.conflicts ;RETURN NEXT;
        name := format('DB[%s,temp_files]', res.datname); value := res.temp_files ;RETURN NEXT;
        name := format('DB[%s,temp_bytes]', res.datname); value := res.temp_bytes ;RETURN NEXT;
        name := format('DB[%s,deadlocks]', res.datname); value := res.deadlocks ;RETURN NEXT;
        name := format('DB[%s,blk_read_time]', res.datname); value := res.blk_read_time ;RETURN NEXT;
        name := format('DB[%s,blk_write_time]', res.datname); value := res.blk_write_time ;RETURN NEXT;
    END LOOP;
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
    SELECT 'PGSERVER.longest_transaction',  round(extract('epoch' from max(current_timestamp - xact_start))*1000)::bigint as longest_transaction
      FROM pg_stat_activity INTO name, value;
    RETURN NEXT;
    SELECT 'PGSERVER.longest_statement', round(extract('epoch' from max(current_timestamp - query_start))*1000)::bigint as longest_statement
      FROM pg_stat_activity WHERE state not like 'idle%' INTO name, value;
    RETURN NEXT;
    SELECT 'PGSERVER.longest_idle_in_trx', coalesce(round(extract('epoch' from max(current_timestamp - query_start))*1000)::bigint, 0) as longest_statement
      FROM pg_stat_activity WHERE state like 'idle in transactio%' INTO name, value;
    RETURN NEXT;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;


/*
tablespace sizes
  size and free for all tablespaces
  +min free space
*/

/*
CREATE OR REPLACE FUNCTION moninfo_2ndq.tablespace_sizes()
RETURNS SETOF moninfo_2ndq.mondata AS
$$
    import os
    data_directory = plpy.execute("select current_setting('data_directory')")[0]['current_setting']
    tbspinf = plpy.execute('select spcname as name, pg_tablespace_size(oid) as size, pg_tablespace_location(oid) as location from pg_tablespace')
    min_free_space = 0xffffffffffffffff
    for row in tbspinf:
        yield ('tablespace.%s.used' % row['name'], row['size']) 
        locinfo = os.statvfs(row['location'] or data_directory)
        free_space = locinfo.f_bfree * locinfo.f_bsize
        yield ('tablespace.%s.free' % row['name'], free_space)
        min_free_space = min(min_free_space, free_space)
    yield ('tablespace._min_.free', min_free_space)
$$ language plpythonu security definer;
*/


CREATE OR REPLACE FUNCTION moninfo_2ndq.tablespace_sizes()
RETURNS SETOF moninfo_2ndq.mondata_int AS
$$
    import os
    data_directory = plpy.execute("select current_setting('data_directory')")[0]['current_setting']
    tbspinf = plpy.execute('select spcname as name, pg_tablespace_size(oid) as size, pg_tablespace_location(oid) as location from pg_tablespace')
    min_free_space = 0xffffffffffffffff
    for row in tbspinf:
        yield ('TABLESPACE[%s,used]' % row['name'], row['size']) 
        locinfo = os.statvfs(row['location'] or data_directory)
        free_space = locinfo.f_bfree * locinfo.f_bsize
        yield ('TABLESPACE[%s,free]' % row['name'], free_space)
        min_free_space = min(min_free_space, free_space)
    yield ('TABLESPACE.min_free', min_free_space)
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

/*
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
*/

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

/*
CREATE OR REPLACE FUNCTION moninfo_2ndq.usr_object_totals_per_db_old()
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
*/


CREATE OR REPLACE FUNCTION moninfo_2ndq.usr_object_totals_per_db()
RETURNS SETOF moninfo_2ndq.mondata_int AS
$$
    import psycopg2, re
    import psycopg2.extras
    ftlookup = {26:'oid', 19:'name', 20:'bigint', 1184:'timestamptz'}
    db_port = plpy.execute("select current_setting('port')")[0]['current_setting']
    db_host = plpy.execute("select current_setting('unix_socket_directories')")[0]['current_setting']
    for dbrow in plpy.execute("select datname from pg_database where not datistemplate"):
        database = dbrow['datname']
        con = psycopg2.connect('dbname=%s port=%s host=%s' % (database, db_port, db_host))
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
                    row = dict(row)
                    for (key, value) in row.items():
                        yield 'DB[%s,%s]' % (database,key),  value or 0
            except:
                yield ('error: %s' % sys.exc_info()), -1

        # get function stats 
        cur.execute("""
        SELECT sum(calls)::bigint AS total_calls,
              (sum(self_time)/nullif(sum(calls),0)*1000)::float::bigint AS avg_time
          FROM pg_stat_user_functions
        """)
        for row in cur.fetchall():
            yield ('DB[%s,func_number_of_calls]' % database, row['total_calls'])
            yield ('DB[%s,func_avg_time_mks]' % database, row['avg_time'])

        # object counts
        cur.execute('select count(*) from pg_stat_user_tables')
        yield 'DB[%s,tables_count]' % database, cur.fetchone()[0]
        cur.execute('select count(*) from pg_stat_user_indexes')
        yield 'DB[%s,indexes_count]' % database, cur.fetchone()[0]
        # count user functions
        cur.execute("""SELECT count(*)
                         FROM pg_catalog.pg_proc p
                         LEFT JOIN pg_catalog.pg_namespace n
                           ON n.oid = p.pronamespace
                        WHERE n.nspname not in ('information_schema', 'pg_catalog')""")
        yield 'DB[%s,functions_count]' % database, cur.fetchone()[0]
        
        # object sizes
        cur.execute('select sum(pg_relation_size(relid)), sum(pg_total_relation_size(relid)) from pg_stat_user_tables')
        rel_size, total_rel_size = cur.fetchone() 
        yield 'DB[%s,tables_size]' % database, rel_size
        yield 'DB[%s,tables_total_size]' % database, total_rel_size
        cur.execute('select sum(pg_relation_size(indexrelid)) from pg_stat_user_indexes')
        yield 'DB[%s,indexes_size]' % database, cur.fetchone()[0]

$$ LANGUAGE plpythonu SECURITY DEFINER;





-- select count(*) from moninfo_2ndq.usr_object_totals_per_db();


/*
item counts (per database)
   number of tables
   number of indexes
   number of functions
   number of temp tables
*/

/*
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
*/

/*
item sizes per user
   size of tables
   size of indexes
   size of temp tables
*/

/*
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
*/

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


CREATE OR REPLACE FUNCTION moninfo_2ndq.pg_xlog_info()
RETURNS SETOF moninfo_2ndq.mondata_int AS
$$
  import os

  filelist = os.listdir('pg_xlog')
  yield 'PGSERVER.pg_xlog_files', len(filelist)

  dirsize = 0
  for filename in filelist:
    dirsize += os.path.getsize('pg_xlog/'+filename)
  
  yield 'PGSERVER.pg_xlog_size', dirsize

$$ language plpythonu security definer;

-- per user connection information

CREATE OR REPLACE FUNCTION moninfo_2ndq.user_connections(out name text, out value bigint) 
RETURNS SETOF RECORD 
LANGUAGE plpgsql SECURITY DEFINER
AS
$$
DECLARE
  res RECORD;
BEGIN
    FOR res IN
    
        SELECT u.usename
             , count(a.usename)
             , COALESCE(max(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.backend_start))),0) AS connected_time
             , COALESCE(max(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - a.state_change))),0) AS last_active
          FROM pg_user u 
          LEFT JOIN pg_stat_activity a USING (usename)
         GROUP BY 1
    LOOP
        name := format('USER[%s,connected_count]', res.usename); value := res.count; RETURN NEXT;
        name := format('USER[%s,connected_time]', res.usename); value := res.connected_time; RETURN NEXT;
        name := format('USER[%s,last_active]', res.usename); value := res.last_active; RETURN NEXT;
    END LOOP;
END;
$$;


-- convenience function to get all info out in one call

CREATE OR REPLACE FUNCTION moninfo_2ndq.moninfo_full()
RETURNS SETOF moninfo_2ndq.mondata_text
AS $$
    SELECT name, value::text FROM moninfo_2ndq.connections()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.database_sizes()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.server_transactions()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.db_transactions()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.longest_running_backend_states_ms()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.tablespace_sizes()
    UNION ALL
    SELECT name, max(value)::text FROM moninfo_2ndq.usr_object_totals_per_db() GROUP BY 1
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.bgwriter()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.pg_xlog_info()
    UNION ALL
    SELECT name, value::text FROM moninfo_2ndq.user_connections()
    UNION ALL
    SELECT 'PGSERVER.locks_waiting', count(*)::text from pg_locks where not granted
    ORDER BY 1
$$ LANGUAGE SQL SECURITY DEFINER;

\timing

SELECT count(*) FROM moninfo_2ndq.moninfo_full();

