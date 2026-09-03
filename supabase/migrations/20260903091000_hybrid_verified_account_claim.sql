begin;

-- Account claiming is separately gated. A verified sign-in phone is the only
-- credential used for matching; names, suffixes, editable profile fields and
-- caller-supplied numbers are never authentication factors.
insert into public.feature_flags(key, enabled, description)
values (
  'hybrid_verified_account_claim',
  false,
  'Pilot gate: link one account-independent member record to an authenticated account only when the full server-verified Rwanda phone exactly matches the stored MoMo number'
)
on conflict (key) do nothing;

create table collect_hybrid.member_account_claims (
  member_record_id uuid primary key
    references collect_hybrid.member_records(id) on delete restrict,
  user_id uuid unique references public.profiles(id) on delete set null,
  verified_phone_sha256 text not null
    check (verified_phone_sha256 ~ '^[0-9a-f]{64}$'),
  identity_revision integer not null check (identity_revision > 0),
  claim_revision integer not null default 1 check (claim_revision > 0),
  claimed_at timestamptz not null default clock_timestamp(),
  last_claimed_at timestamptz not null default clock_timestamp()
);
create index member_account_claims_user_active_idx
  on collect_hybrid.member_account_claims(user_id)
  where user_id is not null;
alter table collect_hybrid.member_account_claims enable row level security;
revoke all on collect_hybrid.member_account_claims
  from public, anon, authenticated, service_role;

