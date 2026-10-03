-- Offline synthetic target: isolated installer owner normalization
grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;
-- Offline synthetic target: query
select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'));
-- Offline synthetic target: query
do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon nologin;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated nologin;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin bypassrls;end if;end$$;
-- Offline synthetic target: isolated platform owner prerequisite
create schema if not exists extensions;create extension if not exists pg_net with schema extensions;
-- Offline synthetic target: isolated platform owner response-ID index
create index collect_receipt_http_response_id on net._http_response(id);
-- Offline synthetic target: demote isolated application installer
alter role postgres nosuperuser;
-- Offline synthetic target: actual ordinary installer existing-index branch
create index if not exists collect_receipt_http_response_id on net._http_response(id);
