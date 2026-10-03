set search_path=public,extensions,auth;set timezone='UTC';
select not rolsuper from pg_roles where rolname=current_user;