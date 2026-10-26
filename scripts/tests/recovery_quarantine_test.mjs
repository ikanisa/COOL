import {historical11Fixture} from './fixtures/recovery_profile11.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {readFile,mkdtemp,writeFile,realpath,rm,access,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {seal,unseal,validatePayload,installSql,restoreSql,main} from '../cloudflare/platform_backup.mjs';
import {recoveryQuarantinePlan,applyRecoveryQuarantine,quarantineMigrationDigests,quarantineSchemaProfiles} from '../cloudflare/recovery_quarantine.mjs';

const sha=bytes=>createHash('sha256').update(bytes).digest('hex'),sourceId='f'.repeat(64),database='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
const root=new URL('../../deploy/platform-api/',import.meta.url);
// Exercise the explicitly qualified recovery schema. An unpublished migration
// must not silently enter this historical fixture or bypass qualification.
const migrationFiles=Object.fromEntries(await Promise.all(Object.keys(quarantineMigrationDigests).sort().map(async name=>{
 const raw=await readFile(new URL(name,root));assert.equal(sha(raw),quarantineMigrationDigests[name]);return [name,raw.toString('utf8')];
})));
const actor='00000000-0000-4000-8000-000000000001',session='00000000-0000-4000-8000-000000000002';
const sql=Object.values(migrationFiles).join('\n')+`
 INSERT INTO users(id,phone,public_id,created_at,updated_at) VALUES('${actor}','+250788123456','123456','2026-10-15T00:00:00.000Z','2026-10-15T00:00:00.000Z');
 INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES('${session}','${actor}','member',1792022400,1792022400,1792108800);
 INSERT INTO support_requests(id,user_id,kind,message,created_at) VALUES('retained-support','${actor}','support','Retained request body','2026-10-15T00:00:00.000Z');
`;
const identity={archiveSha256:'a'.repeat(64),sourceId,operationId:'00000000-0000-4000-8000-000000000003',createdAt:'2026-10-15T18:00:00.000Z'};
for(const [key,value] of [['archiveSha256','bad'],['sourceId','bad'],['operationId',"x'; DELETE FROM users;--"],['createdAt','2026-10-15'],['createdAt','2026-10-15T18:00:00.001Z']]){
 test(`quarantine requires a precise authenticated recovery identity: ${key} ${value.length}`,()=>assert.throws(()=>recoveryQuarantinePlan({...identity,[key]:value}),/identities|timestamp/));
}
test('unsupported SQL in an offline quarantine plan is refused before any mutation',()=>{
 const db=new DatabaseSync(':memory:');try{installSql(db,sql);const plan=recoveryQuarantinePlan(identity);plan.statements.push({sql:'DELETE FROM users',params:[]});assert.throws(()=>applyRecoveryQuarantine(db,plan),/supported quarantine policy/);assert.equal(db.prepare('SELECT access_status FROM users').get().access_status,'active');}finally{db.close();}
});
test('the offline transaction retains exact support/history and rejects conflicting operation reuse',()=>{
 const db=new DatabaseSync(':memory:');try{installSql(db,sql);const before=db.prepare('SELECT * FROM support_requests').all(),plan=recoveryQuarantinePlan(identity);applyRecoveryQuarantine(db,plan);
  assert.deepEqual(db.prepare('SELECT * FROM support_requests').all(),before);assert.equal(db.prepare('SELECT access_status FROM users').get().access_status,'suspended');
  applyRecoveryQuarantine(db,plan);assert.equal(db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='recovery.access.quarantined'").get().n,1);
  const conflict=recoveryQuarantinePlan({...identity,archiveSha256:'b'.repeat(64)});assert.throws(()=>applyRecoveryQuarantine(db,conflict),/admin_bridge_state/);
  assert.equal(db.prepare('SELECT count(*) AS n FROM admin_bridge_guards').get().n,0);
 }finally{db.close();}
});
function payload(){
 const values={'database.sql':sql,'wrangler.json':JSON.stringify({name:'collect-platform-api',d1_databases:[{database_id:database}],vars:{BUILD_SOURCE_ID:sourceId}}),
  'worker-secrets.json':JSON.stringify({AUTH_JWT_SECRET:'a'.repeat(64),AUTH_TOKEN_HASH_SECRET:'b'.repeat(64),DATA_ENCRYPTION_KEY:'c'.repeat(64)}),...migrationFiles};
 return {format:'collect.platform.backup.v1',database_id:database,source_id:sourceId,captured_at:'2026-10-15T01:00:00.000Z',files:Object.fromEntries(Object.entries(values).map(([n,value])=>{const bytes=Buffer.from(value);return[n,{sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')}];}))};
}
for(const defect of ['changed published migration','later migration','extra credential table','missing authority trigger'])test(`quarantine refuses an unqualified recovery schema: ${defect}`,async()=>{
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-quarantine-schema-')));
 try{
  const p=payload(),replace=(name,value)=>{const bytes=Buffer.from(value);p.files[name]={sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')};};
  if(defect==='changed published migration')replace('migrations/0009_operator_notes.sql',migrationFiles['migrations/0009_operator_notes.sql']+'\n-- changed');
  if(defect==='later migration'){
   const next=Math.max(...Object.keys(migrationFiles).map(n=>Number(n.slice(11,15))))+1;
   replace('migrations/'+String(next).padStart(4,'0')+'_credentials.sql','-- unqualified future credential change');
  }
  if(defect==='extra credential table')replace('database.sql',sql+'CREATE TABLE unreviewed_credentials(id TEXT);');
  if(defect==='missing authority trigger')replace('database.sql',sql+'DROP TRIGGER native_claim_authority;');
  const key=randomBytes(32),archive=join(dir,'archive.json'),keyPath=join(dir,'key.base64'),out=join(dir,'must-not-exist');
  await writeFile(archive,JSON.stringify(seal(p,key)),{mode:0o600});await writeFile(keyPath,key.toString('base64'),{mode:0o600});
  await assert.rejects(main(['prepare-quarantine','--archive',archive,'--key',keyPath,'--operation',randomUUID(),'--at',identity.createdAt,'--out',out]),/qualified.*schema|catalog differs/);
  await assert.rejects(access(out));
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('authenticated offline preparation and independent readback distinguish quarantine from an unchanged snapshot',async()=>{
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-quarantined-recovery-')));
 try{
  const key=randomBytes(32),archive=join(dir,'archive.json'),keyPath=join(dir,'key.base64'),out=join(dir,'prepared');
  await writeFile(archive,JSON.stringify(seal(payload(),key)),{mode:0o600});await writeFile(keyPath,key.toString('base64'),{mode:0o600});
  const common=['--archive',archive,'--key',keyPath];
  await assert.rejects(main(['prepare-quarantine',...common,'--operation',randomUUID(),'--at','2026-10-15T00:00:00.000Z','--out',out]),/predate/);
  await assert.rejects(access(out));
  await main(['prepare-quarantine',...common,'--operation',identity.operationId,'--at',identity.createdAt,'--out',out]);
  const planPath=join(out,'quarantine-plan.json'),quarantinedSql=join(out,'quarantined-restore.sql');
  const receipt=JSON.parse(await readFile(join(out,'preparation.json')));assert.equal(receipt.remote_execution,false);assert.equal(receipt.all_captured_financial_and_object_rows_unchanged,true);assert.equal(receipt.production_cutover_accepted,false);
  const restored=new DatabaseSync(':memory:');try{installSql(restored,await readFile(quarantinedSql,'utf8'));assert.equal(restored.prepare('SELECT access_status FROM users').get().access_status,'suspended');assert.equal(restored.prepare('SELECT revocation_reason FROM auth_sessions').get().revocation_reason,'disaster_recovery_quarantine');assert.equal(restored.prepare('PRAGMA foreign_key_check').all().length,0);}finally{restored.close();}
  await main(['verify-quarantine-readback',...common,'--plan',planPath,'--sql',quarantinedSql,'--out',join(dir,'verified')]);
  const verified=JSON.parse(await readFile(join(dir,'verified/verification.json')));assert.equal(verified.authenticated_snapshot_match,false);assert.equal(verified.authenticated_quarantined_snapshot_match,true);assert.equal(verified.remote_execution_proven_by_this_offline_check,false);
  await assert.rejects(main(['verify-readback',...common,'--sql',quarantinedSql,'--out',join(dir,'wrong-normal-verifier')]),/differs from the authenticated backup/);
  const changed=join(dir,'altered.sql');await writeFile(changed,(await readFile(quarantinedSql,'utf8'))+"UPDATE support_requests SET message='Altered';",{mode:0o600});
  await assert.rejects(main(['verify-quarantine-readback',...common,'--plan',planPath,'--sql',changed,'--out',join(dir,'wrong-row')]),/differs from the authenticated backup/);
  const substituted=JSON.parse(await readFile(planPath));substituted.archive_sha256='0'.repeat(64);const otherPlan=join(dir,'substituted-plan.json');await writeFile(otherPlan,JSON.stringify(substituted),{mode:0o600});
  await assert.rejects(main(['verify-quarantine-readback',...common,'--plan',otherPlan,'--sql',quarantinedSql,'--out',join(dir,'wrong-archive')]),/does not identify this authenticated archive/);
 }finally{await rm(dir,{recursive:true,force:true});}
});

test('published9 quarantine plans preserve the exact historical protocol bytes',()=>{
 // Captured from the preserved pre-change recovery_quarantine.mjs source
 // SHA99973ef633cbccfddbb5e9bf12f2054d36a41223ccb7484c72514c0b722bbea3.
 assert.equal(sha(Buffer.from(JSON.stringify(recoveryQuarantinePlan(identity)))),'a483a6803f21858faae92658ba02c9e6ede66438da21890dee10f735b82a21cd');
 assert.equal(recoveryQuarantinePlan(identity).schema_profile,undefined);
 assert.throws(()=>recoveryQuarantinePlan({...identity,schemaProfile:'future11'}),/Unknown recovery schema profile/);
});
test('candidate10 quarantine protocol remains byte-identical to the sealed API13 tooling',()=>{
 // Original module SHA a7864197194ff2a0483c954a87aefe3a808254e4ec940429644c7687132ec9be.
 assert.equal(sha(Buffer.from(JSON.stringify(recoveryQuarantinePlan({...identity,schemaProfile:'candidate10'})))),'6a2b87c6e8b4afaa4ed07e2c7d56567dbafd9648bd722c5bd3d07afe130b6283');
 const current=recoveryQuarantinePlan({...identity,schemaProfile:'candidate11'});assert.equal(current.format,'collect.platform.recovery-quarantine.v3');assert.match(current.statements[0].params[5],/retain_all_key_ids_hashes_and_request_links/);
});

const controls=['privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers'];
const retainedControls=controls.filter(n=>n!=='privacy_retention_guards');
const canonical=value=>JSON.stringify(value,(_,v)=>typeof v==='bigint'?v.toString():v);
let historicalCapture;
async function candidateFixture(){
 if(historicalCapture)return historicalCapture;
 const raw=await readFile(new URL('fixtures/recovery_profile10.sql',import.meta.url)),metadata=JSON.parse(await readFile(new URL('fixtures/recovery_profile10.json',import.meta.url)));
 assert.equal(metadata.format,'collect.synthetic.recovery-profile10.v1');assert.equal(metadata.synthetic_only,true);assert.equal(metadata.no_live_archive_or_private_credential_input,true);
 assert.equal(sha(raw),'b1bb040b375ec8a0674d5bd2fa472b302fbdc24c806e6773acb0a1a53df49e1e');assert.equal(metadata.sql_sha256,sha(raw));assert.equal(metadata.producer.qualified_source_id,'0dd4f494a76ebb6268808c2a7da9f1713c7fd350d7e367ccde4f12ac18cc262a');
 const db=new DatabaseSync(':memory:');try{installSql(db,'BEGIN;'+raw.toString()+'COMMIT;');assert.equal(db.prepare('PRAGMA foreign_key_check').all().length,0);
  const schema=db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY type,name").all();assert.equal(sha(Buffer.from(JSON.stringify(schema))),metadata.schema_sha256);
  assert.equal(db.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE name='auth_identity_rate_aliases'").get().n,0);assert.equal(db.prepare('SELECT count(*) AS n FROM ledger_entries').get().n,2);assert.equal(db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').get().n,0);
  for(const name of controls)assert.equal(db.prepare('SELECT count(*) AS n FROM '+name).get().n,metadata.counts[name],name);assert.equal(metadata.counts.privacy_retention_tasks,83);
 }finally{db.close();}
 const values={'database.sql':raw,'wrangler.json':JSON.stringify({name:'collect-platform-api',d1_databases:[{binding:'DB',database_name:'collect-platform',database_id:database}],vars:{BUILD_SOURCE_ID:sourceId,DATA_KEY_ID:'auth-test-v1',TURNSTILE_SITE_KEY:'0xSYNTHETIC_ISOLATED_TEST_WIDGET_ONLY'}}),'worker-secrets.json':JSON.stringify({AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),TURNSTILE_SECRET:'SYNTHETIC_TURNSTILE_SECRET_NEVER_A_REAL_PROVIDER_KEY'})};
 for(const [name,digest]of Object.entries(quarantineSchemaProfiles.candidate10.digests)){const bytes=await readFile(new URL(name,root));assert.equal(sha(bytes),digest);values[name]=bytes;}
 const payload={format:'collect.platform.backup.v1',database_id:database,source_id:sourceId,captured_at:metadata.captured_at,files:Object.fromEntries(Object.entries(values).map(([name,value])=>{const bytes=Buffer.from(value);return[name,{sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')}];}))};
 historicalCapture={payload,recoveryAt:metadata.recovery_at,actor:metadata.actor,subject:metadata.subject,objectClaim:metadata.object_claim,counts:metadata.counts};
 await saveEvidence('historical10-fixture-provenance.json',{format:metadata.format,synthetic_only:true,SQL_sha256:sha(raw),schema_sha256:metadata.schema_sha256,producer:metadata.producer,counts:metadata.counts,current11_loaded:false});return historicalCapture;
}
const identityBindings={AUTH_IDENTITY_KEY_ID:'recovery-current-v2',AUTH_IDENTITY_HASH_KEY:Buffer.alloc(32,151).toString('base64'),AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({'recovery-old-v1':Buffer.alloc(32,152).toString('base64')})};
let identityCapture;
async function identityFixture(t){
 if(identityCapture)return identityCapture;identityCapture=historical11Fixture(root);const c=await identityCapture;for(const item of c.observations??[])await saveEvidence(item.name,{...item,historical_generated_fixture:true});return c;
}

function capturedDb(c){const db=new DatabaseSync(':memory:');db.exec('BEGIN');installSql(db,Buffer.from(c.payload.files['database.sql'].base64,'base64').toString());db.exec('COMMIT');return db;}
function rowsOf(db,name){return db.prepare('SELECT * FROM "'+name+'"').all().map(r=>canonical(r)).sort();}
async function candidateArchive(t,c){const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-retention-recovery-')));t.after(()=>rm(dir,{recursive:true,force:true}));const key=randomBytes(32),archive=join(dir,'archive.json'),keyPath=join(dir,'key.base64'),raw=Buffer.from(JSON.stringify(seal(c.payload,key)));await writeFile(archive,raw,{mode:0o600});await writeFile(keyPath,key.toString('base64'),{mode:0o600});return {dir,archive,keyPath,archiveSha256:sha(raw),common:['--archive',archive,'--key',keyPath]};}

const approvalRole='PRIVACY_RETENTION_APPROVAL_SHA256',syntheticApproval='d'.repeat(64);
function replacePrivateRole(p,name,value){const bytes=Buffer.from(value);p.files[name]={sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')};}
function withApproval(p,value=syntheticApproval){const next=JSON.parse(JSON.stringify(p)),keys=JSON.parse(Buffer.from(next.files['worker-secrets.json'].base64,'base64'));keys[approvalRole]=value;replacePrivateRole(next,'worker-secrets.json',JSON.stringify(keys));return next;}
async function identityConfigPayload(){
 const p=structuredClone((await candidateFixture()).payload),name='migrations/0011_auth_identity_keys.sql',migration=await readFile(new URL(name,root));assert.equal(sha(migration),quarantineSchemaProfiles.candidate11.digests[name]);replacePrivateRole(p,name,migration);replacePrivateRole(p,'database.sql',Buffer.from(p.files['database.sql'].base64,'base64').toString()+'\n'+migration.toString());
 const config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64')),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));config.vars.AUTH_IDENTITY_KEY_ID=identityBindings.AUTH_IDENTITY_KEY_ID;keys.AUTH_JWT_SECRET='J'.repeat(32);keys.AUTH_TOKEN_HASH_SECRET='L'.repeat(32);keys.AUTH_IDENTITY_HASH_KEY=identityBindings.AUTH_IDENTITY_HASH_KEY;keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=identityBindings.AUTH_IDENTITY_PREVIOUS_KEYS_JSON;
 return {p,config,keys,commit(){replacePrivateRole(p,'wrangler.json',JSON.stringify(config));replacePrivateRole(p,'worker-secrets.json',JSON.stringify(keys));return p;}};
}
test('candidate11 recovery supports the unchanged legacy fallback and the exact bounded identity key ring',async()=>{
 const f=await identityConfigPayload();for(const count of [0,8]){f.keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify(Object.fromEntries(Array.from({length:count},(_,i)=>['old-'+i,Buffer.alloc(32,100+i).toString('base64')])));assert.doesNotThrow(()=>validatePayload(f.commit()));}
 delete f.config.vars.AUTH_IDENTITY_KEY_ID;delete f.keys.AUTH_IDENTITY_HASH_KEY;delete f.keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON;assert.doesNotThrow(()=>validatePayload(f.commit()));
 f.config.vars.AUTH_IDENTITY_KEY_ID='';f.keys.AUTH_IDENTITY_HASH_KEY='';f.keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON='';assert.doesNotThrow(()=>validatePayload(f.commit()));
});
const identityDefects=['missing current id','missing current key','reserved current id','invalid id','noncanonical base64','short key','public key','public history','secret id','unknown role','duplicate secret','escaped duplicate secret','duplicate historical id','escaped historical id','current id in history','legacy id in history','duplicate historical material','current material in history','legacy current material','legacy history material','JWT current material','JWT history material','data current material','data history material','nine previous keys','oversize history','history trailing data','history trailing comma','nonstring history','changed migration','future migration','historical9','historical10'];
for(const defect of identityDefects)test('identity-key recovery refuses '+defect,async()=>{
 const f=await identityConfigPayload(),{p,config,keys}=f,old=Buffer.alloc(32,152).toString('base64');
 if(defect==='missing current id')delete config.vars.AUTH_IDENTITY_KEY_ID;
 if(defect==='missing current key')delete keys.AUTH_IDENTITY_HASH_KEY;
 if(defect==='reserved current id')config.vars.AUTH_IDENTITY_KEY_ID='legacy-token-hash-v1';
 if(defect==='invalid id')config.vars.AUTH_IDENTITY_KEY_ID='bad key';
 if(defect==='noncanonical base64')keys.AUTH_IDENTITY_HASH_KEY=keys.AUTH_IDENTITY_HASH_KEY.replace(/=$/,'');
 if(defect==='short key')keys.AUTH_IDENTITY_HASH_KEY=Buffer.alloc(31,151).toString('base64');
 if(defect==='public key'){config.vars.AUTH_IDENTITY_HASH_KEY=keys.AUTH_IDENTITY_HASH_KEY;delete keys.AUTH_IDENTITY_HASH_KEY;}
 if(defect==='public history'){config.vars.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON;delete keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON;}
 if(defect==='secret id'){keys.AUTH_IDENTITY_KEY_ID=config.vars.AUTH_IDENTITY_KEY_ID;delete config.vars.AUTH_IDENTITY_KEY_ID;}
 if(defect==='unknown role')keys.AUTH_IDENTITY_BACKUP_KEY='PRIVATE_IDENTITY_CANARY';
 if(defect==='duplicate historical id')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON='{"old":"'+old+'","old":"'+Buffer.alloc(32,153).toString('base64')+'"}';
 if(defect==='escaped historical id')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON='{"o\\u006cd":"'+old+'"}';
 if(defect==='current id in history')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify({[config.vars.AUTH_IDENTITY_KEY_ID]:old});
 if(defect==='legacy id in history')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify({'legacy-token-hash-v1':old});
 if(defect==='duplicate historical material')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify({one:old,two:old});
 if(defect==='current material in history')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify({old:keys.AUTH_IDENTITY_HASH_KEY});
 for(const [prefix,value]of [['legacy',Buffer.from(keys.AUTH_TOKEN_HASH_SECRET).toString('base64')],['JWT',Buffer.from(keys.AUTH_JWT_SECRET).toString('base64')],['data',keys.DATA_ENCRYPTION_KEY]]){if(defect===prefix+' current material')keys.AUTH_IDENTITY_HASH_KEY=value;if(defect===prefix+' history material')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify({old:value});}
 if(defect==='nine previous keys')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=JSON.stringify(Object.fromEntries(Array.from({length:9},(_,i)=>['old-'+i,Buffer.alloc(32,100+i).toString('base64')])));
 if(defect==='oversize history')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=' '.repeat(4097);
 if(defect==='history trailing data')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON+='true';
 if(defect==='history trailing comma')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON=keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON.slice(0,-1)+',}';
 if(defect==='nonstring history')keys.AUTH_IDENTITY_PREVIOUS_KEYS_JSON={old};
 if(defect==='changed migration')replacePrivateRole(p,'migrations/0011_auth_identity_keys.sql',Buffer.from(p.files['migrations/0011_auth_identity_keys.sql'].base64,'base64').toString()+'\n-- changed');
 if(defect==='future migration')replacePrivateRole(p,'migrations/0012_unreviewed.sql','CREATE TABLE unreviewed_key_authority(id TEXT);');
 if(defect==='historical9'||defect==='historical10'){delete p.files['migrations/0011_auth_identity_keys.sql'];if(defect==='historical9')delete p.files['migrations/0010_privacy_retention.sql'];}
 f.commit();if(defect==='duplicate secret'||defect==='escaped duplicate secret')replacePrivateRole(p,'worker-secrets.json',JSON.stringify(keys).slice(0,-1)+',"AUTH_IDENTITY_HASH_'+(defect==='duplicate secret'?'KEY':'KE\\u0059')+'":"PRIVATE_IDENTITY_CANARY"}');
 assert.throws(()=>validatePayload(p),error=>/Identity.key recovery|Identity hash keys|Incomplete worker key recovery|Private recovery JSON/.test(error.message)&&!error.message.includes('PRIVATE_IDENTITY_CANARY')&&!error.message.includes(old));
});
test('candidate10 optional approval secret seals and recovers exactly without approving or repinning a policy',async t=>{
 const c=await candidateFixture(t),p=withApproval(c.payload),dir=await realpath(await mkdtemp(join(tmpdir(),'collect-retention-pin-recovery-')));t.after(()=>rm(dir,{recursive:true,force:true}));await mkdir(join(dir,'migrations'),{mode:0o700});
 for(const [name,value]of Object.entries(p.files))await writeFile(join(dir,name),Buffer.from(value.base64,'base64'),{mode:0o600});
 const out=join(dir,'sealed');await main(['seal','--sql',join(dir,'database.sql'),'--config',join(dir,'wrangler.json'),'--secrets',join(dir,'worker-secrets.json'),'--out',out]);
 const raw=await readFile(join(out,'platform-backup.json')),key=Buffer.from((await readFile(join(out,'recovery-key.base64'),'utf8')).trim(),'base64'),restored=unseal(JSON.parse(raw),key),receipt=JSON.parse(await readFile(join(out,'receipt.json')));
 assert.deepEqual(restored.files,p.files);assert.equal(receipt.archive_sha256,sha(raw));assert.deepEqual(receipt.worker_secret_roles,['AUTH_JWT_SECRET','AUTH_TOKEN_HASH_SECRET','DATA_ENCRYPTION_KEY',approvalRole,'TURNSTILE_SECRET'].sort());assert.equal(receipt.full_system_recovery_accepted,false);assert.ok(!JSON.stringify(receipt).includes(syntheticApproval));
 const common=['--archive',join(out,'platform-backup.json'),'--key',join(out,'recovery-key.base64')],prepared=join(dir,'prepared'),at=new Date(Math.ceil(Date.now()/1000)*1000).toISOString();await main(['prepare-quarantine',...common,'--operation',randomUUID(),'--at',at,'--out',prepared]);
 const preparation=JSON.parse(await readFile(join(prepared,'preparation.json')));assert.equal(preparation.schema_profile,'candidate10');assert.equal(preparation.retention_policy_repinned,false);assert.equal(preparation.subject_retention_barriers_released,false);
 await main(['verify-quarantine-readback',...common,'--plan',join(prepared,'quarantine-plan.json'),'--sql',join(prepared,'quarantined-restore.sql'),'--out',join(dir,'readback')]);const verified=JSON.parse(await readFile(join(dir,'readback/verification.json')));assert.ok(verified.worker_secret_roles.includes(approvalRole));assert.equal(verified.retention_policy_repinned,false);
 const unchanged=validatePayload(c.payload);assert.deepEqual(Object.keys(JSON.parse(unchanged['worker-secrets.json'])).sort(),['AUTH_JWT_SECRET','AUTH_TOKEN_HASH_SECRET','DATA_ENCRYPTION_KEY','TURNSTILE_SECRET'].sort());
 await saveEvidence('candidate-optional-approval-secret.json',{synthetic_test_only:true,optional_role:approvalRole,actual_seal_CLI_receipt:true,authenticated_roundtrip_all_private_bytes_exact:true,existing_four_roles_unchanged_without_pin:true,receipt:receipt,preparation:preparation,verification:verified,policy_approved:false,secret_provisioned:false,remote_execution:false});
});
for(const [name,value]of [['empty',''],['null',null],['number',64],['uppercase','D'.repeat(64)],['short','d'.repeat(63)],['long','d'.repeat(65)],['nonhex','g'.repeat(64)],['leading whitespace',' '+syntheticApproval],['trailing newline',syntheticApproval+'\n']])test('approval recovery refuses a malformed exact digest: '+name,async t=>{
 const c=await candidateFixture(t),p=withApproval(c.payload,value);assert.throws(()=>validatePayload(p),/Invalid retention approval recovery pin|Incomplete worker key recovery/);
});
for(const defect of ['published9','changed candidate migration','future migration','public var','unknown role','duplicate core role','duplicate approval role','escaped duplicate approval role'])test('approval recovery denies '+defect,async t=>{
 const c=await candidateFixture(t),p=withApproval(defect==='published9'?payload():c.payload),keys=JSON.parse(Buffer.from(p.files['worker-secrets.json'].base64,'base64'));
 if(defect==='changed candidate migration')replacePrivateRole(p,'migrations/0010_privacy_retention.sql',Buffer.from(p.files['migrations/0010_privacy_retention.sql'].base64,'base64').toString()+'\n-- changed');
 if(defect==='future migration')replacePrivateRole(p,'migrations/0011_unreviewed.sql','-- future policy');
 if(defect==='public var'){const config=JSON.parse(Buffer.from(p.files['wrangler.json'].base64,'base64'));config.vars[approvalRole]=syntheticApproval;replacePrivateRole(p,'wrangler.json',JSON.stringify(config));}
 if(defect==='unknown role'){keys.PRIVACY_RETENTION_APPROVAL_SHA256_OLD=syntheticApproval;replacePrivateRole(p,'worker-secrets.json',JSON.stringify(keys));}
 if(defect==='duplicate core role')replacePrivateRole(p,'worker-secrets.json',JSON.stringify(keys).slice(0,-1)+',"AUTH_JWT_SECRET":"PRIVATE_DUPLICATE_CANARY"}');
 if(defect==='duplicate approval role')replacePrivateRole(p,'worker-secrets.json',JSON.stringify(keys).slice(0,-1)+',"'+approvalRole+'":"'+syntheticApproval+'"}');
 if(defect==='escaped duplicate approval role')replacePrivateRole(p,'worker-secrets.json',JSON.stringify(keys).slice(0,-1)+',"PRIVACY_RETENTION_APPROVAL_SHA25\\u0036":"'+syntheticApproval+'"}');
 assert.throws(()=>validatePayload(p),error=>/exact qualified candidate10, candidate11, candidate12 or candidate13 migrations|separately authorized Worker secret|Incomplete worker key recovery|Private recovery JSON could not be verified/.test(error.message)&&!error.message.includes('PRIVATE_DUPLICATE_CANARY')&&!error.message.includes(syntheticApproval));
});

test('candidate10 quarantines populated control state and preserves immutable history, money and existing barriers',async t=>{
 const c=await candidateFixture(t),db=capturedDb(c);try{
  const before=Object.fromEntries([...retainedControls,'ledger_entries','payment_evidence','upload_objects','support_requests','privacy_submissions','auth_mfa_claims'].map(n=>[n,rowsOf(db,n)])),barrier=rowsOf(db,'privacy_retention_barriers');
  assert.equal(db.prepare('SELECT count(*) AS n FROM admin_sessions').get().n,1);const plan=recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt,schemaProfile:'candidate10'});applyRecoveryQuarantine(db,plan);
  for(const [name,rows]of Object.entries(before))assert.deepEqual(rowsOf(db,name),rows,name);assert.deepEqual(rowsOf(db,'privacy_retention_barriers'),barrier);assert.equal(db.prepare('SELECT count(*) AS n FROM privacy_retention_guards').get().n,0);
  assert.equal(db.prepare("SELECT count(*) AS n FROM users WHERE access_status='active'").get().n,0);assert.equal(db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE revoked_at IS NULL').get().n,0);assert.equal(db.prepare('SELECT count(*) AS n FROM admin_sessions').get().n,0);assert.equal(db.prepare("SELECT count(*) AS n FROM auth_mfa_factors WHERE status!='revoked'").get().n,0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM ledger_entries').get().n,2);assert.equal(db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').get().n,0);assert.equal(db.prepare("SELECT count(*) AS n FROM runtime_config WHERE key='privacy:retention:approved:v1'").get().n,1);
  assert.throws(()=>db.prepare("UPDATE users SET access_status='active' WHERE id=?").run(c.subject),/privacy_retention_access_quarantined/);assert.throws(()=>db.prepare('DELETE FROM privacy_retention_barriers').run(),/separate_recovery_authority/);assert.throws(()=>db.prepare('DELETE FROM privacy_retention_effects').run(),/retain_retention_effect/);
  const once=restoreSql(db);applyRecoveryQuarantine(db,plan);assert.equal(restoreSql(db),once);assert.throws(()=>applyRecoveryQuarantine(db,recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt})),/profile differs/);
 }finally{db.close();}
});

for(const defect of ['changed retention migration','unqualified future migration','extra retention table','missing retention barrier trigger'])test('candidate10 rejects '+defect,async t=>{
 const c=await candidateFixture(t),p=JSON.parse(JSON.stringify(c.payload));const replace=(name,value)=>{const bytes=Buffer.from(value);p.files[name]={sha256:sha(bytes),bytes:bytes.length,base64:bytes.toString('base64')};};
 if(defect==='changed retention migration')replace('migrations/0010_privacy_retention.sql',Buffer.from(p.files['migrations/0010_privacy_retention.sql'].base64,'base64').toString()+'\n-- changed');
 if(defect==='unqualified future migration')replace('migrations/0011_unreviewed.sql','CREATE TABLE new_credentials(id TEXT);');
 if(defect==='extra retention table')replace('database.sql',Buffer.from(p.files['database.sql'].base64,'base64').toString()+'CREATE TABLE privacy_retention_unreviewed(id TEXT);');
 if(defect==='missing retention barrier trigger')replace('database.sql',Buffer.from(p.files['database.sql'].base64,'base64').toString()+'DROP TRIGGER privacy_retention_no_new_session;');
 const a=await candidateArchive(t,{...c,payload:p});await assert.rejects(main(['prepare-quarantine',...a.common,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(a.dir,'rejected')]),/qualified.*schema|catalog differs/);await assert.rejects(access(join(a.dir,'rejected')));
});

test('candidate10 exact archive preparation/readback retains all control copies and refuses profile substitution',async t=>{
 const c=await candidateFixture(t),a=await candidateArchive(t,c),out=join(a.dir,'prepared');await main(['prepare-quarantine',...a.common,'--operation',identity.operationId,'--at',c.recoveryAt,'--out',out]);
 const receipt=JSON.parse(await readFile(join(out,'preparation.json')));assert.equal(receipt.schema_profile,'candidate10');assert.equal(receipt.transient_retention_guards_drained,true);assert.equal(receipt.retained_retention_control_rows_unchanged,true);assert.equal(receipt.subject_retention_barriers_released,false);assert.equal(receipt.retention_policy_repinned,false);assert.equal(receipt.production_cutover_accepted,false);
 const plan=join(out,'quarantine-plan.json'),sql=join(out,'quarantined-restore.sql');await main(['verify-quarantine-readback',...a.common,'--plan',plan,'--sql',sql,'--out',join(a.dir,'readback')]);const result=JSON.parse(await readFile(join(a.dir,'readback/verification.json')));assert.equal(result.schema_profile,'candidate10');assert.equal(result.table_count,74);assert.equal(result.full_system_recovery_accepted,false);assert.equal(result.remote_execution_proven_by_this_offline_check,false);
 const legacy=recoveryQuarantinePlan({...identity,archiveSha256:a.archiveSha256,createdAt:c.recoveryAt}),path=join(a.dir,'wrong-profile.json');await writeFile(path,JSON.stringify(legacy),{mode:0o600});await assert.rejects(main(['verify-quarantine-readback',...a.common,'--plan',path,'--sql',sql,'--out',join(a.dir,'wrong-profile')]),/archive\/profile/);
 await saveEvidence('candidate-preparation-readback.json',{preparation:receipt,verification:result});
});

test('verify-local restores genuine populated Auth/MFA cycles and candidate controls in one actual D1 batch',async t=>{
 const c=await candidateFixture(t),a=await candidateArchive(t,c),runtime=process.env.COLLECT_WRANGLER_MODULE??fileURLToPath(new URL('../../deploy/platform-api/node_modules/wrangler',import.meta.url)),out=join(a.dir,'actual-local-d1');
 await main(['verify-local',...a.common,'--wrangler',runtime,'--out',out]);const result=JSON.parse(await readFile(join(out,'verification.json')));assert.equal(result.actual_local_D1_import,true);assert.equal(result.restore_mode,'single_D1_batch_with_deferred_foreign_keys');assert.equal(result.foreign_keys_disabled,false);assert.equal(result.all_table_rows_and_schema_match,true);assert.equal(result.all_indexes_triggers_and_views_match,true);assert.equal(result.foreign_key_errors,0);assert.equal(result.full_system_recovery_accepted,false);for(const name of controls)assert.equal(result.tables[name],c.counts[name],name);
 await assert.rejects(access(join(out,'restore-data.sql')));assert.equal(JSON.parse(await readFile(join(out,'restore-transaction.json'))).requires_same_D1_batch,true);
 await saveEvidence('verify-local-cyclic-d1.json',{...result,transaction:JSON.parse(await readFile(join(out,'restore-transaction.json'))),local_import_log_sha256:sha(await readFile(join(out,'local-import.log'))),source_database_sql_sha256:c.payload.files['database.sql'].sha256});
});

async function saveEvidence(name,value){const path=process.env.COLLECT_RECOVERY_EVIDENCE_DIR;if(!path)return;await mkdir(path,{recursive:true,mode:0o700});await writeFile(join(path,name),JSON.stringify(value,null,2)+'\n',{flag:'wx',mode:0o600});}
async function d1Fingerprint(db){
 const tables=(await db.prepare("SELECT name,sql FROM sqlite_schema WHERE type='table' AND (name NOT LIKE 'sqlite_%' OR name='sqlite_sequence') AND name NOT LIKE '_cf_%' ORDER BY name").all()).results,result={};
 for(const table of tables){assert.match(table.name,/^[a-z][a-z0-9_]*$/);const rows=(await db.prepare('SELECT * FROM "'+table.name+'"').all()).results.map(canonical).sort();result[table.name]={count:rows.length,sha256:sha(Buffer.from(JSON.stringify([table.sql,rows])))};}
 const schema=(await db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY type,name").all()).results;
 return {tables:result,schema_sha256:sha(Buffer.from(JSON.stringify(schema)))};
}
async function recoveryD1(t,c){
 const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??fileURLToPath(new URL('../../deploy/platform-api/node_modules/miniflare/dist/src/index.js',import.meta.url)));
 const project=new URL('../../',import.meta.url),moduleNames=['scripts/cloudflare/recovery_quarantine.mjs','deploy/platform-api/src/privacy_retention_tasks.js','deploy/platform-api/src/privacy_retention_chunks.js','deploy/platform-api/src/privacy_retention_policy.js','deploy/platform-api/src/privacy_retention_catalog.js','deploy/platform-api/src/core.js'];
 const entry=`import {validateRecoveryQuarantinePlan} from '../cloudflare/recovery_quarantine.mjs';
 import {executeRetentionTask} from '../../deploy/platform-api/src/privacy_retention_tasks.js';
 export default {async fetch(request,env){try{
  const body=await request.json();
  if(new URL(request.url).pathname==='/retention')return Response.json(await executeRetentionTask(env,{...body.actor,permissions:new Set(body.actor.permissions)},body.input));
  const controls=(await env.DB.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND (name GLOB 'privacy_retention_*' OR name='auth_identity_rate_aliases') ORDER BY name").all()).results.map(r=>r.name);
  validateRecoveryQuarantinePlan(body.plan,controls);
  const statements=body.plan.statements.map(s=>env.DB.prepare(s.sql).bind(...s.params));
  if(request.headers.get('x-test-failure')==='after-marker')statements.splice(statements.length-1,0,env.DB.prepare("INSERT INTO admin_bridge_guards(id,passed) VALUES('controlled-invalid',0)"));
  await env.DB.batch(statements);return Response.json({single_D1_batch:true});
 }catch(error){return Response.json({code:error.code??'batch_failed',detail:String(error.message)}, {status:error.status??409});}}};`;
 const mf=new Miniflare((convertV4MiniflareOptions??(v=>v))({modules:[{type:'ESModule',path:fileURLToPath(new URL('scripts/tests/recovery_d1_entry.mjs',project)),contents:entry},...await Promise.all(moduleNames.map(async name=>({type:'ESModule',path:fileURLToPath(new URL(name,project)),contents:await readFile(new URL(name,project),'utf8')})))],modulesRoot:fileURLToPath(project),compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,bindings:{APP_ENVIRONMENT:'test',BUILD_SOURCE_ID:sourceId},outboundService:()=>{throw new Error('No provider sends allowed in recovery tests');}}));t.after(()=>mf.dispose());
 const db=await mf.getD1Database('DB'),require=createRequire(new URL('../../deploy/platform-api/package.json',import.meta.url)),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
 const importSql=async sql=>db.batch(unstable_splitSqlQuery(sql).map(s=>db.prepare(s)));
 const call=async(path,body,headers={})=>{const response=await mf.dispatchFetch('https://isolated-recovery.example'+path,{method:'POST',headers:{'content-type':'application/json',...headers},body:JSON.stringify(body)});return {status:response.status,body:await response.json()};};
 return {db,call,importSql};
}

test('actual D1 quarantine is atomic, drains only transient guards and fences restored retention claims',async t=>{
 const c=await candidateFixture(t),d=await recoveryD1(t,c),sql=Buffer.from(c.payload.files['database.sql'].base64,'base64').toString();await d.importSql(sql);
 const before=await d1Fingerprint(d.db),plan=recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt,schemaProfile:'candidate10'});
 const failed=await d.call('/apply',{plan},{'x-test-failure':'after-marker'});assert.equal(failed.status,409);assert.deepEqual(await d1Fingerprint(d.db),before,'the full D1 batch including sequence/marker rolls back');
 const applied=await d.call('/apply',{plan});assert.equal(applied.status,200,JSON.stringify(applied.body));const after=await d1Fingerprint(d.db);assert.equal(after.schema_sha256,before.schema_sha256);for(const name of [...retainedControls,'ledger_entries','payment_evidence','upload_objects','support_requests','privacy_submissions','auth_mfa_claims'])assert.deepEqual(after.tables[name],before.tables[name],name);assert.equal(before.tables.privacy_retention_guards.count,1);assert.equal(after.tables.privacy_retention_guards.count,0);
 assert.equal((await d.db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE revoked_at IS NULL').first()).n,0);assert.equal((await d.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);assert.equal((await d.db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,0);
 const replay=await d.call('/apply',{plan});assert.equal(replay.status,200);assert.deepEqual(await d1Fingerprint(d.db),after);const wrong=recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt,schemaProfile:'candidate10',archiveSha256:'b'.repeat(64)});assert.equal((await d.call('/apply',{plan:wrong})).status,409);assert.deepEqual(await d1Fingerprint(d.db),after);
 // Historical authentication timestamps stay exact. Once their real five-
 // minute assurance expires, that earlier gate must deny replay; a fresh
 // current11 fixture separately proves live revoked-session denial below.
 const expired=Math.floor(Date.now()/1000)-c.actor.authAt>300||Math.floor(Date.now()/1000)-c.actor.mfaAt>300;
 const oldClaim=await d.call('/retention',{actor:c.actor,input:{operation_id:randomUUID(),claim_id:c.objectClaim.claim_id,fence:c.objectClaim.fence}});assert.equal(oldClaim.status,403,JSON.stringify(oldClaim.body));assert.equal(oldClaim.body.code,expired?'privacy_retention_mfa_required':'privacy_retention_authority_changed');assert.deepEqual(await d1Fingerprint(d.db),after);
 await assert.rejects(d.db.prepare("UPDATE users SET access_status='active' WHERE id=?").bind(c.subject).run(),/privacy_retention_access_quarantined/);await assert.rejects(d.db.prepare("UPDATE support_requests SET message='SHOULD NOT WRITE' WHERE user_id=?").bind(c.subject).run(),/privacy_retention_write_barrier/);
 await saveEvidence('actual-d1-quarantine.json',{actual_Worker_D1_batch:true,rollback_before_and_after_exact:true,exact_replay_unchanged:true,old_claim_status:oldClaim.status,old_claim_code:oldClaim.body.code,before,after,all_retained_control_rows_unchanged:true,transient_guards_drained:true,barriers_released:false,policy_repinned:false,full_system_recovery_accepted:false,remote_execution:false});
});

test('actual D1 deferred batches enforce foreign keys and preserve restored schema/data on rejection',async t=>{
 const c=await candidateFixture(t),d=await recoveryD1(t,c),sql=Buffer.from(c.payload.files['database.sql'].base64,'base64').toString();await d.importSql(sql);
 assert.equal((await d.db.prepare('PRAGMA foreign_keys').first()).foreign_keys,1);
 // The same deferred batch accepts a real referenced session. Only the
 // dangling reference differs in the failure case. workerd may expose its
 // commit-time constraint error as an opaque internal reference; that text
 // is not the contract. Exact rollback and enforced FKs are the assertion.
 await d.db.batch([d.db.prepare('PRAGMA defer_foreign_keys=ON'),d.db.prepare('INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at) VALUES(?,?,1,2)').bind(sha(Buffer.from('valid-fk-control')),c.actor.sessionId)]);
 const before=await d1Fingerprint(d.db);let rejected;
 await assert.rejects(d.db.batch([d.db.prepare('PRAGMA defer_foreign_keys=ON'),d.db.prepare('CREATE TABLE test_fk_rollback_marker(id TEXT)'),d.db.prepare("INSERT INTO test_fk_rollback_marker VALUES('must-rollback')"),d.db.prepare('INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at) VALUES(?,?,1,2)').bind(sha(Buffer.from('invalid-fk-control')),'missing-session')]),error=>{rejected=String(error.message);return true;});
 assert.deepEqual(await d1Fingerprint(d.db),before);assert.equal((await d.db.prepare('PRAGMA foreign_keys').first()).foreign_keys,1);
 await saveEvidence('actual-d1-foreign-keys.json',{actual_D1_deferred_batch:true,foreign_keys_enabled_before_and_after:true,valid_reference_accepted:true,dangling_reference_rejected:true,whole_schema_and_data_rollback_verified:true,diagnostic:rejected,full_system_recovery_accepted:false});
});

test('historical11 generated Worker state seals exact identity roles and independently restores populated cyclic MFA and 84 retention tasks',async t=>{
 const c=await identityFixture(t),dir=await realpath(await mkdtemp(join(tmpdir(),'collect-identity-recovery-seal-')));t.after(()=>rm(dir,{recursive:true,force:true}));await mkdir(join(dir,'migrations'),{mode:0o700});
 for(const [name,value]of Object.entries(c.payload.files))await writeFile(join(dir,name),Buffer.from(value.base64,'base64'),{mode:0o600});
 const out=join(dir,'sealed');await main(['seal','--sql',join(dir,'database.sql'),'--config',join(dir,'wrangler.json'),'--secrets',join(dir,'worker-secrets.json'),'--out',out]);
 const raw=await readFile(join(out,'platform-backup.json')),key=Buffer.from((await readFile(join(out,'recovery-key.base64'),'utf8')).trim(),'base64'),restored=unseal(JSON.parse(raw),key),receipt=JSON.parse(await readFile(join(out,'receipt.json')));assert.deepEqual(restored.files,c.payload.files);assert.deepEqual(receipt.worker_secret_roles,['AUTH_JWT_SECRET','AUTH_TOKEN_HASH_SECRET','DATA_ENCRYPTION_KEY','TURNSTILE_SECRET','AUTH_IDENTITY_HASH_KEY','AUTH_IDENTITY_PREVIOUS_KEYS_JSON'].sort());assert.equal(receipt.archive_sha256,sha(raw));for(const value of [identityBindings.AUTH_IDENTITY_HASH_KEY,identityBindings.AUTH_IDENTITY_PREVIOUS_KEYS_JSON]){assert.ok(!JSON.stringify(receipt).includes(value));assert.ok(!raw.toString().includes(value));}
 const common=['--archive',join(out,'platform-backup.json'),'--key',join(out,'recovery-key.base64')],prepared=join(dir,'prepared'),at=new Date(Math.ceil(Date.now()/1000)*1000).toISOString();await main(['prepare-quarantine',...common,'--operation',randomUUID(),'--at',at,'--out',prepared]);
 const preparation=JSON.parse(await readFile(join(prepared,'preparation.json')));assert.equal(preparation.schema_profile,'candidate11');assert.equal(preparation.identity_alias_history_retained,true);assert.equal(preparation.identity_key_configuration_recovered,true);assert.equal(preparation.subject_retention_barriers_released,false);assert.equal(preparation.retention_policy_repinned,false);assert.equal(preparation.production_cutover_accepted,false);
 await main(['verify-quarantine-readback',...common,'--plan',join(prepared,'quarantine-plan.json'),'--sql',join(prepared,'quarantined-restore.sql'),'--out',join(dir,'readback')]);const readback=JSON.parse(await readFile(join(dir,'readback/verification.json')));assert.equal(readback.schema_profile,'candidate11');assert.equal(readback.table_count,75);assert.equal(readback.full_system_recovery_accepted,false);
 const runtime=process.env.COLLECT_WRANGLER_MODULE??fileURLToPath(new URL('../../deploy/platform-api/node_modules/wrangler',import.meta.url)),local=join(dir,'actual-local-d1');await main(['verify-local',...common,'--wrangler',runtime,'--out',local]);const verified=JSON.parse(await readFile(join(local,'verification.json')));assert.equal(verified.actual_local_D1_import,true);assert.equal(verified.restore_mode,'single_D1_batch_with_deferred_foreign_keys');assert.equal(verified.foreign_keys_disabled,false);assert.equal(verified.all_table_rows_and_schema_match,true);assert.equal(verified.all_indexes_triggers_and_views_match,true);assert.equal(verified.foreign_key_errors,0);assert.equal(verified.tables.privacy_retention_tasks,84);assert.ok(verified.tables.auth_identity_rate_aliases>=6);for(const name of controls)assert.equal(verified.tables[name],c.counts[name],name);
 await saveEvidence('candidate11-seal-local-restore.json',{synthetic_test_only:true,actual_seal_CLI_receipt:true,exact_private_bytes_authenticated:true,receipt,preparation,readback,local_restore:verified,source_database_sql_sha256:c.payload.files['database.sql'].sha256,identity_validator_sha256:quarantineSchemaProfiles.candidate11.identityValidatorSha256,local_import_log_sha256:sha(await readFile(join(local,'local-import.log'))),no_hosted11_execution:true,full_system_recovery_accepted:false});
});

test('candidate11 actual D1 batch preserves current/previous/legacy aliases, all immutable controls and financial net through rollback and replay',async t=>{
 const c=await identityFixture(t),d=await recoveryD1(t,c);await d.importSql(Buffer.from(c.payload.files['database.sql'].base64,'base64').toString());const before=await d1Fingerprint(d.db),plan=recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt,schemaProfile:'candidate11'});
 assert.equal((await d.db.prepare('PRAGMA foreign_keys').first()).foreign_keys,1);assert.equal(before.tables.privacy_retention_tasks.count,84);assert.ok(before.tables.auth_identity_rate_aliases.count>=6);const aliasRows=(await d.db.prepare('SELECT * FROM auth_identity_rate_aliases ORDER BY request_id,identity_key_id').all()).results;
 assert.deepEqual([...new Set(aliasRows.map(r=>r.identity_key_id))].sort(),['legacy-token-hash-v1','recovery-current-v2','recovery-old-v1']);
 const failed=await d.call('/apply',{plan},{'x-test-failure':'after-marker'});assert.equal(failed.status,409);assert.deepEqual(await d1Fingerprint(d.db),before,'every row, schema and sequence rolls back');
 const wrong=recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt,schemaProfile:'candidate10'});assert.equal((await d.call('/apply',{plan:wrong})).status,409);assert.deepEqual(await d1Fingerprint(d.db),before);
 assert.equal((await d.call('/apply',{plan})).status,200);const after=await d1Fingerprint(d.db);assert.equal(after.schema_sha256,before.schema_sha256);for(const name of [...retainedControls,'auth_identity_rate_aliases','auth_rate_claims','auth_otp_throttles','ledger_entries','payment_evidence','upload_objects','support_requests','privacy_submissions','auth_mfa_claims'])assert.deepEqual(after.tables[name],before.tables[name],name);assert.equal(after.tables.privacy_retention_guards.count,0);
 assert.equal((await d.db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE revoked_at IS NULL').first()).n,0);assert.equal((await d.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);assert.equal((await d.db.prepare("SELECT count(*) AS n FROM auth_mfa_factors WHERE status!='revoked'").first()).n,0);assert.equal((await d.db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,0);
 assert.deepEqual((await d.db.prepare('SELECT * FROM auth_identity_rate_aliases ORDER BY request_id,identity_key_id').all()).results,aliasRows);await assert.rejects(d.db.prepare("UPDATE auth_identity_rate_aliases SET identity_key_id='changed'").run(),/auth_identity_alias_immutable/);await assert.rejects(d.db.prepare('DELETE FROM auth_identity_rate_aliases').run(),/auth_identity_alias_immutable/);await assert.rejects(d.db.prepare("UPDATE auth_rate_claims SET identity_key_id='changed'").run(),/auth_identity_history_immutable/);await assert.rejects(d.db.prepare("UPDATE auth_otp_challenges SET identity_key_id='changed'").run(),/auth_identity_history_immutable/);
 assert.equal((await d.call('/apply',{plan})).status,200);assert.deepEqual(await d1Fingerprint(d.db),after);const oldClaim=await d.call('/retention',{actor:c.actor,input:{operation_id:randomUUID(),claim_id:c.objectClaim.claim_id,fence:c.objectClaim.fence}});assert.equal(oldClaim.status,403);assert.equal(oldClaim.body.code,Math.floor(Date.now()/1000)-c.actor.authAt>300||Math.floor(Date.now()/1000)-c.actor.mfaAt>300?'privacy_retention_mfa_required':'privacy_retention_authority_changed');assert.deepEqual(await d1Fingerprint(d.db),after);
 await assert.rejects(d.db.prepare("UPDATE users SET access_status='active' WHERE id=?").bind(c.subject).run(),/privacy_retention_access_quarantined/);await assert.rejects(d.db.prepare("UPDATE support_requests SET message='MUST NOT WRITE' WHERE user_id=?").bind(c.subject).run(),/privacy_retention_write_barrier/);
 await saveEvidence('candidate11-actual-d1-quarantine.json',{actual_Worker_D1_batch:true,synthetic_test_only:true,before,after,identity_alias_rows:aliasRows.length,alias_key_ids:[...new Set(aliasRows.map(r=>r.identity_key_id))].sort(),immutable_alias_and_key_labels_enforced:true,rollback_all_rows_schema_sequence_exact:true,wrong10_profile_rejected:true,exact_replay_unchanged:true,old_claim_status:oldClaim.status,old_claim_code:oldClaim.body.code,all_retained_controls_and_financial_rows_unchanged:true,transient_guards_drained:true,barriers_released:false,policy_repinned:false,remote_execution:false,full_system_recovery_accepted:false});
});

for(const defect of ['changed identity migration','unreviewed12 migration','missing alias trigger','missing identity column','extra identity table','wrong eleven profile on ten'])test('candidate11 schema quarantine refuses '+defect,async t=>{
 const c=await candidateFixture(t),f=await identityConfigPayload();let p=f.commit();
 if(defect==='changed identity migration')replacePrivateRole(p,'migrations/0011_auth_identity_keys.sql',Buffer.from(p.files['migrations/0011_auth_identity_keys.sql'].base64,'base64').toString()+'\n-- changed');
 if(defect==='unreviewed12 migration')replacePrivateRole(p,'migrations/0012_unreviewed.sql','CREATE TABLE unknown_future_credentials(id TEXT);');
 if(defect==='missing alias trigger')replacePrivateRole(p,'database.sql',Buffer.from(p.files['database.sql'].base64,'base64').toString()+'DROP TRIGGER auth_identity_alias_no_delete;');
 if(defect==='missing identity column')replacePrivateRole(p,'database.sql',Buffer.from(c.payload.files['database.sql'].base64,'base64'));
 if(defect==='extra identity table')replacePrivateRole(p,'database.sql',Buffer.from(p.files['database.sql'].base64,'base64').toString()+'CREATE TABLE auth_identity_unreviewed(id TEXT);');
 if(defect==='wrong eleven profile on ten'){const db=capturedDb(c);try{const before=restoreSql(db);assert.throws(()=>applyRecoveryQuarantine(db,recoveryQuarantinePlan({...identity,createdAt:c.recoveryAt,schemaProfile:'candidate11'})),/restored control schema/);assert.equal(restoreSql(db),before);}finally{db.close();}return;}
 // Configured identity keys require an exact reviewed schema even at sealing;
 // a changed/future migration is refused before an archive can be produced.
 if(defect==='changed identity migration'||defect==='unreviewed12 migration'){await assert.rejects(candidateArchive(t,{...c,payload:p}),/Identity key recovery requires the exact qualified candidate11/);return;}
 const a=await candidateArchive(t,{...c,payload:p});await assert.rejects(main(['prepare-quarantine',...a.common,'--operation',randomUUID(),'--at',c.recoveryAt,'--out',join(a.dir,'denied')]),/qualified.*schema|catalog differs|Identity.key recovery/);await assert.rejects(access(join(a.dir,'denied')));
});
