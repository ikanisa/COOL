-- ==========================================================================
-- Phase 4A: notification_preferences table
-- ==========================================================================
-- Enables users to opt in/out of notification categories per channel.
-- The send-notification Edge Function checks this before sending.
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category   TEXT NOT NULL,
  channel    TEXT NOT NULL DEFAULT 'push',
  enabled    BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, category, channel)
);

CREATE INDEX IF NOT EXISTS idx_notification_pref_user
  ON public.notification_preferences (user_id);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Users manage their own preferences
CREATE POLICY notification_pref_manage_own
  ON public.notification_preferences FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Service role can read all (for send-notification Edge Function)
CREATE POLICY notification_pref_service_read
  ON public.notification_preferences FOR SELECT
  TO service_role
  USING (true);

-- updated_at trigger
DROP TRIGGER IF EXISTS trg_notification_pref_updated ON public.notification_preferences;
CREATE TRIGGER trg_notification_pref_updated
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Seed default notification categories in app_config
INSERT INTO public.app_config (key, value, description) VALUES
  ('notification_categories', 'contribution,group_invite,group_activity,admin,promo,biopay',
   'Comma-separated list of valid notification categories')
ON CONFLICT (key) DO NOTHING;

-- RPC: check if user has opted out of a category
CREATE OR REPLACE FUNCTION public.is_notification_enabled(
  p_user_id UUID,
  p_category TEXT,
  p_channel TEXT DEFAULT 'push'
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT np.enabled
     FROM public.notification_preferences np
     WHERE np.user_id = p_user_id
       AND np.category = p_category
       AND np.channel = p_channel
     LIMIT 1),
    true  -- default: enabled if no preference set
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_notification_enabled(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_notification_enabled(uuid, text, text) TO service_role;

COMMENT ON TABLE public.notification_preferences IS
  'Per-user opt-in/out preferences for notification categories and channels.';
