BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
  target regclass;
BEGIN
  PERFORM private._collect_fence_require_operator();
  PERFORM 1 FROM private.collect_fence_control WHERE singleton AND mode = 'fenced' FOR SHARE;
  IF NOT FOUND OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'collect_runtime' AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'burimunsi_journal_runtime_precondition' USING ERRCODE = '55000';
  END IF;
  FOREACH target IN ARRAY ARRAY[
    'private.burimunsi_audit'::regclass,
    'private.burimunsi_command_receipts'::regclass,
    'private.burimunsi_rate_limits'::regclass
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_policy p ON p.polrelid = c.oid
      WHERE c.oid = target AND c.relrowsecurity AND c.relforcerowsecurity
        AND p.polname = 'burimunsi_scoped_runtime' AND p.polcmd = '*' AND p.polpermissive
        AND 'collect_runtime'::regrole = ANY(p.polroles)
    ) THEN
      RAISE EXCEPTION 'burimunsi_journal_runtime_scope_missing' USING ERRCODE = '55000';
    END IF;
  END LOOP;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgrelid = 'private.burimunsi_command_receipts'::regclass
      AND tgname = 'burimunsi_smart_import_guard' AND tgfoid = 'private.burimunsi_smart_import_guard()'::regprocedure
      AND tgenabled = 'A' AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'burimunsi_journal_transition_guard_missing' USING ERRCODE = '55000';
  END IF;
END;
$preflight$;

REVOKE UPDATE ON private.burimunsi_audit, private.burimunsi_command_receipts,
  private.burimunsi_rate_limits FROM collect_runtime;
GRANT UPDATE (response) ON private.burimunsi_command_receipts TO collect_runtime;
GRANT UPDATE (attempts) ON private.burimunsi_rate_limits TO collect_runtime;

CREATE POLICY burimunsi_runtime_import_response
  ON private.burimunsi_command_receipts AS RESTRICTIVE FOR UPDATE TO collect_runtime
  USING (true) WITH CHECK (operation = 'burimunsi.smart_import.v1');

CREATE FUNCTION private.burimunsi_rate_limit_attempt_step() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, pg_temp AS $step$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.attempts = 1 THEN RETURN NEW; END IF;
  ELSIF NEW.attempts = OLD.attempts + 1 THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'burimunsi_rate_limit_attempt_step' USING ERRCODE = '23514';
END;
$step$;
REVOKE ALL ON FUNCTION private.burimunsi_rate_limit_attempt_step()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER burimunsi_runtime_rate_step BEFORE INSERT OR UPDATE OF attempts
  ON private.burimunsi_rate_limits FOR EACH ROW
  WHEN (pg_has_role(current_user, 'collect_runtime', 'USAGE') AND NOT pg_has_role(current_user, 'postgres', 'USAGE'))
  EXECUTE FUNCTION private.burimunsi_rate_limit_attempt_step();
ALTER TABLE private.burimunsi_rate_limits ENABLE ALWAYS TRIGGER burimunsi_runtime_rate_step;

DO $verify$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (VALUES ('private.burimunsi_audit'::regclass, ''::text),
                 ('private.burimunsi_command_receipts'::regclass, 'response'),
                 ('private.burimunsi_rate_limits'::regclass, 'attempts')) AS expected(relation, writable)
    JOIN pg_attribute a ON a.attrelid = expected.relation AND a.attnum > 0 AND NOT a.attisdropped
    WHERE has_column_privilege('collect_runtime', expected.relation, a.attnum, 'UPDATE')
          IS DISTINCT FROM (a.attname::text = expected.writable)
       OR has_table_privilege('collect_runtime', expected.relation, 'DELETE, TRUNCATE')
  ) THEN
    RAISE EXCEPTION 'burimunsi_journal_unexpected_runtime_grants' USING ERRCODE = '55000';
  END IF;
END;
$verify$;
COMMIT;
