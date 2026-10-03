create table if not exists app_realtime_events (
  id uuid primary key default gen_random_uuid(),
  area text not null check (area in (
    'profiles',
    'collections',
    'members',
    'payment_intents',
    'payments',
    'allocations',
    'ledger',
    'receivers',
    'sms_events',
    'admin_roles',
    'audit',
    'feature_flags',
    'settings',
    'system_health'
  )),
  created_at timestamptz not null default now()
);

alter table app_realtime_events enable row level security;

drop policy if exists "realtime invalidations read authenticated" on app_realtime_events;
create policy "realtime invalidations read authenticated"
on app_realtime_events
for select
to authenticated
using (true);

revoke all on app_realtime_events from anon, authenticated;
grant select on app_realtime_events to authenticated;

create or replace function emit_app_realtime_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into app_realtime_events (area)
  values (tg_argv[0]);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function emit_app_realtime_event() from public, anon, authenticated;
grant execute on function emit_app_realtime_event() to service_role;

create or replace function attach_app_realtime_event_trigger(
  p_table_name text,
  p_area text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  execute format('drop trigger if exists %I on %I', 'app_realtime_event_trigger', p_table_name);
  execute format(
    'create trigger %I after insert or update or delete on %I for each row execute function emit_app_realtime_event(%L)',
    'app_realtime_event_trigger',
    p_table_name,
    p_area
  );
end;
$$;

select attach_app_realtime_event_trigger('profiles', 'profiles');
select attach_app_realtime_event_trigger('collections', 'collections');
select attach_app_realtime_event_trigger('collection_members', 'members');
select attach_app_realtime_event_trigger('payment_intents', 'payment_intents');
select attach_app_realtime_event_trigger('payments', 'payments');
select attach_app_realtime_event_trigger('payment_allocations', 'allocations');
select attach_app_realtime_event_trigger('ledger_entries', 'ledger');
select attach_app_realtime_event_trigger('collection_receivers', 'receivers');
select attach_app_realtime_event_trigger('raw_payment_sms', 'sms_events');
select attach_app_realtime_event_trigger('parsed_payment_events', 'sms_events');
select attach_app_realtime_event_trigger('admin_user_roles', 'admin_roles');
select attach_app_realtime_event_trigger('audit_logs', 'audit');
select attach_app_realtime_event_trigger('admin_sensitive_access_logs', 'audit');
select attach_app_realtime_event_trigger('feature_flags', 'feature_flags');
select attach_app_realtime_event_trigger('system_settings', 'settings');

drop function attach_app_realtime_event_trigger(text, text);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'app_realtime_events'
    ) then
    execute 'alter publication supabase_realtime add table public.app_realtime_events';
  end if;
end;
$$;