create function collect_hybrid.member_record_belongs_to_user(
  p_member_record_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_member_record_id is not null
    and p_user_id is not null
    and exists (
      select 1
      from collect_hybrid.member_records member
      left join collect_hybrid.member_account_claims claim
        on claim.member_record_id = member.id
      where member.id = p_member_record_id
        and member.lifecycle = 'active'
        and (
          member.linked_user_id = p_user_id
          or claim.user_id = p_user_id
        )
    );
$$;

create function collect_hybrid.member_record_has_account(
  p_member_record_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from collect_hybrid.member_records member
    left join collect_hybrid.member_account_claims claim
      on claim.member_record_id = member.id
    where member.id = p_member_record_id
      and member.lifecycle = 'active'
      and coalesce(member.linked_user_id, claim.user_id) is not null
  );
$$;

revoke all on function collect_hybrid.member_record_belongs_to_user(uuid, uuid),
  collect_hybrid.member_record_has_account(uuid)
from public, anon, authenticated, service_role;

-- Preserve the established browser/service caller boundary while allowing a
-- successfully claimed offline membership to unlock that same private group.
create or replace function public.user_is_collection_admin(
  collection uuid,
  user_uuid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.role() = 'service_role'
      or user_uuid is not distinct from auth.uid() then
      public.is_platform_admin(user_uuid)
      or exists (
        select 1 from public.collections item
        where item.id = collection and item.creator_user_id = user_uuid
      )
      or exists (
        select 1
        from public.collection_members membership
        where membership.collection_id = collection
          and membership.status = 'active'
          and membership.role in ('owner', 'admin', 'receiver')
          and (
            membership.user_id = user_uuid
            or collect_hybrid.member_record_belongs_to_user(
              membership.member_record_id, user_uuid
            )
          )
      )
    else false
  end;
$$;

create or replace function public.user_can_read_collection(
  collection uuid,
  user_uuid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.role() = 'service_role'
      or user_uuid is not distinct from auth.uid() then
      exists (
        select 1
        from public.collections item
        where item.id = collection
          and (
            item.public_status = 'public_approved'
            or item.creator_user_id = user_uuid
            or public.is_platform_admin(user_uuid)
            or exists (
              select 1
              from public.collection_members membership
              where membership.collection_id = item.id
                and membership.status = 'active'
                and (
                  membership.user_id = user_uuid
                  or collect_hybrid.member_record_belongs_to_user(
                    membership.member_record_id, user_uuid
                  )
                )
            )
          )
      )
    else false
  end;
$$;

revoke execute on function public.user_is_collection_admin(uuid, uuid)
  from public;
revoke execute on function public.user_can_read_collection(uuid, uuid)
  from public;
grant execute on function public.user_is_collection_admin(uuid, uuid),
  public.user_can_read_collection(uuid, uuid)
to anon, authenticated, service_role;

-- Existing and future payments may attach the verified account while the
-- immutable member record remains the financial identity anchor.
create or replace function collect_hybrid.bind_payment_member_record()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_member_id uuid;
  resolved_collect_id char(6);
begin
  if new.member_record_id is null and new.contributor_user_id is not null then
    select member.id, member.collect_id
    into resolved_member_id, resolved_collect_id
    from collect_hybrid.member_records member
    where member.linked_user_id = new.contributor_user_id
      and member.lifecycle = 'active';
  elsif new.member_record_id is null and new.contributor_public_id is not null then
    select member.id, member.collect_id
    into resolved_member_id, resolved_collect_id
    from collect_hybrid.member_records member
    where member.collect_id = new.contributor_public_id
      and member.lifecycle = 'active';
  elsif new.member_record_id is not null then
    select member.id, member.collect_id
    into resolved_member_id, resolved_collect_id
    from collect_hybrid.member_records member
    where member.id = new.member_record_id
      and member.lifecycle = 'active';
  end if;

  if new.member_record_id is not null and resolved_member_id is null then
    raise exception 'Active member record required';
  end if;
  if resolved_member_id is not null then
    if new.contributor_user_id is not null
       and not collect_hybrid.member_record_belongs_to_user(
         resolved_member_id, new.contributor_user_id
       ) then
      raise exception 'Payment account and member record do not match';
    end if;
    if new.contributor_public_id is not null
       and new.contributor_public_id <> resolved_collect_id then
      raise exception 'Payment Collect ID and member record do not match';
    end if;
    new.member_record_id := resolved_member_id;
    new.contributor_public_id := coalesce(
      new.contributor_public_id, resolved_collect_id
    );
  end if;
  return new;
end;
$$;

create function collect_hybrid.attach_claimed_payment_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.member_record_id is not null and new.contributor_user_id is null then
    select claim.user_id into new.contributor_user_id
    from collect_hybrid.member_account_claims claim
    where claim.member_record_id = new.member_record_id
      and claim.user_id is not null;
  end if;
  return new;
end;
$$;
create trigger account_claim_payment_identity_trigger
before insert or update of member_record_id on public.payments
for each row execute function collect_hybrid.attach_claimed_payment_account();
revoke all on function collect_hybrid.attach_claimed_payment_account()
  from public, anon, authenticated, service_role;

-- Defense in depth: even if a future enqueue path forgets channel routing, an
-- account-linked record can never enter the assisted SMS outbox.
create function collect_hybrid.prevent_account_linked_sms_enqueue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if collect_hybrid.member_record_has_account(new.member_record_id) then
    return null;
  end if;
  return new;
end;
$$;
create trigger account_linked_sms_enqueue_guard
before insert on collect_hybrid.sms_notification_outbox
for each row execute function collect_hybrid.prevent_account_linked_sms_enqueue();
revoke all on function collect_hybrid.prevent_account_linked_sms_enqueue()
  from public, anon, authenticated, service_role;

create or replace function collect_hybrid.sms_receipt_job_is_current(
  p_job_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select true
    from collect_hybrid.sms_notification_outbox job
    join public.payments payment on payment.id = job.payment_id
    join collect_hybrid.member_records member on member.id = job.member_record_id
    join collect_hybrid.member_momo_identities identity
      on identity.member_id = member.id
    join collect_hybrid.sms_receipt_policies policy
      on policy.collection_id = job.collection_id
    join collect_hybrid.sms_receipt_member_consents consent
      on consent.member_record_id = job.member_record_id
    where job.id = p_job_id
      and coalesce((
        select flag.enabled from public.feature_flags flag
        where flag.key = 'hybrid_sms_notifications'
      ), false)
      and payment.status = 'posted'
      and payment.amount_rwf = job.amount_rwf
      and member.lifecycle = 'active'
      and not collect_hybrid.member_record_has_account(member.id)
      and identity.revision = job.destination_revision
      and identity.momo_number = job.destination_e164
      and encode(
        extensions.digest(identity.momo_number, 'sha256'), 'hex'
      ) = job.destination_sha256
      and policy.enabled
      and policy.revision = job.policy_revision
      and policy.template_key = job.template_key
      and policy.template_version = job.template_version
      and consent.enabled
      and consent.revision = job.consent_revision
  ), false);
$$;

create function collect_hybrid.claim_verified_current_account()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  verified_phone text;
  phone_hash text;
  identity collect_hybrid.member_momo_identities;
  member collect_hybrid.member_records;
  existing collect_hybrid.member_account_claims;
  updated_payments integer := 0;
  suppressed_jobs integer := 0;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if not coalesce((
    select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_verified_account_claim'
  ), false) then
    raise exception 'Verified offline-member account claiming is disabled';
  end if;
  verified_phone := collect_admin_access.verified_phone(actor);
  if verified_phone is null
     or verified_phone !~ '^\+2507[2389][0-9]{7}$' then
    return jsonb_build_object('ok', true, 'status', 'no_match');
  end if;
  phone_hash := encode(extensions.digest(verified_phone, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    'hybrid-account-claim:' || phone_hash, 0
  ));
  select item.* into identity
  from collect_hybrid.member_momo_identities item
  where item.momo_number = verified_phone
  for update;
  if identity.member_id is null then
    return jsonb_build_object('ok', true, 'status', 'no_match');
  end if;
  select item.* into member
  from collect_hybrid.member_records item
  where item.id = identity.member_id
  for update;
  if member.id is null or member.lifecycle <> 'active' then
    raise exception 'Matching member record requires review';
  end if;
  if member.linked_user_id = actor then
    return jsonb_build_object(
      'ok', true, 'status', 'already_linked', 'collect_id', member.collect_id
    );
  end if;
  if member.linked_user_id is not null then
    raise exception 'Matching member record is linked to another account';
  end if;
  select claim.* into existing
  from collect_hybrid.member_account_claims claim
  where claim.member_record_id = member.id
  for update;
  if existing.user_id = actor
     and existing.identity_revision = identity.revision
     and existing.verified_phone_sha256 = phone_hash then
    return jsonb_build_object(
      'ok', true, 'status', 'already_claimed',
      'member_record_id', member.id, 'collect_id', member.collect_id
    );
  end if;
  if existing.user_id is not null then
    raise exception 'Matching member record is claimed by another account';
  end if;
  if exists (
    select 1 from collect_hybrid.member_account_claims claim
    where claim.user_id = actor and claim.member_record_id <> member.id
  ) then
    raise exception 'Account already claims another member record';
  end if;
  insert into collect_hybrid.member_account_claims(
    member_record_id, user_id, verified_phone_sha256, identity_revision
  ) values (
    member.id, actor, phone_hash, identity.revision
  )
  on conflict (member_record_id) do update
  set user_id = excluded.user_id,
      verified_phone_sha256 = excluded.verified_phone_sha256,
      identity_revision = excluded.identity_revision,
      claim_revision = collect_hybrid.member_account_claims.claim_revision + 1,
      last_claimed_at = clock_timestamp();

  -- Linking identity is not a financial posting. Existing immutable payment,
  -- journal and balance rows stay in place; only their nullable account pointer
  -- is attached so app notifications and own-history privacy work normally.
  update public.payments payment
  set contributor_user_id = actor
  where payment.member_record_id = member.id
    and payment.contributor_user_id is null;
  get diagnostics updated_payments = row_count;

  update collect_hybrid.sms_notification_outbox job
  set state = 'suppressed',
      suppression_reason = 'Member authenticated the app with the exact verified MoMo number',
      claim_token = null,
      claimed_by = null,
      claim_expires_at = null
  where job.member_record_id = member.id
    and job.state in ('queued', 'awaiting_confirmation');
  get diagnostics suppressed_jobs = row_count;

  perform public.create_audit_log(
    'member.offline_account.claimed', 'member_record', member.id,
    jsonb_build_object(
      'collect_id', member.collect_id,
      'identity_revision', identity.revision,
      'verified_phone_sha256', phone_hash,
      'payments_attached', updated_payments,
      'sms_jobs_suppressed', suppressed_jobs
    ),
    actor
  );
  return jsonb_build_object(
    'ok', true, 'status', 'claimed',
    'member_record_id', member.id, 'collect_id', member.collect_id,
    'payments_attached', updated_payments,
    'sms_jobs_suppressed', suppressed_jobs
  );
end;
$$;

create function public.claim_verified_current_account()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select collect_hybrid.claim_verified_current_account(); $$;
revoke all on function collect_hybrid.claim_verified_current_account(),
  public.claim_verified_current_account()
from public, anon, authenticated, service_role;
grant execute on function collect_hybrid.claim_verified_current_account()
  to authenticated;
grant execute on function public.claim_verified_current_account()
  to authenticated;

-- Once the pilot gate is enabled, the normal authenticated profile bootstrap
-- performs the server-owned exact-phone check. A no-match response is silent.
create or replace function public.ensure_current_member_profile(
  p_whatsapp_phone text,
  p_country_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare profile_row public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  profile_row := public.ensure_current_profile(
    p_whatsapp_phone, p_country_code
  );
  if coalesce((
    select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_verified_account_claim'
  ), false) then
    perform collect_hybrid.claim_verified_current_account();
  end if;
  return public._member_profile_payload(profile_row);
end;
$$;
revoke all on function public.ensure_current_member_profile(text, text)
  from public, anon, authenticated;
grant execute on function public.ensure_current_member_profile(text, text)
  to authenticated;

-- Claimed and native app records contribute to the same authenticated own
-- balance without altering the immutable member-record ledger key.
create or replace function public.list_current_member_collection_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with visible as (
    select collection.id
    from public.collections collection
    where public.user_can_read_collection(collection.id, auth.uid())
  ), amounts as (
    select balance.collection_id, 'RWF'::text as currency,
      balance.confirmed_rwf::bigint as raised,
      coalesce((
        select sum(member_balance.confirmed_rwf)::bigint
        from collect_hybrid.member_balances member_balance
        where member_balance.collection_id = balance.collection_id
          and collect_hybrid.member_record_belongs_to_user(
            member_balance.member_record_id, auth.uid()
          )
      ), 0)::bigint as own
    from collect_hybrid.collection_balances balance
    join visible on visible.id = balance.collection_id
    union all
    select allocation.collection_id, transaction.currency,
      sum(transaction.amount_minor)::bigint,
      coalesce(sum(transaction.amount_minor) filter (
        where allocation.contributor_user_id = auth.uid()
      ), 0)::bigint
    from public.bank_transactions transaction
    join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = transaction.id
    join visible on visible.id = allocation.collection_id
    where transaction.status = 'reconciled'
    group by allocation.collection_id, transaction.currency
  ), contributors as (
    select payment.collection_id, payment.contributor_user_id
    from public.payments payment
    join visible on visible.id = payment.collection_id
    where payment.status = 'posted'
    union all
    select allocation.collection_id, allocation.contributor_user_id
    from public.bank_transactions transaction
    join public.bank_transaction_allocations allocation
      on allocation.bank_transaction_id = transaction.id
    join visible on visible.id = allocation.collection_id
    where transaction.status = 'reconciled'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'collection_id', visible.id,
    'balances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', amount.currency,
        'amount_raised_minor', amount.raised,
        'current_user_balance_minor', amount.own
      ) order by amount.currency)
      from amounts amount where amount.collection_id = visible.id
    ), '[]'::jsonb),
    'supporter_count', (
      select case when count(*) filter (
        where contributor_user_id is null
      ) > 0 then null else count(distinct contributor_user_id) end
      from contributors contributor
      where contributor.collection_id = visible.id
    )
  ) order by visible.id), '[]'::jsonb)
  into result from visible;
  return result;
