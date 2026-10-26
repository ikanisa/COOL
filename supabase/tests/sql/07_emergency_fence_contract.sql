BEGIN;
-- Run only through the admitted loopback aggregate, with a genuine durable row
-- and a separate live shared-WORK transaction. No test bypass or owner grant.
CREATE FUNCTION pg_temp.fence_expect_failure(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN
  IF position(expected IN SQLERRM)>0 THEN RETURN;ELSE RAISE EXCEPTION 'Wrong emergency-fence failure';END IF;
 END;
 RAISE EXCEPTION 'Expected emergency-fence denial';
END$$;
CREATE FUNCTION pg_temp.fence_definer_write() RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 UPDATE app.auth_rate_buckets SET used=used WHERE false
$$;
GRANT EXECUTE ON FUNCTION pg_temp.fence_definer_write() TO collect_runtime;
DO $$DECLARE n bigint;r text;
BEGIN
 SELECT count(*) INTO n FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace s ON s.oid=c.relnamespace
 WHERE s.nspname IN('app','private') AND t.tgname='collect_fence_statement_v1' AND t.tgenabled='A' AND t.tgtype=62;
 IF n<>113 THEN RAISE EXCEPTION 'Exact113 table fence coverage including both Admin email tables missing';END IF;
 FOREACH r IN ARRAY ARRAY['collect_runtime','anon','authenticated','service_role','collect_importer'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) AND EXISTS(
   SELECT 1 FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace WHERE s.nspname='private' AND c.relname IN('collect_fence_control','collect_fence_admissions','collect_fence_operations','collect_fence_scheduler_lifecycle')
   AND has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')) THEN RAISE EXCEPTION 'Fence custody table privilege leak';END IF;
 END LOOP;
 IF has_function_privilege('collect_runtime','private.collect_fence_initialize(uuid,text,text)','EXECUTE')
 OR has_function_privilege('collect_runtime','private.collect_fence_begin_quiesce(uuid,bigint,text)','EXECUTE')
 OR has_function_privilege('collect_runtime','private.collect_fence_drain(uuid,bigint,text)','EXECUTE')
 OR has_function_privilege('collect_runtime','private.collect_fence_release(uuid,bigint,text)','EXECUTE')
 OR has_function_privilege('collect_runtime','private.collect_fence_owner_status()','EXECUTE') THEN RAISE EXCEPTION 'Runtime gained fence controller authority';END IF;
 IF (SELECT count(*) FROM app.ledger_entries)<>0 THEN RAISE EXCEPTION 'SQL fixture baseline unexpectedly contains money';END IF;
END$$;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write(current_setting('collect.fence_admission_id')::uuid,current_setting('collect.fence_epoch')::bigint,current_setting('collect.fence_source_sha256'));
SELECT pg_temp.fence_expect_failure($q$SELECT private.collect_fence_assert_write(NULL,NULL,NULL)$q$,'collect_fence_forbidden');
SELECT pg_temp.fence_expect_failure($q$SELECT private.collect_fence_owner_status()$q$,'permission denied');
-- A business connection is not the separately held WORK connection.
SELECT pg_temp.fence_expect_failure($q$SELECT private.collect_fence_assert_work(current_setting('collect.fence_admission_id')::uuid,current_setting('collect.fence_epoch')::bigint,current_setting('collect.fence_source_sha256'))$q$,'collect_fence_unavailable');
SELECT set_config('collect.fence_admission_id','00000000-0000-4000-8000-000000000099',true);
SELECT pg_temp.fence_expect_failure($q$UPDATE app.auth_rate_buckets SET used=used WHERE false$q$,'collect_fence_conflict');
SELECT pg_temp.fence_expect_failure($q$SELECT pg_temp.fence_definer_write()$q$,'collect_fence_conflict');
RESET ROLE;
-- Restore the genuine row from its opaque fixture context, not a synthetic GUC
-- without authority. The aggregate writes this saved value before all suites.
-- This suite ends here so no authority-bearing operation uses the wrong tuple.
ROLLBACK;
