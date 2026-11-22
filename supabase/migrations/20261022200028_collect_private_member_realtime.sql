-- PRIVATE SOURCE PROPOSAL. NOT EXECUTED. Root binds reviewed metadata first.
-- Only policy DDL is performed on managed realtime.messages. No managed RLS,
-- schema, table, function, grant, partition or configuration change is made.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE FUNCTION private._collect_member_realtime_metadata() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $meta$
SELECT pg_catalog.jsonb_build_object(
 'server_major',pg_catalog.current_setting('server_version_num')::integer/10000,
 'schema',(SELECT pg_catalog.jsonb_build_object('owner',pg_catalog.pg_get_userbyid(n.nspowner),'acl',n.nspacl::text) FROM pg_catalog.pg_namespace n WHERE n.nspname='realtime'),
 'relation',(SELECT pg_catalog.jsonb_build_object('kind',c.relkind,'owner',pg_catalog.pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='realtime' AND c.relname='messages'),
 'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'generated',a.attgenerated,'identity',a.attidentity) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a WHERE a.attrelid=pg_catalog.to_regclass('realtime.messages') AND a.attnum>0 AND NOT a.attisdropped),
 'policies',coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',p.polname,'permissive',p.polpermissive,'command',p.polcmd,'roles',(SELECT pg_catalog.jsonb_agg(CASE WHEN r=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(r) END ORDER BY r) FROM pg_catalog.unnest(p.polroles) r),'using',pg_catalog.pg_get_expr(p.polqual,p.polrelid),'check',pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('realtime.messages')),'[]'::jsonb),
 'functions',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',f.proname,'args',pg_catalog.pg_get_function_identity_arguments(f.oid),'owner',pg_catalog.pg_get_userbyid(f.proowner),'definer',f.prosecdef,'settings',f.proconfig,'acl',f.proacl::text,'definition_sha256',pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(f.oid),'UTF8')),'hex')) ORDER BY f.proname,f.oid) FROM pg_catalog.pg_proc f JOIN pg_catalog.pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='realtime' AND f.proname IN('topic','send','broadcast_changes')),
 'roles',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',r.rolname,'super',r.rolsuper,'bypass',r.rolbypassrls,'inherit',r.rolinherit,'schema_usage',pg_catalog.has_schema_privilege(r.oid,'realtime','USAGE'),'messages_select',pg_catalog.has_table_privilege(r.oid,'realtime.messages','SELECT'),'messages_insert',pg_catalog.has_table_privilege(r.oid,'realtime.messages','INSERT')) ORDER BY r.rolname) FROM pg_catalog.pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','postgres','supabase_realtime_admin','collect_runtime','collect_importer')),
 'memberships',coalesce((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('role',pg_catalog.pg_get_userbyid(m.roleid),'member',pg_catalog.pg_get_userbyid(m.member),'inherit',m.inherit_option,'set',m.set_option,'admin',m.admin_option,'grantor',pg_catalog.pg_get_userbyid(m.grantor)) ORDER BY m.roleid,m.member,m.grantor,m.inherit_option,m.set_option,m.admin_option) FROM pg_catalog.pg_auth_members m WHERE m.roleid IN(SELECT oid FROM pg_catalog.pg_roles WHERE rolname IN('anon','authenticated','service_role','postgres','supabase_realtime_admin','collect_runtime','collect_importer')) OR m.member IN(SELECT oid FROM pg_catalog.pg_roles WHERE rolname IN('anon','authenticated','service_role','postgres','supabase_realtime_admin','collect_runtime','collect_importer'))),'[]'::jsonb),
 'postgres_select',pg_catalog.has_table_privilege('postgres','realtime.messages','SELECT'),
 'postgres_insert',pg_catalog.has_table_privilege('postgres','realtime.messages','INSERT'),
 'postgres_send',pg_catalog.has_function_privilege('postgres','realtime.send(jsonb,text,text,boolean)','EXECUTE')
)
$meta$;
CREATE FUNCTION private._collect_member_realtime_metadata_sha() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(private._collect_member_realtime_metadata()::text,'UTF8')),'hex')
$fn$;
DO $preflight$
DECLARE observed jsonb;
BEGIN
 observed:=private._collect_member_realtime_metadata();
 IF '62bf00d15d1bd950a764048c51b1c50558784c0d8f8618ec0b0ca32ea8173440' !~ '^[a-f0-9]{64}$'
  OR private._collect_member_realtime_metadata_sha()<>'62bf00d15d1bd950a764048c51b1c50558784c0d8f8618ec0b0ca32ea8173440'
  OR observed->>'server_major'<>'17' OR observed->'relation'->>'rls'<>'true'
  OR observed->'relation'->>'kind'<>'p' OR observed->'policies'<>'[]'::jsonb
  OR observed->>'postgres_select'<>'true' OR observed->>'postgres_insert'<>'true' OR observed->>'postgres_send'<>'true'
  OR pg_catalog.to_regprocedure('private.collect_fence_assert_write(uuid,bigint,text)') IS NULL
  OR EXISTS(SELECT 1 FROM pg_catalog.pg_namespace n JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid WHERE n.nspname='private' AND c.relname='member_realtime_control') THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='member_realtime_metadata_not_reviewed';
 END IF;
