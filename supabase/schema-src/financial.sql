-- One group lock serializes independent payments before aggregates/snapshots.
-- All existing domain batches run in one transaction; trigger locking also
-- covers callers that append through the dedicated runtime connection.
CREATE FUNCTION private.trg_lock_collection_accounting() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
BEGIN
 PERFORM 1 FROM app.collections WHERE id=NEW.collection_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'collection_unavailable' USING ERRCODE='23503'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER accounting_collection_lock BEFORE INSERT ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION private.trg_lock_collection_accounting();

CREATE FUNCTION private.lock_collections(collection_ids text[]) RETURNS void LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE item text;
BEGIN
 FOR item IN SELECT DISTINCT unnest(collection_ids) ORDER BY 1 LOOP
  PERFORM 1 FROM app.collections WHERE id=item FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'collection_unavailable' USING ERRCODE='23503'; END IF;
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.lock_collections(text[]) TO collect_runtime;

-- All financial commands remain in the canonical domain adapters. No second
-- shortened reversal/posting API is exposed by the baseline.
