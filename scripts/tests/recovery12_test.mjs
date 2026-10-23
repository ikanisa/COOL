import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile,mkdtemp,mkdir,realpath,rm,lstat,readdir,readlink} from 'node:fs/promises';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {prepareAtomicD1Restore,verifyAtomicPackage,verifyAtomicReadback} from '../cloudflare/atomic_d1_restore.mjs';
import {seal,installSql,restoreSql,main as backupMain,validatePayload} from '../cloudflare/platform_backup.mjs';
import {recoveryQuarantinePlan,quarantineSchemaProfiles,assistedSmsRecoveryTables} from '../cloudflare/recovery_quarantine.mjs';
import {current12Fixture,captureD1,controls,dataKeys,sourceId,sha,database} from '../../deploy/platform-api/test/support/recovery12_fixture.mjs';
import {fixture as shippingFixture} from '../../deploy/platform-api/test/support/notification_operator_integration_fixture.mjs';
import {decrypt} from '../../deploy/platform-api/src/encryption.js';
import {assistedSmsDestinationContext} from '../../deploy/platform-api/src/notification_operator.js';
const projectRequire=createRequire(new URL('../../deploy/platform-api/package.json',import.meta.url));
const canonical=value=>JSON.stringify(value,(_,v)=>typeof v==='bigint'?v.toString():v);
const rowSet=async(db,name)=>(await db.prepare('SELECT * FROM "'+name+'"').all()).results.map(canonical).sort();
async function runtimeFixture(dir){
 const module=process.env.COLLECT_WRANGLER_MODULE??projectRequire.resolve('wrangler');let folder=dirname(createRequire(import.meta.url).resolve(module));
 while(JSON.parse(await readFile(join(folder,'package.json')).catch(()=>Buffer.from('{}'))).name!=='wrangler'){const next=dirname(folder);assert.notEqual(next,folder);folder=next;}
 const root=dirname(dirname(folder)),records={node:{sha256:sha(await readFile(process.execPath)),bytes:(await lstat(process.execPath)).size}};
 async function walk(path,prefix){for(const e of await readdir(path,{withFileTypes:true})){const p=join(path,e.name),name=prefix+'/'+e.name;if(e.isDirectory())await walk(p,name);else if(e.isSymbolicLink())records[name]={symlink:await readlink(p)};else{const raw=await readFile(p);records[name]={sha256:sha(raw),bytes:raw.length};}}}
 await walk(join(root,'node_modules'),'node_modules');const raw=Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(records).sort()))),path=join(dir,'runtime.json');await writeFile(path,raw,{mode:0o600});return {node_path:process.execPath,dependency_root:root,manifest_path:path,manifest_sha256:sha(raw)};
}
const wrapper=`import worker from './worker.js';export default {async fetch(request,env){const r=await worker.fetch(request,env);if(request.headers.get('x-test-lost-ack')==='true'&&r.status===200)return Response.json({code:'controlled_unknown_after_actual_action'},{status:503});return r;}};`;

