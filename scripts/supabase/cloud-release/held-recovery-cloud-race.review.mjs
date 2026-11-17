// REVIEW CANDIDATE ONLY. Nothing happens on import. With --execute, this uses
// the existing verified Supabase Cloud connection to create one random schema,
// run synthetic two-connection races and remove only that exact schema.
// It does not read or change production rows and never takes a production
// advisory-lock key. Review and explicit operator invocation are required.
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync,lstatSync} from 'node:fs';
import {createRequire} from 'node:module';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {PROJECT} from './access.mjs';
import {loadProviderRoot} from '../managed-cloud-migrations/provider-ca.mjs';

const tableNames=['collect_sms_witnesses','burimunsi_recovered_sms_holds','burimunsi_observation_requests',
 'burimunsi_unresolved_observations','burimunsi_sms_source_scopes','storage_payload_reservations','storage_put_intents',
 'sms_receipts','burimunsi_auto_sms_jobs','burimunsi_native_financial_work','momo_processing_jobs','momo_parse_attempts',
 'momo_transaction_sources','burimunsi_transaction_scopes','momo_financial_links','payments',
 'burimunsi_scopes','momo_gateway_bindings','momo_receiving_accounts'];
const functions=[['collect_fence_assert_write','uuid,bigint,text'],['burimunsi_observation_actor','boolean'],
 ['burimunsi_observation_consent_current',''],['collect_sms_witness_reserve','text,text,text,text,text,text,timestamptz,text'],
 ['burimunsi_sms_recovery_hold','text,uuid,text,text,timestamptz'],['collect_sms_held_source_guard',''],
 ['collect_sms_recovery_held','text'],['collect_sms_recovery_transaction_matches','text,text'],
 ['collect_sms_recovery_scope_guard',''],['collect_sms_recovery_financial_guard',''],
 ['collect_sms_recovery_work_guard',''],['collect_sms_recovery_raw_work_guard','']];
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
async function connectTest(){
 const path='/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-db-credential-kq92ggw9/database-password.txt';
 const stat=lstatSync(path);
 if(!stat.isFile()||stat.isSymbolicLink()||(stat.mode&0o077)!==0||stat.uid!==process.getuid())throw Error('private_credential_required');
 const {Client}=createRequire(import.meta.url)('pg');
 const client=new Client({host:'aws-0-eu-north-1.pooler.supabase.com',port:5432,user:'postgres.'+PROJECT,
  password:readFileSync(path,'utf8').trim(),database:'postgres',ssl:{ca:loadProviderRoot(),rejectUnauthorized:true},
  connectionTimeoutMillis:15000,statement_timeout:8000,application_name:'collect_heldrace_synthetic'});
 client.on('error',()=>{});
 try{
  await client.connect();
  const identity=(await client.query("SELECT session_user,current_user,current_database(),current_setting('server_version_num')::int version")).rows[0];
  if(PROJECT!=='rrlduytparvsjfmegalh'||identity.session_user!=='postgres'||identity.current_user!=='postgres'||
   identity.current_database!=='postgres'||Math.floor(identity.version/10000)!==17)throw Error('cloud_identity_mismatch');
  return client;
 }catch(error){try{await client.end();}catch{}throw error;}
}

