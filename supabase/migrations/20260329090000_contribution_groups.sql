-- ═══════════════════════════════════════════════════════════
-- Migration: Contribution Groups + Group Messages
-- File: supabase/migrations/20260329090000_contribution_groups.sql
-- Blueprint: §6.6 Contribution Groups + §8.2 Schema Additions
-- ═══════════════════════════════════════════════════════════

-- 1. Contribution Groups table
CREATE TABLE IF NOT EXISTS contribution_groups (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  description   TEXT,
  group_type    TEXT NOT NULL DEFAULT 'community',     -- club|community|savings|fan_circle
  privacy       TEXT NOT NULL DEFAULT 'public',        -- public|friends|private
  target_amount NUMERIC(12,2) DEFAULT 0,
  current_total NUMERIC(12,2) DEFAULT 0,
  momo_code     TEXT,
  deadline      TIMESTAMPTZ,
  is_recurring  BOOL DEFAULT false,
  is_closed     BOOL DEFAULT false,
  invite_code   TEXT UNIQUE,
  member_count  INT DEFAULT 1,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- 2. Group Chat Messages table
CREATE TABLE IF NOT EXISTS group_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    UUID REFERENCES contribution_groups(id) ON DELETE CASCADE,
  sender_id   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  alias       CHAR(6),
  content     TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_contribution_groups_creator  ON contribution_groups(creator_id);
CREATE INDEX IF NOT EXISTS idx_contribution_groups_type     ON contribution_groups(group_type);
CREATE INDEX IF NOT EXISTS idx_contribution_groups_privacy  ON contribution_groups(privacy);
CREATE INDEX IF NOT EXISTS idx_group_messages_group         ON group_messages(group_id);
CREATE INDEX IF NOT EXISTS idx_group_messages_created       ON group_messages(group_id, created_at);

-- 4. RLS Policies
ALTER TABLE contribution_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_messages ENABLE ROW LEVEL SECURITY;

-- Contribution Groups: anyone can read public groups
CREATE POLICY "Public groups are readable by everyone"
  ON contribution_groups FOR SELECT
  USING (privacy = 'public');

-- Contribution Groups: creator can read their own groups
CREATE POLICY "Creator can read own groups"
  ON contribution_groups FOR SELECT
  USING (auth.uid() = creator_id);

-- Contribution Groups: only authenticated users can create
CREATE POLICY "Authenticated users can create groups"
  ON contribution_groups FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = creator_id);

-- Contribution Groups: only creator can update
CREATE POLICY "Creator can update own groups"
  ON contribution_groups FOR UPDATE
  USING (auth.uid() = creator_id)
  WITH CHECK (auth.uid() = creator_id);

-- Group Messages: anyone can read messages from groups they can access
CREATE POLICY "Messages readable by all"
  ON group_messages FOR SELECT
  USING (true);

-- Group Messages: authenticated users can insert
CREATE POLICY "Authenticated users can send messages"
  ON group_messages FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- 5. Realtime: enable for group_messages
ALTER PUBLICATION supabase_realtime ADD TABLE group_messages;

-- ═══════════════════════════════════════════════════════════
-- ROLLBACK (if needed)
-- ═══════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS group_messages;
-- DROP TABLE IF EXISTS contribution_groups;
