import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,writeFile,mkdtemp,mkdir,realpath,rm,lstat,readdir,readlink} from 'node:fs/promises';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {prepareAtomicD1Restore,verifyAtomicPackage,verifyAtomicReadback} from '../cloudflare/atomic_d1_restore.mjs';
import {seal,unseal,installSql,restoreSql,main as backupMain,validatePayload} from '../cloudflare/platform_backup.mjs';
import {recoveryQuarantinePlan,applyRecoveryQuarantine,validateRecoveryQuarantinePlan,quarantineSchemaProfiles,assistedSmsRecoveryTables,momoRecoveryTables} from '../cloudflare/recovery_quarantine.mjs';
import {captureD1,controls,dataKeys,sourceId,sha,database} from '../../deploy/platform-api/test/support/recovery12_fixture.mjs';
import {current15Fixture} from '../../deploy/platform-api/test/support/recovery15_fixture.mjs';
import {fixture as shippingFixture} from '../../deploy/platform-api/test/support/notification_operator_integration_fixture.mjs';
import {decrypt} from '../../deploy/platform-api/src/encryption.js';
import {assistedSmsDestinationContext} from '../../deploy/platform-api/src/notification_operator.js';
const projectRequire=createRequire(new URL('../../deploy/platform-api/package.json',import.meta.url));
const canonical=value=>JSON.stringify(value,(_,v)=>typeof v==='bigint'?v.toString():v);
const rowSetWhere=async(db,table,key,value)=>(await db.prepare('SELECT * FROM \"'+table+'\" WHERE '+key+'=?').bind(value).all()).results.map(canonical).sort();
const rowSet=async(db,name)=>(await db.prepare('SELECT * FROM "'+name+'"').all()).results.map(canonical).sort();
async function runtimeFixture(dir){
 const module=process.env.COLLECT_WRANGLER_MODULE??projectRequire.resolve('wrangler');let folder=dirname(createRequire(import.meta.url).resolve(module));
 while(JSON.parse(await readFile(join(folder,'package.json')).catch(()=>Buffer.from('{}'))).name!=='wrangler'){const next=dirname(folder);assert.notEqual(next,folder);folder=next;}
 const root=dirname(dirname(folder)),records={node:{sha256:sha(await readFile(process.execPath)),bytes:(await lstat(process.execPath)).size}};
 async function walk(path,prefix){for(const e of await readdir(path,{withFileTypes:true})){const p=join(path,e.name),name=prefix+'/'+e.name;if(e.isDirectory())await walk(p,name);else if(e.isSymbolicLink())records[name]={symlink:await readlink(p)};else{const raw=await readFile(p);records[name]={sha256:sha(raw),bytes:raw.length};}}}
 await walk(join(root,'node_modules'),'node_modules');const raw=Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(records).sort()))),path=join(dir,'runtime.json');await writeFile(path,raw,{mode:0o600});return {node_path:process.execPath,dependency_root:root,manifest_path:path,manifest_sha256:sha(raw)};
}
const wrapper=`import worker from './worker.js';export default {async fetch(request,env){const r=await worker.fetch(request,env);if(request.headers.get('x-test-lost-ack')==='true'&&r.status===200)return Response.json({code:'controlled_unknown_after_actual_action'},{status:503});return r;}};`;

