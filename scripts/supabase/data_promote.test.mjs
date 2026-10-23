import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir,mkdtemp,realpath,rm} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {readSnapshot,stageSnapshot,validateTarget} from './data_stage.mjs';
import {disposition,makePromotionPlan,catalogIdentity,promoteSnapshot,reconcilePromotion,reviewedTables} from './data_promote.mjs';
const root=resolve(import.meta.dirname,'../..'),epoch=1792497600;
const sha=value=>createHash('sha256').update(value).digest('hex');

test('every source table is classified; device/native state requires a rebind plan',()=>{
 assert.equal(disposition('auth_sessions'),'historical_revoked');
 for(const n of ['auth_refresh_tokens','auth_google_flows','admin_sessions','mutation_guards'])assert.equal(disposition(n),'archive_only');
 assert.equal(disposition('ledger_entries'),'business_exact');
 const tables=reviewedTables.map(name=>({name,rows:[],row_count:name==='native_consents'?1:0,sha256:'a'.repeat(64)}));
 assert.throws(()=>makePromotionPlan({tables},reviewedTables,epoch),/rebind/);
 assert.throws(()=>disposition('unreviewed_new_table'),/Unknown table/);
 assert.throws(()=>makePromotionPlan({tables:[{name:'users'}]},['users'],epoch),/table set/);
 assert.throws(()=>makePromotionPlan({tables:[]},['extra'],epoch),/table set/);
 assert.throws(()=>makePromotionPlan({tables:[]},[],0),/epoch/);
});

async function withFixture(run){
 const url=process.env.COLLECT_IMPORT_TEST_DATABASE_URL;
 assert.ok(url,'COLLECT_IMPORT_TEST_DATABASE_URL is mandatory; never silently skip import qualification');
 const target=validateTarget(url,'local',{localTest:true});
 assert.equal(target.pathname,'/collect_import_test','This suite resets only its exclusive import fixture');
 const {Client}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
 const db=new Client({connectionString:url,connectionTimeoutMillis:5000,statement_timeout:60000});
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-import-'))),path=join(dir,'synthetic.sqlite');
 let schema;
 try{
  await db.connect();
  await db.query('DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS api CASCADE; DROP SCHEMA IF EXISTS auth CASCADE');
  await db.query(await readFile(join(root,'supabase/tests/sql/00_local_auth_fixture.sql'),'utf8'));
  const migrationNames=(await readdir(join(root,'supabase/migrations'))).filter(n=>/^\d{14}_[a-z0-9_]+\.sql$/.test(n)).sort();
  const migrations=await Promise.all(migrationNames.map(async name=>({name,bytes:await readFile(join(root,'supabase/migrations',name))})));
  for(const m of migrations)await db.query(m.bytes.toString('utf8'));
  const source=new DatabaseSync(path);
  try{
   const manifest=JSON.parse(await readFile(join(root,'supabase/schema-src/source_manifest.json'),'utf8'));
   for(const m of manifest.source_migrations){const bytes=await readFile(join(root,m.path));assert.equal(sha(bytes),m.sha256);source.exec(bytes.toString('utf8'));}
   // Fixture preparation only: source represents an already accepted history,
   // not a new write admission test. PostgreSQL target triggers stay enabled.
   for(const {name} of source.prepare("SELECT name FROM sqlite_schema WHERE type='trigger'").all())source.exec('DROP TRIGGER "'+name+'"');
   source.exec(`INSERT INTO users(id,public_id,full_name,created_at,updated_at) VALUES('synthetic-owner','000001','Import fixture','2026-10-20T00:00:00Z','2026-10-20T00:00:00Z');
    INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES('old-session','synthetic-owner','admin',1,1,2000000000);
    INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,code_hash,created_at,expires_at,status) VALUES('old-otp','${'c'.repeat(64)}','email','synthetic@example.invalid','member',0,'${'d'.repeat(64)}',1,100,'accepted');
    INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at) VALUES('${'e'.repeat(64)}','old-session',1,2000000000);
    INSERT INTO auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,registration_allowed,created_at,expires_at,status) VALUES('old-google','${'f'.repeat(64)}','synthetic-nonce','{"ciphertext":"synthetic-old-provider-payload"}','${'a'.repeat(43)}','synthetic-state',0,1,100,'ready');
    INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES('group-fixture','group-fixture','synthetic-owner','Import history','saving','2026-10-20T00:00:00Z','2026-10-20T00:00:00Z');
    INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES('membership-fixture','group-fixture','synthetic-owner','owner','2026-10-20T00:00:00Z');
    INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,observed_at,created_at) VALUES('evidence-fixture','group-fixture','synthetic-owner','synthetic/ciphertext','${'a'.repeat(64)}',12,'application/octet-stream','operator_recorded','2026-10-20T00:00:00Z','2026-10-20T00:00:00Z');
    INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES('payment-fixture','group-fixture','synthetic-owner','evidence-fixture',1200,'confirmed','2026-10-20T00:00:00Z');
    INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES('ledger-fixture','payment-fixture','group-fixture','synthetic-owner',1200,'contribution','evidence-fixture','synthetic-owner','request-fixture','2026-10-20T00:00:00Z');
    INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES('synthetic-owner','request-fixture','fixture','old-session','${'b'.repeat(64)}','{"accepted":true}','2026-10-20T00:00:00Z');`);
   source.prepare('INSERT INTO audit_log(id,actor_user_id,actor_session_id,action,entity_type,details_json,created_at) VALUES(?,?,?,?,?,?,?)').run(9007199254740993n,'synthetic-owner','old-session','fixture','fixture','{"synthetic":true}','2026-10-20T00:00:00Z');
  }finally{source.close();}
  const snapshot=await readSnapshot(path,sha(await readFile(path))),runId=randomUUID();
  const staged=await stageSnapshot(db,snapshot,{runId});schema=staged.schema;
  const options={schema,approvedTables:snapshot.tables.map(t=>t.name),catalogSha256:await catalogIdentity(db),migrationEpoch:epoch};
  await run({db,snapshot,options,Client,url});
  for(const m of migrations)assert.equal(sha(await readFile(join(root,'supabase/migrations',m.name))),sha(m.bytes),'Migration changed during test; rerun on frozen source');
 }finally{
  try{await db.query('RESET ROLE');if(schema)await db.query('DROP SCHEMA IF EXISTS "'+schema+'" CASCADE');}finally{await db.end();await rm(dir,{recursive:true,force:true});}
 }
}

