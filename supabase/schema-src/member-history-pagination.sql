-- Group-scoped immutable-cursor invalidation and aggregate/page indexes.
-- Does not alter financial rows, balances or existing application revisions.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
LOCK TABLE app.collections,app.memberships,app.ledger_entries,app.payments,app.users,app.payment_evidence IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE private.member_history_versions(
 collection_id text PRIMARY KEY REFERENCES app.collections(id),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0)
);
ALTER TABLE private.member_history_versions ENABLE ROW LEVEL SECURITY;
INSERT INTO private.member_history_versions(collection_id) SELECT id FROM app.collections;

CREATE FUNCTION private._member_history_version_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF pg_trigger_depth()<2 OR TG_OP NOT IN('INSERT','UPDATE') THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_authority_required';END IF;
 IF TG_OP='UPDATE' AND(NEW.collection_id<>OLD.collection_id OR NEW.revision<>OLD.revision+1) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_regression';END IF;
 IF TG_OP='INSERT' AND NEW.revision<>1 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_regression';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER member_history_version_guard BEFORE INSERT OR UPDATE OR DELETE ON private.member_history_versions
 FOR EACH ROW EXECUTE FUNCTION private._member_history_version_guard();
CREATE TRIGGER member_history_version_no_truncate BEFORE TRUNCATE ON private.member_history_versions
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.member_history_versions ENABLE ALWAYS TRIGGER member_history_version_guard;
ALTER TABLE private.member_history_versions ENABLE ALWAYS TRIGGER member_history_version_no_truncate;

CREATE FUNCTION private._member_history_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE group_id text;
BEGIN
 IF TG_TABLE_NAME='users' THEN
  IF NEW.public_id IS NOT DISTINCT FROM OLD.public_id THEN RETURN NEW;END IF;
  FOR group_id IN SELECT DISTINCT collection_id FROM app.ledger_entries WHERE member_id=NEW.id ORDER BY collection_id LOOP
   UPDATE private.member_history_versions SET revision=revision+1 WHERE collection_id=group_id;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_missing';END IF;
  END LOOP;
  RETURN NEW;
 END IF;
 IF TG_TABLE_NAME='collections' THEN
  group_id:=NEW.id;
  IF TG_OP='INSERT' THEN
   INSERT INTO private.member_history_versions(collection_id) VALUES(group_id);RETURN NEW;
  END IF;
  IF NEW.title IS NOT DISTINCT FROM OLD.title THEN RETURN NEW;END IF;
 ELSIF TG_TABLE_NAME='payments' THEN
  IF TG_OP='UPDATE' AND(NEW.status,NEW.rail,NEW.collection_id) IS NOT DISTINCT FROM(OLD.status,OLD.rail,OLD.collection_id) THEN RETURN NEW;END IF;
  group_id:=NEW.collection_id;
 ELSIF TG_TABLE_NAME='payment_evidence' THEN
  IF NEW.external_reference IS NOT DISTINCT FROM OLD.external_reference THEN RETURN NEW;END IF;
  group_id:=NEW.collection_id;
 ELSE
  group_id:=CASE WHEN TG_OP='DELETE' THEN OLD.collection_id ELSE NEW.collection_id END;
 END IF;
 UPDATE private.member_history_versions SET revision=revision+1 WHERE collection_id=group_id;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_missing';END IF;
 IF TG_TABLE_NAME IN('ledger_entries','memberships') THEN
  IF TG_OP='UPDATE' AND OLD.collection_id<>NEW.collection_id THEN
   UPDATE private.member_history_versions SET revision=revision+1 WHERE collection_id=OLD.collection_id;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='history_revision_missing';END IF;
  END IF;
 END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;$fn$;
CREATE TRIGGER member_history_changed AFTER INSERT OR UPDATE OF title ON app.collections
 FOR EACH ROW EXECUTE FUNCTION private._member_history_changed();
CREATE TRIGGER member_history_changed AFTER INSERT OR UPDATE OR DELETE ON app.memberships
 FOR EACH ROW EXECUTE FUNCTION private._member_history_changed();
CREATE TRIGGER member_history_changed AFTER INSERT OR UPDATE OR DELETE ON app.ledger_entries
 FOR EACH ROW EXECUTE FUNCTION private._member_history_changed();
CREATE TRIGGER member_history_changed AFTER UPDATE OF status,rail,collection_id ON app.payments
 FOR EACH ROW EXECUTE FUNCTION private._member_history_changed();
CREATE TRIGGER member_history_changed AFTER UPDATE OF public_id ON app.users
 FOR EACH ROW EXECUTE FUNCTION private._member_history_changed();
CREATE TRIGGER member_history_changed AFTER UPDATE OF external_reference ON app.payment_evidence
 FOR EACH ROW EXECUTE FUNCTION private._member_history_changed();
ALTER TABLE app.collections ENABLE ALWAYS TRIGGER member_history_changed;
ALTER TABLE app.memberships ENABLE ALWAYS TRIGGER member_history_changed;
ALTER TABLE app.ledger_entries ENABLE ALWAYS TRIGGER member_history_changed;
ALTER TABLE app.payments ENABLE ALWAYS TRIGGER member_history_changed;
ALTER TABLE app.users ENABLE ALWAYS TRIGGER member_history_changed;
ALTER TABLE app.payment_evidence ENABLE ALWAYS TRIGGER member_history_changed;

-- The complete filtered total still scans matching ledger entries. These
-- indexes bound group/date filtering, keyset seek and group/member aggregation;
-- no O(history-size) list is returned to an Edge isolate for a 50-item page.
CREATE INDEX ledger_collection_history_newest ON app.ledger_entries(collection_id,posted_at DESC,id ASC);
CREATE INDEX ledger_collection_history_oldest ON app.ledger_entries(collection_id,posted_at ASC,id ASC);
CREATE INDEX ledger_collection_history_highest ON app.ledger_entries(collection_id,amount_minor DESC,posted_at DESC,id ASC);
CREATE INDEX ledger_collection_history_lowest ON app.ledger_entries(collection_id,amount_minor ASC,posted_at DESC,id ASC);
CREATE INDEX ledger_collection_member_balance ON app.ledger_entries(collection_id,member_id) INCLUDE(amount_minor);
CREATE POLICY member_history_version_runtime_read ON private.member_history_versions FOR SELECT TO collect_runtime USING(true);
REVOKE ALL ON TABLE private.member_history_versions FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
GRANT SELECT ON TABLE private.member_history_versions TO collect_runtime;
REVOKE ALL ON FUNCTION private._member_history_changed(),private._member_history_version_guard()
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
COMMIT;
