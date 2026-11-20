BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'payment_reference_fence_required' USING ERRCODE='55000';END IF;
END;$preflight$;
LOCK TABLE app.payments IN ACCESS EXCLUSIVE MODE;

DO $authority$
DECLARE
 expected text[]:=ARRAY['id','collection_id','member_id','evidence_id','intent_id','amount_minor','currency','rail','status','payer_display_name','created_at','revision'];
 actual text[]; allocator regclass:=pg_get_serial_sequence('app.payments','payment_reference')::regclass;
 role_name text;
BEGIN
 SELECT array_agg(attname::text ORDER BY attnum) INTO actual FROM pg_attribute
 WHERE attrelid='app.payments'::regclass AND attnum>0 AND NOT attisdropped;
 IF actual IS DISTINCT FROM array_append(expected,'payment_reference')
  OR NOT has_table_privilege('collect_runtime','app.payments','INSERT') OR NOT has_table_privilege('collect_runtime','app.payments','UPDATE')
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.payments'::regclass AND attname='payment_reference'
    AND attidentity='a' AND atttypid='bigint'::regtype AND attnotnull)
  OR NOT EXISTS(SELECT 1 FROM pg_sequence WHERE seqrelid=allocator AND seqincrement=1 AND seqmin=100000000000
    AND seqmax=999999999999 AND seqstart=100000000000 AND seqcache=1 AND NOT seqcycle)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='app.payments'::regclass
    AND tgname='collect_payment_reference_immutable' AND tgenabled='A'
    AND tgfoid='private.collect_payment_reference_immutable()'::regprocedure) THEN
  RAISE EXCEPTION 'payment_reference_catalog_changed' USING ERRCODE='55000';
 END IF;
 REVOKE INSERT,UPDATE ON TABLE app.payments FROM collect_runtime;
 REVOKE INSERT(payment_reference),UPDATE(payment_reference) ON TABLE app.payments FROM collect_runtime;
 EXECUTE format('GRANT INSERT(%1$s),UPDATE(%1$s) ON app.payments TO collect_runtime',array_to_string(expected,','));
 EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',allocator);
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
  IF has_column_privilege(role_name,'app.payments','payment_reference','INSERT,UPDATE')
   OR has_sequence_privilege(role_name,allocator,'UPDATE') THEN
   RAISE EXCEPTION 'payment_reference_allocation_authority_changed' USING ERRCODE='55000';
  END IF;
 END LOOP;
END;$authority$;

DO $retention$
DECLARE
 body text;
 predecessor constant text:=$columns$    "payments": {
      "columns": [
        "id",
        "collection_id",
        "member_id",
        "evidence_id",
        "intent_id",
        "amount_minor",
        "currency",
        "rail",
        "status",
        "payer_display_name",
        "created_at",
        "revision"
      ]$columns$;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure
  AND pg_get_userbyid(proowner)='postgres' AND NOT prosecdef AND provolatile='i'
  AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}';
 IF length(body)-length(replace(body,predecessor,''))<>length(predecessor)
  OR strpos(body,'private:burimunsi_payment_sms_deliveries')=0 THEN
  RAISE EXCEPTION 'payment_reference_retention_predecessor_changed' USING ERRCODE='55000';
 END IF;
 body:=replace(body,predecessor,replace(predecessor,'"revision"',E'"revision",\n        "payment_reference"'));
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(body);
END;$retention$;
DO $forward$
DECLARE
 allocator regclass:=pg_get_serial_sequence('app.payments','payment_reference')::regclass;
 last_issued bigint; was_called boolean; highest bigint;
BEGIN
 SELECT max(payment_reference) INTO highest FROM app.payments;
 EXECUTE format('SELECT last_value,is_called FROM %s',allocator) INTO last_issued,was_called;
 IF highest>last_issued OR highest=last_issued AND NOT was_called THEN
  PERFORM setval(allocator,highest,true);
 END IF;
END;$forward$;
COMMIT;
