-- UNREGISTERED DESIGN DRAFT. Operator-only installation; no live use.
-- Exact retained owner binding, never an owner email supplied by an HTTP client.
-- Requires the full reviewed chain plus the separate retention inspection draft.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE r record;owners bigint;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres' OR to_regclass('private.collect_owner_identity') IS NOT NULL
  OR to_regprocedure('private.collect_owner_id_valid(text)') IS NOT NULL
  OR to_regprocedure('private.collect_owner_email_valid(text)') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR NOT EXISTS(SELECT 1 FROM pg_index WHERE indexrelid='app.admin_single_owner'::regclass AND indrelid='app.admin_users'::regclass AND indisunique AND indisvalid AND pg_get_expr(indpred,indrelid)='(role = ''owner''::text)')
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app.admin_users'::regclass AND conname='admin_users_check'
   AND encode(sha256(convert_to(pg_get_constraintdef(oid),'UTF8')),'hex')='b334d0399d3897cf35577bb1e38ce2a829e22b9675040f86be22ec2368bb2c23') THEN
  RAISE EXCEPTION 'owner_identity_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES ('private.admin_invitation_actor(text,text,text,text)','9653b09543cc24c9c310b058ecdc99c7e044577ad343afa53ef8d37d77853c10','plpgsql',true,'v','u',ARRAY['search_path=pg_catalog']::text[],'{postgres=X/postgres}'),('private.admin_invitation_v1_prepare_legacy(text,text,text,text,text,text,text,text,text,text,text,text)','9278b1b5260cbccfd87a37001e761bda33f7a654de5da4eefbbd5489628b4ccf','plpgsql',true,'v','u',ARRAY['search_path=pg_catalog']::text[],'{postgres=X/postgres}'),('private.admin_invitation_v2_prepare(text,text,text,text,text,text,text,text,text,text,text,text,uuid)','5b9c211fc17417045d641bdc837de5d9b1aef1dea9f3363c7ade9f4b2ea4030f','plpgsql',true,'v','u',ARRAY['search_path=pg_catalog']::text[],'{postgres=X/postgres,collect_runtime=X/postgres}'),('private.trg_admin_owner_bootstrap_apply()','a55867eb3070740430e6111051a8bb639186da02d57a12d2c716eb74fa3bbfdc','plpgsql',false,'v','u',ARRAY['search_path=app, pg_catalog']::text[],'{postgres=X/postgres,collect_runtime=X/postgres}'),('private.trg_assisted_sms_grant_explicit()','094c0935dac23ecd455e8cb057678dc833522453df1b298e4b0236f5c027a492','plpgsql',false,'v','u',ARRAY['search_path=app, pg_catalog']::text[],'{postgres=X/postgres,collect_runtime=X/postgres}'),('private._retention_manifest_catalog_v2()','1de21d0e945be7ff3612eb8216ec5f4abe7e809ccbccf0e48a8915c3a73a677c','sql',false,'i','u',ARRAY['search_path=pg_catalog, pg_temp']::text[],'{postgres=X/postgres}'),('private._retention_manifest_rows_v2(text)','5aa6ca4011d0fa45e644066da4e90fd74fa55fe0c115a13c047e5399319a30a0','plpgsql',true,'s','u',ARRAY['search_path=app, pg_catalog, pg_temp']::text[],'{postgres=X/postgres}'),('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','2ebb3c0ecb768e8111d5de9a7b8f30a0d7b8e50f64a114644e8f8bf2b31cf354','plpgsql',true,'v','u',ARRAY['search_path=pg_catalog, pg_temp']::text[],'{postgres=X/postgres,collect_runtime=X/postgres}')) e(sig,hash,language,definer,volatility,parallel,config,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres' AND l.lanname=r.language
    AND p.prosecdef=r.definer AND p.provolatile=r.volatility AND p.proparallel=r.parallel AND p.prokind='f' AND NOT p.proleakproof
    AND p.proconfig=r.config AND p.proacl::text=r.acl AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'owner_identity_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 FOR r IN SELECT * FROM (VALUES ('app.admin_owner_bootstrap_claims','admin_owner_bootstrap_admission','O','c34e24cccbc38e9d128c7967c7398267cc55c1ea1491f1e6ff6ba9cf174a80ac'),('app.admin_owner_bootstrap_claims','admin_owner_bootstrap_apply','O','959f08afecbd609dfdfa9db9726375ca8b6d44b60ac6956b4a9031d085978b8e'),('app.admin_owner_bootstrap_claims','admin_owner_bootstrap_no_delete','O','9c6c5d6cceb1117b53c25e83271c19fd7b886b3d7de1c5fa90f3123e6b39413b'),('app.admin_owner_bootstrap_claims','admin_owner_bootstrap_no_update','O','678fea1578eb18bbc5d0449de6424e7e856d9669fd2e05538e975d71037b9704'),('app.admin_owner_bootstrap_claims','collect_fence_statement_v1','A','8f14532d178a27f89aa0dc905c2834d8dcd8c3d9289a91692a6fe9261d768e7a'),('app.admin_principal_links','admin_link_grants','O','c77f7ac126a0377f7ad7ef8cb38d8e0e5b282e89ecce56efd2d41379a2e0b8f4'),('app.admin_principal_links','admin_principal_link_immutable','O','9ec2d81e4d8d3bfc8917ae35e18a1fef755080b200bd0ce95a0f778db909dd81'),('app.admin_principal_links','admin_principal_link_revoked','O','b992c3f8b03fb0cf3109507e249636162478937278aadb64071ae562871f6059'),('app.admin_principal_links','collect_fence_statement_v1','A','92981d6b0749c14c68760c5656757a541fea9ffce4c2db254bd920dc247cce8a'),('app.admin_users','admin_account_authority_changed','O','44c4907a113b80f376d412cc40e035cbc2dd0342c2eb0d79b9b2bd8b246fbabe'),('app.admin_users','collect_fence_statement_v1','A','70427e8721495394178a0a1796f1bac23cc0d5a98c42e6968a60960dfb780cfa')) e(relation,name,enabled,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass(r.relation) AND t.tgname=r.name AND NOT t.tgisinternal
   AND t.tgenabled=r.enabled AND encode(sha256(convert_to(pg_get_triggerdef(t.oid),'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'owner_identity_trigger_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 SELECT count(*) INTO owners FROM app.admin_users WHERE role='owner';
 IF owners>1 OR owners=1 AND NOT EXISTS(SELECT 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  JOIN app.users u ON u.id=l.user_id AND u.access_status='active' JOIN private.auth_principal_links p ON p.user_id=u.id
  JOIN auth.users m ON m.id=p.auth_user_id AND lower(m.email)=a.email AND to_jsonb(m)->>'email_confirmed_at' IS NOT NULL
  WHERE a.role='owner' AND a.status='active' AND a.email=lower(btrim(a.email)) AND length(a.email) BETWEEN 3 AND 254)
 THEN RAISE EXCEPTION 'owner_identity_existing_owner_unverified' USING ERRCODE='55000';END IF;
END;$preflight$;

-- The opt-in session DTO carries opaque IDs and a normalized Admin email.
-- Count supplementary Unicode characters as two UTF-16 code units, as the
-- Android/web clients do, and reject all C0/C1 control characters.
CREATE FUNCTION private.collect_owner_id_valid(v text) RETURNS boolean
 LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT coalesce(v IS NOT NULL AND length(v) BETWEEN 1 AND 200
  AND v=btrim(v,U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF')
  AND v !~ U&'[\0001-\001F\007F-\009F]'
  AND length(v)+(SELECT count(*) FROM generate_series(1,length(v)) n WHERE octet_length(substr(v,n,1))=4)<=200,false)
$fn$;
CREATE FUNCTION private.collect_owner_email_valid(v text) RETURNS boolean
 LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT coalesce(v IS NOT NULL AND length(v) BETWEEN 3 AND 254 AND v=lower(v) AND v=btrim(v)
  AND v ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$'
  AND length(split_part(v,'@',1))<=64 AND split_part(v,'@',1) !~ '(^\.|\.$|\.\.)',false)
$fn$;
REVOKE ALL ON FUNCTION private.collect_owner_id_valid(text),private.collect_owner_email_valid(text)
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
DO $owner_dto_preflight$
BEGIN
 IF EXISTS(SELECT 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  WHERE a.role='owner' AND (NOT private.collect_owner_id_valid(a.id) OR NOT private.collect_owner_id_valid(l.user_id)
   OR NOT private.collect_owner_email_valid(a.email))) THEN
  RAISE EXCEPTION 'owner_identity_existing_owner_unverified' USING ERRCODE='55000';END IF;
END;$owner_dto_preflight$;

CREATE TABLE private.collect_owner_identity(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),operation_id uuid NOT NULL UNIQUE,
 admin_user_id text NOT NULL UNIQUE CHECK(private.collect_owner_id_valid(admin_user_id)),
 principal_user_id text NOT NULL UNIQUE CHECK(private.collect_owner_id_valid(principal_user_id)),
 owner_email text NOT NULL UNIQUE CHECK(private.collect_owner_email_valid(owner_email)),
 approval_reference text NOT NULL CHECK(length(approval_reference) BETWEEN 8 AND 200 AND approval_reference !~ '[[:cntrl:]]'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),recorded_by text NOT NULL DEFAULT session_user::text
);
ALTER TABLE private.collect_owner_identity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_owner_identity FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
INSERT INTO private.collect_owner_identity(operation_id,admin_user_id,principal_user_id,owner_email,approval_reference)
 SELECT gen_random_uuid(),a.id,l.user_id,a.email,'existing-verified-owner-migration'
 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE a.role='owner';
CREATE FUNCTION private.collect_owner_identity_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN RAISE EXCEPTION 'owner_identity_immutable' USING ERRCODE='42501';END;$fn$;
CREATE TRIGGER collect_owner_identity_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_owner_identity
 FOR EACH STATEMENT EXECUTE FUNCTION private.collect_owner_identity_immutable();
ALTER TABLE private.collect_owner_identity ENABLE ALWAYS TRIGGER collect_owner_identity_immutable;

-- Only the runtime's edge-verified SQL frame or the installation operator may
-- read the binding. No caller controls an owner ID/email in an HTTP request.
CREATE FUNCTION private.collect_owner_binding() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b jsonb;
BEGIN
 IF current_setting('role',true)='collect_runtime' THEN PERFORM private._collect_fence_require_runtime();
 ELSE PERFORM private._collect_fence_require_operator();END IF;
 SELECT jsonb_build_object('schemaVersion',1,'adminId',admin_user_id,'principalId',principal_user_id,'email',owner_email)
 INTO b FROM private.collect_owner_identity WHERE singleton;
 RETURN b;
END;$fn$;
CREATE FUNCTION private.collect_owner_email() RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b jsonb:=private.collect_owner_binding();
BEGIN IF b IS NULL THEN RAISE EXCEPTION 'owner_identity_unavailable' USING ERRCODE='42501';END IF;RETURN b->>'email';END;$fn$;
CREATE FUNCTION private.collect_owner_is(p_admin text,p_principal text,p_email text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b jsonb:=private.collect_owner_binding();
BEGIN
 RETURN b IS NOT NULL AND b->>'adminId'=p_admin AND b->>'principalId'=p_principal AND b->>'email'=p_email
  AND EXISTS(SELECT 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
   JOIN app.users u ON u.id=l.user_id WHERE a.id=p_admin AND a.email=p_email AND a.role='owner'
    AND a.status='active' AND l.user_id=p_principal AND u.access_status='active');
END;$fn$;
CREATE FUNCTION private.collect_owner_attestation() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b jsonb:=private.collect_owner_binding();
BEGIN IF b IS NULL OR NOT private.collect_owner_is(b->>'adminId',b->>'principalId',b->>'email') THEN RETURN NULL;END IF;RETURN b;END;$fn$;
REVOKE ALL ON FUNCTION private.collect_owner_identity_immutable(),private.collect_owner_binding(),private.collect_owner_email(),
 private.collect_owner_is(text,text,text),private.collect_owner_attestation() FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_owner_email(),private.collect_owner_is(text,text,text),private.collect_owner_attestation() TO collect_runtime;

-- Ordinary SQL writers cannot promote, relabel, unlink, delete or replace the
-- bound owner. Account/session maintenance that preserves this binding remains.
CREATE FUNCTION private.collect_owner_admin_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b jsonb:=private.collect_owner_binding();
BEGIN
 IF b IS NULL THEN RAISE EXCEPTION 'owner_identity_unavailable' USING ERRCODE='42501';END IF;
 IF TG_OP='DELETE' THEN
  IF OLD.id=b->>'adminId' THEN RAISE EXCEPTION 'owner_identity_immutable' USING ERRCODE='42501';END IF;RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND OLD.id=b->>'adminId' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.email IS DISTINCT FROM OLD.email
   OR NEW.role IS DISTINCT FROM OLD.role OR NEW.status IS DISTINCT FROM OLD.status) THEN
  RAISE EXCEPTION 'owner_identity_immutable' USING ERRCODE='42501';END IF;
 IF NEW.role='owner' OR lower(NEW.email)=b->>'email' OR NEW.id=b->>'adminId' THEN
  IF NEW.id IS DISTINCT FROM b->>'adminId' OR NEW.email IS DISTINCT FROM b->>'email' OR NEW.role<>'owner' OR NEW.status<>'active' THEN
   RAISE EXCEPTION 'owner_identity_mismatch' USING ERRCODE='42501';END IF;
 END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_owner_admin_guard BEFORE INSERT OR UPDATE OR DELETE ON app.admin_users FOR EACH ROW EXECUTE FUNCTION private.collect_owner_admin_guard();
ALTER TABLE app.admin_users ENABLE ALWAYS TRIGGER collect_owner_admin_guard;
CREATE FUNCTION private.collect_owner_link_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b jsonb:=private.collect_owner_binding();
BEGIN
 IF b IS NULL THEN RAISE EXCEPTION 'owner_identity_unavailable' USING ERRCODE='42501';END IF;
 IF TG_OP IN('UPDATE','DELETE') AND (OLD.admin_user_id=b->>'adminId' OR OLD.user_id=b->>'principalId') THEN
  RAISE EXCEPTION 'owner_identity_immutable' USING ERRCODE='42501';END IF;
 IF TG_OP<>'DELETE' AND (NEW.admin_user_id=b->>'adminId' OR NEW.user_id=b->>'principalId')
  AND (NEW.admin_user_id IS DISTINCT FROM b->>'adminId' OR NEW.user_id IS DISTINCT FROM b->>'principalId') THEN
  RAISE EXCEPTION 'owner_identity_mismatch' USING ERRCODE='42501';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_owner_link_guard BEFORE INSERT OR UPDATE OR DELETE ON app.admin_principal_links FOR EACH ROW EXECUTE FUNCTION private.collect_owner_link_guard();
ALTER TABLE app.admin_principal_links ENABLE ALWAYS TRIGGER collect_owner_link_guard;
REVOKE ALL ON FUNCTION private.collect_owner_admin_guard(),private.collect_owner_link_guard() FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
ALTER TABLE app.admin_users DROP CONSTRAINT admin_users_check;
REVOKE INSERT ON app.admin_owner_bootstrap_claims FROM collect_runtime;

-- Rewrite only literal owner predicates from the exact verified predecessors;
-- every other part of each current function definition and ACL is preserved.
DO $rewrite$
DECLARE r record;body text;next_body text;definition text;pattern text;replacement text;n bigint;
BEGIN
 FOR r IN SELECT * FROM (VALUES
  ('private.admin_invitation_actor(text,text,text,text)',1),
  ('private.admin_invitation_v1_prepare_legacy(text,text,text,text,text,text,text,text,text,text,text,text)',2),
  ('private.admin_invitation_v2_prepare(text,text,text,text,text,text,text,text,text,text,text,text,uuid)',2),
  ('private.trg_admin_owner_bootstrap_apply()',3),
  ('private.trg_assisted_sms_grant_explicit()',4)
 ) e(sig,kind) LOOP
  SELECT prosrc,pg_get_functiondef(oid) INTO STRICT body,definition FROM pg_proc WHERE oid=to_regprocedure(r.sig);
  IF r.kind=1 THEN pattern:=$rx$actor->>'identity_value' IS DISTINCT FROM '[^']+'$rx$;
   replacement:=$rx$NOT private.collect_owner_is(actor->>'admin_id',principal,actor->>'identity_value')$rx$;
  ELSIF r.kind=2 THEN pattern:=$rx$p_email='[^']+'$rx$;replacement:=$rx$p_email=private.collect_owner_email()$rx$;
  ELSIF r.kind=3 THEN pattern:=$rx$NEW[[:space:]]*\.[[:space:]]*admin_user_id[[:space:]]*,[[:space:]]*'[^']+'[[:space:]]*,[[:space:]]*'owner'$rx$;
   replacement:=$rx$NEW.admin_user_id,private.collect_owner_email(),'owner'$rx$;
  ELSE pattern:=$rx$a[[:space:]]*\.[[:space:]]*email[[:space:]]*=[[:space:]]*'[^']+'$rx$;
   replacement:=$rx$private.collect_owner_is(a.id,s.user_id,a.email)$rx$;END IF;
  SELECT count(*) INTO n FROM regexp_matches(body,pattern,'g');
  IF n<>1 OR length(definition)-length(replace(definition,body,''))<>length(body) THEN
   RAISE EXCEPTION 'owner_identity_rewrite_changed' USING ERRCODE='55000';END IF;
  next_body:=regexp_replace(body,pattern,replacement);
  EXECUTE replace(definition,body,next_body);
 END LOOP;
