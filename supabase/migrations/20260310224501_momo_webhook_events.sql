-- ==========================================================================
-- Cool App - Mobile Money webhook event log
-- ==========================================================================
-- Stores provider webhook deliveries for idempotent payment processing.
-- ==========================================================================

create table if not exists public.momo_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  reference text,
  transaction_id text,
  event_status text not null default 'received'
    check (event_status in ('received', 'processed', 'ignored', 'failed')),
  target_table text,
  target_record_id uuid,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create index if not exists idx_momo_webhook_events_reference
  on public.momo_webhook_events (reference, received_at desc);

create index if not exists idx_momo_webhook_events_status
  on public.momo_webhook_events (event_status, received_at desc);

drop trigger if exists trg_momo_webhook_events_set_updated_at
  on public.momo_webhook_events;
create trigger trg_momo_webhook_events_set_updated_at
  before update on public.momo_webhook_events
  for each row
  execute function public.set_updated_at();
