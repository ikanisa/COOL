// Isolated, in-memory PGlite. The actual candidate wrapper and existing key
// admission execute against minimal synthetic dependencies. PGlite serializes
// one backend, so this does not replace a reviewed two-connection race test.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
const draft=readFileSync(new URL('./draft-held-consent-admission.sql',import.meta.url),'utf8');
const prior=readFileSync(new URL('../../../supabase/migrations/20261113130000_burimunsi_native_observation_dedup.sql',import.meta.url),'utf8');
function extract(source,head){const start=source.indexOf(head),open=source.indexOf('$fn$',start),end=source.indexOf('$fn$;',open+4);
 assert(start>=0&&open>=0&&end>=0);return source.slice(start,end+5);}
function sourceId(request){const h=createHash('sha256').update('collect.storage.entity.v1\nburimunsi.native.observation.v1\nowner-a\n'+request).digest('hex');
 return `${h.slice(0,8)}-${h.slice(8,12)}-5${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`;}

test('held admission locks the original generation and preserves a single exact intent',{skip:!modulePath},async()=>{
 const {PGlite}=await import(modulePath),db=new PGlite();
 try{
  await db.exec(`CREATE SCHEMA private; CREATE ROLE anon; CREATE ROLE authenticated;CREATE ROLE service_role;
   CREATE ROLE collect_importer;CREATE ROLE collect_runtime;
   CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,
    grant_id uuid,grant_version bigint,generation bigint,enabled boolean);
   CREATE TABLE private.burimunsi_observation_requests(source_id text PRIMARY KEY,collection_id text,account_id uuid,
    principal_user_id text,installation_id uuid,grant_id uuid,grant_version bigint,native_session_id uuid,
    request_id uuid UNIQUE,fingerprint text,initial_profile_version text,initial_profile_sha256 text,
    initial_profile_tuple_sha256 text,initial_consent_generation bigint,created_at bigint,
    source_key text UNIQUE,source_key_content_sha256 text,source_key_body_sha256 text);
   CREATE TABLE private.burimunsi_unresolved_observations(source_id text);
   CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
    BEGIN IF $1 AND current_setting('fixture.reveal',true) IS DISTINCT FROM 'yes' THEN
     RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
    RETURN jsonb_build_object('collectionId','group-a','accountId','10000000-0000-4000-8000-000000000001',
     'principalUserId','owner-a','installationId','20000000-0000-4000-8000-000000000001',
     'sessionId','40000000-0000-4000-8000-000000000001','grantId','30000000-0000-4000-8000-000000000001',
     'grantVersion',coalesce(nullif(current_setting('fixture.grant_version',true),''),'1')::bigint);END$$;
   CREATE FUNCTION private.burimunsi_observation_context() RETURNS jsonb LANGUAGE sql AS $$
    SELECT private.burimunsi_observation_actor(false)||jsonb_build_object('consentGeneration',generation,
     'profile_version','v1','profile_sha256',repeat('b',64),'profile_tuple_sha256',repeat('c',64))
     FROM private.burimunsi_observation_consents LIMIT 1$$;
   CREATE FUNCTION private.burimunsi_observation_key_lookup(text,text,text) RETURNS jsonb LANGUAGE sql AS $$SELECT NULL::jsonb$$;
   ${extract(prior,'CREATE FUNCTION private.burimunsi_observation_key_prepare(')}
   ${extract(draft,'CREATE FUNCTION private.burimunsi_sms_recovery_prepare(')}
   REVOKE ALL ON FUNCTION private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint)
    FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
   GRANT EXECUTE ON FUNCTION private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint) TO collect_runtime;
   INSERT INTO private.burimunsi_observation_consents VALUES('group-a','10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,1,true);
   SELECT set_config('fixture.reveal','yes',false);`);
  const request='50000000-0000-4000-8000-000000000001',id=sourceId(request),fingerprint='a'.repeat(64);
  const args=[ 'e'.repeat(64),'d'.repeat(64),'f'.repeat(64),request,fingerprint,id,'v1','b'.repeat(64),1];
  const call=a=>db.query('SELECT private.burimunsi_sms_recovery_prepare($1,$2,$3,$4::uuid,$5,$6,$7,$8,$9::bigint) result',a);
  await db.exec('UPDATE private.burimunsi_observation_consents SET generation=3,enabled=true');
  await assert.rejects(()=>call(args),/sms_held_consent_changed/);
  assert.equal((await db.query('SELECT count(*)::int n FROM private.burimunsi_observation_requests')).rows[0].n,0);
  await db.exec('UPDATE private.burimunsi_observation_consents SET generation=1');
  const exact=await Promise.all([call(args),call(args)]);
  assert(exact.every(x=>x.rows[0].result.kind==='new'));
  const rows=(await db.query('SELECT request_id,initial_consent_generation,fingerprint FROM private.burimunsi_observation_requests')).rows;
  assert.equal(rows.length,1);assert.equal(rows[0].request_id,request);assert.equal(Number(rows[0].initial_consent_generation),1);
  assert.equal(rows[0].fingerprint,fingerprint);
  await db.exec('UPDATE private.burimunsi_observation_consents SET generation=3');
  await assert.rejects(()=>call(args),/sms_held_consent_changed/);
  const changed=[...args];changed[8]=3;changed[4]='9'.repeat(64);
  await assert.rejects(()=>call(changed),/burimunsi_observation_conflict/);
  await db.exec("SELECT set_config('fixture.grant_version','2',false)");
  await assert.rejects(()=>call(changed),/sms_held_consent_changed/);
  // The number is an authenticated-session claim, not a server-signed proof of
  // what an unseen client originally stored. A first-seen request supplied
  // with the *current* generation is indistinguishable from a fabricated one.
  await db.exec("SELECT set_config('fixture.grant_version','1',false)");
  const unseen='50000000-0000-4000-8000-000000000002';
  const substituted=['8'.repeat(64),'d'.repeat(64),'f'.repeat(64),unseen,'7'.repeat(64),sourceId(unseen),'v1','b'.repeat(64),3];
  assert.equal((await call(substituted)).rows[0].result.kind,'new');
  const privileges=(await db.query(`SELECT has_function_privilege('anon',
   'private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint)','EXECUTE') anon,
   has_function_privilege('collect_runtime','private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint)','EXECUTE') runtime`)).rows[0];
  assert.equal(privileges.anon,false);assert.equal(privileges.runtime,true);
 }finally{await db.close();}
});
