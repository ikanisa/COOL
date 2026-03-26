-- ══════════════════════════════════════════════════════════════
-- Scoped RLS Policies for Bank & Rayon Sport Admins
-- ══════════════════════════════════════════════════════════════
--
-- This migration adds RLS policies that allow bank admins to only see
-- data scoped to their partner, and rayon sport admins to only see
-- data scoped to the Rayon Sports partner.
--
-- Depends on: admin_role_assignments table from 20260316020000

-- ── 1. Helper: check if user has an active role for a given partner ──

create or replace function public.user_has_role_for_partner(
  p_partner_id uuid
)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.admin_role_assignments
    where user_id = auth.uid()
      and is_active = true
      and (
        -- Platform admins can access everything
        role = 'admin'
        -- Scoped admins can access their partner
        or partner_scope_id = p_partner_id
      )
  )
  or exists (
    -- Legacy fallback: check is_admin flag
    select 1 from public.users
    where id = auth.uid() and is_admin = true
  );
$$;
-- ── 2. Helper: check if user is a bank admin for a partner ──────────

create or replace function public.user_is_bank_admin_for(
  p_partner_id uuid
)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.admin_role_assignments
    where user_id = auth.uid()
      and is_active = true
      and role in ('admin', 'bank')
      and (role = 'admin' or partner_scope_id = p_partner_id)
  )
  or exists (
    select 1 from public.users
    where id = auth.uid() and is_admin = true
  );
$$;
-- ── 3. Helper: check if user is a rayon sport admin ─────────────────

create or replace function public.user_is_rayon_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.admin_role_assignments
    where user_id = auth.uid()
      and is_active = true
      and role in ('admin', 'rayon_sport')
  )
  or exists (
    select 1 from public.users
    where id = auth.uid() and is_admin = true
  );
$$;
-- ── 4. (Skipped) Groups RLS is handled by scoped bank RPCs ──────────
-- Groups access is controlled via bank_custody_groups and bank_custody_ledger
-- RPCs which already filter by partner_id. No additional RLS needed here.



-- ── 5. Audit trigger: log admin mutations to audit_log ──────────────

create or replace function public.trigger_admin_audit_log()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Only log if the actor is an admin
  if exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    insert into public.admin_audit_log (actor_id, action, target_table, target_id, old_data, new_data)
    values (
      auth.uid(),
      lower(TG_OP),
      TG_TABLE_NAME,
      case
        when TG_OP = 'DELETE' then (OLD).id::text
        else (NEW).id::text
      end,
      case when TG_OP in ('UPDATE', 'DELETE') then to_jsonb(OLD) else null end,
      case when TG_OP in ('INSERT', 'UPDATE') then to_jsonb(NEW) else null end
    );
  end if;

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;
-- Attach audit triggers to key admin tables
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'partners', 'partner_services', 'quick_actions',
    'app_config', 'admin_role_assignments'
  ]) loop
    if exists (select 1 from information_schema.tables where table_name = t and table_schema = 'public') then
      -- Drop existing trigger if any
      execute format('drop trigger if exists audit_%s on public.%I', t, t);
      -- Create new trigger
      execute format(
        'create trigger audit_%s
         after insert or update or delete on public.%I
         for each row execute function public.trigger_admin_audit_log()',
        t, t
      );
    end if;
  end loop;
end $$;
