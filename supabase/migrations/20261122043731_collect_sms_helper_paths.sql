-- The SMS gateway helpers use only PostgreSQL built-ins.
-- Preserve their definitions and grants while fixing name resolution.
BEGIN;
ALTER FUNCTION collect_sms.json_valid(text) SET search_path TO pg_catalog, pg_temp;
ALTER FUNCTION collect_sms.json_extract(text, text) SET search_path TO pg_catalog, pg_temp;
ALTER FUNCTION collect_sms.json_each(text) SET search_path TO pg_catalog, pg_temp;
ALTER FUNCTION collect_sms.max(bigint, bigint) SET search_path TO pg_catalog, pg_temp;
COMMIT;