end;
$$;

create or replace function public.list_current_user_collection_summaries()
returns table(
  collection_id uuid,
  amount_raised_rwf bigint,
  supporter_count bigint,
  current_user_balance_rwf bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select collection.id,
    coalesce(balance.confirmed_rwf, 0)::bigint,
    coalesce((
      select count(distinct coalesce(
        payment.contributor_user_id::text,
        payment.transaction_id,
        payment.id::text
      ))
      from public.payments payment
      where payment.collection_id = collection.id
        and payment.status = 'posted'
    ), 0)::bigint,
    coalesce((
      select sum(member_balance.confirmed_rwf)
      from collect_hybrid.member_balances member_balance
      where member_balance.collection_id = collection.id
        and collect_hybrid.member_record_belongs_to_user(
          member_balance.member_record_id, auth.uid()
        )
    ), 0)::bigint
  from public.collections collection
  left join collect_hybrid.collection_balances balance
    on balance.collection_id = collection.id
  where auth.uid() is not null
    and collection.archived_at is null
    and public.user_can_read_collection(collection.id, auth.uid());
$$;

revoke all on function public.list_current_member_collection_balances(),
  public.list_current_user_collection_summaries()
from public, anon, authenticated;
grant execute on function public.list_current_member_collection_balances(),
  public.list_current_user_collection_summaries()
to authenticated;

comment on function public.claim_verified_current_account() is
  'Links one account-independent member record using only the full server-verified Rwanda Auth phone. Never matches by name, suffix or editable profile fields.';

commit;
