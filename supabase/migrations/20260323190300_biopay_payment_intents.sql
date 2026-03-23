-- ════════════════════════════════════════════════════════════════
-- BioPay Payment Intents
--
-- Server-issued, time-limited, one-time-use tokens that bind
-- a biometric match to a specific payment action.
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.biopay_payment_intents (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  profile_id        uuid NOT NULL,
  match_score       double precision NOT NULL,
  recipient_value   text NOT NULL,
  route_type        text NOT NULL CHECK (route_type IN ('phone_number', 'code')),
  ussd_code         text NOT NULL,
  nonce             text NOT NULL UNIQUE,
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'dialed', 'expired', 'cancelled')),
  expires_at        timestamptz NOT NULL,
  dialed_at         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- Fast lookups by user and nonce.
CREATE INDEX IF NOT EXISTS idx_biopay_intents_user
  ON public.biopay_payment_intents (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_biopay_intents_nonce
  ON public.biopay_payment_intents (nonce) WHERE status = 'pending';

-- ── Auto-expire stale intents ────────────────────────────────
-- pg_cron job: mark expired intents every minute.
SELECT cron.schedule(
  'expire_biopay_payment_intents',
  '* * * * *',
  $$UPDATE public.biopay_payment_intents
    SET status = 'expired'
    WHERE status = 'pending' AND expires_at < now()$$
);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.biopay_payment_intents ENABLE ROW LEVEL SECURITY;

-- Users can read their own intents.
DROP POLICY IF EXISTS "biopay_intents_select_own" ON public.biopay_payment_intents;
CREATE POLICY "biopay_intents_select_own"
  ON public.biopay_payment_intents
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Users can update their own pending intents (mark as dialed).
DROP POLICY IF EXISTS "biopay_intents_update_own" ON public.biopay_payment_intents;
CREATE POLICY "biopay_intents_update_own"
  ON public.biopay_payment_intents
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid() AND status = 'pending')
  WITH CHECK (user_id = auth.uid());

-- Insert is service-role only (via edge function).
-- No insert policy for authenticated users.
