// Refusal/containment and typed receipt projection only. No real pg, Deno, network or accepted native
// witness is exercised by this file. Run it with the maintained Node24 caller.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile,mkdtemp,mkdir,writeFile,chmod,realpath,access} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {REVIEWED_INPUT_ROLES,verifyLocalConnection,cleanChildEnvironment,validateChildReceipt,projectRealtimeFailure} from './qualify-member-realtime-native.mjs';
import {ROOT_SQL11_SHA256,ROOT_SQL12_SHA256,MIGRATION_ELEVEN_ROLE,MIGRATION_TWELVE_ROLE,EXACT_CURRENT11,EXACT_CURRENT12,EXACT_TEN} from './curated-platform-fixture.mjs';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const caller=join(root,'scripts/supabase/testing/qualify-member-realtime-native.mjs');
const local='postgres://collect_test:synthetic-test-only@127.0.0.1:55443/postgres';
function environment(delta={}){
 return {PATH:process.env.PATH,HOME:process.env.HOME,TMPDIR:process.env.TMPDIR,
  COLLECT_CI_SYNTHETIC:'true',COLLECT_DENO:'/not-a-real-qualification-binary/deno',
  COLLECT_PG_MODULE:'/not-a-real-qualification-driver/pg',
  COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL:local,...delta};
}
function refused({env=environment(),args=[],script=caller,code}){
 const result=spawnSync(process.execPath,[script,...args],{env,shell:false,encoding:'utf8',timeout:15000,maxBuffer:32768});
 assert.equal(result.status,1);assert.equal(result.signal,null);assert.equal(result.stdout,'');
 const receipt=JSON.parse(result.stderr);
 assert.equal(receipt.status,'UNCONFIRMED');assert.equal(receipt.code,code);
 assert.deepEqual(receipt.cases,[]);assert.equal(receipt.reset_or_drop,false);assert.equal(receipt.automatic_retry,false);
 assert(!result.stderr.includes('synthetic-test-only'));assert(!result.stderr.includes('postgres://'));
 return receipt;
}

const invalidTargets=[
 ['hosted','postgres://collect_test:synthetic-test-only@db.rrlduytparvsjfmegalh.supabase.co:5432/postgres'],
 ['localhost','postgres://collect_test:synthetic-test-only@localhost:55443/postgres'],
 ['IPv6','postgres://collect_test:synthetic-test-only@[::1]:55443/postgres'],
 ['wrong user','postgres://postgres:synthetic-test-only@127.0.0.1:55443/postgres'],
 ['encoded user','postgres://%63ollect_test:synthetic-test-only@127.0.0.1:55443/postgres'],
 ['wrong database',local.replace('/postgres','/collect_existing_test')],
 ['normalized path',local.replace('/postgres','/old/../postgres')],
 ['missing port','postgres://collect_test:synthetic-test-only@127.0.0.1/postgres'],
 ['zero port',local.replace(':55443/',':0/')],
 ['leading-zero port',local.replace(':55443/',':055443/')],
 ['overflow port',local.replace(':55443/',':65536/')],
 ['missing password','postgres://collect_test@127.0.0.1:55443/postgres'],
 ['query',local+'?sslmode=require'],['hash',local+'#ignored'],
 ['control password',local.replace('synthetic-test-only','bad%0Avalue')],
 ['alternate protocol',local.replace('postgres:','https:')],
];
for(const[label,target]of invalidTargets)test('CLI refuses '+label+' before source/driver/connection work',()=>{
 const receipt=refused({env:environment({COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL:target}),code:'EXACT_LOCAL_ADMIN_URL_REQUIRED'});
 assert.equal(receipt.output_directory,null);assert.equal(receipt.stage,'preflight');
});
for(const value of[undefined,'false','TRUE','1'])test('CLI requires explicit synthetic flag '+String(value),()=>{
 const env=environment();if(value===undefined)delete env.COLLECT_CI_SYNTHETIC;else env.COLLECT_CI_SYNTHETIC=value;
 refused({env,code:'EXPLICIT_SYNTHETIC_CI_REQUIRED'});
});
test('CLI refuses credential/source arguments before any local preparation',()=>{
 refused({args:['--database',local],code:'NO_ARGUMENTS_ALLOWED'});
});
for(const value of[undefined,'deno','/tmp/../deno'])test('CLI requires explicit normalized absolute Deno '+String(value),()=>{
 const env=environment();if(value===undefined)delete env.COLLECT_DENO;else env.COLLECT_DENO=value;
 refused({env,code:'EXPLICIT_PHYSICAL_DENO_REQUIRED'});
});

