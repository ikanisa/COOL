// REVIEW CANDIDATE ONLY. No action on import. --execute creates and removes
// one randomly named synthetic schema; it never reads or writes business rows.
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {readFileSync,lstatSync} from 'node:fs';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {PROJECT} from './access.mjs';
import {loadProviderRoot} from '../managed-cloud-migrations/provider-ca.mjs';

const migration=new URL('../../../supabase/migrations/20261117220000_burimunsi_held_resume_guard.sql',import.meta.url);
const expected='870284f6146cf4c1a5ee428e5883c378cd30036333a5da5f062e97d00deefd46';
const sha=()=>createHash('sha256').update(readFileSync(migration)).digest('hex');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
async function connect(){
 const path='/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-db-credential-kq92ggw9/database-password.txt';
 const st=lstatSync(path);if(!st.isFile()||st.isSymbolicLink()||(st.mode&0o077)!==0||st.uid!==process.getuid())throw Error('private_credential_required');
 const {Client}=createRequire(import.meta.url)('pg');
 const client=new Client({host:'aws-0-eu-north-1.pooler.supabase.com',port:5432,user:'postgres.'+PROJECT,
  password:readFileSync(path,'utf8').trim(),database:'postgres',ssl:{ca:loadProviderRoot(),rejectUnauthorized:true},
  connectionTimeoutMillis:15000,statement_timeout:8000,application_name:'collect_heldresume_synthetic'});
 client.on('error',()=>{});try{await client.connect();const r=(await client.query(
  "SELECT session_user,current_user,current_database(),current_setting('server_version_num')::int version")).rows[0];
  if(PROJECT!=='rrlduytparvsjfmegalh'||r.session_user!=='postgres'||r.current_user!=='postgres'||r.current_database!=='postgres'||Math.floor(r.version/10000)!==17)throw Error('cloud_identity_mismatch');
  return client;}catch(error){await client.end().catch(()=>{});throw error;}
}
export async function runHeldResumeRace(){
 if(sha()!==expected)throw Error('reviewed_migration_changed');
 const nonce=randomUUID().replaceAll('-',''),schema=`collect_test_heldresume_${nonce}`,marker=`collect-heldresume:${nonce}`,q=`"${schema}"`;
 assert(/^collect_test_heldresume_[a-f0-9]{32}$/.test(schema));
 const lock=(9223372020000000000n-BigInt('0x'+randomBytes(4).toString('hex'))).toString();
 assert.notEqual(lock,'734636924058501');
 let control,a,b,createdOid=null,intent=false,cleaned=false,original=null,cleanupFailure=null;
 const rollback=async c=>{if(c)await c.query('ROLLBACK').catch(()=>{});};
 const begin=async c=>{await c.query('BEGIN');await c.query("SET LOCAL lock_timeout='3s'");await c.query("SET LOCAL statement_timeout='8s'");};
 const wait=async promise=>{const r=await Promise.race([promise.then(()=>({done:true}),error=>({done:true,error})),delay(250).then(()=>({done:false}))]);
  if(r.done)throw r.error??Error('concurrent_attempt_did_not_wait');};
 async function cleanup(){
  if(!control)return;const row=(await control.query("SELECT oid::text,pg_get_userbyid(nspowner) owner,obj_description(oid,'pg_namespace') marker FROM pg_namespace WHERE nspname=$1",[schema])).rows[0];
  if(!row){cleaned=true;return;}if(!intent||row.owner!=='postgres'||row.marker!==marker||(createdOid&&row.oid!==createdOid))throw Error('cleanup_identity_mismatch');
  const tables=(await control.query("SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=$1 AND c.relkind IN('r','p','v','m','S','f') ORDER BY c.relname",[schema])).rows.map(x=>x.relname);
  const funcs=(await control.query('SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=$1 ORDER BY p.proname',[schema])).rows.map(x=>x.proname);
  assert.deepEqual(tables,['burimunsi_observation_consents','burimunsi_observation_requests','burimunsi_recovered_sms_holds','storage_payload_reservations','storage_put_intents','storage_upload_attempts']);
  assert.deepEqual(funcs,['burimunsi_observation_actor','collect_sms_held_authorize','collect_sms_held_payload_guard','collect_sms_held_upload_guard']);await begin(control);
  try{await control.query(`DROP TABLE ${q}.burimunsi_observation_consents,${q}.burimunsi_observation_requests,${q}.burimunsi_recovered_sms_holds,${q}.storage_payload_reservations,${q}.storage_put_intents,${q}.storage_upload_attempts RESTRICT`);
   await control.query(`DROP FUNCTION ${q}.collect_sms_held_upload_guard(),${q}.collect_sms_held_payload_guard(),${q}.collect_sms_held_authorize(text,jsonb),${q}.burimunsi_observation_actor(boolean) RESTRICT`);await control.query(`DROP SCHEMA ${q} RESTRICT`);await control.query('COMMIT');
  }catch(error){await rollback(control);throw error;}
  cleaned=(await control.query('SELECT NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname=$1) removed',[schema])).rows[0]?.removed===true;
  if(!cleaned)throw Error('cleanup_readback_failed');
 }
 try{
  control=await connect();a=await connect();b=await connect();
  if((await control.query('SELECT 1 FROM pg_namespace WHERE nspname=$1',[schema])).rowCount)throw Error('schema_exists');
  if((await control.query('SELECT pg_try_advisory_lock($1::bigint) acquired',[lock])).rows[0]?.acquired!==true)throw Error('test_lock_unavailable');
  if((await control.query('SELECT pg_advisory_unlock($1::bigint) released',[lock])).rows[0]?.released!==true)throw Error('test_lock_release_failed');
  const source=readFileSync(migration,'utf8');
  const extract=name=>{const start=source.indexOf(`CREATE FUNCTION private.${name}(`),open=source.indexOf('$fn$',start),end=source.indexOf('$fn$;',open+4);
   if(start<0||open<0||end<0)throw Error('reviewed_migration_changed');return source.slice(start,end+5);};
  if(sha()!==expected)throw Error('reviewed_migration_changed');
  const fn=['collect_sms_held_authorize','collect_sms_held_payload_guard','collect_sms_held_upload_guard'].map(extract).join('\n')
   .replaceAll('private.',q+'.').replaceAll('734636924058501::bigint',lock+'::bigint');
  if(/(?:^|[^a-z])(private|app)\./i.test(fn)||fn.includes('734636924058501'))throw Error('production_reference_in_fixture');
  intent=true;await begin(control);await control.query(`CREATE SCHEMA ${q}; COMMENT ON SCHEMA ${q} IS '${marker}';
   CREATE TABLE ${q}.burimunsi_recovered_sms_holds(source_id text PRIMARY KEY,object_key text UNIQUE,collection_id text,account_id uuid,owner_id text,body_sha256 text,request_digest text);
   CREATE TABLE ${q}.burimunsi_observation_requests(source_id text PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,
    installation_id uuid,grant_id uuid,grant_version bigint,initial_consent_generation bigint,fingerprint text,source_key_body_sha256 text);
   CREATE TABLE ${q}.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,grant_id uuid,grant_version bigint,generation bigint,enabled boolean);
   CREATE TABLE ${q}.storage_payload_reservations(object_key text,scope jsonb,sealed_body text);
   CREATE TABLE ${q}.storage_put_intents(operation_id text PRIMARY KEY,object_key text UNIQUE,state text,scope jsonb,attempts integer,active_attempt uuid,upload_unresolved boolean,delete_tombstone boolean);
   CREATE TABLE ${q}.storage_upload_attempts(id uuid PRIMARY KEY,operation_id text);
   CREATE FUNCTION ${q}.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE sql AS $actor$
    SELECT jsonb_build_object('collectionId','group-a','accountId','10000000-0000-4000-8000-000000000001','principalUserId','owner-a',
     'installationId','20000000-0000-4000-8000-000000000001','grantId','30000000-0000-4000-8000-000000000001','grantVersion',1)$actor$;
   ${fn}
   CREATE TRIGGER held_payload BEFORE INSERT ON ${q}.storage_payload_reservations FOR EACH ROW EXECUTE FUNCTION ${q}.collect_sms_held_payload_guard();
   ALTER TABLE ${q}.storage_payload_reservations ENABLE ALWAYS TRIGGER held_payload;
   CREATE TRIGGER held_upload BEFORE INSERT ON ${q}.storage_upload_attempts FOR EACH ROW EXECUTE FUNCTION ${q}.collect_sms_held_upload_guard();
   ALTER TABLE ${q}.storage_upload_attempts ENABLE ALWAYS TRIGGER held_upload;`);await control.query('COMMIT');
  const created=(await control.query("SELECT oid::text,pg_get_userbyid(nspowner) owner,obj_description(oid,'pg_namespace') marker FROM pg_namespace WHERE nspname=$1",[schema])).rows[0];
  if(created?.owner!=='postgres'||created?.marker!==marker)throw Error('test_schema_identity_mismatch');createdOid=created.oid;
  await control.query(`INSERT INTO ${q}.burimunsi_recovered_sms_holds
   SELECT n,'sms/'||n,'group-a','10000000-0000-4000-8000-000000000001','owner-a',repeat('b',64),repeat('a',64)
   FROM unnest(ARRAY['one','two','three','payload','revoked','started']) n;
   INSERT INTO ${q}.burimunsi_observation_requests
   SELECT n,'group-a','10000000-0000-4000-8000-000000000001','owner-a','20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',1,CASE WHEN n='started' THEN 5 WHEN n='revoked' THEN 3 ELSE 1 END,repeat('a',64),repeat('b',64)
    FROM unnest(ARRAY['one','two','three','payload','revoked','started']) n;
   INSERT INTO ${q}.burimunsi_observation_consents VALUES('group-a','10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,1,true);
   INSERT INTO ${q}.storage_put_intents
    SELECT n,'sms/'||n,'pending',jsonb_build_object('ownerId','owner-a','purpose','sms_receipt','entityId',n),0,NULL,false,false
    FROM unnest(ARRAY['one','two','three','payload','revoked','started','normal']) n;`);
  // Two concurrent starts: the first durable attempt wins and the second is denied.
  await begin(a);await begin(b);await a.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'one')`,[id(1)]);
  const duplicate=b.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'one')`,[id(2)]);
  await wait(duplicate);await a.query('COMMIT');await assert.rejects(duplicate,e=>e.code==='55000');await rollback(b);
  // If the first database transaction aborts before it can send, the other can
  // make the first and only durable attempt.
  await begin(a);await begin(b);await a.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'two')`,[id(3)]);
  const aborted=b.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'two')`,[id(4)]);
  await wait(aborted);await a.query('ROLLBACK');await aborted;await b.query('COMMIT');
  // A previously completed or uncertain attempt cannot obtain a second start.
  await control.query(`UPDATE ${q}.storage_put_intents SET attempts=1,upload_unresolved=true WHERE operation_id='three'`);
  await assert.rejects(()=>control.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'three')`,[id(5)]),e=>e.code==='55000');
  // Unheld sources keep their existing storage retry behavior.
  await control.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'normal'),($2,'normal')`,[id(6),id(7)]);
  // Revocation commits before ciphertext reservation. The reservation waits,
  // sees revoked consent, and retains no ciphertext in the test database.
  await begin(a);await begin(b);
  await a.query(`UPDATE ${q}.burimunsi_observation_consents SET enabled=false,generation=2`);
  const payload=b.query(`INSERT INTO ${q}.storage_payload_reservations VALUES('sms/payload',jsonb_build_object('ownerId','owner-a','purpose','sms_receipt','entityId','payload'),'synthetic encrypted bytes')`);
  await wait(payload);await a.query('COMMIT');await assert.rejects(payload,e=>e.code==='42501');await rollback(b);
  assert.equal((await control.query(`SELECT count(*)::int n FROM ${q}.storage_payload_reservations WHERE object_key='sms/payload'`)).rows[0].n,0);
  // A separate revocation wins after the earlier context check, but before
  // the provider PUT start; the start waits, sees it and is denied.
  await control.query(`UPDATE ${q}.burimunsi_observation_consents SET enabled=true,generation=3`);
  await begin(a);await begin(b);
  await a.query(`UPDATE ${q}.burimunsi_observation_consents SET enabled=false,generation=4`);
  const revoked=b.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'revoked')`,[id(8)]);
  await wait(revoked);await a.query('COMMIT');await assert.rejects(revoked,e=>e.code==='42501');await rollback(b);
  // Explicitly re-consent at a newer generation for a different source. If
  // upload-start takes the shared row lock first, revocation waits until that
  // start commits. Its outcome may finish, but a later attempt is denied.
  await control.query(`UPDATE ${q}.burimunsi_observation_consents SET enabled=true,generation=5`);
  await begin(a);await begin(b);await a.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'started')`,[id(9)]);
  const revokeAfterStart=b.query(`UPDATE ${q}.burimunsi_observation_consents SET enabled=false,generation=6`);
  await wait(revokeAfterStart);await a.query('COMMIT');await revokeAfterStart;await b.query('COMMIT');
  await assert.rejects(()=>control.query(`INSERT INTO ${q}.storage_upload_attempts VALUES($1,'started')`,[id(10)]),e=>e.code==='42501');
  const counts=(await control.query(`SELECT operation_id,count(*)::int n FROM ${q}.storage_upload_attempts GROUP BY operation_id ORDER BY operation_id`)).rows;
  assert.deepEqual(counts,[{operation_id:'normal',n:2},{operation_id:'one',n:1},{operation_id:'started',n:1},{operation_id:'two',n:1}]);
 }catch(error){original=error;}
 finally{await rollback(a);await rollback(b);await rollback(control);try{await cleanup();}catch(error){cleanupFailure=error;}
  for(const client of [a,b,control])if(client)await client.end().catch(()=>{});}
 if(cleanupFailure)throw new AggregateError([original,cleanupFailure].filter(Boolean),`cleanup_failed_for_exact_test_schema:${schema}`);
 if(original)throw original;return {suite:'held-resume-cloud-race',schemaRemoved:cleaned,productionRowsTouched:false};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(process.argv.length!==3||process.argv[2]!=='--execute')throw Error('review_and_explicit_execute_required');
 runHeldResumeRace().then(r=>console.log(JSON.stringify(r))).catch(error=>{console.error(error.message);process.exitCode=1;});
}
