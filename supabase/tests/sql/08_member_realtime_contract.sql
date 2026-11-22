BEGIN;
DO $contract$
DECLARE r text;n bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace s ON s.oid=c.relnamespace WHERE s.nspname='private' AND c.relname='member_realtime_control' AND c.relrowsecurity) THEN RAISE EXCEPTION 'Realtime private control/RLS missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid='private.member_realtime_control'::regclass AND t.tgname='collect_fence_statement_v1' AND t.tgenabled='A' AND t.tgtype=62) THEN RAISE EXCEPTION 'Realtime control lacks ALWAYS admission guard';END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','collect_runtime','collect_importer','service_role'] LOOP
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=r) AND pg_catalog.has_table_privilege(r,'private.member_realtime_control','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN RAISE EXCEPTION 'Realtime control ACL leak';END IF;
 END LOOP;
 IF NOT pg_catalog.has_function_privilege('authenticated','private.collect_member_realtime_join(text)','EXECUTE')
 OR pg_catalog.has_function_privilege('anon','private.collect_member_realtime_join(text)','EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated','private.collect_member_realtime_publish()','EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated','private.retention_member_realtime_inventory(text)','EXECUTE')
 OR pg_catalog.has_function_privilege('collect_runtime','private.collect_member_realtime_configure(boolean,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Realtime helper capability leak';END IF;
 IF pg_catalog.has_schema_privilege('authenticated','private','USAGE') OR pg_catalog.has_schema_privilege('anon','private','USAGE') THEN RAISE EXCEPTION 'Realtime widened private namespace';END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc f JOIN pg_catalog.pg_namespace s ON s.oid=f.pronamespace CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(f.proacl,pg_catalog.acldefault('f',f.proowner))) a WHERE s.nspname='private' AND(pg_catalog.starts_with(f.proname,'collect_member_realtime_') OR pg_catalog.starts_with(f.proname,'_collect_member_realtime_') OR f.proname='retention_member_realtime_inventory') AND a.grantee=0 AND a.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'Realtime PUBLIC execute leak';END IF;
 SELECT count(*) INTO n FROM pg_catalog.pg_policy p WHERE p.polrelid='realtime.messages'::regclass AND p.polname IN('collect_member_receive_v1','collect_member_receive_guard_v1','collect_member_no_insert_v1','collect_member_no_update_v1','collect_member_no_delete_v1','collect_member_no_anonymous_v1');
 IF n<>6 OR(SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid='realtime.messages'::regclass)<>6 THEN RAISE EXCEPTION 'Realtime policy scope changed';END IF;
 IF(SELECT count(*) FROM pg_catalog.pg_policy WHERE polrelid='realtime.messages'::regclass AND NOT polpermissive)<>5 THEN RAISE EXCEPTION 'Realtime restrictive guards missing';END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc f JOIN pg_catalog.pg_namespace s ON s.oid=f.pronamespace WHERE s.nspname='private' AND(pg_catalog.starts_with(f.proname,'collect_member_realtime_') OR pg_catalog.starts_with(f.proname,'_collect_member_realtime_') OR f.proname='retention_member_realtime_inventory') AND (f.proconfig IS NULL OR pg_catalog.cardinality(f.proconfig)<>1 OR pg_catalog.replace(f.proconfig[1],' ','')<>'search_path=pg_catalog,pg_temp')) THEN RAISE EXCEPTION 'Realtime helper search path differs';END IF;
END;$contract$;
ROLLBACK;