test('missing Deno config stops actual CLI before version dispatch or pg loading',async()=>{
 // Copy only the bounded reviewed inputs, deliberately omitting deno.json.
 // The sentinel executable would leave a marker if accidentally dispatched.
 // No full application copy, pg installation or child Deno runtime is involved.
 const scratch=await realpath(await mkdtemp(join(tmpdir(),'collect-rt-refusal-')));await chmod(scratch,0o700);
 const tree=join(scratch,'source');await mkdir(tree,{mode:0o700});
 for(const role of [...REVIEWED_INPUT_ROLES,'scripts/supabase/testing/qualify-member-realtime-native.mjs']){
  if(role==='supabase/functions/deno.json')continue;
  const path=join(tree,role);await mkdir(dirname(path),{recursive:true,mode:0o700});
  await writeFile(path,await readFile(join(root,role)),{flag:'wx',mode:0o600});
 }
 const marker=join(scratch,'must-not-run');const binary=join(scratch,'deno');
 await writeFile(binary,'#!/bin/sh\n: > "'+marker+'"\nexit 19\n',{flag:'wx',mode:0o700});
 const receipt=refused({script:join(tree,'scripts/supabase/testing/qualify-member-realtime-native.mjs'),env:environment({COLLECT_DENO:binary}),code:'SOURCE_INPUT_UNAVAILABLE'});
 assert.equal(receipt.stage,'preflight');await assert.rejects(access(marker));
 assert.deepEqual(receipt.cases,[]);
 // Retain the private refusal tree and fixed receipt for owner inspection.
 await writeFile(join(scratch,'REFUSAL.json'),JSON.stringify(receipt,null,2)+'\n',{flag:'wx',mode:0o600});
});

const identity={database:'postgres',address:'127.0.0.1',port:55443,version:'170011',
 default_isolation:'read committed',isolation:'read committed',current_role:'collect_test',
 session_role:'collect_test',superuser:true,bypass:true,owner:'collect_test'};
