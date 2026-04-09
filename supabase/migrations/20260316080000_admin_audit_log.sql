-- ═══════════════════════════════════════════════════════════════════════
-- Admin Audit Log — captures all admin mutations for accountability
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action      text NOT NULL,
  target_table text NOT NULL,
  target_id   text,
  old_data    jsonb,
  new_data    jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_audit_log_actor   ON public.admin_audit_log (actor_id);
CREATE INDEX idx_admin_audit_log_action  ON public.admin_audit_log (action);
CREATE INDEX idx_admin_audit_log_created ON public.admin_audit_log (created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Only platform admins can read audit logs
CREATE POLICY admin_audit_log_select ON public.admin_audit_log
  FOR SELECT USING (public.is_admin());

-- ── Trigger function to auto-log admin mutations ──────────────────────

CREATE OR REPLACE FUNCTION public.log_admin_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_table, target_id, new_data)
    VALUES (auth.uid(), 'create', TG_TABLE_NAME, NEW.id::text,
            to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_table, target_id, old_data, new_data)
    VALUES (auth.uid(), 'update', TG_TABLE_NAME, NEW.id::text,
            to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_table, target_id, old_data)
    VALUES (auth.uid(), 'delete', TG_TABLE_NAME, OLD.id::text,
            to_jsonb(OLD));
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

-- ── Attach triggers to admin-managed tables ───────────────────────────

DO $$
DECLARE
  tbl text;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY[
    'partners',
    'partner_services',
    'quick_actions',
    'app_config',
    'admin_role_assignments'
  ])
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON public.%1$I',
      tbl
    );
    EXECUTE format(
      'CREATE TRIGGER trg_audit_%1$s '
      'AFTER INSERT OR UPDATE OR DELETE ON public.%1$I '
      'FOR EACH ROW EXECUTE FUNCTION public.log_admin_mutation()',
      tbl
    );
  END LOOP;
END;
$$;

-- ── RPC to query audit log with pagination + filters ──────────────────

DROP FUNCTION IF EXISTS public.get_admin_audit_log(integer, integer, text, uuid);
CREATE OR REPLACE FUNCTION public.get_admin_audit_log(
  p_limit   integer DEFAULT 50,
  p_offset  integer DEFAULT 0,
  p_action  text    DEFAULT NULL,
  p_actor_id uuid   DEFAULT NULL
)
RETURNS TABLE (
  id           uuid,
  actor_id     uuid,
  actor_name   text,
  actor_phone  text,
  action       text,
  target_table text,
  target_id    text,
  old_data     jsonb,
  new_data     jsonb,
  created_at   timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    a.id,
    a.actor_id,
    u.full_name   AS actor_name,
    u.phone       AS actor_phone,
    a.action,
    a.target_table,
    a.target_id,
    a.old_data,
    a.new_data,
    a.created_at
  FROM public.admin_audit_log a
  LEFT JOIN public.users u ON u.id = a.actor_id
  WHERE (p_action IS NULL OR a.action = p_action)
    AND (p_actor_id IS NULL OR a.actor_id = p_actor_id)
  ORDER BY a.created_at DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_audit_log(integer, integer, text, uuid)
  TO authenticated;
