-- ==========================================================================
-- Cool App - indexes for AI SMS reconciliation
-- ==========================================================================

create index if not exists idx_pending_transactions_reconciliation_lookup
  on public.pending_transactions (user_id, status, amount, provider, created_at desc);
