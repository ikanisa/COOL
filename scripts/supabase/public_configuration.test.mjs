import {loadReviewedPlatformFixture,ORIGINAL_NINE} from './testing/curated-platform-fixture.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {catalogIdentity} from './data_promote.mjs';
import {validateTarget} from './data_stage.mjs';
import {publicConfigurationKeys,preparePublicConfiguration,validatePublicConfigurationPlan,readPublicConfigurationSnapshot,applyPublicConfiguration,reconcilePublicConfiguration} from './public_configuration.mjs';

const root=resolve(import.meta.dirname,'../..');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const at='2026-10-20T18:40:00Z';
const oldAt='2026-10-20T00:00:00Z';
const action='operator.public_configuration.replace.v1';
const fenceSource='a'.repeat(64);
const fenceBaseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const migrationPins=Object.freeze({
 "20261020134444_collect_curated_platform_baseline.sql": "0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0",
 "20261020135932_collect_runtime_role_and_function_paths.sql": "59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1",
 "20261020174856_collect_retention_retry_authority.sql": "d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c",
 "20261020184012_collect_admin_invitation_attempts.sql": "c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665",
 "20261020190301_collect_rls_helper_permissions.sql": "dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645",
 "20261020191847_collect_privacy_email_reauthentication.sql": "d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4",
 "20261020193752_collect_admin_invitation_access_notice_v2.sql": "b48a381169e777160a37396539248325e40b331a61db986622514724517f8467",
 "20261020195249_collect_admin_invitation_public_id_preservation.sql": "78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850",
 "20261022195747_collect_application_mutation_fence.sql": "714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497"
});
const rejected=(promise,code)=>assert.rejects(promise,error=>error.code===code);

function payload(){
 return {schema_version:1,kind:'collect_public_configuration_seed',api_source_id:'a'.repeat(64),legal_release_approved:false,provider_approved:false,retention_policy_activation:false,
  source_inputs:{'synthetic/qualified-source.json':{bytes:10,sha256:'c'.repeat(64)}},
  records:publicConfigurationKeys.map(key=>({key,value_json:key.startsWith('policy:')?
   JSON.stringify({kind:key.slice(7),content_status:'draft_for_legal_review',legal_release_approved:false,sections:[{title:'Synthetic',body:'Fixture content'}]}):
   JSON.stringify({synthetic:key,new_value:true})}))};
}

