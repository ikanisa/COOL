-- ==========================================================================
-- Phase 4B: group_messages v2 (member-scoped RLS)
-- ==========================================================================
-- Reimplements group_messages linked to public.groups (not the dropped
-- contribution_groups). Fixed RLS: only group members can read/write.
-- ==========================================================================

-- Idempotent: only create if not exists
CREATE TABLE IF NOT EXISTS public.group_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  sender_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  alias       TEXT,
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_messages_group_created
  ON public.group_messages (group_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_group_messages_sender
  ON public.group_messages (sender_id);

ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

-- Only group members can read messages (fixes previous USING(true) bug)
DROP POLICY IF EXISTS "Messages readable by all" ON public.group_messages;
DROP POLICY IF EXISTS group_messages_select_member ON public.group_messages;
CREATE POLICY group_messages_select_member
  ON public.group_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_messages.group_id
        AND gm.user_id = auth.uid()
    )
  );

-- Only group members can send messages (must be sender)
DROP POLICY IF EXISTS "Authenticated users can send messages" ON public.group_messages;
DROP POLICY IF EXISTS group_messages_insert_member ON public.group_messages;
CREATE POLICY group_messages_insert_member
  ON public.group_messages FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = group_messages.group_id
        AND gm.user_id = auth.uid()
    )
  );

-- Admin can read all messages
DROP POLICY IF EXISTS group_messages_admin_select ON public.group_messages;
CREATE POLICY group_messages_admin_select
  ON public.group_messages FOR SELECT
  USING (public.is_admin_user());

-- Enable Realtime
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_messages;
  EXCEPTION WHEN duplicate_object THEN
    NULL; -- already added
  END;
END $$;

COMMENT ON TABLE public.group_messages IS
  'Group chat messages. RLS ensures only group members can read and write.';