END;$preflight$;

CREATE TABLE private.member_realtime_control(
 singleton boolean PRIMARY KEY CHECK(singleton),
 enabled boolean NOT NULL DEFAULT false,
 source_sha256 text CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 policy_sha256 text NOT NULL CHECK(policy_sha256 ~ '^[a-f0-9]{64}$'),
 activation_evidence_sha256 text CHECK(activation_evidence_sha256 ~ '^[a-f0-9]{64}$'),
 last_audit_id bigint NOT NULL DEFAULT 0 CHECK(last_audit_id>=0),
 attempted_total bigint NOT NULL DEFAULT 0 CHECK(attempted_total BETWEEN 0 AND 32768),
 failed_total bigint NOT NULL DEFAULT 0 CHECK(failed_total BETWEEN 0 AND 32768),
 window_started_at timestamptz,
 window_attempted integer NOT NULL DEFAULT 0 CHECK(window_attempted BETWEEN 0 AND 32),
 changed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CHECK(NOT enabled OR(source_sha256 IS NOT NULL AND activation_evidence_sha256 IS NOT NULL))
);
ALTER TABLE private.member_realtime_control ENABLE ROW LEVEL SECURITY;
-- No table grant/policy for clients or runtime. Only narrowly granted definers.

CREATE FUNCTION private._collect_member_realtime_transition() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW.singleton IS DISTINCT FROM OLD.singleton OR NEW.policy_sha256 IS DISTINCT FROM OLD.policy_sha256
 OR(OLD.source_sha256 IS NOT NULL AND NEW.source_sha256 IS DISTINCT FROM OLD.source_sha256)
 OR NEW.last_audit_id<OLD.last_audit_id OR NEW.attempted_total<OLD.attempted_total OR NEW.failed_total<OLD.failed_total THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='member_realtime_control_regression';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER member_realtime_transition BEFORE UPDATE ON private.member_realtime_control FOR EACH ROW EXECUTE FUNCTION private._collect_member_realtime_transition();

CREATE FUNCTION private.collect_member_realtime_join(p_topic text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE claims jsonb; principal uuid; sid uuid; enabled_source text;
BEGIN
 claims:=private.request_claims();
 IF claims->>'role' IS DISTINCT FROM 'authenticated'
 OR claims->>'sub' IS NULL OR claims->>'sub' !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
 OR claims->>'session_id' IS NULL OR claims->>'session_id' !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
 OR pg_catalog.jsonb_typeof(claims->'exp') IS DISTINCT FROM 'number' OR claims->>'exp' !~ '^[0-9]{1,12}$' THEN RETURN false; END IF;
 principal:=(claims->>'sub')::uuid;sid:=(claims->>'session_id')::uuid;
 IF (claims->>'exp')::bigint<=extract(epoch FROM pg_catalog.statement_timestamp())::bigint
 OR p_topic IS DISTINCT FROM 'collect:member:'||principal::text||':'||sid::text THEN RETURN false;END IF;
 SELECT c.source_sha256 INTO enabled_source FROM private.member_realtime_control c
 JOIN private.collect_fence_control f ON f.singleton AND f.source_sha256=c.source_sha256 AND f.mode='open'
 WHERE c.singleton AND c.enabled AND c.attempted_total<32768 AND c.policy_sha256=private._collect_member_realtime_metadata_sha();
 IF NOT FOUND THEN RETURN false;END IF;
 RETURN EXISTS(SELECT 1 FROM private.auth_principal_links l JOIN app.users u ON u.id=l.user_id
 JOIN app.auth_sessions s ON s.user_id=u.id AND s.id=sid::text
 JOIN auth.users a ON a.id=l.auth_user_id JOIN auth.sessions z ON z.id=sid AND z.user_id=a.id
 WHERE l.auth_user_id=principal AND u.access_status='active' AND s.surface='member'
 AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM pg_catalog.statement_timestamp())::bigint
 AND a.deleted_at IS NULL AND(a.banned_until IS NULL OR a.banned_until<=pg_catalog.statement_timestamp())
 AND(z.not_after IS NULL OR z.not_after>pg_catalog.statement_timestamp()));
