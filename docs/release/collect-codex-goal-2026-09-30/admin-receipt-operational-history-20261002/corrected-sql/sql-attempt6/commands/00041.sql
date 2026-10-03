set search_path=public,extensions,auth;set timezone='UTC';
select jsonb_agg(column_name order by ordinal_position)from information_schema.columns where table_schema='public' and table_name='payments';