test('distinct current12 synthetic archive and exact canonical adapter preserve SMS, decision heads and91-task controls through real D1 restore/quarantine',async t=>{
 const c=await current12Fixture(t),external=process.env.COLLECT_RECOVERY12_EVIDENCE_DIR;
 const dir=external?await realpath(await mkdir(external,{mode:0o700}).then(()=>external)):await realpath(await mkdtemp(join(tmpdir(),'collect-recovery12-')));
 if(!external)t.after(()=>rm(dir,{recursive:true,force:true}));
 const names=[];async function check(name,fn){await t.test(name,fn);names.push(name);}
 const key=randomBytes(32),archive=join(dir,'synthetic-archive.json'),keyPath=join(dir,'synthetic-key.base64'),restore=join(dir,'restore.sql');
 await writeFile(archive,JSON.stringify(seal(c.payload,key)),{mode:0o600});await writeFile(keyPath,key.toString('base64'),{mode:0o600});key.fill(0);await writeFile(restore,c.sql,{mode:0o600});
 const common=['--archive',archive,'--key',keyPath];await backupMain(['prepare-quarantine',...common,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(dir,'quarantine')]);
 const preparedRecord=JSON.parse(await readFile(join(dir,'quarantine/preparation.json'))),runtime=await runtimeFixture(dir),packagePath=join(dir,'package');
 const prepared=await prepareAtomicD1Restore({archive_path:archive,key_path:keyPath,qualified_restore_sql_path:restore,qualified_quarantine_plan_path:join(dir,'quarantine/quarantine-plan.json'),target:{account_id:'2209b915a85b1c11cee79b7806c6e73b',database_name:'collect-synthetic-current12-local',database_id:randomUUID()},runtime},packagePath),{plan}=await verifyAtomicPackage(packagePath,prepared.manifest_sha256);
 const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??projectRequire.resolve('miniflare')),{build}=await import(process.env.COLLECT_ESBUILD_MODULE??projectRequire.resolve('esbuild'));
 await writeFile(join(packagePath,'test-entry.js'),wrapper,{mode:0o600});const script=(await build({entryPoints:[join(packagePath,'test-entry.js')],bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',logLevel:'silent'})).outputFiles[0].text;
 let networkCalls=0;const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script,compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,bindings:{CAPTURE_TOKEN:'SYNTHETIC_CURRENT12_LOOPBACK_TOKEN_ONLY_1234567890',TARGET_DATABASE_ID:plan.target.database_id,SOURCE_ID:sourceId,PLAN_SHA256:prepared.plan_sha256},outboundService:async()=>{networkCalls++;throw Error('No provider transport allowed');}}));t.after(()=>mf.dispose());const db=await mf.getD1Database('DB');let checkpoint;
 async function call(name,body,headers={}){const r=await mf.dispatchFetch('http://127.0.0.1:8998/'+name,{method:'POST',headers:{Authorization:'Bearer SYNTHETIC_CURRENT12_LOOPBACK_TOKEN_ONLY_1234567890','Content-Type':'application/json',...headers},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
 const read=async()=>{const r=await call('readback',{plan_sha256:prepared.plan_sha256});assert.equal(r.status,200,JSON.stringify(r.body));checkpoint=r.body.sha256;return r.body;};
 const body=name=>({plan_sha256:prepared.plan_sha256,action_sha256:plan.actions[name].statements_sha256,checkpoint_sha256:checkpoint??'0'.repeat(64)});
 const verify=async(stage,name)=>{const sql=await captureD1(db),path=join(dir,name+'.sql');await writeFile(path,sql,{mode:0o600});await verifyAtomicReadback({directory:packagePath,manifest_sha256:prepared.manifest_sha256,archive_path:archive,key_path:keyPath,sql_path:path,stage,out_directory:join(dir,name+'-verified')});return sql;};
 await check('12 is an exact distinct migration profile, all7 SMS tables/all7controls populated and historical protocols are unchanged',async()=>{
  assert.equal(plan.schema_profile,'candidate12');assert.equal(plan.quarantine_plan.format,'collect.platform.recovery-quarantine.v4');assert.equal(Object.keys(quarantineSchemaProfiles.candidate12.digests).length,12);assert.equal(c.counts.privacy_retention_tasks,91);
  for(const name of [...controls,...assistedSmsRecoveryTables])assert.ok(c.counts[name]>0,name);
  assert.equal(preparedRecord.assisted_sms_history_retained,true);assert.equal(preparedRecord.decision_receipt_heads_preserved,true);assert.equal(preparedRecord.assisted_sms_send_authority_restored,false);
  assert.equal(plan.archive.source_provenance.actual_provider_source_database_id,null);assert.equal(plan.archive.source_provenance.never_primary_capture,true);assert.equal(plan.full_system_recovery_accepted,false);
 });
 await check('actual empty D1 restore has an unknown response and must read back before any replay',async()=>{
  assert.equal((await read()).state,'empty');const unknown=await call('restore',body('restore'),{'x-test-lost-ack':'true'});assert.equal(unknown.status,503);assert.equal((await call('restore',body('restore'))).body.code,'already_attempted_readback_required');assert.equal((await read()).state,'restored');assert.equal(await verify('restored','restored'),c.sql);
 });
 const immutable={};for(const name of [...assistedSmsRecoveryTables,'request_receipts','ledger_entries','payment_evidence','auth_identity_rate_aliases',...controls.filter(n=>n!=='privacy_retention_guards')])immutable[name]=await rowSet(db,name);
 await check('whole current12 late CHECK rolls back every schema row, control, SMS record, head and sequence',async()=>{
  const before=await captureD1(db),r=await call('late_failure',body('late_failure'));assert.equal(r.status,422);assert.equal(r.body.expected_late_CHECK,true);assert.equal((await read()).state,'restored');assert.equal(await verify('restored','late-failure'),before);
 });
 await check('canonical quarantine lost reply requires exact readback and immutable original-session SMS history is retained',async()=>{
  assert.equal((await call('quarantine',body('quarantine'),{'x-test-lost-ack':'true'})).status,503);assert.equal((await call('quarantine',body('quarantine'))).body.code,'already_attempted_readback_required');assert.equal((await read()).state,'quarantined');await verify('quarantined','quarantined');
  for(const [name,rows]of Object.entries(immutable))assert.deepEqual(await rowSet(db,name),rows,name);
  assert.equal((await db.prepare('SELECT count(*) AS n FROM privacy_retention_guards').first()).n,0);assert.equal((await db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE revoked_at IS NULL').first()).n,0);assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);
 });
 await check('same-operation replay preserves exact rows, balances, no-op decision heads, barriers and all14 history/control classes',async()=>{
  const before=await captureD1(db);assert.equal((await call('replay',body('replay'))).status,200);assert.equal((await read()).state,'quarantined');assert.equal(await verify('quarantined','replayed'),before);
  assert.equal((await db.prepare("SELECT count(*) AS n FROM request_receipts WHERE user_id=? AND operation='assisted_sms.consent.set'").bind(c.recipient).first()).n,2);assert.equal((await db.prepare("SELECT count(*) AS n FROM request_receipts WHERE user_id=? AND operation='assisted_sms.access.set'").bind(c.account.userId).first()).n,1);assert.equal((await db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,2500);
  await assert.rejects(db.prepare("UPDATE users SET access_status='active' WHERE id=?").bind(c.subject).run(),/privacy_retention_access_quarantined/);await assert.rejects(db.prepare("DELETE FROM request_receipts WHERE operation='assisted_sms.consent.set'").run(),/retain_request_receipt/);
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
  const consent=await current.call('/v1/rpc/get_assisted_sms_consent_v1',{origin:'https://collect.example',headers:{Authorization:'Bearer '+c.phone.access_token},data:{p_collection_id:c.smsGroup}});assert.equal(consent.status,401);assert.equal(await captureD1(current.db),sql);
 });
 await check('current12 refuses unreviewed13 or changed12 migrations and exact provider-prefix/trigger/column drift',async()=>{
  const variants=[['migration',p=>{const name='migrations/0012_notification_operator.sql',raw=Buffer.from(p.files[name].base64,'base64');p.files[name]={sha256:sha(Buffer.concat([raw,Buffer.from('\n-- changed')])),bytes:raw.length+11,base64:Buffer.concat([raw,Buffer.from('\n-- changed')]).toString('base64')};}],['future',p=>{const raw=Buffer.from('CREATE TABLE future_authority(id TEXT);');p.files['migrations/0013_unreviewed.sql']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};}]];
  for(const [,change]of variants){const p=structuredClone(c.payload);change(p);assert.throws(()=>validatePayload(p));}
  for(const [name,suffix]of [['unknown-prefix','CREATE TABLE _cf_unreviewed(id TEXT,authority TEXT);'],['new-copy','CREATE TABLE unreviewed_sms_copy(id TEXT,recipient_user_id TEXT);'],['trigger','DROP TRIGGER receipt_no_delete;'],['column','ALTER TABLE assisted_sms_outcomes ADD COLUMN unreviewed_authority TEXT;']]){const p=structuredClone(c.payload),raw=Buffer.from(c.sql+'\n'+suffix);p.files['database.sql']={sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')};const path=join(dir,'wrong-'+name+'.json');await writeFile(path,JSON.stringify(seal(p,Buffer.from((await readFile(keyPath,'utf8')).trim(),'base64'))),{mode:0o600});await assert.rejects(backupMain(['prepare-quarantine','--archive',path,'--key',keyPath,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(dir,'wrong-'+name)]),/bookkeeping|catalog differs/);}
 });
 await check('actual locked local restore covers cyclic MFA, all12 SQL schemas, every index/trigger/view and source sequence',async()=>{
  await backupMain(['verify-local',...common,'--out',join(dir,'local-restore'),'--wrangler',join(runtime.dependency_root,'node_modules/wrangler')]);const record=JSON.parse(await readFile(join(dir,'local-restore/verification.json')));assert.equal(record.tables.privacy_retention_tasks,91);assert.equal(record.tables.assisted_sms_jobs,2);assert.equal(record.all_indexes_triggers_and_views_match,true);assert.equal(record.foreign_keys_disabled,false);assert.equal(record.accepted_RPO_RTO,false);
 });
 assert.equal(networkCalls,0);await writeFile(join(dir,'case-result.json'),JSON.stringify({kind:'generated_synthetic_current12_local_recovery',never_primary_capture:true,actual_provider_source_database_id:null,profile:'candidate12',cases:names,counts:c.counts,canonical_atomic_source_sha256:sha(await readFile(new URL('../cloudflare/atomic_d1_restore.mjs',import.meta.url))),action_statement_counts:Object.fromEntries(Object.entries(plan.actions).map(([k,v])=>[k,v.statement_count])),network_calls:networkCalls,provider_calls:false,RPO_RTO_accepted:false,full_system_recovery_accepted:false},null,2)+'\n',{mode:0o600});
});
