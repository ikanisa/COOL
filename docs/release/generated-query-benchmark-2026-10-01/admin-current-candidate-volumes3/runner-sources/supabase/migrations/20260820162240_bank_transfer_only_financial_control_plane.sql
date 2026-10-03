begin;

-- Supabase production already provisions pg_cron. Its managed after-create
-- hook can reject a repeated CREATE EXTENSION even with IF NOT EXISTS, so only
-- install it on environments where the extension is genuinely absent.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute 'create extension pg_cron with schema pg_catalog';
  end if;
end;
$$;

-- Collect is now a bank-transfer-only product. Historical MoMo rows remain
-- immutable audit evidence, but no new member payment flow writes to the
-- legacy MoMo intent/event/ledger path. Stripe was never activated in this
-- project; fail closed if a deployment has Stripe data before removing it.
do $$
declare
  stripe_rows bigint := 0;
begin
  if to_regclass('public.stripe_customers') is not null then
    select
      (select count(*) from public.stripe_customers)
      + (select count(*) from public.stripe_payment_methods)
      + (select count(*) from public.diaspora_contribution_intents)
      + (select count(*) from public.stripe_webhook_events)
    into stripe_rows;
    if stripe_rows <> 0 then
      raise exception 'Stripe retirement requires a reviewed export of % existing rows', stripe_rows;
    end if;
  end if;
end;
$$;

drop table if exists public.stripe_webhook_events;
drop table if exists public.diaspora_contribution_intents;
drop table if exists public.stripe_payment_methods;
drop table if exists public.stripe_customers;

alter table public.collections
  add column if not exists bank_transfer_currency text not null default 'EUR'
    check (bank_transfer_currency = 'EUR');

create table public.bank_transfer_destinations (
  id uuid primary key default gen_random_uuid(),
  version integer not null check (version > 0),
  beneficiary_name text not null check (char_length(btrim(beneficiary_name)) between 3 and 160),
  iban text not null check (upper(regexp_replace(iban, '[^A-Za-z0-9]', '', 'g')) ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  bic text not null check (upper(regexp_replace(bic, '[^A-Za-z0-9]', '', 'g')) ~ '^[A-Z0-9]{8}([A-Z0-9]{3})?$'),
  bank_name text not null check (char_length(btrim(bank_name)) between 2 and 160),
  currency text not null default 'EUR' check (currency = 'EUR'),
  transfer_scheme text not null default 'sepa_credit_transfer'
    check (transfer_scheme = 'sepa_credit_transfer'),
  supports_instant boolean not null default true,
  status text not null default 'draft'
    check (status in ('draft', 'pending_approval', 'active', 'retired')),
  is_placeholder boolean not null default false,
  change_reason text not null,
  created_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (currency, version),
  constraint bank_transfer_destination_approval_consistency check (
    (status in ('draft', 'pending_approval') and approved_by is null and approved_at is null)
    or (status in ('active', 'retired') and approved_by is not null and approved_at is not null)
  ),
  constraint bank_transfer_destination_placeholder_not_active check (
    not is_placeholder or status in ('draft', 'retired')
  )
);

create unique index bank_transfer_destinations_one_active_currency_idx
  on public.bank_transfer_destinations (currency)
  where status = 'active';

create table public.bank_destination_change_requests (
  id uuid primary key default gen_random_uuid(),
  beneficiary_name text not null,
  iban text not null,
  bic text not null,
  bank_name text not null,
  currency text not null default 'EUR' check (currency = 'EUR'),
  supports_instant boolean not null default true,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reason text not null check (char_length(btrim(reason)) >= 8),
  proposed_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete restrict,
  review_note text,
  reviewed_at timestamptz,
  destination_id uuid references public.bank_transfer_destinations(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint bank_destination_change_maker_checker check (
    reviewed_by is null or reviewed_by <> proposed_by
  )
);

create table public.bank_transfer_intents (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.collections(id) on delete restrict,
  contributor_user_id uuid not null references public.profiles(id) on delete restrict,
  destination_id uuid not null references public.bank_transfer_destinations(id) on delete restrict,
  destination_snapshot jsonb not null,
  transfer_reference text unique not null check (transfer_reference ~ '^COL-[A-Z0-9]{10}$'),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  status text not null default 'awaiting_transfer' check (status in (
    'awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence',
    'received_unreconciled', 'reconciled', 'exception', 'returned',
    'expired', 'cancelled'
  )),
  handoff_opened_at timestamptz,
  evidence_received_at timestamptz,
  reconciled_at timestamptz,
  exception_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '48 hours')
);

create index bank_transfer_intents_owner_created_idx
  on public.bank_transfer_intents (contributor_user_id, created_at desc);
create index bank_transfer_intents_match_idx
  on public.bank_transfer_intents (transfer_reference, currency, amount_minor, status);
create index bank_transfer_intents_collection_idx
  on public.bank_transfer_intents (collection_id, created_at desc);

create table public.raw_payment_evidence (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('sms', 'email', 'statement')),
  source_uid text not null,
  raw_sender text not null,
  raw_body text not null,
  body_hash text not null check (body_hash ~ '^[0-9a-f]{64}$'),
  headers jsonb not null default '{}'::jsonb,
  received_at timestamptz not null,
  parse_status text not null default 'pending'
    check (parse_status in ('pending', 'parsed', 'failed', 'needs_review', 'ignored')),
  retention_until timestamptz not null default (now() + interval '90 days'),
  created_at timestamptz not null default now(),
  unique (channel, source_uid),
  unique (channel, body_hash)
);

create table public.bank_evidence_events (
  id uuid primary key default gen_random_uuid(),
  raw_evidence_id uuid unique not null references public.raw_payment_evidence(id) on delete restrict,
  direction text not null default 'unknown' check (direction in ('incoming', 'outgoing', 'unknown')),
  amount_minor bigint check (amount_minor is null or amount_minor > 0),
  currency text not null default 'unknown' check (currency in ('EUR', 'unknown')),
  bank_transaction_id text,
  end_to_end_id text,
  transfer_reference text,
  payer_name text,
  payer_account_last4 text check (payer_account_last4 is null or payer_account_last4 ~ '^[A-Z0-9]{4}$'),
  occurred_at timestamptz,
  confidence numeric not null default 0 check (confidence between 0 and 1),
  parser_name text not null default 'collect.bank_rules.v1',
  parser_schema_version text not null default 'collect.bank_evidence.v1',
  parsed_json jsonb not null default '{}'::jsonb,
  allocation_status text not null default 'unallocated'
    check (allocation_status in ('unallocated', 'allocated', 'ambiguous', 'needs_review', 'ignored')),
  review_reason text,
  created_at timestamptz not null default now()
);

create index bank_evidence_events_reference_idx
  on public.bank_evidence_events (transfer_reference, currency, amount_minor, occurred_at desc);
create index bank_evidence_events_review_idx
  on public.bank_evidence_events (allocation_status, created_at desc);

create table public.bank_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_key text unique not null check (transaction_key ~ '^[0-9a-f]{64}$'),
  destination_id uuid references public.bank_transfer_destinations(id) on delete restrict,
  bank_transaction_id text,
  end_to_end_id text,
  transfer_reference text,
  payer_name text,
  payer_account_last4 text,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  occurred_at timestamptz not null,
  value_date date,
  status text not null default 'received'
    check (status in ('received', 'reconciled', 'returned', 'exception')),
  evidence_received_at timestamptz not null default now(),
  reconciled_at timestamptz,
  returned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index bank_transactions_provider_id_idx
  on public.bank_transactions (upper(bank_transaction_id))
  where bank_transaction_id is not null;
create unique index bank_transactions_end_to_end_idx
  on public.bank_transactions (upper(end_to_end_id))
  where end_to_end_id is not null;
create index bank_transactions_reconciliation_idx
  on public.bank_transactions (status, currency, value_date, occurred_at);

create table public.payment_evidence_links (
  bank_transaction_id uuid not null references public.bank_transactions(id) on delete restrict,
  evidence_event_id uuid not null references public.bank_evidence_events(id) on delete restrict,
  linked_at timestamptz not null default now(),
  primary key (bank_transaction_id, evidence_event_id),
  unique (evidence_event_id)
);

create table public.bank_transaction_allocations (
  id uuid primary key default gen_random_uuid(),
  bank_transaction_id uuid unique not null references public.bank_transactions(id) on delete restrict,
  bank_transfer_intent_id uuid unique not null references public.bank_transfer_intents(id) on delete restrict,
  collection_id uuid not null references public.collections(id) on delete restrict,
  contributor_user_id uuid not null references public.profiles(id) on delete restrict,
  allocation_method text not null check (allocation_method in ('auto_exact_reference', 'manual_maker_checker')),
  confidence numeric not null check (confidence between 0 and 1),
  reason text not null,
  allocated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  file_hash text unique not null check (file_hash ~ '^[0-9a-f]{64}$'),
  currency text not null default 'EUR' check (currency = 'EUR'),
  period_start date not null,
  period_end date not null,
  status text not null default 'processing'
    check (status in ('processing', 'processed', 'failed', 'reconciled')),
  line_count integer not null default 0 check (line_count >= 0),
  imported_by uuid references public.profiles(id) on delete set null,
  import_reason text not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (period_end >= period_start)
);

create table public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.bank_statement_imports(id) on delete restrict,
  line_number integer not null check (line_number > 0),
  transaction_key text not null check (transaction_key ~ '^[0-9a-f]{64}$'),
  bank_transaction_id text,
  end_to_end_id text,
  transfer_reference text,
  payer_name text,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  booked_at timestamptz not null,
  value_date date not null,
  match_status text not null default 'unmatched'
    check (match_status in ('unmatched', 'matched', 'exception', 'ignored')),
  created_at timestamptz not null default now(),
  unique (import_id, line_number),
  unique (transaction_key)
);

create index bank_statement_lines_match_idx
  on public.bank_statement_lines (currency, value_date, match_status);

create table public.reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  run_date date not null,
  currency text not null default 'EUR' check (currency = 'EUR'),
  status text not null default 'running'
    check (status in ('running', 'completed', 'completed_with_exceptions', 'failed')),
  statement_line_count integer not null default 0,
  matched_count integer not null default 0,
  exception_count integer not null default 0,
  statement_total_minor bigint not null default 0,
  matched_total_minor bigint not null default 0,
  reason text not null,
  started_by uuid references public.profiles(id) on delete set null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (run_date, currency)
);

create table public.reconciliation_matches (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.reconciliation_runs(id) on delete restrict,
  statement_line_id uuid unique not null references public.bank_statement_lines(id) on delete restrict,
  bank_transaction_id uuid unique not null references public.bank_transactions(id) on delete restrict,
  match_method text not null check (match_method in ('bank_transaction_id', 'end_to_end_id', 'reference_amount')),
  created_at timestamptz not null default now()
);

create table public.reconciliation_exceptions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references public.reconciliation_runs(id) on delete restrict,
  bank_transaction_id uuid references public.bank_transactions(id) on delete restrict,
  statement_line_id uuid references public.bank_statement_lines(id) on delete restrict,
  bank_transfer_intent_id uuid references public.bank_transfer_intents(id) on delete restrict,
  exception_type text not null check (exception_type in (
    'missing_reference', 'no_exact_intent', 'ambiguous_intent',
    'unmatched_statement_line', 'missing_statement_confirmation',
    'amount_mismatch', 'currency_mismatch', 'duplicate_evidence', 'returned_transfer'
  )),
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  details jsonb not null default '{}'::jsonb,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index reconciliation_exceptions_open_idx
  on public.reconciliation_exceptions (status, exception_type, created_at desc);

create table public.daily_bank_closes (
  id uuid primary key default gen_random_uuid(),
  close_date date not null,
  currency text not null default 'EUR' check (currency = 'EUR'),
  statement_total_minor bigint not null default 0,
  reconciled_total_minor bigint not null default 0,
  variance_minor bigint not null default 0,
  transaction_count integer not null default 0,
  exception_count integer not null default 0,
  status text not null default 'open' check (status in ('open', 'balanced', 'exception', 'reopened')),
  reconciliation_run_id uuid references public.reconciliation_runs(id) on delete restrict,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  reopened_at timestamptz,
  reopened_by uuid references public.profiles(id) on delete set null,
  reopen_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (close_date, currency)
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  bank_transaction_id uuid references public.bank_transactions(id) on delete restrict,
  collection_id uuid references public.collections(id) on delete restrict,
  entry_type text not null check (entry_type in ('bank_receipt', 'bank_return', 'manual_adjustment')),
  currency text not null default 'EUR' check (currency = 'EUR'),
  external_reference text not null,
  description text not null,
  posted_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (bank_transaction_id, entry_type)
);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  account_code text not null,
  collection_id uuid references public.collections(id) on delete restrict,
  contributor_user_id uuid references public.profiles(id) on delete set null,
  direction text not null check (direction in ('debit', 'credit')),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (journal_entry_id, account_code, direction)
);

create index journal_lines_collection_idx
  on public.journal_lines (collection_id, currency, created_at desc);

alter table public.notification_events
  add column if not exists bank_transfer_intent_id uuid
    references public.bank_transfer_intents(id) on delete set null;
create unique index if not exists notification_events_bank_intent_confirmed_idx
  on public.notification_events (bank_transfer_intent_id, type)
  where bank_transfer_intent_id is not null and type = 'contribution_confirmed';

insert into public.bank_transfer_destinations (
  version, beneficiary_name, iban, bic, bank_name, currency,
  supports_instant, status, is_placeholder, change_reason
) values (
  1,
  'PLACEHOLDER — DO NOT TRANSFER',
  'XX00PLACEHOLDER0000000000',
  'PLACEHOL',
  'PLACEHOLDER BANK',
  'EUR',
  true,
  'draft',
  true,
  'Non-routable placeholder required by the bank-transfer-only product definition'
) on conflict (currency, version) do nothing;

insert into public.feature_flags (key, enabled, description, metadata, updated_reason)
values (
  'bank_transfer_v1',
  false,
  'Enable EUR SEPA bank-transfer contribution creation only after a real beneficiary is maker-checker approved.',
  jsonb_build_object('rail', 'sepa_credit_transfer', 'payment_api', false),
  'Bank-transfer-only implementation installed with a disabled placeholder destination'
) on conflict (key) do update set
  description = excluded.description,
  metadata = excluded.metadata,
  enabled = case when public.feature_flags.enabled then true else false end;

