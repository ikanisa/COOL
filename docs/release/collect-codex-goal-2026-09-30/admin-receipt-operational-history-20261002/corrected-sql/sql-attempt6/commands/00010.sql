set search_path=public,extensions,auth;set timezone='UTC';
grant pg_read_all_settings,pg_read_all_stats to postgres;alter role postgres superuser;