EXCEPTION WHEN OTHERS THEN RETURN false;
END;$fn$;

-- A matching restrictive policy prevents another permissive policy OR-bypassing
-- the fixed topic/member/session guard. Separate denies cover future grants.
CREATE POLICY collect_member_receive_v1 ON realtime.messages FOR SELECT TO authenticated
 USING(topic=(SELECT realtime.topic()) AND extension='broadcast' AND private.collect_member_realtime_join((SELECT realtime.topic())));
CREATE POLICY collect_member_receive_guard_v1 ON realtime.messages AS RESTRICTIVE FOR SELECT TO authenticated
 USING(topic=(SELECT realtime.topic()) AND extension='broadcast' AND private.collect_member_realtime_join((SELECT realtime.topic())));
CREATE POLICY collect_member_no_insert_v1 ON realtime.messages AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK(false);
CREATE POLICY collect_member_no_update_v1 ON realtime.messages AS RESTRICTIVE FOR UPDATE TO authenticated USING(false) WITH CHECK(false);
CREATE POLICY collect_member_no_delete_v1 ON realtime.messages AS RESTRICTIVE FOR DELETE TO authenticated USING(false);
CREATE POLICY collect_member_no_anonymous_v1 ON realtime.messages AS RESTRICTIVE FOR ALL TO anon USING(false) WITH CHECK(false);

-- Initial install is OFF and requires no mutation of an initialized SQL9 control.
INSERT INTO private.member_realtime_control(singleton,enabled,policy_sha256)
 VALUES(true,false,private._collect_member_realtime_metadata_sha());
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.member_realtime_control FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.member_realtime_control ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER member_realtime_retain BEFORE DELETE OR TRUNCATE ON private.member_realtime_control
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();

