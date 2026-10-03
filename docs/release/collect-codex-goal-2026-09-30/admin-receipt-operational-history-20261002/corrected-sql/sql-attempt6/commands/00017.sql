set search_path=public,extensions,auth;set timezone='UTC';
grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;