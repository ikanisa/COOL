BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'burimunsi_members_fence_required' USING ERRCODE='55000';
 END IF;
END;$preflight$;

-- Parse only the wire instant forms already recognized by native listing.
-- Offset arithmetic keeps the key independent of database and session locale.
CREATE FUNCTION private.burimunsi_member_joined(value text) RETURNS timestamptz
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
SET search_path=pg_catalog SET datestyle='ISO, YMD' SET timezone='UTC' AS $fn$
DECLARE parts text[]; wall timestamp; zone text; offset_minutes integer:=0;
BEGIN
 parts:=regexp_match(value,'^([0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,6})?)(Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$');
 IF parts IS NULL OR NOT pg_input_is_valid(parts[1],'timestamp without time zone') THEN RETURN NULL; END IF;
 wall:=parts[1]::timestamp;
 zone:=parts[2];
 IF zone<>'Z' THEN
  offset_minutes:=substr(zone,2,2)::integer*60+substr(zone,5,2)::integer;
  IF left(zone,1)='-' THEN offset_minutes:=-offset_minutes; END IF;
 END IF;
 RETURN date_trunc('milliseconds',wall-make_interval(mins=>offset_minutes)) AT TIME ZONE 'UTC';
END;
$fn$;

CREATE FUNCTION private.burimunsi_member_phone(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE SET search_path=pg_catalog AS $fn$
 WITH clean AS (
  SELECT regexp_replace(value,'[ ()-]','','g') AS compact
  WHERE length(value)<=40 AND value ~ '^[+0-9 ()-]+$'
 ), prefix AS (
  SELECT CASE WHEN compact LIKE '00%' THEN '+'||substr(compact,3) ELSE compact END AS value FROM clean
 ), normalized AS (
  SELECT CASE WHEN value ~ '^0[0-9]{9}$' THEN '+250'||substr(value,2)
              WHEN value ~ '^[0-9]{9}$' THEN '+250'||value
              WHEN value ~ '^250[0-9]{9}$' THEN '+'||value ELSE value END AS value
  FROM prefix
 )
 SELECT value FROM normalized WHERE value ~ '^\+2507[2389][0-9]{7}$';
$fn$;

-- Membership and ledger triggers already advance this group generation. A
-- display-name or MoMo update also changes list order and must stale cursors.
-- The existing version guard accepts only nested trigger writes and +1.
CREATE FUNCTION private._burimunsi_member_identity_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE group_id text;
BEGIN
 FOR group_id IN SELECT collection_id FROM app.memberships WHERE user_id=NEW.id ORDER BY collection_id LOOP
  UPDATE private.member_history_versions SET revision=revision+1 WHERE collection_id=group_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_missing'; END IF;
 END LOOP;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER burimunsi_member_identity_changed AFTER UPDATE OF full_name,momo_number ON app.users
 FOR EACH ROW WHEN ((OLD.full_name,OLD.momo_number) IS DISTINCT FROM (NEW.full_name,NEW.momo_number))
 EXECUTE FUNCTION private._burimunsi_member_identity_changed();
ALTER TABLE app.users ENABLE ALWAYS TRIGGER burimunsi_member_identity_changed;

CREATE INDEX burimunsi_members_joined_newest ON app.memberships
 (collection_id,private.burimunsi_member_joined(joined_at) DESC NULLS LAST,user_id COLLATE "C");
CREATE INDEX burimunsi_members_joined_oldest ON app.memberships
 (collection_id,private.burimunsi_member_joined(joined_at) ASC NULLS LAST,user_id COLLATE "C");

REVOKE ALL ON FUNCTION private._burimunsi_member_identity_changed(),
 private.burimunsi_member_joined(text),private.burimunsi_member_phone(text)
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
-- The importer computes membership index keys during its existing inserts.
GRANT EXECUTE ON FUNCTION private.burimunsi_member_joined(text) TO collect_runtime,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_member_phone(text) TO collect_runtime;
COMMIT;
