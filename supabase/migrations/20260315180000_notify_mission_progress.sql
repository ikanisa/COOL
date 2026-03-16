-- ═══════════════════════════════════════════════════════════════════════
-- Mission Progress Push Notification Trigger
-- ═══════════════════════════════════════════════════════════════════════
--
-- Uses pg_net (Supabase HTTP extension) to call the `send-notification`
-- Edge Function when a user completes a mission.
--
-- Fires on INSERT or UPDATE of `cool_mission_progress` when
-- `completed = true`.
-- ═══════════════════════════════════════════════════════════════════════

-- Ensure pg_net extension is available (already provided by Supabase).
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── Trigger function ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_mission_completed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _supabase_url    TEXT;
  _service_key     TEXT;
  _mission_title   TEXT;
  _request_id      BIGINT;
BEGIN
  -- Only fire when transitioning TO completed.
  IF NEW.completed_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.completed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Look up the mission title.
  SELECT title INTO _mission_title
  FROM public.cool_missions
  WHERE id = NEW.mission_id;

  IF _mission_title IS NULL THEN
    _mission_title := 'a mission';
  END IF;

  -- Read project URL and service role key from vault or env.
  -- Supabase automatically makes these available in edge function env,
  -- but pg_net needs them explicitly.
  _supabase_url := current_setting('app.settings.supabase_url', TRUE);
  _service_key  := current_setting('app.settings.service_role_key', TRUE);

  -- Fallback: skip if settings are not configured yet.
  IF _supabase_url IS NULL OR _service_key IS NULL THEN
    RAISE WARNING '[notify_mission_completed] app.settings.supabase_url or service_role_key not configured. Skipping push.';
    RETURN NEW;
  END IF;

  -- Fire async HTTP POST to the send-notification Edge Function.
  SELECT extensions.http_post(
    url     := _supabase_url || '/functions/v1/send-notification',
    body    := jsonb_build_object(
      'type',    'user',
      'user_id', NEW.user_id::TEXT,
      'title',   'Mission Complete! 🎉',
      'body',    'You completed: ' || _mission_title,
      'data',    jsonb_build_object(
        'route', '/missions',
        'type',  'mission_complete',
        'mission_id', NEW.mission_id::TEXT
      )
    ),
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || _service_key
    )
  ) INTO _request_id;

  RETURN NEW;
END;
$$;

-- ── Trigger ──────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_notify_mission_completed ON public.cool_mission_progress;

CREATE TRIGGER trg_notify_mission_completed
  AFTER INSERT OR UPDATE OF completed_at
  ON public.cool_mission_progress
  FOR EACH ROW
  WHEN (NEW.completed_at IS NOT NULL)
  EXECUTE FUNCTION public.notify_mission_completed();

-- Add a comment for documentation.
COMMENT ON FUNCTION public.notify_mission_completed() IS
  'Sends a push notification via the send-notification Edge Function when a user completes a Cool mission.';
