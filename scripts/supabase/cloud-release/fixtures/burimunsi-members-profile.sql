SET search_path=app,public,pg_catalog;
-- Put one searchable surname on the last hundred numbered members. The
-- highest numbered membership is inactive, leaving 99 eligible matches.
WITH last_hundred AS (SELECT id FROM app.users ORDER BY id DESC LIMIT 100)
UPDATE app.users u SET full_name=u.full_name||' Mugisha'
FROM last_hundred h WHERE u.id=h.id;

CREATE FUNCTION private.fixture_post(entry text, grp text, member text, amount integer) RETURNS void
  LANGUAGE sql SET search_path=app,pg_catalog AS $$
  INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
  VALUES(entry,entry,grp,member,amount,'contribution',entry,'synthetic-operator',entry,'2026-11-01T16:20:00.000Z')$$;
INSERT INTO app.users(id,public_id,full_name,member_type,created_at,updated_at)
SELECT private.fixture_member_id(i),i::text,'Scope control '||i,CASE WHEN i>=900003 THEN 'operator' ELSE 'app' END,
  '2026-11-01T16:00:00.000Z','2026-11-01T16:00:00.000Z' FROM generate_series(900001,900004) i;
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,status,created_at,updated_at)
SELECT id,id,'fixture',id,'savings',status,'2026-11-01T16:00:00.000Z','2026-11-01T16:00:00.000Z'
FROM (VALUES('other-active','active'),('other-archived','archived')) t(id,status);
INSERT INTO app.memberships(id,collection_id,user_id,joined_at)
SELECT grp||n,grp,private.fixture_member_id(n),'2026-11-01T18:00:00.123+02:00'
FROM (VALUES('other-active',1),('other-active',900001),('other-archived',900002),('other-active',900003)) t(grp,n);
SELECT private.fixture_post('other-ledger','other-active',private.fixture_member_id(1),700);

CREATE TABLE private.burimunsi_scopes(collection_id text PRIMARY KEY, enabled boolean, active_binding_id text, receiving_account_id text, binding_version bigint);
CREATE TABLE private.burimunsi_accounts(id uuid PRIMARY KEY,collection_id text,principal_user_id text,phone text,name text,role text,
  capabilities jsonb,active boolean,removed boolean,credential_version bigint);
CREATE TABLE private.burimunsi_device_grants(id uuid PRIMARY KEY,collection_id text,active boolean,version bigint,installation_id uuid,profile text);
CREATE TABLE private.burimunsi_device_accounts(grant_id uuid,account_id uuid,collection_id text,PRIMARY KEY(grant_id,account_id));
CREATE TABLE private.burimunsi_sessions(id uuid PRIMARY KEY,account_id uuid,collection_id text,grant_id uuid,revoked boolean,expires_at bigint,
  installation_id uuid,token_hash text,credential_version bigint,grant_version bigint,principal_user_id text,created_at bigint);
CREATE TABLE app.momo_gateway_bindings(id text PRIMARY KEY,receiving_account_id text,version bigint,status text);
CREATE TABLE app.momo_gateway_credentials(binding_id text,installation_id uuid,revoked_at text);
INSERT INTO private.burimunsi_scopes(collection_id,enabled) SELECT id,true FROM collections WHERE id LIKE 'group-%';
INSERT INTO private.burimunsi_accounts SELECT private.fixture_member_id(900005)::uuid,collection_id,private.fixture_member_id(900004),
  '+250780000000','Scope operator','staff','["records.read"]'::jsonb,true,false,1 FROM private.burimunsi_scopes;
INSERT INTO private.burimunsi_device_grants SELECT private.fixture_member_id(900006)::uuid,collection_id,true,1,
  private.fixture_member_id(900007)::uuid,'staff' FROM private.burimunsi_scopes;
INSERT INTO private.burimunsi_device_accounts SELECT d.id,a.id,d.collection_id FROM private.burimunsi_device_grants d JOIN private.burimunsi_accounts a USING(collection_id);
INSERT INTO private.burimunsi_sessions SELECT private.fixture_member_id(900008)::uuid,a.id,a.collection_id,d.id,false,
  (unixepoch()+3600)*1000,d.installation_id,repeat('b',64),1,1,a.principal_user_id,(unixepoch()-30)*1000
  FROM private.burimunsi_accounts a JOIN private.burimunsi_device_grants d USING(collection_id);

INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at)
VALUES(private.fixture_member_id(900009),'reader@fixture.invalid','staff','active','synthetic',unixepoch(),unixepoch());
INSERT INTO admin_principal_links VALUES(private.fixture_member_id(900009),private.fixture_member_id(900004),'fixture','2026-11-01T16:00:00.000Z');
INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
VALUES(private.fixture_member_id(900010),private.fixture_member_id(900004),'admin',unixepoch(),unixepoch(),unixepoch()+3600);
INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
VALUES(repeat('a',64),private.fixture_member_id(900011),private.fixture_member_id(900009),1,private.fixture_member_id(900010),'https://members.fixture.invalid',unixepoch(),unixepoch()+3600);
INSERT INTO admin_grants VALUES(private.fixture_member_id(900004),'users.read','fixture','2026-11-01T16:00:00.000Z');
INSERT INTO admin_account_role_capabilities VALUES('staff','users.read');

CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('contractVersion',1,'epoch',1,'mode','open')
  WHERE $1='00000000-0000-4000-8000-000000900012'::uuid AND $2=1 AND $3=repeat('c',64)$$;
CREATE FUNCTION private.set_admin_email_context(text,text,text,text) RETURNS text LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
BEGIN
  PERFORM 1 FROM admin_sessions WHERE user_id=$1 AND token_hash=$2 AND origin=$3 AND public_id=$4 FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'admin_email_denied'; END IF;
  RETURN 'fixture';
END$$;
CREATE FUNCTION private.assert_admin_email_context(integer) RETURNS app.admin_users LANGUAGE sql AS $$SELECT NULL::app.admin_users$$;
GRANT SELECT ON ALL TABLES IN SCHEMA private,app TO collect_runtime;
GRANT UPDATE ON app.admin_sessions,app.admin_grants,app.admin_account_role_capabilities TO collect_runtime;