test('full curated PostgreSQL import preserves history and lost COMMIT reconciles without replay',{timeout:60000},()=>withFixture(async({db,snapshot,options})=>{
 let dropped=false;
 const uncertain={query:async(...args)=>{const result=await db.query(...args);if(args[0]==='COMMIT'&&!dropped){dropped=true;throw new Error('synthetic lost COMMIT acknowledgement');}return result;}};
 await assert.rejects(promoteSnapshot(uncertain,snapshot,options),/lost COMMIT/);
 const plan=makePromotionPlan(snapshot,options.approvedTables,epoch);
 assert.equal((await reconcilePromotion(db,snapshot,{...options,plan})).verified,true);
 assert.equal((await promoteSnapshot(db,snapshot,options)).verified,true);
 assert.equal((await db.query('SELECT count(*)::int AS count,sum(amount_minor)::text AS total FROM app.ledger_entries')).rows[0].total,'1200');
 const old=(await db.query('SELECT * FROM app.auth_sessions')).rows[0];
 assert.equal(old.id,'old-session');assert.equal(old.revoked_at,String(epoch));assert.equal(old.assurance_level,'1');assert.equal(old.mfa_factor_id,null);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM private.auth_principal_links')).rows[0].count,0);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM private.bff_sessions')).rows[0].count,0);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM auth.users')).rows[0].count,0);
 for(const name of ['auth_otp_challenges','auth_refresh_tokens','auth_google_flows']){
  assert.equal((await db.query('SELECT count(*)::int AS count FROM app.'+name)).rows[0].count,0);
  const archived=await db.query('SELECT cells,sha256 FROM "'+options.schema+'".rows WHERE table_name=$1',[name]);
  assert.equal(archived.rowCount,1);assert.equal(archived.rows[0].sha256,snapshot.tables.find(t=>t.name===name).rows[0].sha256);
 }
 const next=(await db.query("INSERT INTO app.audit_log(action,entity_type,details_json,created_at) VALUES('next','fixture','{}','2026-10-20T00:00:00Z') RETURNING id::text")).rows[0].id;
 assert.equal(next,'9007199254740994');
 await assert.rejects(db.query("UPDATE app.ledger_entries SET amount_minor=1 WHERE id='ledger-fixture'"),/immutable|append|update|permission|forbid/i);
 await db.query('SET ROLE collect_runtime');await assert.rejects(db.query('SELECT * FROM "'+options.schema+'".rows'),/permission denied/);await db.query('RESET ROLE');
 await db.query('SET ROLE anon');await assert.rejects(db.query('SELECT * FROM app.users'),/permission denied/);await db.query('RESET ROLE');
 assert.equal(await catalogIdentity(db),options.catalogSha256);
}));