export async function runHeldRecoveryRace(){
 const fixture=new URL('./generate-held-recovery-temp-fixture.mjs',import.meta.url);
 const migration=new URL('../../../supabase/migrations/20261117210000_burimunsi_held_recovery.sql',import.meta.url);
 const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
 if(hash(fixture)!=='506a0dc78e55c919c6e7e4b60ade82b42fb28a20a4709b6d70d0427d55a5cbf4'||
  hash(migration)!=='ec9a1bb74603237262d66d09f71a1e49b1ac1941ca114e20700b22e8c90bf293')throw Error('reviewed_fixture_or_migration_changed');
 const nonce=randomUUID().replaceAll('-',''),schema=`collect_test_heldrace_${nonce}`,marker=`collect-heldrace:${nonce}`;
 assert(/^collect_test_heldrace_[a-f0-9]{32}$/.test(schema));
 const quoted=`"${schema}"`,lock=(9223372030000000000n-BigInt('0x'+randomBytes(4).toString('hex'))).toString();
 assert(lock!=='734636924058501');
 let control,a,b,intent=false,cleanupDone=false,createdOid=null,originalError=null,cleanupError=null;
 const rollback=async c=>{if(c)try{await c.query('ROLLBACK');}catch{}};
 async function configure(c){
  await c.query('BEGIN');await c.query("SET LOCAL lock_timeout='3s'");await c.query("SET LOCAL statement_timeout='8s'");
  await c.query(`SELECT set_config('fixture.authorized','yes',true),set_config('fixture.consent','yes',true),
   set_config('fixture.collection','group-a',true),set_config('fixture.owner','owner-a',true),
   set_config('collect.fence_admission_id','40000000-0000-4000-8000-000000000001',true),
   set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',repeat('f',64),true)`);
 }
 async function confirmWaiting(promise){
  const state=await Promise.race([promise.then(()=>({done:true}),error=>({done:true,error})),delay(250).then(()=>({done:false}))]);
  if(state.done)throw state.error??Error('reservation_did_not_wait_for_shared_lock');
 }
 async function cleanup(){
  if(!control)return;
  const found=(await control.query(`SELECT oid::text,pg_get_userbyid(nspowner) owner,obj_description(oid,'pg_namespace') marker
   FROM pg_namespace WHERE nspname=$1`,[schema])).rows[0];
  if(!found){cleanupDone=true;return;}
  if(!intent||found.owner!=='postgres'||found.marker!==marker||(createdOid!==null&&found.oid!==createdOid))throw Error('cleanup_identity_mismatch');
  // Every DROP uses RESTRICT. Unknown objects or outside dependencies cause a
  // rollback and leave the exact marked schema for manual review, not CASCADE.
  const currentTables=(await control.query(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname=$1 AND c.relkind IN('r','p','v','m','S','f') ORDER BY c.relname`,[schema])).rows.map(x=>x.relname);
  const currentFunctions=(await control.query(`SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname=$1 ORDER BY p.proname`,[schema])).rows.map(x=>x.proname);
  assert.deepEqual(currentTables,[...tableNames].sort());assert.deepEqual(currentFunctions,functions.map(x=>x[0]).sort());
  await control.query('BEGIN');
  try{
   await control.query("SET LOCAL lock_timeout='3s'");await control.query("SET LOCAL statement_timeout='8s'");
   await control.query(`DROP TABLE ${tableNames.map(x=>`${quoted}."${x}"`).join(',')} RESTRICT`);
   await control.query(`DROP FUNCTION ${functions.map(([n,args])=>`${quoted}."${n}"(${args})`).join(',')} RESTRICT`);
   await control.query(`DROP SCHEMA ${quoted} RESTRICT`);await control.query('COMMIT');
  }catch(error){await rollback(control);throw error;}
  cleanupDone=(await control.query('SELECT NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname=$1) AS removed',[schema])).rows[0]?.removed===true;
  if(!cleanupDone)throw Error('cleanup_readback_failed');
 }
 try{
  control=await connectTest();a=await connectTest();b=await connectTest();
  if((await control.query('SELECT 1 FROM pg_namespace WHERE nspname=$1',[schema])).rowCount)throw Error('test_schema_already_exists');
  const available=(await control.query('SELECT pg_try_advisory_lock($1::bigint) AS acquired',[lock])).rows[0]?.acquired===true;
  if(!available)throw Error('test_lock_already_held');
  if((await control.query('SELECT pg_advisory_unlock($1::bigint) AS released',[lock])).rows[0]?.released!==true)throw Error('test_lock_release_failed');
  const generated=execFileSync(process.execPath,[fileURLToPath(fixture)],{encoding:'utf8'});
  if(hash(fixture)!=='506a0dc78e55c919c6e7e4b60ade82b42fb28a20a4709b6d70d0427d55a5cbf4'||
   hash(migration)!=='ec9a1bb74603237262d66d09f71a1e49b1ac1941ca114e20700b22e8c90bf293')throw Error('reviewed_fixture_or_migration_changed');
  const cut=generated.indexOf('DO $test$');if(cut<0||!generated.startsWith('\nBEGIN;'))throw Error('fixture_setup_changed');
  let setup=generated.slice(0,cut).replaceAll('CREATE TEMP TABLE ',`CREATE TABLE ${quoted}.`)
   .replaceAll('pg_temp.',`${quoted}.`).replaceAll('9223372036854773000::bigint',`${lock}::bigint`);
  if(/(?:^|[^a-z])(private|app)\./i.test(setup)||setup.includes('734636924058501'))throw Error('production_reference_in_fixture');
  setup=setup.replace('BEGIN;',`BEGIN; SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='8s'; CREATE SCHEMA ${quoted}; COMMENT ON SCHEMA ${quoted} IS '${marker}';`);
  intent=true;await control.query(setup+'\nCOMMIT;');
  const check=(await control.query("SELECT oid::text,pg_get_userbyid(nspowner) owner,obj_description(oid,'pg_namespace') marker FROM pg_namespace WHERE nspname=$1",[schema])).rows[0];
  if(check?.owner!=='postgres'||check?.marker!==marker)throw Error('test_schema_identity_mismatch');
  createdOid=check.oid;
  // Ordinary witness commits first. A concurrent held recovery waits, then
  // must see it and reject equal-body ambiguity even at another inbox time.
  await configure(a);await configure(b);
  await a.query(`SELECT ${quoted}.collect_sms_witness_reserve('native',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,['sms/'+id(101),'1'.repeat(64),'a'.repeat(64),'2026-11-11T12:00:00Z']);
  const recovery=b.query(`SELECT ${quoted}.collect_sms_witness_reserve('recovery',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,['sms/'+id(102),'2'.repeat(64),'a'.repeat(64),'2026-11-12T12:00:00Z']);
  await confirmWaiting(recovery);await a.query('COMMIT');
  await assert.rejects(recovery,error=>error.code==='55000');await rollback(b);
  // Recovery and immutable hold commit first. A concurrent ordinary capture
  // may be retained, but the actual job trigger must park its financial work.
  await configure(a);await configure(b);
  const source=id(103),other=id(104),request='40000000-0000-4000-8000-000000000002',time='2026-11-11T12:00:00Z';
  await a.query(`INSERT INTO ${quoted}.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2::uuid,$3,$4,$5)`,[source,request,'7'.repeat(64),'8'.repeat(64),'9'.repeat(64)]);
  await a.query(`SELECT ${quoted}.collect_sms_witness_reserve('recovery',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,['sms/'+source,'7'.repeat(64),'9'.repeat(64),time]);
  await a.query(`SELECT ${quoted}.burimunsi_sms_recovery_hold($1,$2::uuid,$3,$4,$5::timestamptz)`,[source,request,'7'.repeat(64),'9'.repeat(64),time]);
  const ordinary=b.query(`SELECT ${quoted}.collect_sms_witness_reserve('native',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,['sms/'+other,'6'.repeat(64),'9'.repeat(64),time]);
  await confirmWaiting(ordinary);await a.query('COMMIT');await ordinary;
  await b.query(`INSERT INTO ${quoted}.sms_receipts(id,object_key,body_sha256) VALUES($1,$2,$3)`,[other,'sms/'+other,'9'.repeat(64)]);
  await b.query(`INSERT INTO ${quoted}.momo_processing_jobs(raw_sms_id,state) VALUES($1,'pending')`,[other]);
  const parked=(await b.query(`SELECT state,last_error FROM ${quoted}.momo_processing_jobs WHERE raw_sms_id=$1`,[other])).rows[0];
  assert.deepEqual(parked,{state:'source_unresolved',last_error:'sms_recovery_financial_hold'});await b.query('COMMIT');
  // A parsed, previously unscoped source exists BEFORE the recovery request.
  // Exercise both lock orderings at the final link and scope boundaries.
  async function seedParsed(number,body,transaction,payment){
   const raw=id(number);await control.query(`INSERT INTO ${quoted}.sms_receipts VALUES($1,$2,$3)`,[raw,'sms/'+raw,body]);
   await control.query(`INSERT INTO ${quoted}.momo_transaction_sources(raw_sms_id,transaction_id) VALUES($1,$2)`,[raw,transaction]);
   if(payment)await control.query(`INSERT INTO ${quoted}.payments VALUES($1,'group-a')`,[payment]);
  }
  async function prepareHold(c,number,body){
   const sourceId=id(number),req=id(number+1000),fingerprint='a'.repeat(64),sourceKey='b'.repeat(64);
   await c.query(`INSERT INTO ${quoted}.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
    '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2::uuid,$3,$4,$5)`,
    [sourceId,req,fingerprint,sourceKey,body]);
   await c.query(`SELECT ${quoted}.collect_sms_witness_reserve('recovery',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,
    ['sms/'+sourceId,fingerprint,body,time]);
   await c.query(`SELECT ${quoted}.burimunsi_sms_recovery_hold($1,$2::uuid,$3,$4,$5::timestamptz)`,
    [sourceId,req,fingerprint,body,time]);
  }
  await seedParsed(110,'c'.repeat(64),'pre-link','pay-c');await configure(a);await configure(b);
  await prepareHold(a,111,'c'.repeat(64));
  const lateLink=b.query(`INSERT INTO ${quoted}.momo_financial_links VALUES('pre-link','pay-c')`);
  await confirmWaiting(lateLink);await a.query('COMMIT');await assert.rejects(lateLink,e=>e.code==='55000');await rollback(b);
  await seedParsed(112,'d'.repeat(64),'link-first','pay-d');await configure(a);await configure(b);
  await b.query(`INSERT INTO ${quoted}.momo_financial_links VALUES('link-first','pay-d')`);
  const linkFirst=a.query(`SELECT ${quoted}.collect_sms_witness_reserve('recovery',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,
   ['sms/'+id(113),'e'.repeat(64),'d'.repeat(64),time]);
  await confirmWaiting(linkFirst);await b.query('COMMIT');await assert.rejects(linkFirst,e=>e.code==='55000');await rollback(a);
  await seedParsed(114,'e'.repeat(64),'pre-scope',null);await configure(a);await configure(b);
  await prepareHold(a,115,'e'.repeat(64));
  const lateScope=b.query(`INSERT INTO ${quoted}.burimunsi_transaction_scopes VALUES('pre-scope','group-a')`);
  await confirmWaiting(lateScope);await a.query('COMMIT');await assert.rejects(lateScope,e=>e.code==='55000');await rollback(b);
  await seedParsed(116,'f'.repeat(64),'scope-first',null);await configure(a);await configure(b);
  await b.query(`INSERT INTO ${quoted}.burimunsi_transaction_scopes VALUES('scope-first','group-a')`);
  const scopeFirst=a.query(`SELECT ${quoted}.collect_sms_witness_reserve('recovery',$1,'owner-a','group-a',$2,$3,$4::timestamptz,NULL)`,
   ['sms/'+id(117),'f'.repeat(64),'f'.repeat(64),time]);
  await confirmWaiting(scopeFirst);await b.query('COMMIT');await assert.rejects(scopeFirst,e=>e.code==='55000');await rollback(a);
  // Equal body in another collection is not a reason to prevent a valid link.
  await control.query(`INSERT INTO ${quoted}.payments VALUES('pay-other','group-b')`);
  await control.query(`INSERT INTO ${quoted}.momo_financial_links VALUES('pre-link','pay-other')`);
 }catch(error){originalError=error;}
 finally{
  await rollback(a);await rollback(b);await rollback(control);
  try{await cleanup();}catch(error){cleanupError=error;}
  for(const client of [a,b,control])if(client)try{await client.end();}catch{}
 }
 if(cleanupError)throw new AggregateError([originalError,cleanupError].filter(Boolean),`cleanup_failed_for_exact_test_schema:${schema}`);
 if(originalError)throw originalError;
 return {suite:'held-recovery-cloud-race',schemaRemoved:cleanupDone,productionRowsTouched:false};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(process.argv.length!==3||process.argv[2]!=='--execute')throw Error('review_and_explicit_execute_required');
 runHeldRecoveryRace().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1;});
}
