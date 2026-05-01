-- Harden generic payment intent status transitions.
--
-- Client-owned payment instructions are not payment confirmation. Status
-- changes are reserved for verified backend evidence, service-role flows, or
-- authorized admins.

update public.payment_intents
set status = 'fulfilled'
where status = 'completed';

alter table public.payment_intents
  drop constraint if exists payment_intents_status_check;

alter table public.payment_intents
  add constraint payment_intents_status_check
  check (status in ('pending', 'fulfilled', 'expired', 'cancelled'));

drop policy if exists "payment_intents_update_auth" on public.payment_intents;
drop policy if exists payment_intents_update_admin on public.payment_intents;

create policy payment_intents_update_admin
  on public.payment_intents
  for update
  to authenticated
  using (public.is_admin_user())
  with check (public.is_admin_user());

create or replace function public.enforce_payment_intent_status_transition()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.status = 'completed' then
    new.status := 'fulfilled';
  end if;

  if tg_op = 'INSERT' then
    if auth.role() = 'authenticated'
      and not public.is_admin_user()
      and new.status <> 'pending' then
      raise exception
        'Payment intent status changes require verified backend confirmation or authorized admin action.'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if new.status is distinct from old.status then
    if old.status <> 'pending' then
      raise exception
        'Terminal payment intent statuses cannot be changed.'
        using errcode = '23514';
    end if;

    if auth.role() = 'authenticated' and not public.is_admin_user() then
      raise exception
        'Payment intent status changes require verified backend confirmation or authorized admin action.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_payment_intent_status_transition
  on public.payment_intents;
create trigger trg_enforce_payment_intent_status_transition
  before insert or update of status on public.payment_intents
  for each row execute function public.enforce_payment_intent_status_transition();

comment on function public.enforce_payment_intent_status_transition() is
  'Normalizes legacy completed to fulfilled and blocks client-side payment confirmation.';
