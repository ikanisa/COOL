-- ═══════════════════════════════════════════════════════════════════════
-- Drop Legacy Tables + Group Push Notification Triggers
-- ═══════════════════════════════════════════════════════════════════════
--
-- 1. Drops contribution_groups (legacy duplicate of groups table)
-- 2. Drops group_messages (unused; can be recreated when messaging ships)
-- 3. Creates notify_group_member_joined trigger
-- 4. Creates notify_contribution_allocated trigger
--
-- Notification triggers follow the same pg_net + send-notification
-- pattern established in 20260315180000_notify_mission_progress.sql.
-- ═══════════════════════════════════════════════════════════════════════

-- Ensure pg_net extension is available.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. DROP LEGACY TABLES
-- ═══════════════════════════════════════════════════════════════════════

-- group_messages was created alongside contribution_groups (20260329090000)
-- but has zero app references. Remove the realtime publication first.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'group_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE group_messages;
  END IF;
END $$;

-- Drop policies before tables.
DROP POLICY IF EXISTS "group_messages_select_member" ON group_messages;
DROP POLICY IF EXISTS "group_messages_insert_member" ON group_messages;
DROP TABLE IF EXISTS group_messages CASCADE;

-- contribution_groups was the old groups table before schema convergence.
-- RPCs were already fixed in 20260410181000. Safe to drop.
DROP POLICY IF EXISTS "contribution_groups_select_public" ON contribution_groups;
DROP POLICY IF EXISTS "contribution_groups_select_member" ON contribution_groups;
DROP POLICY IF EXISTS "contribution_groups_insert_auth" ON contribution_groups;
DROP POLICY IF EXISTS "contribution_groups_update_creator" ON contribution_groups;
DROP TABLE IF EXISTS contribution_groups CASCADE;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. NOTIFY: Group Member Joined
-- ═══════════════════════════════════════════════════════════════════════
-- Fires when a new row is inserted into group_members.
-- Sends a push to the group creator: "New Member! 👋"

CREATE OR REPLACE FUNCTION public.notify_group_member_joined()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _supabase_url  TEXT;
  _service_key   TEXT;
  _group_name    TEXT;
  _creator_id    UUID;
  _request_id    BIGINT;
BEGIN
  -- Don't notify if the creator is joining their own group (at creation time).
  SELECT name, creator_id INTO _group_name, _creator_id
  FROM public.groups
  WHERE id = NEW.group_id;

  IF _creator_id IS NULL OR _creator_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  IF _group_name IS NULL THEN
    _group_name := 'your group';
  END IF;

  _supabase_url := current_setting('app.settings.supabase_url', TRUE);
  _service_key  := current_setting('app.settings.service_role_key', TRUE);

  IF _supabase_url IS NULL OR _service_key IS NULL THEN
    RAISE WARNING '[notify_group_member_joined] app.settings not configured. Skipping push.';
    RETURN NEW;
  END IF;

  SELECT extensions.http_post(
    url     := _supabase_url || '/functions/v1/send-notification',
    body    := jsonb_build_object(
      'type',    'user',
      'user_id', _creator_id::TEXT,
      'title',   'New Member! 👋',
      'body',    'Someone joined ' || _group_name,
      'data',    jsonb_build_object(
        'route',    '/groups/' || NEW.group_id::TEXT,
        'type',     'group_member_joined',
        'group_id', NEW.group_id::TEXT
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

DROP TRIGGER IF EXISTS trg_notify_group_member_joined ON public.group_members;

CREATE TRIGGER trg_notify_group_member_joined
  AFTER INSERT
  ON public.group_members
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_group_member_joined();

COMMENT ON FUNCTION public.notify_group_member_joined() IS
  'Sends a push notification to the group creator when a new member joins.';

-- ═══════════════════════════════════════════════════════════════════════
-- 3. NOTIFY: Contribution Allocated / Confirmed
-- ═══════════════════════════════════════════════════════════════════════
-- Fires when a group_contributions row status transitions to 'confirmed'.
-- Sends a push to the contributor: "Contribution Confirmed ✅"

CREATE OR REPLACE FUNCTION public.notify_contribution_allocated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _supabase_url  TEXT;
  _service_key   TEXT;
  _group_name    TEXT;
  _request_id    BIGINT;
BEGIN
  -- Only fire on transition TO 'confirmed'.
  IF NEW.status <> 'confirmed' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status = 'confirmed' THEN
    RETURN NEW;
  END IF;

  SELECT name INTO _group_name
  FROM public.groups
  WHERE id = NEW.group_id;

  IF _group_name IS NULL THEN
    _group_name := 'your group';
  END IF;

  _supabase_url := current_setting('app.settings.supabase_url', TRUE);
  _service_key  := current_setting('app.settings.service_role_key', TRUE);

  IF _supabase_url IS NULL OR _service_key IS NULL THEN
    RAISE WARNING '[notify_contribution_allocated] app.settings not configured. Skipping push.';
    RETURN NEW;
  END IF;

  SELECT extensions.http_post(
    url     := _supabase_url || '/functions/v1/send-notification',
    body    := jsonb_build_object(
      'type',    'user',
      'user_id', NEW.user_id::TEXT,
      'title',   'Contribution Confirmed ✅',
      'body',    'Your contribution to ' || _group_name || ' was confirmed',
      'data',    jsonb_build_object(
        'route',    '/groups/' || NEW.group_id::TEXT,
        'type',     'contribution_confirmed',
        'group_id', NEW.group_id::TEXT
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

DROP TRIGGER IF EXISTS trg_notify_contribution_allocated ON public.group_contributions;

CREATE TRIGGER trg_notify_contribution_allocated
  AFTER INSERT OR UPDATE OF status
  ON public.group_contributions
  FOR EACH ROW
  WHEN (NEW.status = 'confirmed')
  EXECUTE FUNCTION public.notify_contribution_allocated();

COMMENT ON FUNCTION public.notify_contribution_allocated() IS
  'Sends a push notification to the contributor when their payment is confirmed/allocated.';
