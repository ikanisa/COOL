-- ==========================================================================
-- Cool App - Repair MoMo SMS pipeline on projects that still have legacy SMS
-- schema and never created the user-scoped AI ingestion tables.
-- ==========================================================================

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'momo_sms_raw'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'momo_sms_raw'
      and column_name = 'user_id'
  ) and not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'momo_sms_raw_legacy_20260312223000'
  ) then
    alter table public.momo_sms_raw
      rename to momo_sms_raw_legacy_20260312223000;
  end if;
end $$;
create table if not exists public.momo_sms_raw (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_message_key text not null,
  sender text not null,
  sms_body text not null,
  provider text,
  country text,
  sms_received_at timestamptz not null,
  detected_tx_type text,
  detected_amount integer,
  detected_tx_id text,
  ingestion_source text not null default 'android_sms_listener',
  parse_status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.momo_sms_raw
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists device_message_key text,
  add column if not exists sender text,
  add column if not exists sms_body text,
  add column if not exists provider text,
  add column if not exists country text,
  add column if not exists sms_received_at timestamptz,
  add column if not exists detected_tx_type text,
  add column if not exists detected_amount integer,
  add column if not exists detected_tx_id text,
  add column if not exists ingestion_source text default 'android_sms_listener',
  add column if not exists updated_at timestamptz not null default now();
alter table public.momo_sms_raw
  alter column device_message_key set not null,
  alter column sender set not null,
  alter column sms_body set not null,
  alter column sms_received_at set not null,
  alter column ingestion_source set not null;
alter table public.momo_sms_raw
  drop constraint if exists momo_sms_raw_parse_status_check;
alter table public.momo_sms_raw
  add constraint momo_sms_raw_parse_status_check
    check (parse_status in ('pending', 'processing', 'parsed', 'failed', 'ignored'));
create unique index if not exists idx_momo_sms_raw_user_message_key
  on public.momo_sms_raw (user_id, device_message_key);
create index if not exists idx_momo_sms_raw_user
  on public.momo_sms_raw (user_id);
create index if not exists idx_momo_sms_raw_parse_status
  on public.momo_sms_raw (parse_status);
create index if not exists idx_momo_sms_raw_received_at
  on public.momo_sms_raw (sms_received_at desc);
create table if not exists public.momo_sms_parsed (
  id uuid primary key default gen_random_uuid(),
  raw_sms_id uuid not null unique references public.momo_sms_raw(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parser_provider text not null,
  parser_model text not null,
  parse_status text not null default 'parsed',
  confidence numeric(5,4),
  tx_direction text not null default 'unknown',
  tx_type text not null default 'unknown',
  tx_category text not null default 'uncategorized',
  cashflow_bucket text not null default 'unknown',
  momo_tx_id text,
  amount integer,
  currency text not null default 'RWF',
  tx_date date,
  tx_time time,
  tx_datetime timestamptz,
  payer_name text,
  payer_number_last3 text,
  payer_number_full text,
  payee_name text,
  payee_number_or_code text,
  merchant_code text,
  fee_amount integer,
  balance_after integer,
  counterparty_name text,
  ai_summary text,
  recurring_pattern_hint text,
  narrative text,
  structured_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.momo_sms_parsed
  add column if not exists tx_category text not null default 'uncategorized',
  add column if not exists cashflow_bucket text not null default 'unknown',
  add column if not exists counterparty_name text,
  add column if not exists ai_summary text,
  add column if not exists recurring_pattern_hint text;
alter table public.momo_sms_parsed
  drop constraint if exists momo_sms_parsed_parse_status_check,
  drop constraint if exists momo_sms_parsed_tx_direction_check,
  drop constraint if exists momo_sms_parsed_cashflow_bucket_check;
alter table public.momo_sms_parsed
  add constraint momo_sms_parsed_parse_status_check
    check (parse_status in ('parsed', 'needs_review', 'failed')),
  add constraint momo_sms_parsed_tx_direction_check
    check (tx_direction in ('credit', 'debit', 'unknown')),
  add constraint momo_sms_parsed_cashflow_bucket_check
    check (cashflow_bucket in ('income', 'expense', 'savings', 'transfer', 'loan', 'fees', 'unknown'));
create index if not exists idx_momo_sms_parsed_user
  on public.momo_sms_parsed (user_id);
create index if not exists idx_momo_sms_parsed_momo_tx_id
  on public.momo_sms_parsed (momo_tx_id);
create index if not exists idx_momo_sms_parsed_tx_datetime
  on public.momo_sms_parsed (tx_datetime desc);
create index if not exists idx_momo_sms_parsed_category
  on public.momo_sms_parsed (tx_category, cashflow_bucket);
create table if not exists public.momo_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  parsed_sms_id uuid not null unique references public.momo_sms_parsed(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_type text not null,
  ledger_scope text not null default 'wallet',
  ledger_status text not null default 'draft',
  amount integer not null,
  currency text not null default 'RWF',
  tx_datetime timestamptz,
  tx_category text not null default 'uncategorized',
  cashflow_bucket text not null default 'unknown',
  counterparty_name text,
  statement_label text,
  external_reference text,
  target_table text,
  target_record_id uuid,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.momo_ledger_entries
  drop constraint if exists momo_ledger_entries_type_check,
  drop constraint if exists momo_ledger_entries_status_check,
  drop constraint if exists momo_ledger_entries_cashflow_bucket_check;
alter table public.momo_ledger_entries
  add constraint momo_ledger_entries_type_check
    check (entry_type in ('credit', 'debit')),
  add constraint momo_ledger_entries_status_check
    check (ledger_status in ('draft', 'posted', 'reversed')),
  add constraint momo_ledger_entries_cashflow_bucket_check
    check (cashflow_bucket in ('income', 'expense', 'savings', 'transfer', 'loan', 'fees', 'unknown'));
create index if not exists idx_momo_ledger_entries_user
  on public.momo_ledger_entries (user_id);
create index if not exists idx_momo_ledger_entries_scope
  on public.momo_ledger_entries (ledger_scope, ledger_status);
create index if not exists idx_momo_ledger_entries_statement
  on public.momo_ledger_entries (user_id, ledger_status, tx_datetime desc);
create index if not exists idx_momo_ledger_entries_category
  on public.momo_ledger_entries (tx_category, cashflow_bucket);
create table if not exists public.momo_reconciliations (
  id uuid primary key default gen_random_uuid(),
  parsed_sms_id uuid not null unique references public.momo_sms_parsed(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  target_table text,
  target_record_id uuid,
  match_type text not null default 'ai_match',
  match_status text not null default 'pending_review',
  confidence numeric(5,4),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.momo_reconciliations
  drop constraint if exists momo_reconciliations_status_check;
alter table public.momo_reconciliations
  add constraint momo_reconciliations_status_check
    check (match_status in ('pending_review', 'matched', 'manual_review', 'rejected'));
create index if not exists idx_momo_reconciliations_user
  on public.momo_reconciliations (user_id);
create index if not exists idx_momo_reconciliations_target
  on public.momo_reconciliations (target_table, target_record_id);
create table if not exists public.momo_parse_attempts (
  id uuid primary key default gen_random_uuid(),
  raw_sms_id uuid not null references public.momo_sms_raw(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  model text not null,
  attempt_number integer not null default 1,
  status text not null default 'pending',
  prompt_version text not null default 'v1',
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now()
);
alter table public.momo_parse_attempts
  drop constraint if exists momo_parse_attempts_status_check;
alter table public.momo_parse_attempts
  add constraint momo_parse_attempts_status_check
    check (status in ('pending', 'success', 'failed'));
create unique index if not exists idx_momo_parse_attempts_unique_attempt
  on public.momo_parse_attempts (raw_sms_id, provider, attempt_number);
create index if not exists idx_momo_parse_attempts_raw_sms
  on public.momo_parse_attempts (raw_sms_id, created_at desc);
create index if not exists idx_momo_parse_attempts_user
  on public.momo_parse_attempts (user_id);
drop trigger if exists trg_momo_sms_raw_set_updated_at on public.momo_sms_raw;
create trigger trg_momo_sms_raw_set_updated_at
  before update on public.momo_sms_raw
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_momo_sms_parsed_set_updated_at on public.momo_sms_parsed;
create trigger trg_momo_sms_parsed_set_updated_at
  before update on public.momo_sms_parsed
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_momo_ledger_entries_set_updated_at on public.momo_ledger_entries;
create trigger trg_momo_ledger_entries_set_updated_at
  before update on public.momo_ledger_entries
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_momo_reconciliations_set_updated_at on public.momo_reconciliations;
create trigger trg_momo_reconciliations_set_updated_at
  before update on public.momo_reconciliations
  for each row
  execute function public.set_updated_at();
alter table public.momo_sms_raw enable row level security;
alter table public.momo_sms_parsed enable row level security;
alter table public.momo_ledger_entries enable row level security;
alter table public.momo_reconciliations enable row level security;
alter table public.momo_parse_attempts enable row level security;
drop policy if exists "momo_sms_raw_select_own" on public.momo_sms_raw;
create policy "momo_sms_raw_select_own"
  on public.momo_sms_raw for select
  using (auth.uid() = user_id);
drop policy if exists "momo_sms_raw_insert_own" on public.momo_sms_raw;
create policy "momo_sms_raw_insert_own"
  on public.momo_sms_raw for insert
  with check (auth.uid() = user_id);
drop policy if exists "momo_sms_raw_update_own" on public.momo_sms_raw;
create policy "momo_sms_raw_update_own"
  on public.momo_sms_raw for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "momo_sms_parsed_select_own" on public.momo_sms_parsed;
create policy "momo_sms_parsed_select_own"
  on public.momo_sms_parsed for select
  using (auth.uid() = user_id);
drop policy if exists "momo_ledger_entries_select_own" on public.momo_ledger_entries;
create policy "momo_ledger_entries_select_own"
  on public.momo_ledger_entries for select
  using (auth.uid() = user_id);
drop policy if exists "momo_reconciliations_select_own" on public.momo_reconciliations;
create policy "momo_reconciliations_select_own"
  on public.momo_reconciliations for select
  using (auth.uid() = user_id);
drop policy if exists "momo_parse_attempts_select_own" on public.momo_parse_attempts;
create policy "momo_parse_attempts_select_own"
  on public.momo_parse_attempts for select
  using (auth.uid() = user_id);
