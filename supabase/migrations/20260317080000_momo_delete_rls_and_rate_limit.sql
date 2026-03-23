-- Migration: Add DELETE RLS policies for GDPR/data-deletion compliance (G7)
-- Users can delete their own MoMo SMS records.
-- Cascade from momo_sms_raw handles downstream tables via FK ON DELETE CASCADE.

-- 1. momo_sms_raw — user can delete their own raw SMS
create policy "Users can delete own raw SMS"
  on public.momo_sms_raw
  for delete
  to authenticated
  using (auth.uid() = user_id);
-- 2. momo_sms_parsed — user can delete own parsed records
create policy "Users can delete own parsed SMS"
  on public.momo_sms_parsed
  for delete
  to authenticated
  using (auth.uid() = user_id);
-- 3. momo_ledger_entries — user can delete own ledger entries
create policy "Users can delete own ledger entries"
  on public.momo_ledger_entries
  for delete
  to authenticated
  using (auth.uid() = user_id);
-- 4. momo_reconciliations — user can delete own reconciliation records
create policy "Users can delete own reconciliations"
  on public.momo_reconciliations
  for delete
  to authenticated
  using (auth.uid() = user_id);
-- 5. momo_parse_attempts — user can delete own parse attempt audit trail
create policy "Users can delete own parse attempts"
  on public.momo_parse_attempts
  for delete
  to authenticated
  using (auth.uid() = user_id);
