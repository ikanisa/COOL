-- Offline synthetic target: isolated installer owner normalization
grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;
-- Offline synthetic target: query
select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'));
-- Offline synthetic target: query
do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon nologin;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated nologin;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin bypassrls;end if;end$$;
-- Offline synthetic target: query
create schema if not exists extensions;create extension if not exists pg_net with schema extensions;
-- Offline synthetic target: query
select jsonb_build_object('extension',(select jsonb_build_object('name',extname,'version',extversion)from pg_extension where extname='pg_net'),'tables',(select jsonb_object_agg(c.relname,(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull)order by a.attnum)from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped))from pg_class c where c.relnamespace='net'::regnamespace and c.relkind='r'),'functions',(select jsonb_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)from pg_proc p where p.pronamespace='net'::regnamespace));
