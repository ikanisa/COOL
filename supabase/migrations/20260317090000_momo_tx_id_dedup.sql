-- Migration: Add TX-ID dedup guards to prevent duplicate ledger/parsed entries
-- Rollback: DROP INDEX idx_momo_ledger_user_extref; DROP INDEX idx_momo_parsed_user_txid;

-- Step 1: Clean up any pre-existing duplicates (keep earliest row per group)
DELETE FROM momo_ledger_entries
WHERE id IN (
  SELECT id FROM (
    SELECT id,
      ROW_NUMBER() OVER (
        PARTITION BY user_id, external_reference
        ORDER BY created_at ASC, id ASC
      ) AS rn
    FROM momo_ledger_entries
    WHERE external_reference IS NOT NULL
      AND external_reference NOT LIKE 'SMS-%'
  ) sub
  WHERE rn > 1
);
DELETE FROM momo_sms_parsed
WHERE id IN (
  SELECT id FROM (
    SELECT id,
      ROW_NUMBER() OVER (
        PARTITION BY user_id, momo_tx_id
        ORDER BY created_at ASC, id ASC
      ) AS rn
    FROM momo_sms_parsed
    WHERE momo_tx_id IS NOT NULL
  ) sub
  WHERE rn > 1
);
-- Step 2: Prevent duplicate ledger entries for the same user + transaction ref.
-- Partial index: only enforce when external_reference IS NOT NULL
-- (fallback refs like 'SMS-{id}' are unique by construction).
CREATE UNIQUE INDEX IF NOT EXISTS idx_momo_ledger_user_extref
  ON momo_ledger_entries (user_id, external_reference)
  WHERE external_reference IS NOT NULL
    AND external_reference NOT LIKE 'SMS-%';
-- Step 3: Prevent duplicate parsed entries for the same user + MoMo TX ID.
CREATE UNIQUE INDEX IF NOT EXISTS idx_momo_parsed_user_txid
  ON momo_sms_parsed (user_id, momo_tx_id)
  WHERE momo_tx_id IS NOT NULL;