CREATE FUNCTION private.collect_member_realtime_configure(p_enabled boolean,p_source text,p_policy_sha256 text,p_evidence_sha256 text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE fence private.collect_fence_control%ROWTYPE;c private.member_realtime_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF p_enabled IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' OR p_policy_sha256 IS DISTINCT FROM private._collect_member_realtime_metadata_sha()
 OR p_evidence_sha256 IS NULL OR p_evidence_sha256 !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='member_realtime_activation_invalid';END IF;
 SELECT * INTO fence FROM private.collect_fence_control WHERE singleton;
 SELECT * INTO c FROM private.member_realtime_control WHERE singleton FOR UPDATE;
 IF fence.mode<>'open' OR fence.source_sha256<>p_source OR c.policy_sha256<>p_policy_sha256
 OR(c.source_sha256 IS NOT NULL AND c.source_sha256<>p_source) OR(p_enabled AND c.attempted_total>=32768) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='member_realtime_activation_unqualified';END IF;
 -- First activation starts at the current authoritative cursor, never replays
 -- historical events. Re-enable preserves cursor and finite total; no reset API.
 UPDATE private.member_realtime_control SET enabled=p_enabled,source_sha256=p_source,
  activation_evidence_sha256=p_evidence_sha256,
  last_audit_id=CASE WHEN c.source_sha256 IS NULL THEN coalesce((SELECT max(id) FROM app.audit_log),0) ELSE c.last_audit_id END,
  changed_at=pg_catalog.clock_timestamp() WHERE singleton;
 RETURN pg_catalog.jsonb_build_object('status',CASE WHEN p_enabled THEN 'enabled' ELSE 'disabled' END,'source_bound',true,'delivery_confirmed',false);
END;$fn$;

CREATE FUNCTION private.collect_member_realtime_publish() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.member_realtime_control%ROWTYPE; event_row record; target record; targets jsonb; source text;
 scanned integer:=0;attempted integer:=0;failed integer:=0;overflowed integer:=0; available integer;now_at timestamptz:=pg_catalog.clock_timestamp();
BEGIN
 PERFORM private._collect_fence_require_runtime();
 PERFORM private.collect_fence_assert_write(nullif(pg_catalog.current_setting('collect.fence_admission_id',true),'')::uuid,
  nullif(pg_catalog.current_setting('collect.fence_epoch',true),'')::bigint,
  nullif(pg_catalog.current_setting('collect.fence_source_sha256',true),''));
 SELECT * INTO c FROM private.member_realtime_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR NOT c.enabled THEN RETURN pg_catalog.jsonb_build_object('status','disabled','scanned',0,'attempted',0,'failed',0,'overflowed',0,'delivery_confirmed',false);END IF;
 SELECT source_sha256 INTO source FROM private.collect_fence_control WHERE singleton;
 IF c.source_sha256 IS DISTINCT FROM source OR c.policy_sha256<>private._collect_member_realtime_metadata_sha() THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='member_realtime_source_or_policy_changed';END IF;
 IF c.attempted_total>=32768 THEN RETURN pg_catalog.jsonb_build_object('status','capacity','scanned',0,'attempted',0,'failed',0,'overflowed',0,'delivery_confirmed',false);END IF;
 IF c.window_started_at IS NULL OR c.window_started_at<=now_at-interval '10 seconds' THEN c.window_started_at:=now_at;c.window_attempted:=0;END IF;
 available:=least(32-c.window_attempted,32768-c.attempted_total);
 IF available<=0 THEN RETURN pg_catalog.jsonb_build_object('status','rate_limited','scanned',0,'attempted',0,'failed',0,'overflowed',0,'delivery_confirmed',false);END IF;
 FOR event_row IN SELECT a.id,a.actor_user_id,a.entity_id FROM app.audit_log a WHERE a.id>c.last_audit_id ORDER BY a.id LIMIT 4 LOOP
  scanned:=scanned+1;
  -- Mirrors sync.js audience union; no payload contains any audit/entity ID.
  -- Publication additionally requires a CURRENT member/managed session. Locks
  -- serialize projection/user/session revocation before the transaction commits;
  -- cached joins or already emitted packets cannot be retroactively recalled.
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('auth_user_id',q.auth_user_id,'sid',q.sid,'user_id',q.user_id) ORDER BY q.sid),'[]'::jsonb)
   INTO targets FROM(
    SELECT l.auth_user_id,z.id AS sid,u.id AS user_id FROM private.auth_principal_links l
    JOIN app.users u ON u.id=l.user_id JOIN app.auth_sessions s ON s.user_id=u.id
    JOIN auth.users a ON a.id=l.auth_user_id JOIN auth.sessions z ON z.id::text=s.id AND z.user_id=a.id
    WHERE u.access_status='active' AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM pg_catalog.clock_timestamp())::bigint
    AND a.deleted_at IS NULL AND(a.banned_until IS NULL OR a.banned_until<=pg_catalog.clock_timestamp()) AND(z.not_after IS NULL OR z.not_after>pg_catalog.clock_timestamp())
    AND(event_row.actor_user_id=u.id OR event_row.entity_id=u.id
     OR EXISTS(SELECT 1 FROM app.memberships m JOIN app.collections g ON g.id=m.collection_id WHERE m.user_id=u.id AND m.active=1 AND g.status='active' AND m.collection_id=event_row.entity_id)
     OR EXISTS(SELECT 1 FROM app.payments p JOIN app.memberships m ON m.collection_id=p.collection_id JOIN app.collections g ON g.id=m.collection_id WHERE m.user_id=u.id AND m.active=1 AND g.status='active' AND p.id=event_row.entity_id))
    ORDER BY z.id LIMIT 33 FOR SHARE OF u,s,a,z
   )q;
  IF pg_catalog.jsonb_array_length(targets)>available THEN
   overflowed:=overflowed+1; -- Drop the entire hint row; authoritative polling catches up.
  ELSE
   FOR target IN SELECT value FROM pg_catalog.jsonb_array_elements(targets) LOOP
    -- Lock current collection/membership eligibility through commit for group
    -- recipients. The actor/self branches mirror authoritative sync visibility.
    IF event_row.actor_user_id IS DISTINCT FROM target.value->>'user_id' AND event_row.entity_id IS DISTINCT FROM target.value->>'user_id' THEN
     PERFORM 1 FROM app.memberships m JOIN app.collections g ON g.id=m.collection_id
      WHERE m.user_id=target.value->>'user_id' AND m.active=1 AND g.status='active'
      AND(g.id=event_row.entity_id OR EXISTS(SELECT 1 FROM app.payments p WHERE p.collection_id=g.id AND p.id=event_row.entity_id)) FOR SHARE OF m,g;
     IF NOT FOUND THEN CONTINUE;END IF;
    END IF;
    -- Time-based expiry is rechecked immediately before each send even though
    -- identity/status rows remain locked from the audience statement.
    PERFORM 1 FROM private.auth_principal_links l JOIN app.users u ON u.id=l.user_id
     JOIN app.auth_sessions s ON s.user_id=u.id JOIN auth.users a ON a.id=l.auth_user_id
     JOIN auth.sessions z ON z.id::text=s.id AND z.user_id=a.id
     WHERE l.auth_user_id::text=target.value->>'auth_user_id' AND z.id::text=target.value->>'sid'
      AND u.id=target.value->>'user_id' AND u.access_status='active' AND s.surface='member'
      AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM pg_catalog.clock_timestamp())::bigint
      AND a.deleted_at IS NULL AND(a.banned_until IS NULL OR a.banned_until<=pg_catalog.clock_timestamp())
      AND(z.not_after IS NULL OR z.not_after>pg_catalog.clock_timestamp()) FOR SHARE OF u,s,a,z;
    IF NOT FOUND THEN CONTINUE;END IF;
    attempted:=attempted+1;available:=available-1;
    BEGIN
     PERFORM realtime.send(pg_catalog.jsonb_build_object('v',1,'id',pg_catalog.gen_random_uuid()),'invalidate',
      'collect:member:'||(target.value->>'auth_user_id')||':'||(target.value->>'sid'),true);
    EXCEPTION WHEN OTHERS THEN failed:=failed+1;
    END;
   END LOOP;
  END IF;
  c.last_audit_id:=event_row.id;
  IF available=0 THEN EXIT;END IF;
 END LOOP;
 UPDATE private.member_realtime_control SET last_audit_id=c.last_audit_id,attempted_total=c.attempted_total+attempted,
 failed_total=c.failed_total+failed,window_started_at=c.window_started_at,window_attempted=c.window_attempted+attempted,changed_at=now_at WHERE singleton;
 -- realtime.send may swallow a missing-partition warning and return void. This
 -- counts attempts only. Neither zero exceptions nor COMMIT proves delivery.
 RETURN pg_catalog.jsonb_build_object('status',CASE WHEN attempted>0 THEN 'attempted_unconfirmed' ELSE 'idle' END,'scanned',scanned,'attempted',attempted,'failed',failed,'overflowed',overflowed,'delivery_confirmed',false);