async function withFixture(run){
 const url=process.env.COLLECT_PUBLIC_CONFIG_TEST_DATABASE_URL;
 assert.ok(url,'COLLECT_PUBLIC_CONFIG_TEST_DATABASE_URL is mandatory; PostgreSQL qualification must not silently skip');
 const target=validateTarget(url,'local',{localTest:true});
 assert.equal(target.pathname,'/collect_public_configuration_test','Only this exclusively owned fixture may be reset');
 assert.equal(decodeURIComponent(target.username),'collect_test','Only the existing fixture owner is permitted');
 const alternate=process.env.COLLECT_CI_SYNTHETIC==='true'&&target.hostname==='127.0.0.1'&&['55441','55443'].includes(target.port);
 assert.ok(target.port==='55439'||alternate,'Only the owned local fixture cluster or explicit synthetic qualification port is permitted');
 const {Client,Pool}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
 const config={connectionString:target.href,connectionTimeoutMillis:5000,statement_timeout:30000};
 const db=new Client(config);await db.connect();
 let migrations=[];
 try{
  await db.query('DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS api CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS realtime CASCADE');
  await db.query(await readFile(join(root,'supabase/tests/sql/00_local_auth_fixture.sql'),'utf8'));
  // Synthetic local managed schema only; never an alteration for hosted Auth.
  await db.query('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
  assert.deepEqual(migrationPins,ORIGINAL_NINE,'All nine predecessor pins remain exact');
  const reviewedPlatform=await loadReviewedPlatformFixture(root);migrations=reviewedPlatform.rawMigrations;
  await reviewedPlatform.apply(text=>db.query(text));
  // Real owner-only initialization; no stub/default OPEN or application bypass.
  const initialized=(await db.query('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text) AS result',[randomUUID(),fenceSource,fenceBaseline])).rows[0].result;
  assert.equal(initialized.contractVersion,1);assert.equal(initialized.sourceSha256,fenceSource);
  assert.equal(initialized.mode,'open');assert.equal(initialized.epoch,1);
  assert.equal(initialized.activeAdmissions,0);assert.equal(initialized.unresolvedAdmissions,0);
  await db.query("INSERT INTO app.users(id,public_id,full_name,created_at,updated_at) VALUES('synthetic-prior-author','000001','Synthetic prior author',$1,$1)",[oldAt]);
  const reset=async()=>{
   await db.query('TRUNCATE app.runtime_config,app.audit_log RESTART IDENTITY');
   const input=payload();
   for(const record of input.records){
    const value=record.key==='list_account_request_reasons'?record.value_json:'{ "old" : true }';
    const revision=record.key==='get_collection_type_catalog'?'9007199254740993':'2';
    await db.query('INSERT INTO app.runtime_config(key,value_json,revision,updated_by,updated_at) VALUES($1,$2,$3::bigint,$4,$5)',[record.key,value,revision,'synthetic-prior-author',oldAt]);
   }
   for(const key of ['unrelated:é','privacy:retention:approved:v1'])await db.query('INSERT INTO app.runtime_config(key,value_json,revision,updated_by,updated_at) VALUES($1,$2,7,$3,$4)',[key,'{ "approved": false, "raw": [1, 2] }','synthetic-prior-author',oldAt]);
   await db.query("INSERT INTO app.audit_log(action,entity_type,request_id,details_json,created_at) VALUES('fixture','fixture','unrelated-request','{}',$1)",[oldAt]);
  };
  const options=async(overrides={})=>{
   const bytes=Buffer.from(JSON.stringify(payload(),null,2)+'\n');
   const identity={payload_sha256:sha(bytes),source_manifest_sha256:'b'.repeat(64),api_source_id:'a'.repeat(64)};
   return {payloadBytes:bytes,payloadSha256:identity.payload_sha256,sourceManifestSha256:identity.source_manifest_sha256,apiSourceId:identity.api_source_id,
    catalogSha256:await catalogIdentity(db),operationId:randomUUID(),createdAt:at,verifySource:async()=>({...identity}),...overrides};
  };
  const state=async()=>({config:await readPublicConfigurationSnapshot(db),audit:(await db.query('SELECT id::text AS id,actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at FROM app.audit_log ORDER BY id')).rows});
  await run({db,Client,Pool,config,reset,options,state});
  for(const migration of migrations)assert.equal(sha(await readFile(join(root,'supabase/migrations',migration.name))),sha(migration.bytes),'Migration source changed during qualification');
 }finally{await db.end();}
}

// These are actual PostgreSQL fixture cases. No provider, hosted project, public
// RPC, SDK or mobile/device behavior is exercised or claimed by this suite.
test('guarded public configuration on the complete curated local schema',{timeout:180000},t=>withFixture(async({db,Client,Pool,config,reset,options,state})=>{
 await reset();
 const steps=[];
 const step=async(name,run)=>t.test(name,async()=>{await reset();await run();steps.push(name);});

 await step('atomic update, exact raw postimage, bigint revisions and one unimpersonated audit',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input);
  assert.ok(Object.isFrozen(plan)&&Object.isFrozen(plan.preimage)&&Object.isFrozen(plan.preimage[0]));
  assert.deepEqual(validatePublicConfigurationPlan(JSON.parse(JSON.stringify(plan))),plan);
  assert.deepEqual(plan.keys,publicConfigurationKeys);assert.equal(plan.changed_keys.length,4);
  assert.equal((await reconcilePublicConfiguration(db,plan,input)).status,'not_applied');
  const result=await applyPublicConfiguration({client:db},plan,input);
  assert.equal(result.status,'applied');assert.equal(result.replayed,false);
  assert.deepEqual(await readPublicConfigurationSnapshot(db),plan.postimage);
  assert.equal(plan.postimage.find(row=>row.key==='get_collection_type_catalog').revision,'9007199254740994');
  const unchanged=plan.preimage.filter(row=>!plan.changed_keys.includes(row.key));
  assert.deepEqual(plan.postimage.filter(row=>!plan.changed_keys.includes(row.key)),unchanged);
  assert.ok(plan.postimage.filter(row=>plan.changed_keys.includes(row.key)).every(row=>row.updated_by===null&&row.updated_at===at));
  const receipts=(await db.query('SELECT id::text AS id,actor_user_id,actor_session_id,details_json FROM app.audit_log WHERE request_id=$1',[plan.operation_id])).rows;
  assert.equal(receipts.length,1);assert.equal(receipts[0].id,result.audit_id);
  assert.equal(receipts[0].actor_user_id,null);assert.equal(receipts[0].actor_session_id,null);
  const receipt=JSON.parse(receipts[0].details_json);
  for(const key of ['legal_release_approved','provider_approved','retention_policy_activation'])assert.equal(receipt[key],false);
  assert.deepEqual(receipt.changed_keys,plan.changed_keys);assert.equal(receipt.plan_sha256,plan.plan_sha256);
  const before=await state();assert.equal((await applyPublicConfiguration(db,plan,input)).replayed,true);assert.deepEqual(await state(),before);
 });

 await step('missing selected key refuses preparation without a replacement insert',async()=>{
  await db.query("DELETE FROM app.runtime_config WHERE key='policy:terms'");const before=await state();
  await rejected(preparePublicConfiguration(db,await options()),'MISSING_KEY');assert.deepEqual(await state(),before);
 });

 await step('positive selected revisions and overflow are mandatory',async()=>{
  for(const value of ['0','-1','9223372036854775807']){
   await db.query("UPDATE app.runtime_config SET revision=$1::bigint WHERE key='get_collection_type_catalog'",[value]);const before=await state();
   await rejected(preparePublicConfiguration(db,await options()),value==='9223372036854775807'?'REVISION_OVERFLOW':'INVALID_REVISION');
   assert.deepEqual(await state(),before);
  }
 });

 await step('all-row preimage rejects unrelated raw JSON, revision, author or timestamp drift',async()=>{
  for(const [column,value] of [['value_json','{"approved":false,"raw":[1,2]}'],['revision','8'],['updated_by',null],['updated_at',at]]){
   await reset();const input=await options(),plan=await preparePublicConfiguration(db,input);
   assert.ok(['value_json','revision','updated_by','updated_at'].includes(column));
   await db.query('UPDATE app.runtime_config SET '+column+'=$1 WHERE key=$2',[value,'unrelated:é']);const before=await state();
   await rejected(applyPublicConfiguration(db,plan,input),'PREIMAGE_DRIFT');
   await rejected(reconcilePublicConfiguration(db,plan,input),'PREIMAGE_DRIFT');assert.deepEqual(await state(),before);
  }
 });

 await step('unrelated row insertion/deletion and selected partial state refuse',async()=>{
  for(const mutate of [()=>db.query("INSERT INTO app.runtime_config(key,value_json,updated_at) VALUES('unexpected','{}','fixture')"),
   ()=>db.query("DELETE FROM app.runtime_config WHERE key='unrelated:é'"),
   ()=>db.query("UPDATE app.runtime_config SET revision=revision+1 WHERE key='policy:privacy'")]){
   await reset();const input=await options(),plan=await preparePublicConfiguration(db,input);await mutate();const before=await state();
   await rejected(applyPublicConfiguration(db,plan,input),'PREIMAGE_DRIFT');assert.deepEqual(await state(),before);
  }
 });

 await step('changed catalog refuses before data mutation',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input);
  await db.query('CREATE INDEX public_configuration_fixture_changed ON app.runtime_config(updated_at)');
  try{const before=await state();await rejected(applyPublicConfiguration(db,plan,input),'CATALOG_DRIFT');await rejected(reconcilePublicConfiguration(db,plan,input),'CATALOG_DRIFT');assert.deepEqual(await state(),before);}
  finally{await db.query('DROP INDEX app.public_configuration_fixture_changed');}
 });

 await step('source pins are reverified and changed source rolls the entire transaction back',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),before=await state();
  await rejected(applyPublicConfiguration(db,plan,{}),'SOURCE_VERIFICATION_REQUIRED');
  await rejected(applyPublicConfiguration(db,plan,{verifySource:async()=>({...await input.verifySource(),api_source_id:'d'.repeat(64)})}),'SOURCE_DRIFT');
  let calls=0;
  await rejected(applyPublicConfiguration(db,plan,{verifySource:async()=>({...await input.verifySource(),source_manifest_sha256:++calls===1?input.sourceManifestSha256:'d'.repeat(64)})}),'SOURCE_DRIFT');
  assert.equal(calls,2);assert.deepEqual(await state(),before);
 });

 await step('audit insertion failure rolls back every changed configuration row',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),before=await state();let updated=0;
  const failing={query:async(text,values)=>{
   if(text.startsWith('INSERT INTO app.audit_log'))throw new Error('synthetic audit write failure');
   const result=await db.query(text,values);if(text.startsWith('UPDATE app.runtime_config'))updated++;return result;
  }};
  await assert.rejects(applyPublicConfiguration(failing,plan,input),/synthetic audit write failure/);
  assert.equal(updated,4);assert.deepEqual(await state(),before);
 });

 await step('lost COMMIT acknowledgement reconciles original committed operation without another update',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input);let lost=false;
  const uncertain={query:async(text,values)=>{
   const result=await db.query(text,values);
   if(text==='COMMIT'&&!lost){lost=true;throw new Error('synthetic lost commit acknowledgement');}return result;
  }};
  await assert.rejects(applyPublicConfiguration(uncertain,plan,input),error=>error.code==='COMMIT_UNCONFIRMED'&&error.reconcile_required&&error.operation_id===plan.operation_id);
  const before=await state(),reconciled=await reconcilePublicConfiguration(db,JSON.parse(JSON.stringify(plan)),input);
  assert.equal(reconciled.status,'applied');assert.equal(reconciled.committed,true);
  assert.equal((await applyPublicConfiguration(db,plan,input)).replayed,true);assert.deepEqual(await state(),before);
 });

 await step('uncertain COMMIT and failed rollback discard the injected Pool connection',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input);let released;
  const pool={connect:async()=>({
   query:async(text,values)=>{
    if(text==='ROLLBACK')throw new Error('synthetic rollback failure');
    const result=await db.query(text,values);if(text==='COMMIT')throw new Error('synthetic lost pooled COMMIT');return result;
   },release:error=>{released=error;},
  })};
  await assert.rejects(applyPublicConfiguration({pool},plan,input),error=>error.code==='COMMIT_UNCONFIRMED'&&error.discard_connection&&error.rollback_error?.message==='synthetic rollback failure'&&error.cause?.message==='synthetic lost pooled COMMIT');
  assert.equal(released?.code,'COMMIT_UNCONFIRMED');assert.equal(released.discard_connection,true);
  assert.equal((await reconcilePublicConfiguration(db,plan,input)).status,'applied');
 });

 await step('lost BEGIN acknowledgement rolls back and discards the injected Pool connection',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),before=await state();let released;
  const pool={connect:async()=>({
   query:async(text,values)=>{
    const result=await db.query(text,values);if(text.startsWith('BEGIN '))throw new Error('synthetic lost BEGIN');return result;
   },release:error=>{released=error;},
  })};
  await assert.rejects(applyPublicConfiguration({pool},plan,input),error=>error.code==='BEGIN_UNCONFIRMED'&&error.discard_connection&&error.cause?.message==='synthetic lost BEGIN');
  assert.equal(released?.code,'BEGIN_UNCONFIRMED');assert.equal(released.discard_connection,true);assert.deepEqual(await state(),before);
 });

 await step('concurrent apply through injected Pool commits exactly one change and one receipt',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),pool=new Pool({...config,max:2});
  try{
   const results=await Promise.all([applyPublicConfiguration({pool},plan,input),applyPublicConfiguration({pool},plan,input)]);
   assert.deepEqual(results.map(result=>result.replayed).sort(),[false,true]);
   assert.equal(new Set(results.map(result=>result.audit_id)).size,1);
   assert.equal((await db.query('SELECT count(*)::int AS count FROM app.audit_log WHERE request_id=$1',[plan.operation_id])).rows[0].count,1);
   assert.deepEqual(await readPublicConfigurationSnapshot(db),plan.postimage);
  }finally{await pool.end();}
 });

 await step('reconciliation waits for an in-flight writer before classifying not-applied',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),reader=new Client(config);await reader.connect();
  let releaseCommit,atCommit;
  const committed=new Promise(resolve=>{atCommit=resolve;});
  const hold=new Promise(resolve=>{releaseCommit=resolve;});
  const writer={query:async(text,values)=>{
   if(text==='COMMIT'){atCommit();await hold;}return db.query(text,values);
  }};
  let writing,reading,finished=false;
  try{
   writing=applyPublicConfiguration(writer,plan,input);await committed;
   reading=reconcilePublicConfiguration(reader,plan,input).then(result=>{finished=true;return result;});
   // Observe the actual lock wait, rather than infer a fence from elapsed time.
   let waiting=false;
   for(let attempt=0;attempt<100;attempt++){
    await db.query('SELECT pg_stat_clear_snapshot()');
    const result=await db.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[reader.processID]);
    if(result.rows[0]?.wait_event_type==='Lock'){waiting=true;break;}
    await new Promise(resolve=>setTimeout(resolve,5));
   }
   assert.equal(waiting,true,'The independent reconciliation reader must reach a real PostgreSQL lock wait');assert.equal(finished,false);
   releaseCommit();assert.equal((await writing).status,'applied');assert.equal((await reading).status,'applied');
  }finally{releaseCommit();if(writing)await writing.catch(()=>{});if(reading)await reading.catch(()=>{});await reader.end();}
 });

 await step('receipt absence plus exact preimage is not-applied only under the same table fence',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input);const queries=[];
  const observed={query:async(text,values)=>{queries.push(text);return db.query(text,values);}};
  assert.equal((await reconcilePublicConfiguration(observed,plan,input)).status,'not_applied');
  assert.equal(queries[0],'BEGIN ISOLATION LEVEL READ COMMITTED');
  assert.ok(queries.findIndex(text=>text.startsWith('LOCK TABLE app.runtime_config,app.audit_log IN SHARE ROW EXCLUSIVE MODE'))<queries.findIndex(text=>text.startsWith('SELECT key,value_json')));
 });

 await step('duplicate or different operation receipts and post-commit drift refuse reconciliation',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input);await applyPublicConfiguration(db,plan,input);
  await db.query('INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at) SELECT actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at FROM app.audit_log WHERE request_id=$1',[plan.operation_id]);
  await rejected(reconcilePublicConfiguration(db,plan,input),'RECEIPT_CARDINALITY');await rejected(applyPublicConfiguration(db,plan,input),'RECEIPT_CARDINALITY');
  await reset();const otherInput=await options(),otherPlan=await preparePublicConfiguration(db,otherInput);
  await db.query("INSERT INTO app.audit_log(action,entity_type,request_id,details_json,created_at) VALUES('different-action','fixture',$1,'{}',$2)",[otherPlan.operation_id,at]);
  await rejected(reconcilePublicConfiguration(db,otherPlan,otherInput),'RECEIPT_DRIFT');await rejected(applyPublicConfiguration(db,otherPlan,otherInput),'RECEIPT_DRIFT');
  await reset();const driftInput=await options(),driftPlan=await preparePublicConfiguration(db,driftInput);await applyPublicConfiguration(db,driftPlan,driftInput);
  await db.query("UPDATE app.runtime_config SET revision=revision+1 WHERE key='unrelated:é'");
  await rejected(reconcilePublicConfiguration(db,driftPlan,driftInput),'POSTIMAGE_DRIFT');
 });

 await step('plan tampering and approval changes are refused',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),before=await state();
  for(const mutate of [value=>value.postimage[0].revision='1',value=>value.project_ref='wrong-project',value=>value.legal_release_approved=true,
   value=>value.source_manifest_sha256='d'.repeat(64),value=>value.extra='unreviewed']){
   const changed=JSON.parse(JSON.stringify(plan));mutate(changed);await rejected(applyPublicConfiguration(db,changed,input),'INVALID_PLAN');
  }
  for(const key of ['legal_release_approved','provider_approved','retention_policy_activation']){
   const bad=payload();bad[key]=true;const bytes=Buffer.from(JSON.stringify(bad));
   await rejected(preparePublicConfiguration(db,{...input,payloadBytes:bytes,payloadSha256:sha(bytes)}),'INVALID_PAYLOAD');
  }
  const policy=payload();const row=policy.records.find(row=>row.key==='policy:privacy');row.value_json=JSON.stringify({...JSON.parse(row.value_json),content_status:'approved'});
  const bytes=Buffer.from(JSON.stringify(policy));await rejected(preparePublicConfiguration(db,{...input,payloadBytes:bytes,payloadSha256:sha(bytes)}),'INVALID_PAYLOAD');
  assert.deepEqual(await state(),before);
 });

 await step('a prepared public-configuration plan is refused after committed QUIESCING without current-state changes',async()=>{
  const input=await options(),plan=await preparePublicConfiguration(db,input),stopId=randomUUID();
  await db.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{
   const stopped=(await db.query('SELECT private.collect_fence_begin_quiesce($1::uuid,$2::bigint,$3::text) AS result',[stopId,1,fenceSource])).rows[0].result;
   assert.equal(stopped.mode,'quiescing');assert.equal(stopped.operationId,stopId);
   await db.query('COMMIT');
  }catch(error){await db.query('ROLLBACK');throw error;}
  const observer=new Client(config);await observer.connect();
  try{
   const fenceBefore=(await observer.query('SELECT private.collect_fence_owner_status() AS result')).rows[0].result;
   assert.equal(fenceBefore.mode,'quiescing','Independent connection must observe the committed stop');
   assert.equal(fenceBefore.epoch,1);assert.equal(fenceBefore.sourceSha256,fenceSource);assert.equal(fenceBefore.operationId,stopId);
   const before=await state();
   await assert.rejects(applyPublicConfiguration(db,plan,input),error=>error.code==='55000'&&error.message==='collect_fence_closed');
   assert.deepEqual(await state(),before,'Failed apply must preserve every configuration/audit row');
   assert.deepEqual((await observer.query('SELECT private.collect_fence_owner_status() AS result')).rows[0].result,fenceBefore,'Refusal must preserve the committed fence state');
   assert.equal((await db.query('SELECT count(*)::int AS count FROM app.audit_log WHERE request_id=$1',[plan.operation_id])).rows[0].count,0);
   assert.equal(fenceBefore.applicationFenceComplete,false);assert.equal(fenceBefore.wholeSystemAcceptance,false);assert.equal(fenceBefore.sb29Satisfied,false);
  }finally{await observer.end();}
 });

 assert.equal(steps.length,17);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM auth.users')).rows[0].count,0);
 assert.equal((await db.query('SELECT count(*)::int AS count FROM app.ledger_entries')).rows[0].count,0);
 assert.ok((await db.query('SELECT action FROM app.audit_log WHERE action=$1',[action])).rows.every(row=>row.action===action));
}));