test('distinct current15 synthetic archive and exact canonical adapter preserve SMS, decision heads and91-task controls through real D1 restore/quarantine',async t=>{
 const c=await current15Fixture(t),external=process.env.COLLECT_RECOVERY15_EVIDENCE_DIR;
 const dir=external?await realpath(await mkdir(external,{mode:0o700}).then(()=>external)):await realpath(await mkdtemp(join(tmpdir(),'collect-recovery15-')));
 if(!external)t.after(()=>rm(dir,{recursive:true,force:true}));
 const names=[];async function check(name,fn){await t.test(name,fn);names.push(name);}
 // Exercise the actual archive CLI for this exact15 cohort, preserving every
 // synthetic role byte. Its capture time is a new offline capture, not a claim
 // about any hosted source or provider-approved state.
 const inputs=join(dir,'inputs');await mkdir(join(inputs,'migrations'),{recursive:true,mode:0o700});
 for(const [name,record]of Object.entries(c.payload.files))await writeFile(join(inputs,name),Buffer.from(record.base64,'base64'),{mode:0o600});
 const sealed=join(dir,'sealed');await backupMain(['seal','--sql',join(inputs,'database.sql'),'--config',join(inputs,'wrangler.json'),'--secrets',join(inputs,'worker-secrets.json'),'--out',sealed]);
 const archive=join(sealed,'platform-backup.json'),keyPath=join(sealed,'recovery-key.base64'),restore=join(dir,'restore.sql'),key=Buffer.from((await readFile(keyPath,'utf8')).trim(),'base64'),captured=unseal(JSON.parse(await readFile(archive)),key);key.fill(0);assert.deepEqual(captured.files,c.payload.files);await writeFile(restore,c.sql,{mode:0o600});c.recoveryAt=new Date(Math.ceil(Date.now()/1000)*1000).toISOString();
 const common=['--archive',archive,'--key',keyPath];await backupMain(['prepare-quarantine',...common,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(dir,'quarantine')]);
 const preparedRecord=JSON.parse(await readFile(join(dir,'quarantine/preparation.json'))),runtime=await runtimeFixture(dir),packagePath=join(dir,'package');
 const prepared=await prepareAtomicD1Restore({archive_path:archive,key_path:keyPath,qualified_restore_sql_path:restore,qualified_quarantine_plan_path:join(dir,'quarantine/quarantine-plan.json'),target:{account_id:'2209b915a85b1c11cee79b7806c6e73b',database_name:'collect-synthetic-current15-local',database_id:randomUUID()},runtime},packagePath),{plan}=await verifyAtomicPackage(packagePath,prepared.manifest_sha256);
 const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??projectRequire.resolve('miniflare')),{build}=await import(process.env.COLLECT_ESBUILD_MODULE??projectRequire.resolve('esbuild'));
 await writeFile(join(packagePath,'test-entry.js'),wrapper,{mode:0o600});const script=(await build({entryPoints:[join(packagePath,'test-entry.js')],bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent'})).outputFiles[0].text;
 let networkCalls=0;const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script,compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,bindings:{CAPTURE_TOKEN:'SYNTHETIC_CURRENT15_LOOPBACK_TOKEN_ONLY_1234567890',TARGET_DATABASE_ID:plan.target.database_id,SOURCE_ID:sourceId,PLAN_SHA256:prepared.plan_sha256},outboundService:async()=>{networkCalls++;throw Error('No provider transport allowed');}}));t.after(()=>mf.dispose());const db=await mf.getD1Database('DB');let checkpoint;
 async function call(name,body,headers={}){const r=await mf.dispatchFetch('http://127.0.0.1:8998/'+name,{method:'POST',headers:{Authorization:'Bearer SYNTHETIC_CURRENT15_LOOPBACK_TOKEN_ONLY_1234567890','Content-Type':'application/json',...headers},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
 const read=async()=>{const r=await call('readback',{plan_sha256:prepared.plan_sha256});assert.equal(r.status,200,JSON.stringify(r.body));checkpoint=r.body.sha256;return r.body;};
 const body=name=>({plan_sha256:prepared.plan_sha256,action_sha256:plan.actions[name].statements_sha256,checkpoint_sha256:checkpoint??'0'.repeat(64)});
 const verify=async(stage,name)=>{const sql=await captureD1(db),path=join(dir,name+'.sql');await writeFile(path,sql,{mode:0o600});await verifyAtomicReadback({directory:packagePath,manifest_sha256:prepared.manifest_sha256,archive_path:archive,key_path:keyPath,sql_path:path,stage,out_directory:join(dir,name+'-verified')});return sql;};
 await check('15 is exact with all13 MoMo/history tables plus assisted SMS and retention controls populated',async()=>{
  assert.equal(plan.schema_profile,'candidate15');assert.equal(plan.quarantine_plan.format,'collect.platform.recovery-quarantine.v5');assert.equal(Object.keys(quarantineSchemaProfiles.candidate15.digests).length,15);assert.equal(c.counts.privacy_retention_tasks,91);
  for(const name of [...controls,...assistedSmsRecoveryTables,...momoRecoveryTables])assert.ok(c.counts[name]>0,name);
  assert.equal(preparedRecord.assisted_sms_history_retained,true);assert.equal(preparedRecord.decision_receipt_heads_preserved,true);assert.equal(preparedRecord.assisted_sms_send_authority_restored,false);
  assert.equal(preparedRecord.momo_history_retained,true);assert.equal(preparedRecord.momo_gateway_authority_restored,false);assert.equal(preparedRecord.momo_processing_budgets_retained,true);
  assert.equal(plan.archive.source_provenance.actual_provider_source_database_id,null);assert.equal(plan.archive.source_provenance.never_primary_capture,true);assert.equal(plan.full_system_recovery_accepted,false);
 });
 await check('exact15 admits configured identity recovery and optional strict retention pin without provisioning authority',async()=>{
  assert.ok(validatePayload(c.payload));const role='PRIVACY_RETENTION_APPROVAL_SHA256',replace=(p,name,value)=>{const raw=Buffer.from(JSON.stringify(value));p.files[name]={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};},keys=JSON.parse(Buffer.from(c.payload.files['worker-secrets.json'].base64,'base64'));
  const admitted=structuredClone(c.payload);replace(admitted,'worker-secrets.json',{...keys,[role]:'a'.repeat(64)});assert.ok(validatePayload(admitted));
  for(const changes of [{...keys,[role]:'A'.repeat(64)},{...keys,UNREVIEWED_RECOVERY_ROLE:'synthetic-only-value'},{...keys,AUTH_IDENTITY_HASH_KEY:'not-a-base64-key'}]){const bad=structuredClone(c.payload);replace(bad,'worker-secrets.json',changes);assert.throws(()=>validatePayload(bad),/retention approval|worker key recovery|Identity-key recovery/);}
  const publicPin=structuredClone(c.payload),config=JSON.parse(Buffer.from(publicPin.files['wrangler.json'].base64,'base64'));config.vars[role]='a'.repeat(64);replace(publicPin,'wrangler.json',config);assert.throws(()=>validatePayload(publicPin),/separately authorized Worker secret/);
 });
 await check('actual empty D1 restore has an unknown response and must read back before any replay',async()=>{
  assert.equal((await read()).state,'empty');const unknown=await call('restore',body('restore'),{'x-test-lost-ack':'true'});assert.equal(unknown.status,503);assert.equal((await call('restore',body('restore'))).body.code,'already_attempted_readback_required');assert.equal((await read()).state,'restored');assert.equal(await verify('restored','restored'),c.sql);
 });
 const momoMutable=['momo_gateway_bindings','momo_gateway_credentials','momo_gateway_pairings','momo_processing_jobs','momo_processing_guards'];
 const immutable={};for(const name of [...momoRecoveryTables.filter(name=>!momoMutable.includes(name)),...assistedSmsRecoveryTables,'request_receipts','admin_account_role_capabilities','ledger_entries','payment_evidence','auth_identity_rate_aliases',...controls.filter(n=>n!=='privacy_retention_guards')])immutable[name]=await rowSet(db,name);
 await check('whole current15 late CHECK rolls back every schema row, control, SMS record, head and sequence',async()=>{
  const before=await captureD1(db),r=await call('late_failure',body('late_failure'));assert.equal(r.status,422);assert.equal(r.body.expected_late_CHECK,true);assert.equal((await read()).state,'restored');assert.equal(await verify('restored','late-failure'),before);
 });
 await check('canonical quarantine lost reply requires exact readback and immutable original-session SMS history is retained',async()=>{
  assert.equal((await call('quarantine',body('quarantine'),{'x-test-lost-ack':'true'})).status,503);assert.equal((await call('quarantine',body('quarantine'))).body.code,'already_attempted_readback_required');assert.equal((await read()).state,'quarantined');await verify('quarantined','quarantined');
  for(const [name,rows]of Object.entries(immutable))assert.deepEqual(await rowSet(db,name),rows,name);
  assert.equal((await db.prepare('SELECT count(*) AS n FROM privacy_retention_guards').first()).n,0);assert.equal((await db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE revoked_at IS NULL').first()).n,0);assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);
 });
 await check('same-operation replay preserves exact rows, balances, no-op decision heads, barriers and all retained history/control classes',async()=>{
  const before=await captureD1(db);assert.equal((await call('replay',body('replay'))).status,200);assert.equal((await read()).state,'quarantined');assert.equal(await verify('quarantined','replayed'),before);
  assert.equal((await db.prepare("SELECT count(*) AS n FROM request_receipts WHERE user_id=? AND operation='assisted_sms.consent.set'").bind(c.recipient).first()).n,2);assert.equal((await db.prepare("SELECT count(*) AS n FROM request_receipts WHERE user_id=? AND operation='assisted_sms.access.set'").bind(c.account.userId).first()).n,1);assert.equal((await db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,2500);
  await assert.rejects(db.prepare("UPDATE users SET access_status='active' WHERE id=?").bind(c.subject).run(),/privacy_retention_access_quarantined/);await assert.rejects(db.prepare("DELETE FROM request_receipts WHERE operation='assisted_sms.consent.set'").run(),/retain_request_receipt/);
 });
 await check('MoMo authorities/leases are quarantined without changing budgets, profiles or retained review history',async()=>{
  for(const table of ['momo_gateway_bindings','momo_gateway_credentials','momo_gateway_pairings']){const predicate=table==='momo_gateway_bindings'?"status='active'":table==='momo_gateway_credentials'?'revoked_at IS NULL':'expires_at>0';assert.equal((await db.prepare('SELECT count(*) AS n FROM '+table+' WHERE '+predicate).first()).n,0);}
  assert.equal((await db.prepare('SELECT count(*) AS n FROM momo_processing_guards').first()).n,0);
  for(const state of ['pending','retry','processing','resolved']){const before=await c.f.db.prepare('SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?').bind(c.momo.jobs[state]).first(),after=await db.prepare('SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?').bind(c.momo.jobs[state]).first();assert.equal(after.state,'needs_review');assert.equal(after.lease_token,null);assert.equal(after.lease_until,null);assert.equal(after.last_error,'disaster_recovery_quarantine');assert.equal(after.attempt_count,before.attempt_count);assert.equal(after.max_attempts,before.max_attempts);assert.equal(after.available_at,before.available_at);}
  for(const state of ['completed','duplicate','conflict','needs_review','source_unresolved'])assert.deepEqual(await rowSetWhere(db,'momo_processing_jobs','raw_sms_id',c.momo.jobs[state]),await rowSetWhere(c.f.db,'momo_processing_jobs','raw_sms_id',c.momo.jobs[state]));
  for(const table of ['momo_gateway_bindings','momo_gateway_credentials']){const key=table==='momo_gateway_bindings'?'id':'binding_id';assert.deepEqual(await rowSetWhere(db,table,key,c.momo.revoked.binding.binding_id),await rowSetWhere(c.f.db,table,key,c.momo.revoked.binding.binding_id));}
 });
 await check('direct core replay retains newly reapproved MoMo authority/new jobs; conflicting operation reuse rolls back atomically',async()=>{
  const copy=new DatabaseSync(':memory:');try{copy.exec('BEGIN;PRAGMA defer_foreign_keys=ON');installSql(copy,await captureD1(db));copy.exec('COMMIT');const q=plan.quarantine_plan;
   const old=recoveryQuarantinePlan({archiveSha256:q.archive_sha256,sourceId:q.source_id,operationId:q.operation_id,createdAt:q.created_at,schemaProfile:'candidate13'});assert.throws(()=>applyRecoveryQuarantine(copy,old),/restored control schema/);
   const binding=c.momo.gateway.binding.binding_id,rawId=c.momo.jobs.pending;
   copy.prepare("UPDATE momo_gateway_bindings SET status='active',revoked_at=NULL WHERE id=?").run(binding);copy.prepare('UPDATE momo_gateway_credentials SET revoked_at=NULL WHERE binding_id=?').run(binding);copy.prepare('UPDATE momo_gateway_pairings SET expires_at=2000000000 WHERE binding_id=?').run(binding);copy.prepare("UPDATE momo_processing_jobs SET state='pending',last_error=NULL WHERE raw_sms_id=?").run(rawId);copy.prepare("INSERT INTO momo_processing_guards(id,passed) VALUES('reapproved-transient',1)").run();
   const newRaw={...copy.prepare('SELECT * FROM sms_receipts WHERE id=?').get(c.momo.jobs.completed),id:randomUUID(),client_envelope_id:randomUUID(),object_key:'synthetic-reapproved/'+randomUUID()};copy.prepare('INSERT INTO sms_receipts('+Object.keys(newRaw).join(',')+') VALUES('+Object.keys(newRaw).map(()=>'?').join(',')+')').run(...Object.values(newRaw));copy.prepare("INSERT INTO momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at) VALUES(?,?,1,?,'live','pending',2000000000,?,?)").run(newRaw.id,binding,c.momo.accountId,q.created_at,q.created_at);
   const before=restoreSql(copy);applyRecoveryQuarantine(copy,q);assert.equal(restoreSql(copy),before);
   for(const change of [{archive_sha256:'b'.repeat(64)},{source_id:'e'.repeat(64)},{created_at:new Date(Date.parse(q.created_at)+1000).toISOString()}]){const altered=recoveryQuarantinePlan({archiveSha256:change.archive_sha256??q.archive_sha256,sourceId:change.source_id??q.source_id,operationId:q.operation_id,createdAt:change.created_at??q.created_at,schemaProfile:'candidate15'});assert.throws(()=>applyRecoveryQuarantine(copy,altered),/CHECK constraint failed/);assert.equal(restoreSql(copy),before);}
   const controlsFound=copy.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND (name GLOB 'privacy_retention_*' OR name='auth_identity_rate_aliases' OR name GLOB 'assisted_sms_*' OR name GLOB 'momo_*' OR name='contribution_posting_snapshots')").all().map(row=>row.name);assert.throws(()=>validateRecoveryQuarantinePlan({...q,statements:q.statements.slice(1)},controlsFound),/differs from/);
  }finally{copy.close();}
 });
 await check('decrypted restored SMS values match exact application contexts without reissuing a send permit',async()=>{
  const rows=(await db.prepare('SELECT * FROM assisted_sms_jobs ORDER BY id').all()).results;
  for(const row of rows){const text=new TextDecoder().decode(await decrypt(dataKeys,row.body_ciphertext,`assisted-sms-body:${row.id}:${row.payment_id}:${row.entry_id}`));assert.equal(sha(text),row.body_sha256);const phone=await decrypt(dataKeys,row.destination_ciphertext,assistedSmsDestinationContext(row.collection_id,row.recipient_user_id,row.destination_revision));assert.equal(sha(phone),row.destination_sha256);}
  const starts=(await db.prepare("SELECT response_json FROM request_receipts WHERE operation='assisted_sms.send_start'").all()).results;assert.equal(starts.length,1);for(const row of starts)assert.notEqual(JSON.parse(row.response_json).may_send,true);
 });
 await check('shipping API consumers of exact quarantined readback deny old cookies/consent and never continue original confirmations',async()=>{
  const current=await shippingFixture(t,{BUILD_SOURCE_ID:sourceId},{migrationsThrough:0}),{unstable_splitSqlQuery}=createRequire(import.meta.url)(process.env.COLLECT_WRANGLER_MODULE??projectRequire.resolve('wrangler'));
  const sql=await captureD1(db);await current.db.batch([current.db.prepare('PRAGMA defer_foreign_keys=ON'),...unstable_splitSqlQuery(sql).map(q=>current.db.prepare(q))]);assert.equal(await captureD1(current.db),sql);
  for(const action of ['get_claimed','record_send_start']){const result=await current.call('/api/admin/notification-operator',{cookie:c.operator.cookie,headers:{'X-Collect-Admin':'1'},data:{action,...(action==='get_claimed'?c.jobs[1].fields:c.jobs[1].startBody)}});assert.equal(result.status,401);assert.equal(result.body.result,undefined);}
  const metadata=await current.call('/api/admin/sms/receipts',{method:'GET',cookie:c.operator.cookie});assert.equal(metadata.status,401);assert.equal(metadata.body.rows,undefined);
  const consent=await current.call('/v1/rpc/get_assisted_sms_consent_v1',{origin:'https://collect.example',headers:{Authorization:'Bearer '+c.phone.access_token},data:{p_collection_id:c.smsGroup}});assert.equal(consent.status,401);assert.equal(await captureD1(current.db),sql);
 });
 await check('current15 refuses partial14/future16/changed15 migrations and exact provider-prefix/SQL drift',async()=>{
  const variants=[['changed15',p=>{const name='migrations/0015_momo_gateway_allocation.sql',raw=Buffer.concat([Buffer.from(p.files[name].base64,'base64'),Buffer.from('\n-- changed')]);p.files[name]={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};}],['partial14',p=>{delete p.files['migrations/0015_momo_gateway_allocation.sql'];}],['future16',p=>{const raw=Buffer.from('CREATE TABLE future_authority(id TEXT);');p.files['migrations/0016_unreviewed.sql']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};}]];
  for(const [name,change]of variants){const p=structuredClone(c.payload);change(p);assert.throws(()=>validatePayload(p));
   // Identity keys are optional for generic historical captures. Their absence
   // must not turn an unknown schema into a qualified quarantine profile.
   const config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64')),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));delete config.vars.AUTH_IDENTITY_KEY_ID;delete keys.AUTH_IDENTITY_HASH_KEY;delete keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON;
   for(const [role,value]of Object.entries({'wrangler.json':config,'worker-secrets.json':keys})){const raw=Buffer.from(JSON.stringify(value));p.files[role]={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};}
   assert.ok(validatePayload(p));const path=join(dir,'unconfigured-'+name+'.json');await writeFile(path,JSON.stringify(seal(p,Buffer.from((await readFile(keyPath,'utf8')).trim(),'base64'))),{mode:0o600});await assert.rejects(backupMain(['prepare-quarantine','--archive',path,'--key',keyPath,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(dir,'unconfigured-'+name)]),/qualified schema profile/);
  }
  for(const [name,suffix]of [['unknown-prefix','CREATE TABLE _cf_unreviewed(id TEXT,authority TEXT);'],['ordinary-sqlite-name','CREATE TABLE sqliteevil_copy(id TEXT,authority TEXT);'],['missing-metadata-index','DROP INDEX sms_receipts_metadata_order;'],['new-copy','CREATE TABLE momo_unreviewed_copy(id TEXT,token TEXT);'],['trigger','DROP TRIGGER momo_gateway_capture_immutable;'],['column','ALTER TABLE momo_gateway_credentials ADD COLUMN unreviewed_authority TEXT;'],['changed-trigger',"DROP TRIGGER momo_transaction_facts;CREATE TRIGGER momo_transaction_facts BEFORE UPDATE OF amount_minor ON momo_transactions BEGIN SELECT RAISE(ABORT,'changed');END;"]]){const p=structuredClone(c.payload),raw=Buffer.from(c.sql+'\n'+suffix);p.files['database.sql']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};const path=join(dir,'wrong-'+name+'.json');await writeFile(path,JSON.stringify(seal(p,Buffer.from((await readFile(keyPath,'utf8')).trim(),'base64'))),{mode:0o600});await assert.rejects(backupMain(['prepare-quarantine','--archive',path,'--key',keyPath,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(dir,'wrong-'+name)]),/bookkeeping|catalog differs/);}
 });
 await check('actual locked local restore covers cyclic MFA, all15 SQL schemas, every index/trigger/view and source sequence',async()=>{
  await backupMain(['verify-local',...common,'--out',join(dir,'local-restore'),'--wrangler',join(runtime.dependency_root,'node_modules/wrangler')]);const record=JSON.parse(await readFile(join(dir,'local-restore/verification.json')));assert.equal(record.tables.privacy_retention_tasks,91);assert.equal(record.tables.assisted_sms_jobs,2);assert.equal(record.all_indexes_triggers_and_views_match,true);assert.equal(record.foreign_keys_disabled,false);assert.equal(record.accepted_RPO_RTO,false);
 });
 assert.equal(networkCalls,0);await writeFile(join(dir,'case-result.json'),JSON.stringify({kind:'generated_synthetic_current15_local_recovery',never_primary_capture:true,actual_provider_source_database_id:null,profile:'candidate15',cases:names,counts:c.counts,upgrade15:c.upgrade15,canonical_atomic_source_sha256:sha(await readFile(new URL('../cloudflare/atomic_d1_restore.mjs',import.meta.url))),action_statement_counts:Object.fromEntries(Object.entries(plan.actions).map(([k,v])=>[k,v.statement_count])),network_calls:networkCalls,provider_calls:false,RPO_RTO_accepted:false,full_system_recovery_accepted:false},null,2)+'\n',{mode:0o600});
});

const historicalProfileProtocols={"published9":{"profile_sha256":"3db5c0576bd33c73f48df5d86d00f96e4b0e22205a1be5832b3ca3c0042f7b3a","plan_sha256":"1e8664288d64eeff316f1442756df68961c06cfcd9a02b89a7a8bc12d58470ed"},"candidate10":{"profile_sha256":"386a1a82c76f9f9f65ccc3ead709894b1a6a2786b555e4d813a37e0dfa65131c","plan_sha256":"bdb8cf96d3d0e1ec5b864aabea02663c054077179d370aeb2962309de14cc7e9"},"candidate11":{"profile_sha256":"7759e9155fe3e550213aea63b6d2ad7ef379c2092d6719020cac1c9547de5d85","plan_sha256":"dc0e8e62a49ac53a073f328c105558ed5a145c56cfa55f90c77cc7a52ada8c9a"},"candidate12":{"profile_sha256":"3817fa6abcaa61f3ae46fb0bed002c0902af1b921d3c0ce2de15ada2085757c2","plan_sha256":"b2d7d4afe1e85e5512829a4f0824e957bc7c0a616fc659312827ba2f95f015ac"},"candidate13":{"profile_sha256":"5e40cdd06a79d5f596b9c85acecd408f2109bea61b8499b6dd953646e49f1db4","plan_sha256":"c33c725d39115f53518bedeffc8b3a997e40cca7d449d980360b4d022754989d"}};
test('serialized published9 and candidate10/11/12/13 profiles and original plans remain byte-identical',()=>{const id={archiveSha256:'a'.repeat(64),sourceId:'f'.repeat(64),operationId:'00000000-0000-4000-8000-000000000003',createdAt:'2026-10-16T00:00:00.000Z'};for(const [name,expected]of Object.entries(historicalProfileProtocols)){assert.equal(sha(JSON.stringify(quarantineSchemaProfiles[name])),expected.profile_sha256,name);assert.equal(sha(JSON.stringify(recoveryQuarantinePlan({...id,schemaProfile:name}))),expected.plan_sha256,name);}});