insert into public.admin_permissions (name, description)
values
  ('bank_details.read', 'Read full active bank beneficiary details'),
  ('bank_details.propose', 'Propose a bank beneficiary change'),
  ('bank_details.approve', 'Approve another administrator bank beneficiary proposal'),
  ('bank_evidence.read', 'Read bank evidence metadata'),
  ('bank_evidence.ingest', 'Ingest beneficiary-bank SMS evidence from a controlled device'),
  ('bank_evidence.raw.reveal', 'Reveal raw bank evidence with an audited reason'),
  ('bank_transactions.read', 'Read canonical bank transactions'),
  ('bank_reconciliation.read', 'Read statement imports, reconciliation runs, exceptions, and closes'),
  ('bank_reconciliation.manage', 'Import statements and run or reopen daily reconciliation')
on conflict (name) do update set description = excluded.description;

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, desired.permission_name
from public.admin_roles role
join (
  values
    ('platform_owner', 'bank_details.read'),
    ('platform_owner', 'bank_details.propose'),
    ('platform_owner', 'bank_details.approve'),
    ('platform_owner', 'bank_evidence.read'),
    ('platform_owner', 'bank_evidence.ingest'),
    ('platform_owner', 'bank_evidence.raw.reveal'),
    ('platform_owner', 'bank_transactions.read'),
    ('platform_owner', 'bank_reconciliation.read'),
    ('platform_owner', 'bank_reconciliation.manage'),
    ('payments_admin', 'bank_details.read'),
    ('payments_admin', 'bank_evidence.read'),
    ('payments_admin', 'bank_evidence.ingest'),
    ('payments_admin', 'bank_transactions.read'),
    ('payments_admin', 'bank_reconciliation.read'),
    ('payments_admin', 'bank_reconciliation.manage'),
    ('operations_admin', 'bank_details.read'),
    ('operations_admin', 'bank_evidence.read'),
    ('operations_admin', 'bank_evidence.ingest'),
    ('operations_admin', 'bank_transactions.read'),
    ('operations_admin', 'bank_reconciliation.read'),
    ('compliance_admin', 'bank_details.read'),
    ('compliance_admin', 'bank_evidence.read'),
    ('compliance_admin', 'bank_evidence.raw.reveal'),
    ('compliance_admin', 'bank_transactions.read'),
    ('compliance_admin', 'bank_reconciliation.read'),
    ('read_only_admin', 'bank_transactions.read'),
    ('read_only_admin', 'bank_reconciliation.read')
) as desired(role_name, permission_name)
  on desired.role_name = role.name
on conflict (role_id, permission_name) do nothing;

alter table public.bank_transfer_destinations enable row level security;
alter table public.bank_destination_change_requests enable row level security;
alter table public.bank_transfer_intents enable row level security;
alter table public.raw_payment_evidence enable row level security;
alter table public.bank_evidence_events enable row level security;
alter table public.bank_transactions enable row level security;
alter table public.payment_evidence_links enable row level security;
alter table public.bank_transaction_allocations enable row level security;
alter table public.bank_statement_imports enable row level security;
alter table public.bank_statement_lines enable row level security;
alter table public.reconciliation_runs enable row level security;
alter table public.reconciliation_matches enable row level security;
alter table public.reconciliation_exceptions enable row level security;
alter table public.daily_bank_closes enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

create policy bank_transfer_intents_owner_read
on public.bank_transfer_intents for select to authenticated
using ((select auth.uid()) = contributor_user_id);

revoke all on public.bank_transfer_destinations from public, anon, authenticated;
revoke all on public.bank_destination_change_requests from public, anon, authenticated;
revoke all on public.bank_transfer_intents from public, anon, authenticated;
revoke all on public.raw_payment_evidence from public, anon, authenticated;
revoke all on public.bank_evidence_events from public, anon, authenticated;
revoke all on public.bank_transactions from public, anon, authenticated;
revoke all on public.payment_evidence_links from public, anon, authenticated;
revoke all on public.bank_transaction_allocations from public, anon, authenticated;
revoke all on public.bank_statement_imports from public, anon, authenticated;
revoke all on public.bank_statement_lines from public, anon, authenticated;
revoke all on public.reconciliation_runs from public, anon, authenticated;
revoke all on public.reconciliation_matches from public, anon, authenticated;
revoke all on public.reconciliation_exceptions from public, anon, authenticated;
revoke all on public.daily_bank_closes from public, anon, authenticated;
revoke all on public.journal_entries from public, anon, authenticated;
revoke all on public.journal_lines from public, anon, authenticated;

