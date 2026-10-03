set search_path=public,extensions,auth;set timezone='UTC';
-- Audit reads use the existing session-bound Admin RPCs and audit.read
-- permission. No member application or Admin consumer reads this table
-- directly. Preserve the retained RPC bodies, RLS and service audit writes.
begin;

revoke select on table public.audit_logs from public, anon, authenticated;

-- PostgreSQL column privileges survive a table-level revocation. Close that
-- alternate direct-read path as well, including all current ordinary columns.
do $$
declare
  audit_columns text;
begin
  select string_agg(quote_ident(attname), ', ' order by attnum)
    into audit_columns
    from pg_catalog.pg_attribute
    where attrelid = 'public.audit_logs'::regclass
      and attnum > 0
      and not attisdropped;

  if audit_columns is null then
    raise exception 'audit_read_schema_unavailable';
  end if;

  execute format(
    'revoke select (%s) on table public.audit_logs from public, anon, authenticated',
    audit_columns
  );
end;
$$;

commit;