test('failure after disabled triggers and partial INSERT rolls back all application rows',{timeout:60000},()=>withFixture(async({db,snapshot,options})=>{
 let disabled=0,inserted=0;
 const broken={query:async(...args)=>{
  const result=await db.query(...args);
  if(/DISABLE TRIGGER USER$/.test(args[0]))disabled++;
  if(/^INSERT INTO app\./.test(args[0])){inserted++;if(inserted===2)throw new Error('synthetic midway import failure');}
  return result;
 }};
 await assert.rejects(promoteSnapshot(broken,snapshot,options),/midway import/);
 assert.ok(disabled>2);assert.equal(inserted,2);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM app.users')).rows[0].count,0);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM app.ledger_entries')).rows[0].count,0);
 assert.equal(await catalogIdentity(db),options.catalogSha256);
 assert.deepEqual(await reconcilePromotion(db,snapshot,{...options,plan:makePromotionPlan(snapshot,options.approvedTables,epoch)}),{committed:false});
 assert.equal((await promoteSnapshot(db,snapshot,options)).verified,true);
}));

test('concurrent writer commit before table locks is visible and refuses a pristine import',{timeout:60000},()=>withFixture(async({db,snapshot,options,Client,url})=>{
 const writer=new Client({connectionString:url,connectionTimeoutMillis:5000,statement_timeout:5000});
 await writer.connect();let committed=false;
 const racing={query:async(...args)=>{
  const result=await db.query(...args);
  if(args[0]==='SELECT pg_advisory_xact_lock(734636924058501::bigint)'&&!committed){
   await writer.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('concurrent-writer','999997','2026-10-20','2026-10-20')");committed=true;
  }
  return result;
 }};
 try{
  await assert.rejects(promoteSnapshot(racing,snapshot,options),/already contains application records/);
  assert.equal(committed,true);
  assert.equal((await db.query('SELECT count(*)::int AS count FROM app.users')).rows[0].count,1);
  assert.equal((await db.query('SELECT count(*)::int AS count FROM app.ledger_entries')).rows[0].count,0);
  assert.equal(await catalogIdentity(db),options.catalogSha256);
 }finally{await writer.end();}
}));

test('populated or changed target refuses promotion and restores all user triggers',{timeout:60000},()=>withFixture(async({db,snapshot,options})=>{
 await db.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('unexpected','999998','2026-10-20','2026-10-20')");
 await assert.rejects(promoteSnapshot(db,snapshot,options),/already contains/);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM app.users')).rows[0].count,1);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM app.ledger_entries')).rows[0].count,0);
 assert.equal(await catalogIdentity(db),options.catalogSha256);
 await assert.rejects(promoteSnapshot(db,snapshot,{...options,catalogSha256:'f'.repeat(64)}),/schema differs/);
 assert.equal((await db.query("SELECT count(*)::int AS count FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND NOT t.tgisinternal AND t.tgenabled<>'O'")).rows[0].count,0);
}));