for(const[key,value]of[
 ['database','collect_existing_test'],['address','::1'],['port',5432],['version','180001'],
 ['default_isolation','repeatable read'],['isolation','repeatable read'],
 ['current_role','postgres'],['session_role','postgres'],['superuser',false],['bypass',false],['owner','postgres'],
])test('observed '+key+' mismatch cannot reach a subsequent CREATE/setup action',async()=>{
 const database=key==='owner'?'collect_fence_runtime_'+'1'.repeat(24)+'_test':'postgres';
 const calls=[];const client={async connect(){calls.push('connect');},async query(sql){calls.push(sql);return{rows:[{...identity,database,[key]:value}]};}};
 await assert.rejects(async()=>{
  await verifyLocalConnection(client,{target:new URL(local),database,parity:async()=>{calls.push('parity');}});
  // This continuation stands for the production CREATE/setup boundary. The
  // genuine guard must reject before it; this is not a successful DB fixture.
  calls.push('CREATE DATABASE must_not_dispatch');
 },error=>error.qualificationCode==='EXACT_LOCAL_PG17_OWNER_IDENTITY_REQUIRED');
 assert.equal(calls.filter(item=>item==='connect').length,1);
 assert.equal(calls.filter(item=>item.startsWith('SELECT ')).length,1);
 assert(!calls.some(item=>/CREATE DATABASE|collect_fence_initialize/.test(item)));
});
test('source drift refuses before connecting even to a supplied local client',async()=>{
 let connected=false;
 await assert.rejects(verifyLocalConnection({async connect(){connected=true;}},{target:new URL(local),database:'postgres',parity:async()=>{throw Error('synthetic source drift');}}));
 assert.equal(connected,false);
});
test('child environment drops ambient credentials, loaders, proxies and PG options',()=>{
 const env=cleanChildEnvironment({PATH:'/synthetic/bin',HOME:'/synthetic/home',NODE_OPTIONS:'secret',NODE_PATH:'secret',PGPASSWORD:'secret',PGHOST:'remote',PGOPTIONS:'secret',SUPABASE_ACCESS_TOKEN:'secret',HTTPS_PROXY:'secret',COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL:'secret',COLLECT_NOTICE_SMTP_PASSWORD:'secret'},
  {pgEntry:'/synthetic/pg/index.js',fixtureVariable:'COLLECT_MEMBER_REALTIME_SQL_TEST_DATABASE_URL',fixtureUrl:local.replace('/postgres','/collect_member_realtime_'+'1'.repeat(24)+'_test')});
 assert.deepEqual(Object.keys(env).sort(),['COLLECT_CI_SYNTHETIC','COLLECT_MEMBER_REALTIME_SQL_TEST_DATABASE_URL','COLLECT_PG_MODULE','HOME','PATH']);
 assert(!JSON.stringify(env).includes('secret'));assert.equal(env.COLLECT_CI_SYNTHETIC,'true');
});
for(const delta of[{full_matrix_qualified:true},{sb22Satisfied:true},{managed_project_writes:1},{provider_calls:1},{subset:false},{fixture:'new_unique_loopback_actual_runtime_sql10'},{hosted_delivery_accepted:true}])test('Realtime overclaim/drift is refused '+Object.keys(delta)[0],()=>{
 const typed={status:'PASS',checks:80,fixture:'new_unique_loopback_realtime_interface_only',subset:true,full_matrix_qualified:false,provider_calls:0,managed_project_writes:0,hosted_delivery_accepted:false,whole_system_acceptance:false,sb22Satisfied:false,...delta};
 assert.throws(()=>validateChildReceipt('realtime',typed,{binding:{},closureSha256:''}));
});

// Root follow-through: only closed diagnostic metadata may leave a failed native child.
const safeFailure={status:'UNCONFIRMED',fixture:'new_unique_loopback_realtime_interface_only',stage:'actor_admin_mfa_projection',code:'SQLSTATE_23503'};
test('failed native child exposes only the exact approved diagnostic fields',()=>{
 const result=projectRealtimeFailure('realtime',Buffer.from(JSON.stringify(safeFailure)));
 assert.deepEqual(result,safeFailure);assert.notEqual(result,safeFailure);
 assert.deepEqual(Object.keys(result).sort(),['code','fixture','stage','status']);
});
test('raw errors, mixed documents, private fields and invalid encoding are discarded',()=>{
 const raw=[Buffer.from('driver error: PRIVATE_TEST_DETAIL'),Buffer.from(JSON.stringify(safeFailure)+'\n'+JSON.stringify(safeFailure)),Buffer.from(JSON.stringify({...safeFailure,message:'PRIVATE_TEST_DETAIL'})),Buffer.from([255]),Buffer.alloc(65537,32)];
 for(const bytes of raw)assert.equal(projectRealtimeFailure('realtime',bytes),null);
});
test('diagnostics cannot cross witness boundaries or claim successful acceptance',()=>{
 assert.equal(projectRealtimeFailure('runtime',Buffer.from(JSON.stringify(safeFailure))),null);
 for(const delta of[{status:'PASS'},{fixture:'new_unique_loopback_actual_runtime_sql10'},{stage:'PRIVATE_TEST_DETAIL'},{code:'PRIVATE_TEST_DETAIL'}])assert.equal(projectRealtimeFailure('realtime',Buffer.from(JSON.stringify({...safeFailure,...delta}))),null);
});

