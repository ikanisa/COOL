-- ==========================================================================
-- Phase 5B: Soft-delete support for user accounts
-- ==========================================================================
-- Adds deleted_at and deletion_reason columns to users table.
-- The delete-account Edge Function can use soft-delete mode.
-- ==========================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS deletion_reason TEXT;

-- Index for finding soft-deleted users (cleanup cron)
CREATE INDEX IF NOT EXISTS idx_users_deleted_at
  ON public.users (deleted_at)
  WHERE deleted_at IS NOT NULL;

-- RPC: soft-delete a user account
CREATE OR REPLACE FUNCTION public.soft_delete_user(
  p_reason TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  -- Mark user as soft-deleted
  UPDATE public.users
  SET
    deleted_at = now(),
    deletion_reason = nullif(btrim(coalesce(p_reason, '')), '')
  WHERE id = v_user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found or already deleted.';
  END IF;

  -- Deactivate BioPay enrollment if exists
  UPDATE public.biopay_profiles
  SET active = false, revoked_at = now()
  WHERE user_id = v_user_id AND active = true AND deleted_at IS NULL;

  -- Deactivate BioPay embeddings
  UPDATE public.biopay_embeddings
  SET active = false, retired_at = now()
  WHERE profile_id IN (
    SELECT id FROM public.biopay_profiles WHERE user_id = v_user_id
  ) AND active = true;

  RETURN jsonb_build_object(
    'status', 'soft_deleted',
    'user_id', v_user_id,
    'deleted_at', now(),
    'permanent_deletion_after', now() + interval '30 days'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.soft_delete_user(text) TO authenticated;

-- RPC: admin can permanently purge soft-deleted users older than N days
CREATE OR REPLACE FUNCTION public.purge_soft_deleted_users(
  p_days_old INT DEFAULT 30
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_count INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  -- Delete from auth.users will cascade to public.users and all dependent tables
  DELETE FROM auth.users
  WHERE id IN (
    SELECT u.id FROM public.users u
    WHERE u.deleted_at IS NOT NULL
      AND u.deleted_at < now() - (p_days_old || ' days')::INTERVAL
  );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.purge_soft_deleted_users(int) TO authenticated;

COMMENT ON FUNCTION public.soft_delete_user(text) IS
  'Soft-deletes the authenticated user. Data is retained for 30 days before '
  'permanent deletion via purge_soft_deleted_users().';