END;$rewrite$;

-- Fresh installation only: one operator-controlled atomic binding plus existing
-- bootstrap receipt. No runtime principal can call or replace the binding.
CREATE FUNCTION private.collect_initialize_owner(p_operation uuid,p_admin text,p_principal text,p_email text,p_password_hash text,p_name text,p_reference text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE at_time timestamptz:=clock_timestamp();
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF session_user<>'postgres' OR current_setting('role',true) NOT IN('none','postgres') OR current_setting('transaction_isolation')<>'read committed'
  OR p_operation IS NULL OR p_admin !~ '^[0-9a-f-]{36}$' OR p_principal !~ '^[0-9a-f-]{36}$'
  OR NOT private.collect_owner_email_valid(p_email)
  OR p_password_hash IS NULL OR p_password_hash !~ '^pbkdf2-sha256\$600000\$' OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 2 AND 120
  OR p_reference IS NULL OR length(p_reference) NOT BETWEEN 8 AND 200 OR p_reference ~ '[[:cntrl:]]' THEN
  RAISE EXCEPTION 'owner_identity_initialization_invalid' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='open')
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state<>'settled')
  OR EXISTS(SELECT 1 FROM private.collect_owner_identity) OR EXISTS(SELECT 1 FROM app.admin_users WHERE role='owner') THEN
  RAISE EXCEPTION 'owner_identity_initialization_refused' USING ERRCODE='42501';END IF;
 INSERT INTO private.collect_owner_identity(operation_id,admin_user_id,principal_user_id,owner_email,approval_reference)
 VALUES(p_operation,p_admin,p_principal,p_email,p_reference);
 INSERT INTO app.admin_owner_bootstrap_claims(operation_id,admin_user_id,principal_user_id,password_hash,display_name,approval_reference,created_at,created_seconds)
 VALUES(p_operation::text,p_admin,p_principal,p_password_hash,p_name,p_reference,
  to_char(at_time AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),floor(extract(epoch FROM at_time))::bigint);
 RETURN true;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_initialize_owner(uuid,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;

-- Retention: unknown subject mapping and owner data are reported as blocked,
-- never a zero count. The prior exact catalog and row-capture bytes are pinned.
DO $retention$
DECLARE body text;next_body text;definition text;anchor text;
BEGIN
 SELECT prosrc,pg_get_functiondef(oid) INTO STRICT body,definition FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:='SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||''{"name":"private:collect_owner_identity","relation":"private.collect_owner_identity","scope":"unmapped_private","purpose":"Protected owner identity; subject mapping and disposition unreviewed","blocked":true}''::jsonb) FROM ('||body||') prior(base)';
 EXECUTE replace(definition,body,next_body);
 SELECT prosrc,pg_get_functiondef(oid) INTO STRICT body,definition FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'private:burimunsi_accounts'$a$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'owner_identity_retention_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,$b$'private:collect_owner_identity','private:burimunsi_accounts'$b$);
 EXECUTE replace(definition,body,next_body);
END;$retention$;
COMMIT;