// This validates the maintained parent's strict projection, not an accepted
// runtime journey. Root must separately execute the actual native child.
const runtimeBinding={hosted_sql_sha256:'ebfd0389e6ba3aa5fe1595f854b25c69b9b31a0500f202b8e0643209ab0ef6e4',synthetic_sql_sha256:'f27233a124b3b737f469915aa4eade6a4149272cfea2f6a15b6060389eefcf20'};
const runtimeClosure='c'.repeat(64);
const runtimeReceipt=()=>({status:'PASS',checks:299,fixture:'new_unique_loopback_actual_runtime_sql11',migration_count:11,sql11_sha256:ROOT_SQL11_SHA256,source_sha256:'a'.repeat(64),source_closure_sha256:runtimeClosure,sql10_sha256:runtimeBinding.hosted_sql_sha256,synthetic_sql10_sha256:runtimeBinding.synthetic_sql_sha256,sql9_sha256:'714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497',actual_smtp_timeout:true,synthetic_raw_send_calls:1,provider_calls:0,external_fetch_calls:0,app_tables_unchanged_outside_exact_owned_rows:97,original_unknown_receipt_sha256:'d'.repeat(64),original_unknown_receipt_preserved:true,durable_settled_unknown:1,retained_unknown_obligations:1,held_work_prevented_drain:true,final_mode:'fenced',applicationFenceComplete:true,preserve_database:true,automatic_replay:false,hosted_capacity_accepted:false,providerSettlement:false,wholeSystemAcceptance:false,managedInternalWritesFenced:false,humanMessagesFenced:false,atomicRecoverySnapshot:false,sb29Satisfied:false});
test('typed current11 runtime receipt requires explicit successor identity and retains original97-table scope',()=>{
 assert.match(ROOT_SQL11_SHA256,/^[a-f0-9]{64}$/,'Root must render the independently supplied SQL11 pin');
 assert.equal(EXACT_CURRENT11.length,11);assert.deepEqual(EXACT_CURRENT11.slice(0,10),EXACT_TEN);assert(REVIEWED_INPUT_ROLES.includes(MIGRATION_ELEVEN_ROLE));
 const value=validateChildReceipt('runtime',runtimeReceipt(),{binding:runtimeBinding,closureSha256:runtimeClosure});
 assert.equal(value.migration_count,11);assert.equal(value.sql11_sha256,ROOT_SQL11_SHA256);assert.equal(value.app_tables_unchanged_outside_exact_owned_rows,97);assert.equal(value.sb29Satisfied,false);
});
test('native SQL11 qualification admits the pinned SQL12 source while retaining its historical eleven-migration runtime witness',()=>{
 assert.equal(EXACT_CURRENT11.length,11);assert.equal(EXACT_CURRENT12.length,12);assert.deepEqual(EXACT_CURRENT12.slice(0,11),EXACT_CURRENT11);
 assert.equal(EXACT_CURRENT12[11],'20261023072038_collect_admin_initial_email_proof_ack.sql');
 assert(REVIEWED_INPUT_ROLES.includes(MIGRATION_TWELVE_ROLE));assert.match(ROOT_SQL12_SHA256,/^[a-f0-9]{64}$/);
 assert.equal(ROOT_SQL11_SHA256,'02c93209f546880032cf38382c61e78a3de0b0073dd2cb88699319afc6f0f185');
});
for(const delta of [{fixture:'new_unique_loopback_actual_runtime_sql10'},{migration_count:10},{sql11_sha256:'0'.repeat(64)},{sql11_sha256:undefined},{source_closure_sha256:'0'.repeat(64)},{app_tables_unchanged_outside_exact_owned_rows:118},{sb29Satisfied:true}])test('old/inexact runtime identity remains refused: '+Object.keys(delta)[0],()=>{
 assert.throws(()=>validateChildReceipt('runtime',{...runtimeReceipt(),...delta},{binding:runtimeBinding,closureSha256:runtimeClosure}));
});
test('new runtime label still cannot be projected as Realtime delivery evidence',()=>{
 assert.throws(()=>validateChildReceipt('realtime',runtimeReceipt(),{binding:runtimeBinding,closureSha256:runtimeClosure}));
 assert.equal(projectRealtimeFailure('realtime',Buffer.from(JSON.stringify({...safeFailure,fixture:'new_unique_loopback_actual_runtime_sql11'}))),null);
});
