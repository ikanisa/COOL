-- =============================================================================
-- Trip Status Alignment Migration
-- Adds 'active' and 'paused' to the mobility_trips status CHECK constraint.
-- The existing lowercase trigger ensures all writes are lowercased.
-- =============================================================================

-- Drop the old constraint (only allows open, matched, cancelled, expired).
ALTER TABLE mobility_trips
  DROP CONSTRAINT IF EXISTS mobility_trips_status_check;
-- Add the expanded constraint including active and paused.
ALTER TABLE mobility_trips
  ADD CONSTRAINT mobility_trips_status_check
    CHECK (status IN ('open', 'active', 'paused', 'matched', 'cancelled', 'expired'));
-- Normalise any existing uppercase values that may have slipped through.
UPDATE mobility_trips SET status = lower(status)
  WHERE status <> lower(status);