create or replace function public.normalize_iban(p_iban text)
returns text
language sql
immutable
set search_path = public
as $$
  select upper(regexp_replace(coalesce(p_iban, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.mask_iban(p_iban text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when char_length(public.normalize_iban(p_iban)) < 8 then 'Unavailable'
    else left(public.normalize_iban(p_iban), 4)
      || repeat('•', greatest(char_length(public.normalize_iban(p_iban)) - 8, 4))
      || right(public.normalize_iban(p_iban), 4)
  end;
$$;

create or replace function public.bank_transfer_destination_json(
  p_destination public.bank_transfer_destinations
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_destination.id,
    'version', p_destination.version,
    'beneficiary_name', p_destination.beneficiary_name,
    'iban', public.normalize_iban(p_destination.iban),
    'iban_masked', public.mask_iban(p_destination.iban),
    'bic', upper(regexp_replace(p_destination.bic, '[^A-Za-z0-9]', '', 'g')),
    'bank_name', p_destination.bank_name,
    'currency', p_destination.currency,
    'transfer_scheme', p_destination.transfer_scheme,
    'supports_instant', p_destination.supports_instant,
    'status', p_destination.status,
    'is_placeholder', p_destination.is_placeholder,
    'enabled', p_destination.status = 'active' and not p_destination.is_placeholder
  );
$$;

create or replace function public.get_bank_transfer_destination()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  destination public.bank_transfer_destinations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into destination
  from public.bank_transfer_destinations
  where currency = 'EUR'
  order by (status = 'active') desc, version desc
  limit 1;

  if destination.id is null then
    return '{}'::jsonb;
  end if;
  return public.bank_transfer_destination_json(destination);
end;
$$;

create or replace function public.create_bank_transfer_intent(
  p_collection_id uuid,
  p_amount_minor bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  collection_row public.collections%rowtype;
  destination public.bank_transfer_destinations%rowtype;
  intent public.bank_transfer_intents%rowtype;
  reference_value text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Contribution amount must be above zero';
  end if;
  if p_amount_minor > 999999999999 then
    raise exception 'Contribution amount exceeds the supported limit';
  end if;
  if not coalesce((
    select enabled from public.feature_flags where key = 'bank_transfer_v1'
  ), false) then
    raise exception 'Bank transfers are not active yet';
  end if;

  select * into collection_row
  from public.collections
  where id = p_collection_id
    and archived_at is null
    and public_status <> 'archived';
  if collection_row.id is null then
    raise exception 'Collection is unavailable';
  end if;
  if collection_row.creator_user_id <> auth.uid()
     and not exists (
       select 1 from public.collection_members member
       where member.collection_id = collection_row.id
         and member.user_id = auth.uid()
         and member.status = 'active'
     ) then
    raise exception 'Join this group before contributing';
  end if;

  select * into destination
  from public.bank_transfer_destinations
  where currency = 'EUR'
    and status = 'active'
    and not is_placeholder
  order by version desc
  limit 1;
  if destination.id is null then
    raise exception 'Approved bank transfer details are not available';
  end if;

  update public.bank_transfer_intents
  set status = 'expired', updated_at = now()
  where contributor_user_id = auth.uid()
    and status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence')
    and expires_at <= now();

  select * into intent
  from public.bank_transfer_intents
  where collection_id = collection_row.id
    and contributor_user_id = auth.uid()
    and destination_id = destination.id
    and amount_minor = p_amount_minor
    and currency = 'EUR'
    and status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence')
    and expires_at > now()
  order by created_at desc
  limit 1;

  if intent.id is null then
    loop
      reference_value := 'COL-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
      exit when not exists (
        select 1 from public.bank_transfer_intents where transfer_reference = reference_value
      );
    end loop;

    insert into public.bank_transfer_intents (
      collection_id,
      contributor_user_id,
      destination_id,
      destination_snapshot,
      transfer_reference,
      amount_minor,
      currency
    ) values (
      collection_row.id,
      auth.uid(),
      destination.id,
      public.bank_transfer_destination_json(destination),
      reference_value,
      p_amount_minor,
      'EUR'
    ) returning * into intent;

    perform public.create_audit_log(
      'bank_transfer.intent.created',
      'bank_transfer_intent',
      intent.id,
      jsonb_build_object(
        'collection_id', intent.collection_id,
        'amount_minor', intent.amount_minor,
        'currency', intent.currency,
        'destination_version', destination.version
      )
    );
  end if;

  return to_jsonb(intent) || jsonb_build_object(
    'destination', public.bank_transfer_destination_json(destination),
    'collection_title', collection_row.title
  );
end;
$$;

create or replace function public.list_current_user_bank_transfer_intents()
returns table (
  id uuid,
  collection_id uuid,
  collection_title text,
  contributor_user_id uuid,
  destination_id uuid,
  destination jsonb,
  transfer_reference text,
  amount_minor bigint,
  currency text,
  status text,
  handoff_opened_at timestamptz,
  evidence_received_at timestamptz,
  reconciled_at timestamptz,
  exception_reason text,
  created_at timestamptz,
  updated_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    intent.id,
    intent.collection_id,
    collection.title,
    intent.contributor_user_id,
    intent.destination_id,
    intent.destination_snapshot,
    intent.transfer_reference,
    intent.amount_minor,
    intent.currency,
    case
      when intent.status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence')
        and intent.expires_at <= now() then 'expired'
      else intent.status
    end,
    intent.handoff_opened_at,
    intent.evidence_received_at,
    intent.reconciled_at,
    intent.exception_reason,
    intent.created_at,
    intent.updated_at,
    intent.expires_at
  from public.bank_transfer_intents intent
  join public.collections collection on collection.id = intent.collection_id
  where intent.contributor_user_id = auth.uid()
  order by intent.created_at desc;
$$;

create or replace function public.get_bank_transfer_intent(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select to_jsonb(intent) || jsonb_build_object(
    'destination', intent.destination_snapshot,
    'collection_title', collection.title
  ) into result
  from public.bank_transfer_intents intent
  join public.collections collection on collection.id = intent.collection_id
  where intent.id = p_id
    and intent.contributor_user_id = auth.uid();
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.mark_bank_transfer_handoff_opened(p_intent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  intent public.bank_transfer_intents%rowtype;
begin
  update public.bank_transfer_intents
  set status = case when status = 'awaiting_transfer' then 'handoff_opened' else status end,
      handoff_opened_at = coalesce(handoff_opened_at, now()),
      updated_at = now()
  where id = p_intent_id
    and contributor_user_id = auth.uid()
    and status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence')
    and expires_at > now()
  returning * into intent;
  if intent.id is null then
    raise exception 'Active bank transfer request not found';
  end if;
  return to_jsonb(intent);
end;
$$;

create or replace function public.cancel_bank_transfer_intent(p_intent_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bank_transfer_intents
  set status = 'cancelled', updated_at = now()
  where id = p_intent_id
    and contributor_user_id = auth.uid()
    and status in ('awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence');
end;
$$;

revoke execute on function public.normalize_iban(text) from public, anon, authenticated;
revoke execute on function public.mask_iban(text) from public, anon;
revoke execute on function public.bank_transfer_destination_json(public.bank_transfer_destinations) from public, anon, authenticated;
revoke execute on function public.get_bank_transfer_destination() from public, anon;
revoke execute on function public.create_bank_transfer_intent(uuid, bigint) from public, anon;
revoke execute on function public.list_current_user_bank_transfer_intents() from public, anon;
revoke execute on function public.get_bank_transfer_intent(uuid) from public, anon;
revoke execute on function public.mark_bank_transfer_handoff_opened(uuid) from public, anon;
revoke execute on function public.cancel_bank_transfer_intent(uuid) from public, anon;
grant execute on function public.mask_iban(text) to authenticated, service_role;
grant execute on function public.get_bank_transfer_destination() to authenticated;
grant execute on function public.create_bank_transfer_intent(uuid, bigint) to authenticated;
grant execute on function public.list_current_user_bank_transfer_intents() to authenticated;
grant execute on function public.get_bank_transfer_intent(uuid) to authenticated;
grant execute on function public.mark_bank_transfer_handoff_opened(uuid) to authenticated;
grant execute on function public.cancel_bank_transfer_intent(uuid) to authenticated;

create or replace function public.ingest_bank_evidence(
  p_channel text,
  p_source_uid text,
  p_raw_sender text,
  p_raw_body text,
  p_received_at timestamptz,
  p_direction text,
  p_amount_minor bigint,
  p_currency text,
  p_bank_transaction_id text default null,
  p_end_to_end_id text default null,
  p_transfer_reference text default null,
  p_payer_name text default null,
  p_payer_account_last4 text default null,
  p_occurred_at timestamptz default null,
  p_confidence numeric default 0,
  p_parser_name text default 'collect.bank_rules.v1',
  p_parsed_json jsonb default '{}'::jsonb,
  p_headers jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  evidence public.raw_payment_evidence%rowtype;
  event public.bank_evidence_events%rowtype;
  transaction public.bank_transactions%rowtype;
  intent public.bank_transfer_intents%rowtype;
  allocation public.bank_transaction_allocations%rowtype;
  clean_channel text := lower(btrim(coalesce(p_channel, '')));
  clean_currency text := upper(btrim(coalesce(p_currency, 'unknown')));
  clean_reference text := upper(regexp_replace(btrim(coalesce(p_transfer_reference, '')), '[^A-Za-z0-9-]', '', 'g'));
  clean_bank_id text := nullif(upper(btrim(coalesce(p_bank_transaction_id, ''))), '');
  clean_end_to_end text := nullif(upper(btrim(coalesce(p_end_to_end_id, ''))), '');
  clean_last4 text := nullif(upper(regexp_replace(coalesce(p_payer_account_last4, ''), '[^A-Za-z0-9]', '', 'g')), '');
  body_digest text;
  transaction_key_value text;
  candidate_count integer := 0;
  exception_kind text;
begin
  if auth.role() <> 'service_role'
     and not public.has_admin_permission('bank_evidence.ingest', auth.uid()) then
    raise exception 'Bank evidence ingestion permission required';
  end if;
  if clean_channel not in ('sms', 'email', 'statement') then
    raise exception 'Unsupported evidence channel';
  end if;
  if nullif(btrim(coalesce(p_source_uid, '')), '') is null then
    raise exception 'Evidence source UID is required';
  end if;
  if nullif(btrim(coalesce(p_raw_sender, '')), '') is null then
    raise exception 'Evidence sender is required';
  end if;
  if nullif(p_raw_body, '') is null or octet_length(p_raw_body) > 200000 then
    raise exception 'Evidence body is required and must be at most 200 KB';
  end if;
  if p_received_at is null or p_received_at > now() + interval '5 minutes' then
    raise exception 'Evidence received timestamp is invalid';
  end if;
  if p_confidence < 0 or p_confidence > 1 then
    raise exception 'Evidence confidence must be between zero and one';
  end if;
  if clean_last4 is not null and clean_last4 !~ '^[A-Z0-9]{4}$' then
    clean_last4 := null;
  end if;

  body_digest := encode(extensions.digest(convert_to(p_raw_body, 'UTF8'), 'sha256'), 'hex');

  insert into public.raw_payment_evidence (
    channel, source_uid, raw_sender, raw_body, body_hash,
    headers, received_at, parse_status
  ) values (
    clean_channel,
    btrim(p_source_uid),
    btrim(p_raw_sender),
    p_raw_body,
    body_digest,
    coalesce(p_headers, '{}'::jsonb),
    p_received_at,
    'pending'
  )
  on conflict (channel, source_uid) do nothing
  returning * into evidence;

  if evidence.id is null then
    select * into evidence
    from public.raw_payment_evidence
    where channel = clean_channel and source_uid = btrim(p_source_uid);
    if evidence.body_hash <> body_digest then
      raise exception 'Evidence source UID was reused with different content';
    end if;
  end if;

  select * into event
  from public.bank_evidence_events
  where raw_evidence_id = evidence.id;

  if event.id is null then
    insert into public.bank_evidence_events (
      raw_evidence_id,
      direction,
      amount_minor,
      currency,
      bank_transaction_id,
      end_to_end_id,
      transfer_reference,
      payer_name,
      payer_account_last4,
      occurred_at,
      confidence,
      parser_name,
      parsed_json,
      allocation_status,
      review_reason
    ) values (
      evidence.id,
      case when p_direction in ('incoming', 'outgoing') then p_direction else 'unknown' end,
      case when p_amount_minor > 0 then p_amount_minor else null end,
      case when clean_currency = 'EUR' then 'EUR' else 'unknown' end,
      clean_bank_id,
      clean_end_to_end,
      nullif(clean_reference, ''),
      nullif(btrim(coalesce(p_payer_name, '')), ''),
      clean_last4,
      coalesce(p_occurred_at, p_received_at),
      p_confidence,
      coalesce(nullif(btrim(p_parser_name), ''), 'collect.bank_rules.v1'),
      coalesce(p_parsed_json, '{}'::jsonb),
      'unallocated',
      null
    ) returning * into event;
  end if;

  if event.direction <> 'incoming'
     or event.amount_minor is null
     or event.currency <> 'EUR'
     or event.confidence < 0.90 then
    update public.bank_evidence_events
    set allocation_status = 'needs_review',
        review_reason = 'Evidence is incomplete, non-incoming, non-EUR, or below the 0.90 threshold'
    where id = event.id
    returning * into event;
    update public.raw_payment_evidence set parse_status = 'needs_review' where id = evidence.id;
    return jsonb_build_object(
      'evidence_id', evidence.id,
      'event_id', event.id,
      'status', 'needs_review'
    );
  end if;

  transaction_key_value := encode(extensions.digest(convert_to(
    case
      when clean_bank_id is not null then 'bank:' || clean_bank_id
      when clean_end_to_end is not null then 'end-to-end:' || clean_end_to_end
      else 'composite:' || event.currency || '|' || event.amount_minor::text || '|' ||
        coalesce(nullif(clean_reference, ''), '') || '|' ||
        coalesce(event.occurred_at::date::text, p_received_at::date::text) || '|' ||
        coalesce(lower(btrim(event.payer_name)), '')
    end,
    'UTF8'
  ), 'sha256'), 'hex');

  insert into public.bank_transactions (
    transaction_key,
    bank_transaction_id,
    end_to_end_id,
    transfer_reference,
    payer_name,
    payer_account_last4,
    amount_minor,
    currency,
    occurred_at,
    value_date,
    evidence_received_at
  ) values (
    transaction_key_value,
    clean_bank_id,
    clean_end_to_end,
    nullif(clean_reference, ''),
    event.payer_name,
    event.payer_account_last4,
    event.amount_minor,
    event.currency,
    coalesce(event.occurred_at, p_received_at),
    coalesce(event.occurred_at, p_received_at)::date,
    p_received_at
  )
  on conflict (transaction_key) do update set
    bank_transaction_id = coalesce(public.bank_transactions.bank_transaction_id, excluded.bank_transaction_id),
    end_to_end_id = coalesce(public.bank_transactions.end_to_end_id, excluded.end_to_end_id),
    transfer_reference = coalesce(public.bank_transactions.transfer_reference, excluded.transfer_reference),
    payer_name = coalesce(public.bank_transactions.payer_name, excluded.payer_name),
    payer_account_last4 = coalesce(public.bank_transactions.payer_account_last4, excluded.payer_account_last4),
    evidence_received_at = least(public.bank_transactions.evidence_received_at, excluded.evidence_received_at),
    updated_at = now()
  returning * into transaction;

  insert into public.payment_evidence_links (bank_transaction_id, evidence_event_id)
  values (transaction.id, event.id)
  on conflict (evidence_event_id) do nothing;

  if nullif(clean_reference, '') is not null then
    select count(*), (array_agg(candidate.id order by candidate.created_at))[1]
    into candidate_count, intent.id
    from public.bank_transfer_intents candidate
    where candidate.transfer_reference = clean_reference
      and candidate.amount_minor = event.amount_minor
      and candidate.currency = event.currency
      and candidate.status in (
        'awaiting_transfer', 'handoff_opened', 'awaiting_bank_evidence',
        'received_unreconciled'
      )
      and candidate.expires_at >= coalesce(event.occurred_at, p_received_at) - interval '2 hours';
  end if;

  if candidate_count = 1 then
    select * into intent from public.bank_transfer_intents where id = intent.id for update;
    insert into public.bank_transaction_allocations (
      bank_transaction_id,
      bank_transfer_intent_id,
      collection_id,
      contributor_user_id,
      allocation_method,
      confidence,
      reason,
      allocated_by
    ) values (
      transaction.id,
      intent.id,
      intent.collection_id,
      intent.contributor_user_id,
      'auto_exact_reference',
      event.confidence,
      'Exact unique transfer reference, amount, currency, and active intent window',
      case when auth.role() = 'service_role' then null else auth.uid() end
    )
    on conflict (bank_transaction_id) do update set
      bank_transfer_intent_id = excluded.bank_transfer_intent_id,
      collection_id = excluded.collection_id,
      contributor_user_id = excluded.contributor_user_id,
      confidence = greatest(public.bank_transaction_allocations.confidence, excluded.confidence),
      reason = excluded.reason
    returning * into allocation;

    update public.bank_transactions
    set destination_id = intent.destination_id,
        status = case when status = 'reconciled' then status else 'received' end,
        updated_at = now()
    where id = transaction.id
    returning * into transaction;

    update public.bank_transfer_intents
    set status = case when status = 'reconciled' then status else 'received_unreconciled' end,
        evidence_received_at = coalesce(evidence_received_at, p_received_at),
        updated_at = now()
    where id = intent.id
    returning * into intent;

    update public.bank_evidence_events
    set allocation_status = 'allocated',
        review_reason = 'Exact unique bank transfer intent match'
    where id = event.id
    returning * into event;
    update public.raw_payment_evidence set parse_status = 'parsed' where id = evidence.id;
  else
    exception_kind := case
      when nullif(clean_reference, '') is null then 'missing_reference'
      when candidate_count > 1 then 'ambiguous_intent'
      else 'no_exact_intent'
    end;
    insert into public.reconciliation_exceptions (
      bank_transaction_id,
      exception_type,
      details
    ) values (
      transaction.id,
      exception_kind,
      jsonb_build_object(
        'transfer_reference', nullif(clean_reference, ''),
        'amount_minor', event.amount_minor,
        'currency', event.currency,
        'candidate_count', candidate_count
      )
    );
    update public.bank_transactions
    set status = 'exception', updated_at = now()
    where id = transaction.id
    returning * into transaction;
    update public.bank_evidence_events
    set allocation_status = case when candidate_count > 1 then 'ambiguous' else 'needs_review' end,
        review_reason = exception_kind
    where id = event.id
    returning * into event;
    update public.raw_payment_evidence set parse_status = 'needs_review' where id = evidence.id;
  end if;

  perform public.create_audit_log(
    'bank_evidence.ingested',
    'bank_transaction',
    transaction.id,
    jsonb_build_object(
      'channel', clean_channel,
      'event_id', event.id,
      'allocation_status', event.allocation_status,
      'bank_transfer_intent_id', allocation.bank_transfer_intent_id,
      'transaction_key', transaction.transaction_key
    ),
    case when auth.role() = 'service_role' then null else auth.uid() end
  );

  return jsonb_build_object(
    'evidence_id', evidence.id,
    'event_id', event.id,
    'bank_transaction_id', transaction.id,
    'bank_transfer_intent_id', allocation.bank_transfer_intent_id,
    'status', event.allocation_status,
    'transaction_status', transaction.status
  );
end;
$$;

revoke execute on function public.ingest_bank_evidence(
  text, text, text, text, timestamptz, text, bigint, text,
  text, text, text, text, text, timestamptz, numeric, text, jsonb, jsonb
) from public, anon;
grant execute on function public.ingest_bank_evidence(
  text, text, text, text, timestamptz, text, bigint, text,
  text, text, text, text, text, timestamptz, numeric, text, jsonb, jsonb
) to authenticated, service_role;

create or replace function public.run_daily_bank_reconciliation(
  p_run_date date default current_date,
  p_reason text default 'scheduled daily reconciliation'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  run_row public.reconciliation_runs%rowtype;
  v_statement_count integer := 0;
  v_matched_count integer := 0;
  v_exception_count integer := 0;
  v_statement_total bigint := 0;
  v_matched_total bigint := 0;
  transitioned record;
begin
  if p_run_date is null or p_run_date > current_date then
    raise exception 'Reconciliation date must not be in the future';
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Reconciliation reason is required';
  end if;
  if auth.role() <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin')
     and not public.has_admin_permission('bank_reconciliation.manage', auth.uid()) then
    raise exception 'Bank reconciliation permission required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bank-reconciliation:EUR:' || p_run_date::text, 0));

  insert into public.reconciliation_runs (
    run_date, currency, status, reason, started_by, started_at, completed_at
  ) values (
    p_run_date,
    'EUR',
    'running',
    btrim(p_reason),
    case when auth.uid() is null then null else auth.uid() end,
    now(),
    null
  )
  on conflict (run_date, currency) do update set
    status = 'running',
    reason = excluded.reason,
    started_by = excluded.started_by,
    started_at = now(),
    completed_at = null
  returning * into run_row;

  insert into public.reconciliation_matches (
    run_id, statement_line_id, bank_transaction_id, match_method
  )
  select
    run_row.id,
    line.id,
    candidate.id,
    case
      when line.bank_transaction_id is not null
        and upper(line.bank_transaction_id) = upper(candidate.bank_transaction_id)
        then 'bank_transaction_id'
      when line.end_to_end_id is not null
        and upper(line.end_to_end_id) = upper(candidate.end_to_end_id)
        then 'end_to_end_id'
      else 'reference_amount'
    end
  from public.bank_statement_lines line
  join lateral (
    select transaction.*
    from public.bank_transactions transaction
    where transaction.currency = line.currency
      and transaction.amount_minor = line.amount_minor
      and (
        (line.bank_transaction_id is not null
          and transaction.bank_transaction_id is not null
          and upper(line.bank_transaction_id) = upper(transaction.bank_transaction_id))
        or (line.end_to_end_id is not null
          and transaction.end_to_end_id is not null
          and upper(line.end_to_end_id) = upper(transaction.end_to_end_id))
        or (line.transfer_reference is not null
          and transaction.transfer_reference is not null
          and upper(line.transfer_reference) = upper(transaction.transfer_reference)
          and abs(line.value_date - coalesce(transaction.value_date, transaction.occurred_at::date)) <= 2)
      )
    order by
      (line.bank_transaction_id is not null
        and transaction.bank_transaction_id is not null
        and upper(line.bank_transaction_id) = upper(transaction.bank_transaction_id)) desc,
      (line.end_to_end_id is not null
        and transaction.end_to_end_id is not null
        and upper(line.end_to_end_id) = upper(transaction.end_to_end_id)) desc,
      transaction.created_at
    limit 1
  ) candidate on true
  where line.currency = 'EUR'
    and line.value_date = p_run_date
  on conflict (statement_line_id) do nothing;

  update public.bank_statement_lines line
  set match_status = 'matched'
  from public.reconciliation_matches match
  where match.run_id = run_row.id
    and match.statement_line_id = line.id;

  for transitioned in
    select
      transaction.id as transaction_id,
      transaction.amount_minor,
      transaction.currency,
      transaction.transfer_reference,
      allocation.collection_id,
      allocation.contributor_user_id,
      allocation.bank_transfer_intent_id,
      intent.status as prior_intent_status
    from public.reconciliation_matches match
    join public.bank_transactions transaction on transaction.id = match.bank_transaction_id
    join public.bank_transaction_allocations allocation on allocation.bank_transaction_id = transaction.id
    join public.bank_transfer_intents intent on intent.id = allocation.bank_transfer_intent_id
    where match.run_id = run_row.id
    order by transaction.id
  loop
    update public.bank_transactions
    set status = 'reconciled',
        reconciled_at = coalesce(reconciled_at, now()),
        updated_at = now()
    where id = transitioned.transaction_id;

    update public.bank_transfer_intents
    set status = 'reconciled',
        reconciled_at = coalesce(reconciled_at, now()),
        updated_at = now()
    where id = transitioned.bank_transfer_intent_id;

    insert into public.journal_entries (
      bank_transaction_id,
      collection_id,
      entry_type,
      currency,
      external_reference,
      description,
      created_by
    ) values (
      transitioned.transaction_id,
      transitioned.collection_id,
      'bank_receipt',
      transitioned.currency,
      coalesce(transitioned.transfer_reference, transitioned.transaction_id::text),
      'Reconciled SEPA bank transfer receipt',
      case when auth.uid() is null then null else auth.uid() end
    )
    on conflict (bank_transaction_id, entry_type) do nothing;

    insert into public.journal_lines (
      journal_entry_id,
      account_code,
      collection_id,
      contributor_user_id,
      direction,
      amount_minor,
      currency,
      metadata
    )
    select
      entry.id,
      line.account_code,
      transitioned.collection_id,
      transitioned.contributor_user_id,
      line.direction,
      transitioned.amount_minor,
      transitioned.currency,
      jsonb_build_object(
        'bank_transaction_id', transitioned.transaction_id,
        'bank_transfer_intent_id', transitioned.bank_transfer_intent_id,
        'reconciliation_run_id', run_row.id
      )
    from public.journal_entries entry
    cross join (
      values
        ('bank_cash:EUR'::text, 'debit'::text),
        ('collection_liability'::text, 'credit'::text)
    ) as line(account_code, direction)
    where entry.bank_transaction_id = transitioned.transaction_id
      and entry.entry_type = 'bank_receipt'
    on conflict (journal_entry_id, account_code, direction) do nothing;

    if transitioned.prior_intent_status <> 'reconciled' then
      insert into public.notification_events (
        user_id,
        collection_id,
        bank_transfer_intent_id,
        type,
        title,
        body,
        deep_link
      ) values (
        transitioned.contributor_user_id,
        transitioned.collection_id,
        transitioned.bank_transfer_intent_id,
        'contribution_confirmed',
        'Bank transfer reconciled',
        'Your SEPA bank transfer has been reconciled and added to the confirmed group ledger.',
        '/groups/' || transitioned.collection_id::text || '/ledger'
      ) on conflict (bank_transfer_intent_id, type)
        where bank_transfer_intent_id is not null and type = 'contribution_confirmed'
        do nothing;
    end if;
  end loop;

  insert into public.reconciliation_exceptions (
    run_id, statement_line_id, exception_type, details
  )
  select
    run_row.id,
    line.id,
    'unmatched_statement_line',
    jsonb_build_object(
      'amount_minor', line.amount_minor,
      'currency', line.currency,
      'transfer_reference', line.transfer_reference,
      'value_date', line.value_date
    )
  from public.bank_statement_lines line
  where line.currency = 'EUR'
    and line.value_date = p_run_date
    and line.match_status = 'unmatched'
    and not exists (
      select 1 from public.reconciliation_exceptions exception
      where exception.statement_line_id = line.id
        and exception.exception_type = 'unmatched_statement_line'
        and exception.status in ('open', 'reviewing')
    );

  insert into public.reconciliation_exceptions (
    run_id, bank_transaction_id, bank_transfer_intent_id,
    exception_type, details
  )
  select
    run_row.id,
    transaction.id,
    allocation.bank_transfer_intent_id,
    'missing_statement_confirmation',
    jsonb_build_object(
      'amount_minor', transaction.amount_minor,
      'currency', transaction.currency,
      'transfer_reference', transaction.transfer_reference,
      'occurred_at', transaction.occurred_at
    )
  from public.bank_transactions transaction
  join public.bank_transaction_allocations allocation
    on allocation.bank_transaction_id = transaction.id
  where transaction.currency = 'EUR'
    and coalesce(transaction.value_date, transaction.occurred_at::date) <= p_run_date
    and transaction.status = 'received'
    and not exists (
      select 1 from public.reconciliation_matches match
      where match.bank_transaction_id = transaction.id
    )
    and not exists (
      select 1 from public.reconciliation_exceptions exception
      where exception.bank_transaction_id = transaction.id
        and exception.exception_type = 'missing_statement_confirmation'
        and exception.status in ('open', 'reviewing')
    );

  update public.bank_statement_imports import
  set status = case
        when exists (
          select 1 from public.bank_statement_lines line
          where line.import_id = import.id and line.match_status in ('unmatched', 'exception')
        ) then 'processed'
        else 'reconciled'
      end,
      completed_at = now()
  where import.currency = 'EUR'
    and import.period_start <= p_run_date
    and import.period_end >= p_run_date;

  select count(*), coalesce(sum(amount_minor), 0)
  into v_statement_count, v_statement_total
  from public.bank_statement_lines
  where currency = 'EUR' and value_date = p_run_date;

  select count(*), coalesce(sum(line.amount_minor), 0)
  into v_matched_count, v_matched_total
  from public.reconciliation_matches match
  join public.bank_statement_lines line on line.id = match.statement_line_id
  where match.run_id = run_row.id;

  select count(*) into v_exception_count
  from public.reconciliation_exceptions
  where run_id = run_row.id and status in ('open', 'reviewing');

  update public.reconciliation_runs
  set status = case when v_exception_count = 0 then 'completed' else 'completed_with_exceptions' end,
      statement_line_count = v_statement_count,
      matched_count = v_matched_count,
      exception_count = v_exception_count,
      statement_total_minor = v_statement_total,
      matched_total_minor = v_matched_total,
      completed_at = now()
  where id = run_row.id
  returning * into run_row;

  insert into public.daily_bank_closes (
    close_date,
    currency,
    statement_total_minor,
    reconciled_total_minor,
    variance_minor,
    transaction_count,
    exception_count,
    status,
    reconciliation_run_id,
    closed_at,
    closed_by
  ) values (
    p_run_date,
    'EUR',
    v_statement_total,
    v_matched_total,
    v_statement_total - v_matched_total,
    v_matched_count,
    v_exception_count,
    case
      when v_exception_count = 0 and v_statement_total = v_matched_total then 'balanced'
      else 'exception'
    end,
    run_row.id,
    case
      when v_exception_count = 0 and v_statement_total = v_matched_total then now()
      else null
    end,
    case
      when v_exception_count = 0 and v_statement_total = v_matched_total then auth.uid()
      else null
    end
  ) on conflict (close_date, currency) do update set
    statement_total_minor = excluded.statement_total_minor,
    reconciled_total_minor = excluded.reconciled_total_minor,
    variance_minor = excluded.variance_minor,
    transaction_count = excluded.transaction_count,
    exception_count = excluded.exception_count,
    status = excluded.status,
    reconciliation_run_id = excluded.reconciliation_run_id,
    closed_at = excluded.closed_at,
    closed_by = excluded.closed_by,
    updated_at = now();

  perform public.create_audit_log(
    'bank_reconciliation.completed',
    'reconciliation_run',
    run_row.id,
    jsonb_build_object(
      'run_date', p_run_date,
      'currency', 'EUR',
      'statement_line_count', v_statement_count,
      'matched_count', v_matched_count,
      'exception_count', v_exception_count,
      'statement_total_minor', v_statement_total,
      'matched_total_minor', v_matched_total
    ),
    auth.uid()
  );

  return to_jsonb(run_row) || jsonb_build_object(
    'variance_minor', v_statement_total - v_matched_total
  );
exception
  when others then
    if run_row.id is not null then
      update public.reconciliation_runs
      set status = 'failed', completed_at = now()
      where id = run_row.id;
    end if;
    raise;
end;
$$;

create or replace function public.admin_import_bank_statement(
  p_file_name text,
  p_file_hash text,
  p_period_start date,
  p_period_end date,
  p_lines jsonb,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  import_row public.bank_statement_imports%rowtype;
  line jsonb;
  line_number integer := 0;
  line_amount bigint;
  line_booked timestamptz;
  line_value_date date;
  line_key text;
  reconciliation jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.manage');
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Import reason is required';
  end if;
  if p_file_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Statement file hash must be lowercase SHA-256';
  end if;
  if p_period_end < p_period_start then
    raise exception 'Statement period is invalid';
  end if;
  if jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0
     or jsonb_array_length(p_lines) > 5000 then
    raise exception 'Statement must contain between 1 and 5000 lines';
  end if;

  insert into public.bank_statement_imports (
    file_name, file_hash, currency, period_start, period_end,
    status, line_count, imported_by, import_reason
  ) values (
    btrim(p_file_name), lower(p_file_hash), 'EUR', p_period_start, p_period_end,
    'processing', jsonb_array_length(p_lines), auth.uid(), btrim(p_reason)
  )
  on conflict (file_hash) do nothing
  returning * into import_row;

  if import_row.id is null then
    raise exception 'Statement file was already imported';
  end if;

  for line in select value from jsonb_array_elements(p_lines)
  loop
    line_number := line_number + 1;
    line_amount := (line ->> 'amount_minor')::bigint;
    line_booked := (line ->> 'booked_at')::timestamptz;
    line_value_date := coalesce((line ->> 'value_date')::date, line_booked::date);
    if line_amount <= 0 then
      raise exception 'Statement line % amount must be positive', line_number;
    end if;
    if upper(coalesce(line ->> 'currency', 'EUR')) <> 'EUR' then
      raise exception 'Statement line % currency must be EUR', line_number;
    end if;
    if line_value_date < p_period_start or line_value_date > p_period_end then
      raise exception 'Statement line % is outside the declared period', line_number;
    end if;

    line_key := encode(extensions.digest(convert_to(
      coalesce(upper(btrim(line ->> 'bank_transaction_id')), '') || '|' ||
      coalesce(upper(btrim(line ->> 'end_to_end_id')), '') || '|' ||
      coalesce(upper(btrim(line ->> 'transfer_reference')), '') || '|' ||
      line_amount::text || '|EUR|' || line_value_date::text,
      'UTF8'
    ), 'sha256'), 'hex');

    insert into public.bank_statement_lines (
      import_id,
      line_number,
      transaction_key,
      bank_transaction_id,
      end_to_end_id,
      transfer_reference,
      payer_name,
      amount_minor,
      currency,
      booked_at,
      value_date
    ) values (
      import_row.id,
      line_number,
      line_key,
      nullif(upper(btrim(line ->> 'bank_transaction_id')), ''),
      nullif(upper(btrim(line ->> 'end_to_end_id')), ''),
      nullif(upper(btrim(line ->> 'transfer_reference')), ''),
      nullif(btrim(line ->> 'payer_name'), ''),
      line_amount,
      'EUR',
      line_booked,
      line_value_date
    ) on conflict (transaction_key) do nothing;
  end loop;

  update public.bank_statement_imports
  set status = 'processed', completed_at = now()
  where id = import_row.id
  returning * into import_row;

  reconciliation := public.run_daily_bank_reconciliation(
    p_period_end,
    'Statement import ' || import_row.id::text || ': ' || btrim(p_reason)
  );

  perform public.create_audit_log(
    'bank_statement.imported',
    'bank_statement_import',
    import_row.id,
    jsonb_build_object(
      'file_name', import_row.file_name,
      'file_hash', import_row.file_hash,
      'line_count', import_row.line_count,
      'period_start', import_row.period_start,
      'period_end', import_row.period_end
    )
  );

  return to_jsonb(import_row) || jsonb_build_object('reconciliation', reconciliation);
end;
$$;

create or replace function public.admin_run_bank_reconciliation(
  p_run_date date,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('bank_reconciliation.manage');
  return public.run_daily_bank_reconciliation(p_run_date, p_reason);
end;
$$;

create or replace function public.admin_reopen_daily_bank_close(
  p_close_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  close_row public.daily_bank_closes%rowtype;
begin
  perform public.assert_admin_permission('bank_reconciliation.manage');
  if char_length(btrim(coalesce(p_reason, ''))) < 8 then
    raise exception 'Reopen reason must be at least 8 characters';
  end if;
  update public.daily_bank_closes
  set status = 'reopened',
      reopened_at = now(),
      reopened_by = auth.uid(),
      reopen_reason = btrim(p_reason),
      closed_at = null,
      closed_by = null,
      updated_at = now()
  where id = p_close_id
    and status in ('balanced', 'exception')
  returning * into close_row;
  if close_row.id is null then
    raise exception 'Daily close not found or already open';
  end if;
  perform public.create_audit_log(
    'bank_reconciliation.close_reopened',
    'daily_bank_close',
    close_row.id,
    jsonb_build_object('reason', btrim(p_reason))
  );
  return to_jsonb(close_row);
end;
$$;

revoke execute on function public.run_daily_bank_reconciliation(date, text) from public, anon;
revoke execute on function public.admin_import_bank_statement(text, text, date, date, jsonb, text) from public, anon;
revoke execute on function public.admin_run_bank_reconciliation(date, text) from public, anon;
revoke execute on function public.admin_reopen_daily_bank_close(uuid, text) from public, anon;
grant execute on function public.run_daily_bank_reconciliation(date, text) to authenticated, service_role;
grant execute on function public.admin_import_bank_statement(text, text, date, date, jsonb, text) to authenticated;
grant execute on function public.admin_run_bank_reconciliation(date, text) to authenticated;
grant execute on function public.admin_reopen_daily_bank_close(uuid, text) to authenticated;

create or replace function public.list_current_user_bank_contributions()
returns table (
  payment_id uuid,
  collection_id uuid,
  amount_rwf bigint,
  amount_minor bigint,
  currency text,
  posted_at timestamptz,
  transaction_id text,
  supporter_label text,
  is_current_user_contribution boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    transaction.id,
    allocation.collection_id,
    transaction.amount_minor,
    transaction.amount_minor,
    transaction.currency,
    transaction.reconciled_at,
    coalesce(transaction.bank_transaction_id, transaction.end_to_end_id),
    case
      when allocation.contributor_user_id = auth.uid() then 'Your contribution'
      else 'Collect member'
    end,
    allocation.contributor_user_id = auth.uid()
  from public.bank_transactions transaction
  join public.bank_transaction_allocations allocation
    on allocation.bank_transaction_id = transaction.id
  where transaction.status = 'reconciled'
    and (
      allocation.contributor_user_id = auth.uid()
      or public.user_can_read_collection(allocation.collection_id, auth.uid())
    )
  order by transaction.reconciled_at desc, transaction.created_at desc;
$$;

create or replace function public.list_current_user_bank_collection_summaries()
returns table (
  collection_id uuid,
  amount_raised_rwf bigint,
  amount_raised_minor bigint,
  supporter_count bigint,
  current_user_balance_rwf bigint,
  current_user_balance_minor bigint,
  currency text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    collection.id,
    coalesce(sum(transaction.amount_minor) filter (where transaction.status = 'reconciled'), 0)::bigint,
    coalesce(sum(transaction.amount_minor) filter (where transaction.status = 'reconciled'), 0)::bigint,
    count(distinct allocation.contributor_user_id) filter (where transaction.status = 'reconciled')::bigint,
    coalesce(sum(transaction.amount_minor) filter (
      where transaction.status = 'reconciled'
        and allocation.contributor_user_id = auth.uid()
    ), 0)::bigint,
    coalesce(sum(transaction.amount_minor) filter (
      where transaction.status = 'reconciled'
        and allocation.contributor_user_id = auth.uid()
    ), 0)::bigint,
    'EUR'::text
  from public.collections collection
  left join public.bank_transaction_allocations allocation
    on allocation.collection_id = collection.id
  left join public.bank_transactions transaction
    on transaction.id = allocation.bank_transaction_id
  where public.user_can_read_collection(collection.id, auth.uid())
  group by collection.id
  order by collection.id;
$$;

revoke execute on function public.list_current_user_bank_contributions()
  from public, anon;
revoke execute on function public.list_current_user_bank_collection_summaries()
  from public, anon;
grant execute on function public.list_current_user_bank_contributions()
  to authenticated;
grant execute on function public.list_current_user_bank_collection_summaries()
  to authenticated;

create or replace function public.admin_propose_bank_destination(
  p_beneficiary_name text,
  p_iban text,
  p_bic text,
  p_bank_name text,
  p_supports_instant boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.bank_destination_change_requests%rowtype;
  clean_iban text := public.normalize_iban(p_iban);
  clean_bic text := upper(regexp_replace(coalesce(p_bic, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  perform public.assert_admin_permission('bank_details.propose');
  if clean_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'
     or clean_iban like 'XX00%'
     or clean_iban like '%PLACEHOLDER%' then
    raise exception 'A valid non-placeholder IBAN is required';
  end if;
  if clean_bic !~ '^[A-Z0-9]{8}([A-Z0-9]{3})?$'
     or clean_bic like 'PLACEH%' then
    raise exception 'A valid non-placeholder BIC is required';
  end if;
  if char_length(btrim(coalesce(p_beneficiary_name, ''))) < 3
     or char_length(btrim(coalesce(p_bank_name, ''))) < 2 then
    raise exception 'Beneficiary and bank names are required';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 8 then
    raise exception 'Change reason must be at least 8 characters';
  end if;

  insert into public.bank_destination_change_requests (
    beneficiary_name, iban, bic, bank_name, currency,
    supports_instant, status, reason, proposed_by
  ) values (
    btrim(p_beneficiary_name), clean_iban, clean_bic, btrim(p_bank_name),
    'EUR', coalesce(p_supports_instant, true), 'pending', btrim(p_reason), auth.uid()
  ) returning * into request;

  perform public.create_audit_log(
    'bank_destination.change_proposed',
    'bank_destination_change_request',
    request.id,
    jsonb_build_object(
      'beneficiary_name', request.beneficiary_name,
      'iban_masked', public.mask_iban(request.iban),
      'bic', request.bic,
      'bank_name', request.bank_name,
      'supports_instant', request.supports_instant,
      'reason', request.reason
    )
  );
  return to_jsonb(request) - 'iban' || jsonb_build_object('iban_masked', public.mask_iban(request.iban));
end;
$$;

create or replace function public.admin_review_bank_destination_change(
  p_request_id uuid,
  p_approve boolean,
  p_review_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.bank_destination_change_requests%rowtype;
  destination public.bank_transfer_destinations%rowtype;
  next_version integer;
begin
  perform public.assert_admin_permission('bank_details.approve');
  if char_length(btrim(coalesce(p_review_note, ''))) < 8 then
    raise exception 'Review note must be at least 8 characters';
  end if;
  select * into request
  from public.bank_destination_change_requests
  where id = p_request_id
  for update;
  if request.id is null or request.status <> 'pending' then
    raise exception 'Pending bank destination change was not found';
  end if;
  if request.proposed_by = auth.uid() then
    raise exception 'Maker-checker control prohibits approving your own bank destination proposal';
  end if;

  if not p_approve then
    update public.bank_destination_change_requests
    set status = 'rejected',
        reviewed_by = auth.uid(),
        review_note = btrim(p_review_note),
        reviewed_at = now()
    where id = request.id
    returning * into request;
    perform public.create_audit_log(
      'bank_destination.change_rejected',
      'bank_destination_change_request',
      request.id,
      jsonb_build_object('review_note', request.review_note)
    );
    return to_jsonb(request) - 'iban' || jsonb_build_object('iban_masked', public.mask_iban(request.iban));
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bank-destination:EUR', 0));
  select coalesce(max(version), 0) + 1 into next_version
  from public.bank_transfer_destinations
  where currency = 'EUR';

  update public.bank_transfer_destinations
  set status = 'retired', retired_at = now(), updated_at = now()
  where currency = 'EUR' and status = 'active';

  insert into public.bank_transfer_destinations (
    version,
    beneficiary_name,
    iban,
    bic,
    bank_name,
    currency,
    supports_instant,
    status,
    is_placeholder,
    change_reason,
    created_by,
    approved_by,
    approved_at,
    activated_at
  ) values (
    next_version,
    request.beneficiary_name,
    request.iban,
    request.bic,
    request.bank_name,
    'EUR',
    request.supports_instant,
    'active',
    false,
    request.reason,
    request.proposed_by,
    auth.uid(),
    now(),
    now()
  ) returning * into destination;

  update public.bank_destination_change_requests
  set status = 'approved',
      reviewed_by = auth.uid(),
      review_note = btrim(p_review_note),
      reviewed_at = now(),
      destination_id = destination.id
  where id = request.id
  returning * into request;

  update public.feature_flags
  set enabled = true,
      updated_by = auth.uid(),
      updated_reason = 'Maker-checker approved bank destination version ' || destination.version::text,
      updated_at = now()
  where key = 'bank_transfer_v1';

  perform public.create_audit_log(
    'bank_destination.change_approved',
    'bank_transfer_destination',
    destination.id,
    jsonb_build_object(
      'request_id', request.id,
      'version', destination.version,
      'beneficiary_name', destination.beneficiary_name,
      'iban_masked', public.mask_iban(destination.iban),
      'bic', destination.bic,
      'bank_name', destination.bank_name,
      'review_note', request.review_note
    )
  );
  return public.bank_transfer_destination_json(destination);
end;
$$;

create or replace function public.admin_list_bank_destinations(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.assert_admin_permission('bank_details.read');
  with filtered as (
    select destination.*
    from public.bank_transfer_destinations destination
    where (p_status is null or destination.status = p_status)
      and (
        p_search is null
        or destination.beneficiary_name ilike '%' || p_search || '%'
        or destination.bank_name ilike '%' || p_search || '%'
        or destination.bic ilike '%' || p_search || '%'
      )
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id,
      beneficiary_name,
      bank_name || ' · ' || bic,
      status,
      currency || ' · ' || public.mask_iban(iban),
      created_at,
      jsonb_build_object('version', version, 'is_placeholder', is_placeholder)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_bank_destination(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  destination public.bank_transfer_destinations%rowtype;
begin
  perform public.assert_admin_permission('bank_details.read');
  select * into destination from public.bank_transfer_destinations where id = p_id;
  if destination.id is null then return '{}'::jsonb; end if;
  return public.bank_transfer_destination_json(destination) || jsonb_build_object(
    'change_reason', destination.change_reason,
    'created_by', destination.created_by,
    'approved_by', destination.approved_by,
    'approved_at', destination.approved_at,
    'activated_at', destination.activated_at,
    'retired_at', destination.retired_at,
    'created_at', destination.created_at,
    'updated_at', destination.updated_at
  );
end;
$$;

-- Pending beneficiary changes are separately visible so a checker can review
-- the exact proposal without relying on an out-of-band request identifier.
create or replace function public.admin_list_bank_destination_change_requests(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_details.read');
  with filtered as (
    select request.* from public.bank_destination_change_requests request
    where (p_status is null or request.status = p_status)
      and (p_search is null
        or request.beneficiary_name ilike '%' || p_search || '%'
        or request.bank_name ilike '%' || p_search || '%'
        or request.reason ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, beneficiary_name, bank_name || ' · ' || bic, status,
      currency || ' · ' || public.mask_iban(iban), created_at,
      jsonb_build_object('reason', reason, 'proposed_by', proposed_by)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_bank_destination_change_request(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare request public.bank_destination_change_requests%rowtype;
begin
  perform public.assert_admin_permission('bank_details.read');
  select * into request from public.bank_destination_change_requests where id = p_id;
  if request.id is null then return '{}'::jsonb; end if;
  return to_jsonb(request) - 'iban' || jsonb_build_object(
    'iban', public.normalize_iban(request.iban),
    'iban_masked', public.mask_iban(request.iban)
  );
end;
$$;

create or replace function public.admin_list_bank_transfer_intents(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_transactions.read');
  with filtered as (
    select intent.*, collection.title as collection_title
    from public.bank_transfer_intents intent
    join public.collections collection on collection.id = intent.collection_id
    where (p_status is null or intent.status = p_status)
      and (
        p_search is null
        or intent.transfer_reference ilike '%' || p_search || '%'
        or collection.title ilike '%' || p_search || '%'
      )
  ), counted as (
    select count(*) over () as total_count, filtered.*
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      case when p_sort = 'amount_asc' then amount_minor end asc nulls last,
      case when p_sort = 'amount_desc' then amount_minor end desc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, transfer_reference, collection_title, status,
      currency || ' ' || to_char(amount_minor::numeric / 100, 'FM999G999G999D00'),
      created_at,
      jsonb_build_object('collection_id', collection_id)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_bank_transfer_intent(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_transactions.read');
  select to_jsonb(intent) || jsonb_build_object(
    'collection_title', collection.title,
    'destination', intent.destination_snapshot,
    'allocation', coalesce(to_jsonb(allocation), '{}'::jsonb),
    'transaction', coalesce(to_jsonb(transaction), '{}'::jsonb)
  ) into result
  from public.bank_transfer_intents intent
  join public.collections collection on collection.id = intent.collection_id
  left join public.bank_transaction_allocations allocation
    on allocation.bank_transfer_intent_id = intent.id
  left join public.bank_transactions transaction
    on transaction.id = allocation.bank_transaction_id
  where intent.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

-- Manual allocation is a financial posting precursor and therefore uses a
-- separate maker-checker request instead of a direct mutable allocation API.
create table public.bank_allocation_change_requests (
  id uuid primary key default gen_random_uuid(),
  bank_transaction_id uuid not null references public.bank_transactions(id) on delete restrict,
  bank_transfer_intent_id uuid not null references public.bank_transfer_intents(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reason text not null check (char_length(btrim(reason)) >= 8),
  proposed_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete restrict,
  review_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint bank_allocation_change_maker_checker check (
    reviewed_by is null or reviewed_by <> proposed_by
  )
);

create unique index bank_allocation_change_one_pending_transaction_idx
  on public.bank_allocation_change_requests (bank_transaction_id)
  where status = 'pending';
create unique index bank_allocation_change_one_pending_intent_idx
  on public.bank_allocation_change_requests (bank_transfer_intent_id)
  where status = 'pending';

alter table public.bank_allocation_change_requests enable row level security;
revoke all on public.bank_allocation_change_requests from public, anon, authenticated;

insert into public.admin_permissions (name, description)
values
  ('bank_allocations.propose', 'Propose a manual bank transaction allocation'),
  ('bank_allocations.approve', 'Approve another administrator manual bank transaction allocation')
on conflict (name) do update set description = excluded.description;

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, desired.permission_name
from public.admin_roles role
join (
  values
    ('platform_owner', 'bank_allocations.propose'),
    ('platform_owner', 'bank_allocations.approve'),
    ('payments_admin', 'bank_allocations.propose'),
    ('payments_admin', 'bank_allocations.approve'),
    ('operations_admin', 'bank_allocations.propose'),
    ('compliance_admin', 'bank_allocations.approve')
) as desired(role_name, permission_name)
  on desired.role_name = role.name
on conflict (role_id, permission_name) do nothing;

create or replace function public.admin_propose_bank_allocation(
  p_bank_transaction_id uuid,
  p_bank_transfer_intent_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.bank_allocation_change_requests%rowtype;
  transaction_row public.bank_transactions%rowtype;
  intent public.bank_transfer_intents%rowtype;
begin
  perform public.assert_admin_permission('bank_allocations.propose');
  if char_length(btrim(coalesce(p_reason, ''))) < 8 then
    raise exception 'Allocation reason must be at least 8 characters';
  end if;
  select * into transaction_row
  from public.bank_transactions
  where id = p_bank_transaction_id
  for update;
  select * into intent
  from public.bank_transfer_intents
  where id = p_bank_transfer_intent_id
  for update;
  if transaction_row.id is null or intent.id is null then
    raise exception 'Bank transaction and transfer intent are required';
  end if;
  if transaction_row.currency <> intent.currency
     or transaction_row.amount_minor <> intent.amount_minor then
    raise exception 'Manual allocation requires an exact amount and currency match';
  end if;
  if transaction_row.status in ('reconciled', 'returned')
     or intent.status in ('reconciled', 'returned', 'cancelled', 'expired') then
    raise exception 'The transaction or transfer intent is no longer allocatable';
  end if;
  if exists (
    select 1 from public.bank_transaction_allocations allocation
    where allocation.bank_transaction_id = transaction_row.id
       or allocation.bank_transfer_intent_id = intent.id
  ) then
    raise exception 'The transaction or transfer intent is already allocated';
  end if;
  insert into public.bank_allocation_change_requests (
    bank_transaction_id, bank_transfer_intent_id, reason, proposed_by
  ) values (
    transaction_row.id, intent.id, btrim(p_reason), auth.uid()
  ) returning * into request;
  perform public.create_audit_log(
    'bank_allocation.proposed',
    'bank_allocation_change_request',
    request.id,
    jsonb_build_object(
      'bank_transaction_id', transaction_row.id,
      'bank_transfer_intent_id', intent.id,
      'reason', request.reason
    )
  );
  return to_jsonb(request);
end;
$$;

create or replace function public.admin_review_bank_allocation(
  p_request_id uuid,
  p_approve boolean,
  p_review_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.bank_allocation_change_requests%rowtype;
  transaction_row public.bank_transactions%rowtype;
  intent public.bank_transfer_intents%rowtype;
  allocation public.bank_transaction_allocations%rowtype;
begin
  perform public.assert_admin_permission('bank_allocations.approve');
  if char_length(btrim(coalesce(p_review_note, ''))) < 8 then
    raise exception 'Review note must be at least 8 characters';
  end if;
  select * into request
  from public.bank_allocation_change_requests
  where id = p_request_id
  for update;
  if request.id is null or request.status <> 'pending' then
    raise exception 'Pending allocation request was not found';
  end if;
  if request.proposed_by = auth.uid() then
    raise exception 'Maker-checker control prohibits approving your own allocation';
  end if;
  if not p_approve then
    update public.bank_allocation_change_requests
    set status = 'rejected', reviewed_by = auth.uid(),
        review_note = btrim(p_review_note), reviewed_at = now()
    where id = request.id
    returning * into request;
    perform public.create_audit_log(
      'bank_allocation.rejected', 'bank_allocation_change_request', request.id,
      jsonb_build_object('review_note', request.review_note)
    );
    return to_jsonb(request);
  end if;

  select * into transaction_row
  from public.bank_transactions
  where id = request.bank_transaction_id
  for update;
  select * into intent
  from public.bank_transfer_intents
  where id = request.bank_transfer_intent_id
  for update;
  if transaction_row.currency <> intent.currency
     or transaction_row.amount_minor <> intent.amount_minor
     or transaction_row.status in ('reconciled', 'returned')
     or intent.status in ('reconciled', 'returned', 'cancelled', 'expired') then
    raise exception 'The proposed allocation is no longer valid';
  end if;

  insert into public.bank_transaction_allocations (
    bank_transaction_id, bank_transfer_intent_id, collection_id,
    contributor_user_id, allocation_method, confidence, reason, allocated_by
  ) values (
    transaction_row.id, intent.id, intent.collection_id,
    intent.contributor_user_id, 'manual_maker_checker', 1,
    request.reason || ' | Checker: ' || btrim(p_review_note), auth.uid()
  ) returning * into allocation;

  update public.bank_transactions
  set destination_id = intent.destination_id,
      status = 'received', updated_at = now()
  where id = transaction_row.id;
  update public.bank_transfer_intents
  set status = 'received_unreconciled',
      evidence_received_at = coalesce(evidence_received_at, transaction_row.evidence_received_at),
      exception_reason = null, updated_at = now()
  where id = intent.id;
  update public.bank_evidence_events event
  set allocation_status = 'allocated',
      review_reason = 'Approved manual maker-checker allocation'
  from public.payment_evidence_links link
  where link.bank_transaction_id = transaction_row.id
    and link.evidence_event_id = event.id;
  update public.reconciliation_exceptions
  set status = 'resolved', resolved_by = auth.uid(),
      resolution_note = btrim(p_review_note), resolved_at = now()
  where bank_transaction_id = transaction_row.id
    and status in ('open', 'reviewing')
    and exception_type in ('missing_reference', 'no_exact_intent', 'ambiguous_intent');
  update public.bank_allocation_change_requests
  set status = 'approved', reviewed_by = auth.uid(),
      review_note = btrim(p_review_note), reviewed_at = now()
  where id = request.id
  returning * into request;
  perform public.create_audit_log(
    'bank_allocation.approved', 'bank_transaction_allocation', allocation.id,
    jsonb_build_object(
      'request_id', request.id,
      'bank_transaction_id', transaction_row.id,
      'bank_transfer_intent_id', intent.id,
      'review_note', request.review_note
    )
  );
  return to_jsonb(request) || jsonb_build_object('allocation_id', allocation.id);
end;
$$;

create or replace function public.admin_list_bank_transactions(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_transactions.read');
  with filtered as (
    select transaction.*
    from public.bank_transactions transaction
    where (p_status is null or transaction.status = p_status)
      and (p_search is null
        or transaction.transfer_reference ilike '%' || p_search || '%'
        or transaction.bank_transaction_id ilike '%' || p_search || '%'
        or transaction.end_to_end_id ilike '%' || p_search || '%'
        or transaction.payer_name ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      case when p_sort = 'amount_asc' then amount_minor end asc nulls last,
      case when p_sort = 'amount_desc' then amount_minor end desc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, coalesce(transfer_reference, 'Unreferenced bank receipt'),
      coalesce(payer_name, 'Unknown payer'), status,
      currency || ' ' || to_char(amount_minor::numeric / 100, 'FM999G999G999D00'),
      created_at,
      jsonb_build_object('bank_transaction_id', bank_transaction_id, 'value_date', value_date)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_bank_transaction(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_transactions.read');
  select to_jsonb(transaction) || jsonb_build_object(
    'allocation', coalesce(to_jsonb(allocation), '{}'::jsonb),
    'intent', coalesce(to_jsonb(intent), '{}'::jsonb),
    'evidence', coalesce((
      select jsonb_agg(to_jsonb(event) - 'parsed_json' order by event.created_at)
      from public.payment_evidence_links link
      join public.bank_evidence_events event on event.id = link.evidence_event_id
      where link.bank_transaction_id = transaction.id
    ), '[]'::jsonb)
  ) into result
  from public.bank_transactions transaction
  left join public.bank_transaction_allocations allocation
    on allocation.bank_transaction_id = transaction.id
  left join public.bank_transfer_intents intent
    on intent.id = allocation.bank_transfer_intent_id
  where transaction.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.admin_list_bank_evidence(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_evidence.read');
  with filtered as (
    select event.*, evidence.channel, evidence.raw_sender, evidence.parse_status,
           evidence.received_at
    from public.bank_evidence_events event
    join public.raw_payment_evidence evidence on evidence.id = event.raw_evidence_id
    where (p_status is null or event.allocation_status = p_status or evidence.parse_status = p_status)
      and (p_search is null
        or event.transfer_reference ilike '%' || p_search || '%'
        or event.bank_transaction_id ilike '%' || p_search || '%'
        or event.payer_name ilike '%' || p_search || '%'
        or evidence.raw_sender ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, coalesce(transfer_reference, 'Evidence awaiting reference'),
      channel || ' · ' || coalesce(payer_name, raw_sender), allocation_status,
      case when amount_minor is null then currency
        else currency || ' ' || to_char(amount_minor::numeric / 100, 'FM999G999G999D00') end,
      created_at,
      jsonb_build_object('confidence', confidence, 'parse_status', parse_status)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_bank_evidence(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_evidence.read');
  select to_jsonb(event) || jsonb_build_object(
    'channel', evidence.channel,
    'sender', evidence.raw_sender,
    'received_at', evidence.received_at,
    'parse_status', evidence.parse_status,
    'retention_until', evidence.retention_until,
    'raw_body_restricted', true
  ) into result
  from public.bank_evidence_events event
  join public.raw_payment_evidence evidence on evidence.id = event.raw_evidence_id
  where event.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.admin_reveal_raw_bank_evidence(p_event_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare evidence public.raw_payment_evidence%rowtype;
begin
  perform public.assert_admin_permission('bank_evidence.raw.reveal');
  if char_length(btrim(coalesce(p_reason, ''))) < 8 then
    raise exception 'Reveal reason must be at least 8 characters';
  end if;
  select raw.* into evidence
  from public.bank_evidence_events event
  join public.raw_payment_evidence raw on raw.id = event.raw_evidence_id
  where event.id = p_event_id;
  if evidence.id is null then raise exception 'Bank evidence not found'; end if;
  insert into public.admin_sensitive_access_logs (
    actor_user_id, entity_type, entity_id, reason
  ) values (
    auth.uid(), 'raw_payment_evidence', evidence.id, btrim(p_reason)
  );
  perform public.create_audit_log(
    'bank_evidence.raw_revealed', 'raw_payment_evidence', evidence.id,
    jsonb_build_object('reason', btrim(p_reason), 'channel', evidence.channel)
  );
  return jsonb_build_object(
    'id', evidence.id, 'channel', evidence.channel,
    'sender', evidence.raw_sender, 'body', evidence.raw_body,
    'headers', evidence.headers, 'received_at', evidence.received_at
  );
end;
$$;

create or replace function public.admin_list_reconciliation_runs(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.read');
  with filtered as (
    select run.* from public.reconciliation_runs run
    where (p_status is null or run.status = p_status)
      and (p_search is null or run.run_date::text ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then started_at end asc nulls last,
      started_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, run_date::text || ' · ' || currency,
      matched_count::text || '/' || statement_line_count::text || ' matched',
      status, currency || ' ' || to_char(matched_total_minor::numeric / 100, 'FM999G999G999D00'),
      started_at, jsonb_build_object('exception_count', exception_count)
    ) order by started_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_reconciliation_run(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.read');
  select to_jsonb(run) || jsonb_build_object(
    'daily_close', coalesce(to_jsonb(close), '{}'::jsonb),
    'exceptions', coalesce((
      select jsonb_agg(to_jsonb(exception) order by exception.created_at)
      from public.reconciliation_exceptions exception where exception.run_id = run.id
    ), '[]'::jsonb)
  ) into result
  from public.reconciliation_runs run
  left join public.daily_bank_closes close on close.reconciliation_run_id = run.id
  where run.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.admin_list_reconciliation_exceptions(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.read');
  with filtered as (
    select exception.* from public.reconciliation_exceptions exception
    where (p_status is null or exception.status = p_status)
      and (p_search is null or exception.exception_type ilike '%' || p_search || '%'
        or exception.details::text ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, replace(exception_type, '_', ' '),
      coalesce(details ->> 'transfer_reference', 'Reconciliation exception'),
      status, coalesce(details ->> 'currency', 'EUR'), created_at,
      jsonb_build_object('bank_transaction_id', bank_transaction_id, 'intent_id', bank_transfer_intent_id)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_reconciliation_exception(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.read');
  select to_jsonb(exception) into result
  from public.reconciliation_exceptions exception where exception.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.admin_resolve_reconciliation_exception(
  p_exception_id uuid, p_resolution_note text, p_dismiss boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare exception public.reconciliation_exceptions%rowtype;
begin
  perform public.assert_admin_permission('bank_reconciliation.manage');
  if char_length(btrim(coalesce(p_resolution_note, ''))) < 8 then
    raise exception 'Resolution note must be at least 8 characters';
  end if;
  update public.reconciliation_exceptions
  set status = case when p_dismiss then 'dismissed' else 'resolved' end,
      resolved_by = auth.uid(), resolution_note = btrim(p_resolution_note),
      resolved_at = now()
  where id = p_exception_id and status in ('open', 'reviewing')
  returning * into exception;
  if exception.id is null then raise exception 'Open exception was not found'; end if;
  perform public.create_audit_log(
    'bank_reconciliation.exception_resolved', 'reconciliation_exception', exception.id,
    jsonb_build_object('status', exception.status, 'resolution_note', exception.resolution_note)
  );
  return to_jsonb(exception);
end;
$$;

create or replace function public.admin_list_journal_entries(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.read');
  with filtered as (
    select entry.*,
      coalesce((select sum(line.amount_minor) from public.journal_lines line
        where line.journal_entry_id = entry.id and line.direction = 'debit'), 0) amount_minor
    from public.journal_entries entry
    where (p_status is null or entry.entry_type = p_status)
      and (p_search is null or entry.external_reference ilike '%' || p_search || '%'
        or entry.description ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, external_reference, description, entry_type,
      currency || ' ' || to_char(amount_minor::numeric / 100, 'FM999G999G999D00'),
      created_at, jsonb_build_object('collection_id', collection_id)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_journal_entry(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_reconciliation.read');
  select to_jsonb(entry) || jsonb_build_object(
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.direction, line.account_code)
      from public.journal_lines line where line.journal_entry_id = entry.id), '[]'::jsonb),
    'balanced', coalesce((select sum(case when line.direction = 'debit' then line.amount_minor else -line.amount_minor end)
      from public.journal_lines line where line.journal_entry_id = entry.id), 1) = 0
  ) into result from public.journal_entries entry where entry.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

create or replace function public.admin_list_bank_allocation_requests(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_transactions.read');
  with filtered as (
    select request.*, intent.transfer_reference
    from public.bank_allocation_change_requests request
    join public.bank_transfer_intents intent on intent.id = request.bank_transfer_intent_id
    where (p_status is null or request.status = p_status)
      and (p_search is null or intent.transfer_reference ilike '%' || p_search || '%'
        or request.reason ilike '%' || p_search || '%')
  ), counted as (
    select count(*) over () total_count, filtered.* from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(public._admin_row(
      id, transfer_reference, reason, status, 'Manual allocation', created_at,
      jsonb_build_object('bank_transaction_id', bank_transaction_id, 'intent_id', bank_transfer_intent_id)
    ) order by created_at desc), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result from counted;
  return result;
end;
$$;

create or replace function public.admin_get_bank_allocation_request(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('bank_transactions.read');
  select to_jsonb(request) || jsonb_build_object(
    'transaction', to_jsonb(transaction), 'intent', to_jsonb(intent)
  ) into result
  from public.bank_allocation_change_requests request
  join public.bank_transactions transaction on transaction.id = request.bank_transaction_id
  join public.bank_transfer_intents intent on intent.id = request.bank_transfer_intent_id
  where request.id = p_id;
  return coalesce(result, '{}'::jsonb);
end;
$$;

-- Timestamps and financial journals are protected at the database boundary.
create trigger bank_transfer_destinations_touch_updated_at
before update on public.bank_transfer_destinations
for each row execute function public.touch_updated_at();
create trigger bank_transfer_intents_touch_updated_at
before update on public.bank_transfer_intents
for each row execute function public.touch_updated_at();
create trigger bank_transactions_touch_updated_at
before update on public.bank_transactions
for each row execute function public.touch_updated_at();
create trigger daily_bank_closes_touch_updated_at
before update on public.daily_bank_closes
for each row execute function public.touch_updated_at();

create or replace function public.prevent_financial_journal_mutation()
returns trigger language plpgsql set search_path = public
as $$
begin
  raise exception 'Posted financial journals are immutable; post a correcting entry';
end;
$$;
revoke execute on function public.prevent_financial_journal_mutation() from public, anon, authenticated;
create trigger journal_entries_immutable
before update or delete on public.journal_entries
for each row execute function public.prevent_financial_journal_mutation();
create trigger journal_lines_immutable
before update or delete on public.journal_lines
for each row execute function public.prevent_financial_journal_mutation();

-- Publish only invalidation events. Raw financial evidence is never placed on
-- Realtime; clients refetch through permissioned RPCs after an area change.
alter table public.app_realtime_events
  drop constraint if exists app_realtime_events_area_check;
alter table public.app_realtime_events
  add constraint app_realtime_events_area_check check (area in (
    'profiles', 'collections', 'members', 'payment_intents', 'payments',
    'allocations', 'ledger', 'receivers', 'sms_events', 'admin_roles',
    'audit', 'feature_flags', 'settings', 'system_health', 'notifications',
    'bank_intents', 'bank_transactions', 'bank_evidence',
    'bank_reconciliation', 'bank_details'
  ));

drop trigger if exists app_realtime_event_trigger on public.bank_transfer_intents;
create trigger app_realtime_event_trigger
after insert or update or delete on public.bank_transfer_intents
for each row execute function public.emit_app_realtime_event('bank_intents');
drop trigger if exists app_realtime_event_trigger on public.bank_transactions;
create trigger app_realtime_event_trigger
after insert or update or delete on public.bank_transactions
for each row execute function public.emit_app_realtime_event('bank_transactions');
drop trigger if exists app_realtime_event_trigger on public.bank_evidence_events;
create trigger app_realtime_event_trigger
after insert or update or delete on public.bank_evidence_events
for each row execute function public.emit_app_realtime_event('bank_evidence');
drop trigger if exists app_realtime_event_trigger on public.reconciliation_runs;
create trigger app_realtime_event_trigger
after insert or update or delete on public.reconciliation_runs
for each row execute function public.emit_app_realtime_event('bank_reconciliation');
drop trigger if exists app_realtime_event_trigger on public.reconciliation_exceptions;
create trigger app_realtime_event_trigger
after insert or update or delete on public.reconciliation_exceptions
for each row execute function public.emit_app_realtime_event('bank_reconciliation');
drop trigger if exists app_realtime_event_trigger on public.bank_transfer_destinations;
create trigger app_realtime_event_trigger
after insert or update or delete on public.bank_transfer_destinations
for each row execute function public.emit_app_realtime_event('bank_details');

update public.admin_navigation_items
set enabled = false, updated_at = now(),
    updated_reason = 'Replaced by bank-transfer-only control plane'
where key in (
  'payment_intents', 'transactions', 'sms_parsing', 'allocations',
  'exceptions', 'ledger', 'receivers', 'sms'
);

insert into public.admin_navigation_items
  (key, label, icon_key, route_path, required_permission, display_order, enabled, metadata)
values
  ('bank_details', 'Bank details', 'account_balance', '/admin/bank-destinations', 'bank_details.read', 38, true, '{"rail":"sepa"}'),
  ('bank_detail_approvals', 'Bank detail approvals', 'fact_check', '/admin/bank-destination-requests', 'bank_details.read', 39, true, '{"maker_checker":true}'),
  ('bank_intents', 'Transfer requests', 'payments', '/admin/bank-intents', 'bank_transactions.read', 40, true, '{"currency":"EUR"}'),
  ('bank_transactions', 'Bank transactions', 'receipt_long', '/admin/bank-transactions', 'bank_transactions.read', 45, true, '{"currency":"EUR"}'),
  ('bank_evidence', 'Bank evidence', 'fact_check', '/admin/bank-evidence', 'bank_evidence.read', 48, true, '{"channels":["sms","email","statement"]}'),
  ('bank_reconciliation', 'Reconciliation', 'balance', '/admin/reconciliation', 'bank_reconciliation.read', 50, true, '{"daily":true}'),
  ('bank_exceptions', 'Reconciliation exceptions', 'report_problem', '/admin/reconciliation-exceptions', 'bank_reconciliation.read', 52, true, '{}'),
  ('bank_allocations', 'Allocation approvals', 'rule', '/admin/bank-allocation-requests', 'bank_transactions.read', 54, true, '{"maker_checker":true}'),
  ('bank_journal', 'Bank journal', 'menu_book', '/admin/bank-journal', 'bank_reconciliation.read', 56, true, '{"double_entry":true}')
on conflict (key) do update set
  label = excluded.label, icon_key = excluded.icon_key,
  route_path = excluded.route_path, required_permission = excluded.required_permission,
  display_order = excluded.display_order, enabled = excluded.enabled,
  metadata = excluded.metadata, updated_at = now();

insert into public.admin_queue_specs
  (rpc_name, title, subtitle, required_permission, display_order, enabled, metadata)
values
  ('admin_list_bank_destinations', 'Bank details', 'Approved beneficiary versions and pending activation state.', 'bank_details.read', 28, true, '{"detail_rpc":"admin_get_bank_destination"}'),
  ('admin_list_bank_destination_change_requests', 'Bank detail approvals', 'Maker-checker beneficiary changes waiting for independent review.', 'bank_details.read', 29, true, '{"detail_rpc":"admin_get_bank_destination_change_request"}'),
  ('admin_list_bank_transfer_intents', 'Transfer requests', 'Member bank transfer reference lifecycle.', 'bank_transactions.read', 30, true, '{"detail_rpc":"admin_get_bank_transfer_intent"}'),
  ('admin_list_bank_transactions', 'Bank transactions', 'Canonical incoming bank receipts across SMS, email, and statements.', 'bank_transactions.read', 32, true, '{"detail_rpc":"admin_get_bank_transaction"}'),
  ('admin_list_bank_evidence', 'Bank evidence', 'Parsed metadata with separately audited raw-content reveal.', 'bank_evidence.read', 34, true, '{"detail_rpc":"admin_get_bank_evidence"}'),
  ('admin_list_reconciliation_runs', 'Daily reconciliation', 'Statement matching, daily close, and balance status.', 'bank_reconciliation.read', 36, true, '{"detail_rpc":"admin_get_reconciliation_run"}'),
  ('admin_list_reconciliation_exceptions', 'Reconciliation exceptions', 'Items requiring controlled operations review.', 'bank_reconciliation.read', 38, true, '{"detail_rpc":"admin_get_reconciliation_exception"}'),
  ('admin_list_bank_allocation_requests', 'Allocation approvals', 'Maker-checker manual allocation requests.', 'bank_transactions.read', 40, true, '{"detail_rpc":"admin_get_bank_allocation_request"}'),
  ('admin_list_journal_entries', 'Bank journal', 'Immutable balanced debit and credit entries.', 'bank_reconciliation.read', 42, true, '{"detail_rpc":"admin_get_journal_entry"}')
on conflict (rpc_name) do update set
  title = excluded.title, subtitle = excluded.subtitle,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order, enabled = excluded.enabled,
  metadata = excluded.metadata, updated_at = now();

update public.admin_queue_specs
set enabled = false, updated_at = now(),
    updated_reason = 'Replaced by bank-transfer-only control plane'
where rpc_name in (
  'admin_list_payment_intents', 'admin_list_payments',
  'admin_list_payment_events', 'admin_list_allocations',
  'admin_list_unallocated', 'admin_list_ledger',
  'admin_list_receivers', 'admin_list_sms_metadata'
);

delete from public.admin_queue_filter_options
where rpc_name in (
  'admin_list_bank_destinations', 'admin_list_bank_destination_change_requests',
  'admin_list_bank_transfer_intents',
  'admin_list_bank_transactions', 'admin_list_bank_evidence',
  'admin_list_reconciliation_runs', 'admin_list_reconciliation_exceptions',
  'admin_list_bank_allocation_requests', 'admin_list_journal_entries'
);
insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
select rpc_name, 'sort', 'created_at_desc', 'Newest', 10, true
from public.admin_queue_specs where rpc_name like 'admin_list_bank_%'
   or rpc_name in ('admin_list_reconciliation_runs', 'admin_list_reconciliation_exceptions', 'admin_list_journal_entries')
union all
select rpc_name, 'sort', 'created_at_asc', 'Oldest', 20, true
from public.admin_queue_specs where rpc_name like 'admin_list_bank_%'
   or rpc_name in ('admin_list_reconciliation_runs', 'admin_list_reconciliation_exceptions', 'admin_list_journal_entries');

insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_bank_transfer_intents', 'status', '', 'All', 10, true),
  ('admin_list_bank_transfer_intents', 'status', 'received_unreconciled', 'Received', 20, true),
  ('admin_list_bank_transfer_intents', 'status', 'reconciled', 'Reconciled', 30, true),
  ('admin_list_bank_transfer_intents', 'status', 'exception', 'Exception', 40, true),
  ('admin_list_bank_transactions', 'status', '', 'All', 10, true),
  ('admin_list_bank_transactions', 'status', 'received', 'Received', 20, true),
  ('admin_list_bank_transactions', 'status', 'reconciled', 'Reconciled', 30, true),
  ('admin_list_bank_transactions', 'status', 'exception', 'Exception', 40, true),
  ('admin_list_bank_evidence', 'status', '', 'All', 10, true),
  ('admin_list_bank_evidence', 'status', 'allocated', 'Allocated', 20, true),
  ('admin_list_bank_evidence', 'status', 'needs_review', 'Needs review', 30, true),
  ('admin_list_reconciliation_runs', 'status', '', 'All', 10, true),
  ('admin_list_reconciliation_runs', 'status', 'completed', 'Completed', 20, true),
  ('admin_list_reconciliation_runs', 'status', 'completed_with_exceptions', 'With exceptions', 30, true),
  ('admin_list_reconciliation_exceptions', 'status', 'open', 'Open', 10, true),
  ('admin_list_reconciliation_exceptions', 'status', 'resolved', 'Resolved', 20, true),
  ('admin_list_bank_allocation_requests', 'status', 'pending', 'Pending', 10, true),
  ('admin_list_bank_allocation_requests', 'status', 'approved', 'Approved', 20, true),
  ('admin_list_bank_destination_change_requests', 'status', 'pending', 'Pending', 10, true),
  ('admin_list_bank_destination_change_requests', 'status', 'approved', 'Approved', 20, true),
  ('admin_list_bank_destination_change_requests', 'status', 'rejected', 'Rejected', 30, true),
  ('admin_list_bank_destinations', 'status', 'active', 'Active', 10, true),
  ('admin_list_bank_destinations', 'status', 'retired', 'Retired', 20, true),
  ('admin_list_journal_entries', 'status', 'bank_receipt', 'Bank receipts', 10, true);

insert into public.admin_queue_sla_policies (queue_key, target, owner, escalation)
values
  ('admin_list_bank_evidence', 'Review unallocated or low-confidence evidence within 4 business hours', 'Payments operations', 'Escalate duplicate or unidentified receipts same day'),
  ('admin_list_reconciliation_exceptions', 'Resolve daily reconciliation exceptions by next business day', 'Finance operations', 'Escalate unresolved variance to platform owner'),
  ('admin_list_bank_allocation_requests', 'Complete independent allocation review within 1 business day', 'Payments control checker', 'Escalate aged requests without bypassing maker-checker')
on conflict (queue_key) do update set
  target = excluded.target, owner = excluded.owner,
  escalation = excluded.escalation, updated_at = now();

-- Kigali is UTC+2 year-round. Run after the operational day at 23:30 Kigali.
do $$
declare existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job where jobname = 'collect-daily-bank-reconciliation'
  loop
    perform cron.unschedule(existing_job);
  end loop;
  perform cron.schedule(
    'collect-daily-bank-reconciliation',
    '30 21 * * *',
    $cron$select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');$cron$
  );
end;
$$;

revoke execute on function public.admin_propose_bank_allocation(uuid, uuid, text) from public, anon;
revoke execute on function public.admin_review_bank_allocation(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_propose_bank_destination(text, text, text, text, boolean, text) from public, anon;
revoke execute on function public.admin_review_bank_destination_change(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_list_bank_destinations(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_bank_destination(uuid) from public, anon;
revoke execute on function public.admin_list_bank_transfer_intents(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_bank_transfer_intent(uuid) from public, anon;
revoke execute on function public.admin_list_bank_transactions(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_bank_transaction(uuid) from public, anon;
revoke execute on function public.admin_list_bank_evidence(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_bank_evidence(uuid) from public, anon;
revoke execute on function public.admin_reveal_raw_bank_evidence(uuid, text) from public, anon;
revoke execute on function public.admin_list_reconciliation_runs(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_reconciliation_run(uuid) from public, anon;
revoke execute on function public.admin_list_reconciliation_exceptions(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_reconciliation_exception(uuid) from public, anon;
revoke execute on function public.admin_resolve_reconciliation_exception(uuid, text, boolean) from public, anon;
revoke execute on function public.admin_list_journal_entries(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_journal_entry(uuid) from public, anon;
revoke execute on function public.admin_list_bank_allocation_requests(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_bank_allocation_request(uuid) from public, anon;
revoke execute on function public.admin_list_bank_destination_change_requests(text, text, integer, integer, text) from public, anon;
revoke execute on function public.admin_get_bank_destination_change_request(uuid) from public, anon;
grant execute on function public.admin_propose_bank_allocation(uuid, uuid, text) to authenticated;
grant execute on function public.admin_review_bank_allocation(uuid, boolean, text) to authenticated;
grant execute on function public.admin_propose_bank_destination(text, text, text, text, boolean, text) to authenticated;
grant execute on function public.admin_review_bank_destination_change(uuid, boolean, text) to authenticated;
grant execute on function public.admin_list_bank_destinations(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_bank_destination(uuid) to authenticated;
grant execute on function public.admin_list_bank_transfer_intents(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_bank_transfer_intent(uuid) to authenticated;
grant execute on function public.admin_list_bank_transactions(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_bank_transaction(uuid) to authenticated;
grant execute on function public.admin_list_bank_evidence(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_bank_evidence(uuid) to authenticated;
grant execute on function public.admin_reveal_raw_bank_evidence(uuid, text) to authenticated;
grant execute on function public.admin_list_reconciliation_runs(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_reconciliation_run(uuid) to authenticated;
grant execute on function public.admin_list_reconciliation_exceptions(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_reconciliation_exception(uuid) to authenticated;
grant execute on function public.admin_resolve_reconciliation_exception(uuid, text, boolean) to authenticated;
grant execute on function public.admin_list_journal_entries(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_journal_entry(uuid) to authenticated;
grant execute on function public.admin_list_bank_allocation_requests(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_bank_allocation_request(uuid) to authenticated;
grant execute on function public.admin_list_bank_destination_change_requests(text, text, integer, integer, text) to authenticated;
grant execute on function public.admin_get_bank_destination_change_request(uuid) to authenticated;

-- Explicit grants are required for new public-schema objects. Direct table
-- reads stay denied except the member's own intent RLS view; RPCs are the API.
grant usage on schema public to authenticated, service_role;
grant all on table public.bank_transfer_destinations,
  public.bank_destination_change_requests, public.bank_transfer_intents,
  public.raw_payment_evidence, public.bank_evidence_events,
  public.bank_transactions, public.payment_evidence_links,
  public.bank_transaction_allocations, public.bank_statement_imports,
  public.bank_statement_lines, public.reconciliation_runs,
  public.reconciliation_matches, public.reconciliation_exceptions,
  public.daily_bank_closes, public.journal_entries, public.journal_lines,
  public.bank_allocation_change_requests to service_role;

-- Group creation no longer depends on a member-owned MoMo receiver, SMS
-- permission, or Play Integrity payment capability. Every group contributes
-- to the independently governed Collect EUR beneficiary.
create or replace function public.create_bank_transfer_group(
  p_group_name text,
  p_group_description text default '',
  p_group_collection_type text default 'ikimina',
  p_group_category_subtype text default null,
  p_group_purpose_label text default null,
  p_group_is_public boolean default false,
  p_cover_image_url text default null,
  p_accent_color_hex text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  created_group_id uuid;
  clean_title text := btrim(coalesce(p_group_name, ''));
  clean_description text := btrim(coalesce(p_group_description, ''));
  catalog_choice jsonb;
  base_slug text;
  final_slug text;
  next_visibility public.collection_visibility := case
    when coalesce(p_group_is_public, false) then 'public_requested'::public.collection_visibility
    else 'private'::public.collection_visibility
  end;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(clean_title) not between 3 and 120 then
    raise exception 'Group name must be between 3 and 120 characters';
  end if;
  if char_length(clean_description) > 1000 then
    raise exception 'Group description must be 1000 characters or fewer';
  end if;
  if p_accent_color_hex is not null and btrim(p_accent_color_hex) !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Accent color must be a six-digit hex color';
  end if;
  catalog_choice := public.resolve_collection_catalog_choice(
    p_group_collection_type,
    p_group_category_subtype,
    p_group_purpose_label,
    'RW'
  );
  base_slug := public.normalize_slug(clean_title);
  if base_slug = '' then base_slug := 'group'; end if;
  final_slug := base_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
  insert into public.collections (
    slug, creator_user_id, title, description, cover_image_url,
    accent_color_hex, collection_type, category_subtype, purpose_label,
    receiver_display_label, visibility, public_status, bank_transfer_currency
  ) values (
    final_slug, auth.uid(), clean_title, clean_description,
    nullif(btrim(coalesce(p_cover_image_url, '')), ''),
    nullif(btrim(coalesce(p_accent_color_hex, '')), ''),
    catalog_choice ->> 'collection_type',
    catalog_choice ->> 'category_subtype',
    catalog_choice ->> 'purpose_label',
    'Collect EUR bank account',
    'private'::public.collection_visibility,
    next_visibility,
    'EUR'
  ) returning id into created_group_id;
  insert into public.collection_members (collection_id, user_id, role, status)
  values (created_group_id, auth.uid(), 'owner', 'active');
  insert into public.collection_share_secrets (collection_id, rotated_by)
  values (created_group_id, auth.uid());
  perform public.create_audit_log(
    'group.created', 'collection', created_group_id,
    jsonb_build_object(
      'collection_type', catalog_choice ->> 'collection_type',
      'category_subtype', catalog_choice ->> 'category_subtype',
      'purpose_label', catalog_choice ->> 'purpose_label',
      'public_status', next_visibility::text,
      'payment_rail', 'sepa_credit_transfer'
    )
  );
  return created_group_id;
end;
$$;

create or replace function public.update_bank_transfer_group_profile(
  p_collection_id uuid,
  p_group_name text,
  p_group_description text,
  p_group_image_url text default null,
  p_group_accent_color_hex text default null,
  p_group_is_public boolean default false,
  p_group_recurring_cadence text default 'monthly',
  p_group_collection_type text default null,
  p_group_category_subtype text default null,
  p_group_purpose_label text default null,
  p_group_is_recurring boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.collections collection
    where collection.id = p_collection_id
      and collection.creator_user_id = auth.uid()
      and collection.archived_at is null
  ) then raise exception 'Only the current group owner can update group settings'; end if;
  perform public.update_collection_profile(
    p_collection_id,
    p_group_name,
    p_group_description,
    p_group_image_url,
    p_group_accent_color_hex,
    p_group_is_public,
    p_group_recurring_cadence,
    p_group_collection_type,
    p_group_category_subtype,
    p_group_purpose_label,
    p_group_is_recurring
  );
  update public.collections
  set receiver_display_label = 'Collect EUR bank account',
      bank_transfer_currency = 'EUR', updated_at = now()
  where id = p_collection_id;
end;
$$;

revoke execute on function public.create_bank_transfer_group(text, text, text, text, text, boolean, text, text) from public, anon;
revoke execute on function public.update_bank_transfer_group_profile(uuid, text, text, text, text, boolean, text, text, text, text, boolean) from public, anon;
grant execute on function public.create_bank_transfer_group(text, text, text, text, text, boolean, text, text) to authenticated;
grant execute on function public.update_bank_transfer_group_profile(uuid, text, text, text, text, boolean, text, text, text, text, boolean) to authenticated;

-- Retire all member-facing mobile-money runtime configuration. The legacy
-- rows remain as history but cannot be returned by public runtime config.
do $$
declare
  retired record;
begin
  for retired in
    select procedure.oid::regprocedure as signature
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any (array[
        'create_payment_intent',
        'create_contribution_intent',
        'create_payment_intent_with_instructions',
        'list_current_user_payment_intents',
        'record_sms_access_consent',
        'create_group_with_owner_attested',
        'update_collection_profile_and_receiver',
        'update_collection_receiver',
        'ingest_raw_payment_sms',
        'claim_raw_payment_sms_for_parse',
        'allocate_parsed_payment_event',
        'post_payment_from_event',
        'record_provider_finality_and_post',
        'admin_list_payment_intents',
        'admin_get_payment_intent',
        'admin_list_payments',
        'admin_get_payment',
        'admin_list_payment_events',
        'admin_get_payment_event',
        'admin_list_allocations',
        'admin_list_unallocated',
        'admin_list_ledger',
        'admin_list_receivers',
        'admin_get_receiver',
        'admin_list_sms_metadata',
        'admin_get_sms_metadata',
        'admin_reparse_payment_event',
        'admin_reveal_raw_sms'
      ])
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated, service_role',
      retired.signature
    );
  end loop;
end;
$$;

revoke all on table public.payment_intents,
  public.raw_payment_sms, public.parsed_payment_events,
  public.payments, public.ledger_entries,
  public.collection_receivers
from public, anon, authenticated;
revoke all on table public.public_contributions_view,
  public.member_contributions_view,
  public.member_collection_summary_view
from public, anon, authenticated;

drop view if exists public.member_collections_view;
create view public.member_collections_view
with (security_invoker = true)
as
select
  collection.id,
  collection.slug,
  collection.creator_user_id,
  collection.title,
  collection.description,
  'EUR'::text as currency,
  null::text as receiver_momo_number,
  'Collect EUR bank account'::text as receiver_display_label,
  'sepa_credit_transfer'::text as receiver_network,
  collection.created_at,
  collection.updated_at,
  collection.archived_at
from public.collections collection
where public.user_can_read_collection(collection.id, auth.uid());
revoke all on public.member_collections_view from public, anon;
grant select on public.member_collections_view to authenticated;

update public.payment_entrypoints
set is_active = false,
    updated_reason = 'Retired by bank-transfer-only production cutover',
    updated_at = now()
where network = 'mtn_momo' or key like 'rw.mtn_momo.%';

update public.feature_flags
set enabled = false,
    updated_reason = 'Member builds do not read SMS in the bank-transfer-only product',
    updated_at = now()
where key in ('enable_android_sms_access', 'enable_sms_reader');

update public.system_settings
set value = '{"provider":"sepa_credit_transfer","currency":"EUR","handoff":"revolut_app","settlement_finality":"daily_bank_statement"}'::jsonb,
    description = 'Collect bank-transfer-only payment mode with Revolut handoff and daily statement reconciliation',
    updated_at = now()
where key = 'payments.mode';

update public.policy_documents
set status = 'archived', updated_at = now(),
    updated_reason = 'Superseded by bank-transfer-only policy version'
where kind in ('privacy', 'terms') and status = 'published';

with documents as (
  insert into public.policy_documents (
    kind, locale, version, title, summary, status, effective_at, published_at,
    updated_reason
  ) values
    (
      'privacy', 'en', '2026-08-20-bank-v1', 'Privacy Policy',
      'Collect account, bank evidence, reconciliation, support, and retention rules.',
      'published', now(), now(), 'Bank-transfer-only production cutover'
    ),
    (
      'terms', 'en', '2026-08-20-bank-v1', 'Terms & Conditions',
      'Collect group, EUR bank transfer, reconciliation, dispute, and acceptable-use terms.',
      'published', now(), now(), 'Bank-transfer-only production cutover'
    )
  on conflict (kind, locale, version) do update set
    title = excluded.title, summary = excluded.summary, status = 'published',
    effective_at = excluded.effective_at, published_at = excluded.published_at,
    updated_reason = excluded.updated_reason, updated_at = now()
  returning id, kind
), sections(kind, section_key, title, body, display_order) as (
  values
    ('privacy', 'data_we_collect', 'Data we collect',
      'Collect stores your Collect ID, WhatsApp sign-in phone, group memberships, group profile details, bank transfer requests, contribution records, notification preferences, and audit status. Controlled operations channels process beneficiary-bank SMS, email, and statement evidence.', 10),
    ('privacy', 'how_we_use_data', 'How we use data',
      'We use this data to operate groups, reconcile incoming EUR transfers, keep ledgers accurate, prevent duplicate posting, notify members, provide support, and maintain dispute and audit records.', 20),
    ('privacy', 'what_stays_private', 'What stays private',
      'Sign-in phones, payer details, raw bank notification text, statement source data, and support evidence are not shown on public group pages. Raw evidence has a separately audited administrator reveal permission.', 30),
    ('privacy', 'sharing', 'Sharing',
      'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, and bank-transfer verification. We do not sell personal data.', 40),
    ('privacy', 'retention', 'Choices and retention',
      'You can request account deletion and data correction. Ledger, reconciliation, and audit records may be retained where needed for security, disputes, accounting, and legal obligations.', 50),
    ('terms', 'using_collect', 'Using Collect',
      'Collect helps groups organize contributions, issue unique EUR transfer references, share group links and QR codes, and maintain a reconciled contribution ledger. Use accurate group and transfer information.', 10),
    ('terms', 'bank_transfers', 'Bank transfers',
      'You approve transfers outside Collect in your banking app. Collect shows the approved beneficiary, amount, and unique reference but never asks for bank credentials, card details, a PIN, or an OTP.', 20),
    ('terms', 'group_ownership', 'Group ownership',
      'Group owners manage group profiles and membership. Collect centrally governs the beneficiary bank account through independent maker-checker approval and daily reconciliation.', 30),
    ('terms', 'disputes', 'Disputes and corrections',
      'If a transfer is missing, duplicated, returned, incorrect, or needs review, contact support. Collect may use bank references, controlled notification evidence, statements, and audit logs to investigate.', 40),
    ('terms', 'acceptable_use', 'Acceptable use',
      'Do not create misleading groups, impersonate another person, abuse group links, submit false payment claims, or use Collect to request illegal or unauthorized payments.', 50)
)
insert into public.policy_document_sections (
  policy_document_id, section_key, title, body, display_order
)
select documents.id, sections.section_key, sections.title, sections.body,
       sections.display_order
from documents join sections on sections.kind = documents.kind
on conflict (policy_document_id, section_key) do update set
  title = excluded.title, body = excluded.body,
  display_order = excluded.display_order, updated_at = now();

-- The admin landing page must report the active bank control plane, not the
-- archived MoMo queues retained for audit history.
create or replace function public.admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  evidence_total bigint;
  evidence_ready bigint;
begin
  perform public.assert_admin_permission('overview.read');
  select count(*), count(*) filter (where allocation_status <> 'needs_review')
  into evidence_total, evidence_ready
  from public.bank_evidence_events;
  return jsonb_build_object(
    'metrics', jsonb_build_array(
      jsonb_build_object(
        'label', 'Open exceptions',
        'value', (select count(*) from public.reconciliation_exceptions where status in ('open', 'reviewing')),
        'status', 'needs_review'
      ),
      jsonb_build_object(
        'label', 'Awaiting approvals',
        'value',
          (select count(*) from public.bank_destination_change_requests where status = 'pending')
          + (select count(*) from public.bank_allocation_change_requests where status = 'pending'),
        'status', 'pending'
      ),
      jsonb_build_object(
        'label', 'Unreconciled transfers',
        'value', (select count(*) from public.bank_transactions where status = 'received'),
        'status', 'pending'
      ),
      jsonb_build_object(
        'label', 'Evidence health',
        'value', case when evidence_total = 0 then '100%' else round(100.0 * evidence_ready / evidence_total)::text || '%' end,
        'status', case when evidence_ready = evidence_total then 'active' else 'needs_review' end
      )
    )
  );
end;
$$;
revoke execute on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

commit;