END;$fn$;

CREATE FUNCTION private.retention_member_realtime_inventory(p_subject text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal uuid; topics text[]; retained_count integer; invalid_count integer;
 copies jsonb; metadata_sha text; partition_schema jsonb; schema_identity jsonb;
BEGIN
 -- Same fresh actual Admin permission/MFA/session gate as existing inventory.
 PERFORM private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF p_subject IS NOT NULL AND(length(p_subject)<1 OR length(p_subject)>200) THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='retention_subject_invalid';END IF;
 metadata_sha:=private._collect_member_realtime_metadata_sha();
 WITH RECURSIVE children AS(
  SELECT pg_catalog.to_regclass('realtime.messages')::oid AS oid
  UNION ALL SELECT i.inhrelid FROM pg_catalog.pg_inherits i JOIN children x ON x.oid=i.inhparent
 ) SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',n.nspname||'.'||c.relname,'kind',c.relkind,
  'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name',a.attname,'type',pg_catalog.format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'partition_bound',pg_catalog.pg_get_expr(c.relpartbound,c.oid)) ORDER BY n.nspname,c.relname),'[]'::jsonb) INTO partition_schema
 FROM children x JOIN pg_catalog.pg_class c ON c.oid=x.oid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace;
 IF pg_catalog.jsonb_array_length(partition_schema)>16 OR pg_catalog.to_regclass('realtime.messages') IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='54000',MESSAGE='retention_realtime_schema_unavailable';END IF;
 schema_identity:=pg_catalog.jsonb_build_object('contract','collect.member.realtime.inventory.v1','metadata_sha256',metadata_sha,
  'partitions_sha256',pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(partition_schema::text,'UTF8')),'hex'));
 IF p_subject IS NULL THEN RETURN pg_catalog.jsonb_build_object('contract_version',1,'schema',schema_identity);END IF;
 SELECT auth_user_id INTO principal FROM private.auth_principal_links WHERE user_id=p_subject;
 -- Losing a principal/session attribution path is NOT observed global absence.
 IF principal IS NULL THEN RETURN pg_catalog.jsonb_build_object('contract_version',1,'schema',schema_identity,'class',
  pg_catalog.jsonb_build_object('status','unavailable','count',0,'rows','[]'::jsonb,'reason','principal_attribution_unavailable'));END IF;
 SELECT count(*),count(*) FILTER(WHERE s.id !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$') INTO retained_count,invalid_count
 FROM(SELECT id FROM app.auth_sessions WHERE user_id=p_subject AND surface='member' LIMIT 501)s;
 IF retained_count>500 OR invalid_count>0 THEN RAISE EXCEPTION USING ERRCODE='54000',MESSAGE='retention_realtime_session_attribution_limit';END IF;
 -- Deliberately no auth.sessions JOIN: original managed session deletion/revoke
 -- must not hide already persisted pseudonymous topic copies.
 SELECT coalesce(pg_catalog.array_agg('collect:member:'||principal::text||':'||s.id ORDER BY s.id),ARRAY[]::text[]) INTO topics
 FROM app.auth_sessions s WHERE s.user_id=p_subject AND s.surface='member';
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
  'key_sha256',pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(q.topic||':'||q.id::text||':'||q.inserted_at::text,'UTF8')),'hex'),
  'row_sha256',pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.to_jsonb(q)::text,'UTF8')),'hex'),
  'identity_sha256',pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.to_jsonb(q)::text,'UTF8')),'hex'),
  'lifecycle',pg_catalog.jsonb_build_object('managed_copy',true,'erasure_verified',false)) ORDER BY q.topic,q.id,q.inserted_at),'[]'::jsonb) INTO copies
 FROM(SELECT r.* FROM realtime.messages r WHERE r.topic=ANY(topics) ORDER BY r.topic,r.id,r.inserted_at LIMIT 501)q;
 IF pg_catalog.jsonb_array_length(copies)>500 THEN RAISE EXCEPTION USING ERRCODE='54000',MESSAGE='retention_realtime_copy_limit';END IF;
 RETURN pg_catalog.jsonb_build_object('contract_version',1,'schema',schema_identity,'class',pg_catalog.jsonb_build_object(
  'status','observed','count',pg_catalog.jsonb_array_length(copies),'rows',copies,'scope','retained_member_topics_only',
  'provider_logs_backups','blocked','erasure_verified',false));
END;$fn$;

DO $acl$
DECLARE routine record; r text;
BEGIN
 REVOKE ALL ON TABLE private.member_realtime_control FROM PUBLIC;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=r) THEN EXECUTE pg_catalog.format('REVOKE ALL ON TABLE private.member_realtime_control FROM %I',r);END IF;
 END LOOP;
 FOR routine IN SELECT f.oid::regprocedure AS signature FROM pg_catalog.pg_proc f JOIN pg_catalog.pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='private' AND(pg_catalog.starts_with(f.proname,'collect_member_realtime_') OR pg_catalog.starts_with(f.proname,'_collect_member_realtime_') OR f.proname='retention_member_realtime_inventory') LOOP
  EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',routine.signature);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
   IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=r) THEN EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM %I',routine.signature,r);END IF;
  END LOOP;
 END LOOP;
END;$acl$;
GRANT EXECUTE ON FUNCTION private.collect_member_realtime_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.collect_member_realtime_publish(),private.retention_member_realtime_inventory(text) TO collect_runtime;
-- No schema USAGE or raw managed/private table grants are added. The owner-bound
-- RLS expression calls its fixed function OID; native policy qualification must
-- prove authenticated joins without granting broader private namespace access.
COMMIT;
