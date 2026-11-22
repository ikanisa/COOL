-- Candidate predecessor for held-SMS recovery. Apply only while the existing
-- application fence is closed and writers are drained. The bounded ordinary
-- index build is transactional; it does not silently run CONCURRENTLY outside
-- the controlled migration, or wait indefinitely on production writers.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='app' AND c.relname='momo_transaction_sources' AND c.relkind='r'
     AND c.relowner='postgres'::regrole)
  OR to_regclass('app.burimunsi_momo_sources_raw_lookup') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.momo_transaction_sources'::regclass
    AND attname='raw_sms_id' AND atttypid='text'::regtype AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.momo_transaction_sources'::regclass
    AND attname='transaction_id' AND atttypid='text'::regtype AND NOT attisdropped) THEN
  RAISE EXCEPTION 'sms_source_index_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;
CREATE INDEX burimunsi_momo_sources_raw_lookup ON app.momo_transaction_sources(raw_sms_id,transaction_id);
COMMIT;
