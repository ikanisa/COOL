begin;

-- An editable profile hash is not evidence that a member controls a payer
-- number. Restore the confirmed Supabase Auth phone boundary for new intents
-- and every intent-backed posting, including candidates created before this
-- migration.
create or replace function public._authenticated_momo_phone_hash(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth, extensions
as $$
declare
  profile_digits text;
  auth_digits text;
  canonical_profile_phone text;
  canonical_auth_phone text;
  auth_phone_confirmed_at timestamptz;
begin
  select
    regexp_replace(coalesce(profile.momo_number, ''), '[^0-9]', '', 'g'),
    regexp_replace(coalesce(auth_user.phone, ''), '[^0-9]', '', 'g'),
    auth_user.phone_confirmed_at
    into profile_digits, auth_digits, auth_phone_confirmed_at
  from public.profiles profile
  join auth.users auth_user on auth_user.id = profile.id
  where profile.id = p_user_id
    and auth_user.deleted_at is null
    and profile.country_code = 'RW';

  if profile_digits ~ '^250[0-9]{9}$' then
    canonical_profile_phone := '+' || profile_digits;
  elsif profile_digits ~ '^0[0-9]{9}$' then
    canonical_profile_phone := '+250' || substr(profile_digits, 2);
  elsif profile_digits ~ '^[0-9]{9}$' then
    canonical_profile_phone := '+250' || profile_digits;
  else
    return null;
  end if;

  if auth_digits ~ '^250[0-9]{9}$' then
    canonical_auth_phone := '+' || auth_digits;
  elsif auth_digits ~ '^0[0-9]{9}$' then
    canonical_auth_phone := '+250' || substr(auth_digits, 2);
  elsif auth_digits ~ '^[0-9]{9}$' then
    canonical_auth_phone := '+250' || auth_digits;
  else
    return null;
  end if;

  if auth_phone_confirmed_at is null
     or canonical_profile_phone <> canonical_auth_phone then
    return null;
  end if;

  return encode(extensions.digest(canonical_auth_phone, 'sha256'), 'hex');
end;
$$;
revoke all on function public._authenticated_momo_phone_hash(uuid)
  from public, anon, authenticated;

update public.payment_intents intent
set status = 'cancelled'
where intent.status = 'pending'
  and intent.sender_phone_hash is distinct from
    public._authenticated_momo_phone_hash(intent.contributor_user_id);

-- Existing candidates are evidence to reconcile, not balances to rewrite.
-- This table contains IDs and reason codes; source SMS and financial journals
-- retain their existing access controls and immutability.
create table collect_hybrid.payer_identity_reconciliation (
  payment_id uuid primary key references public.payments(id) on delete restrict,
  observed_payment_status text not null check (observed_payment_status in ('review', 'posted')),
  reason text not null check (reason in (
    'intent_identity_unverified', 'payment_intent_binding_mismatch',
    'sms_payer_missing_or_mismatch'
  )),
  review_status text not null default 'open'
    check (review_status in ('open', 'resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (
    (review_status = 'open' and resolved_at is null)
    or (review_status = 'resolved' and resolved_at is not null)
  )
);
alter table collect_hybrid.payer_identity_reconciliation enable row level security;
revoke all on collect_hybrid.payer_identity_reconciliation
  from public, anon, authenticated, service_role;
grant select on collect_hybrid.payer_identity_reconciliation to service_role;

insert into collect_hybrid.payer_identity_reconciliation(
  payment_id, observed_payment_status, reason
)
select payment.id, payment.status,
  case
    when intent.sender_phone_hash is distinct from
         public._authenticated_momo_phone_hash(intent.contributor_user_id)
      then 'intent_identity_unverified'
    when payment.contributor_user_id is distinct from intent.contributor_user_id
      or payment.collection_id is distinct from intent.collection_id
      then 'payment_intent_binding_mismatch'
    else 'sms_payer_missing_or_mismatch'
  end
from public.payments payment
join public.payment_intents intent on intent.id = payment.payment_intent_id
left join public.parsed_payment_events event on event.id = payment.parsed_event_id
where payment.status in ('review', 'posted')
  and (
    intent.sender_phone_hash is distinct from
      public._authenticated_momo_phone_hash(intent.contributor_user_id)
    or payment.contributor_user_id is distinct from intent.contributor_user_id
    or payment.collection_id is distinct from intent.collection_id
    or event.sender_phone_hash is distinct from intent.sender_phone_hash
  );

create function collect_hybrid.require_confirmed_intent_payer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  intent_row public.payment_intents;
  verified_payer_hash text;
  observed_payer_hash text;
begin
  if tg_op = 'UPDATE' then
    if old.payment_intent_id is not null or new.payment_intent_id is not null then
      if new.payment_intent_id is distinct from old.payment_intent_id
         or new.parsed_event_id is distinct from old.parsed_event_id
         or new.contributor_user_id is distinct from old.contributor_user_id
         or new.collection_id is distinct from old.collection_id
         or new.receiver_user_id is distinct from old.receiver_user_id
         or new.receiver_momo_number_hash is distinct from old.receiver_momo_number_hash
         or new.amount_rwf is distinct from old.amount_rwf
         or new.currency is distinct from old.currency
         or new.transaction_id is distinct from old.transaction_id
         or new.provider_network is distinct from old.provider_network
         or new.member_record_id is distinct from old.member_record_id then
        raise exception 'Intent-backed payment attribution is immutable'
          using errcode = '23514';
      end if;
    end if;
  end if;

  if new.status <> 'posted' or new.payment_intent_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.status = 'posted' then return new; end if;
  end if;

  select * into intent_row
  from public.payment_intents
  where id = new.payment_intent_id
  for share;
  if intent_row.id is null
     or new.contributor_user_id is distinct from intent_row.contributor_user_id
     or new.collection_id is distinct from intent_row.collection_id then
    raise exception 'Payment intent attribution requires reconciliation'
      using errcode = '23514';
  end if;

  verified_payer_hash :=
    public._authenticated_momo_phone_hash(intent_row.contributor_user_id);
  select event.sender_phone_hash into observed_payer_hash
  from public.parsed_payment_events event
  where event.id = new.parsed_event_id;
  if verified_payer_hash is null
     or intent_row.sender_phone_hash is distinct from verified_payer_hash
     or observed_payer_hash is distinct from verified_payer_hash
     or exists (
       select 1
       from collect_hybrid.payer_identity_reconciliation review
       where review.payment_id = new.id and review.review_status = 'open'
     ) then
    raise exception 'Confirmed payer identity and SMS sender evidence are required'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function collect_hybrid.require_confirmed_intent_payer()
  from public, anon, authenticated;

create trigger require_confirmed_intent_payer_before_post
before insert or update
on public.payments
for each row execute function collect_hybrid.require_confirmed_intent_payer();

comment on table collect_hybrid.payer_identity_reconciliation is
  'Open legacy intent-backed payer attribution exceptions; no automatic balance rewrite or silent resolution.';

commit;
