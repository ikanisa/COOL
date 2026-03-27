-- ============================================================================
-- Notification event log + user-readable inbox RPC
-- Provides durable observability for FCM sends and a server-trusted user feed.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL
    CHECK (target_type IN ('user', 'topic')),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  topic text,
  title text NOT NULL,
  body text NOT NULL,
  route text,
  image_url text,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  provider text NOT NULL DEFAULT 'fcm',
  send_status text NOT NULL DEFAULT 'queued'
    CHECK (send_status IN ('queued', 'sent', 'partial', 'failed')),
  sent_count integer NOT NULL DEFAULT 0 CHECK (sent_count >= 0),
  failed_count integer NOT NULL DEFAULT 0 CHECK (failed_count >= 0),
  cleaned_tokens integer NOT NULL DEFAULT 0 CHECK (cleaned_tokens >= 0),
  errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  CONSTRAINT notification_events_target_user_check CHECK (
    (target_type = 'user' AND user_id IS NOT NULL)
    OR (target_type = 'topic' AND topic IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_notification_events_user_created_at
  ON public.notification_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_events_topic_created_at
  ON public.notification_events (topic, created_at DESC)
  WHERE topic IS NOT NULL;

ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own notification events"
  ON public.notification_events
  FOR SELECT
  TO authenticated
  USING (
    target_type = 'user'
    AND auth.uid() = user_id
  );

CREATE POLICY "Service role manages notification events"
  ON public.notification_events
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.get_my_notification_events(
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      id,
      title,
      body,
      route,
      image_url,
      data,
      provider,
      send_status,
      sent_count,
      failed_count,
      cleaned_tokens,
      errors,
      created_at,
      sent_at
    FROM public.notification_events
    WHERE target_type = 'user'
      AND user_id = auth.uid()
    ORDER BY COALESCE(sent_at, created_at) DESC, created_at DESC
    LIMIT GREATEST(p_limit, 1)
    OFFSET GREATEST(p_offset, 0)
  ) t;

  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_notification_events(integer, integer)
  TO authenticated;

COMMENT ON TABLE public.notification_events IS
  'Durable record of user-targeted and topic-targeted push notification send attempts.';

COMMENT ON FUNCTION public.get_my_notification_events(integer, integer) IS
  'Returns the authenticated user''s recent server-trusted notification events.';
