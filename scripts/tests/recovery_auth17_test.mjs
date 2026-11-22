import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {readFile,mkdtemp,writeFile,realpath,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {seal,unseal,validatePayload,installSql,restoreSql,main} from '../cloudflare/platform_backup.mjs';
import {quarantineSchemaProfiles,recoveryQuarantinePlan,applyRecoveryQuarantine} from '../cloudflare/recovery_quarantine.mjs';

// Synthetic-only fixtures: no provider credential or private production input.
const sha=v=>createHash('sha256').update(v).digest('hex'),api=new URL('../../deploy/platform-api/',import.meta.url);
const database='a6a0d284-c445-4fe3-8e64-af5fd42491ae',source='f'.repeat(64),date='2026-10-19T00:00:00.000Z';
const identity={archiveSha256:'a'.repeat(64),sourceId:source,operationId:'00000000-0000-4000-8000-000000000003',createdAt:'2026-10-19T18:00:00.000Z',schemaProfile:'candidate17'};
const core={AUTH_JWT_SECRET:'synthetic-recovery-jwt-'.repeat(3),AUTH_TOKEN_HASH_SECRET:'synthetic-recovery-hash-'.repeat(3),DATA_ENCRYPTION_KEY:Buffer.alloc(32,9).toString('base64')};
const googleSecret='synthetic-google-secret-not-provider-key',relaySecret='synthetic-relay-secret-not-provider-key';
const enabled={GOOGLE_AUTH_ENABLED:'true',GOOGLE_CLIENT_ID:'synthetic.apps.googleusercontent.com',GOOGLE_REDIRECT_URI:'https://api.collect.ikanisa.com/v1/auth/google/callback'};
const role=(p,n)=>JSON.parse(Buffer.from(p.files[n].base64,'base64'));
function replace(p,n,v){const b=Buffer.from(typeof v==='string'?v:JSON.stringify(v));p.files[n]={sha256:sha(b),bytes:b.length,base64:b.toString('base64')};}
async function fixture({vars={},keys={}}={}){
 const db=new DatabaseSync(':memory:'),files={};
 try{
  for(const [name,pin]of Object.entries(quarantineSchemaProfiles.candidate17.digests)){const b=await readFile(new URL(name,api));assert.equal(sha(b),pin);files[name]=b;db.exec(b.toString());}
  const user=randomUUID(),admin=randomUUID(),session=randomUUID();
  db.prepare('INSERT INTO users(id,email,public_id,created_at,updated_at) VALUES(?,?,?,?,?)').run(user,'synthetic@example.test','123456',date,date);
  db.prepare("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,'staff','active','email-otp-only',1,1)").run(admin,'synthetic@example.test');
  db.prepare('INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(?,?,?,?)').run(admin,user,'synthetic-owner-review',date);
  db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',1,1,3000000000)").run(session,user);
  db.prepare('INSERT INTO auth_google_identities(subject,user_id,created_at) VALUES(?,?,?)').run('synthetic-google-subject',user,date);
  for(const status of ['pending','exchanging','ready','consumed','failed'])db.prepare(`INSERT INTO auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,registration_allowed,created_at,expires_at,status,consumed_operation_id) VALUES(?,?,?,?,?,?,1,1,3000000000,?,?)`).run(randomUUID(),sha(status),'synthetic-nonce','{}','x'.repeat(43),'synthetic-state',status,status==='consumed'?randomUUID():null);
  let at=1;for(const status of ['pending','accepted','unknown','failed','superseded','consumed'])db.prepare(`INSERT INTO admin_email_otp_challenges(id,user_id,principal_user_id,origin,role,auth_version,challenge_version,account_status,code_hash,created_at,expires_at,delivery_status,used_at,consumed_session_id) VALUES(?,?,?,'https://platform-admin.collect.ikanisa.com','staff',1,0,'active',?,?,3000000000,?,?,?)`).run(randomUUID(),admin,user,sha('synthetic-code-'+status),at+=61,status==='consumed'?'accepted':status,status==='consumed'?10:null,status==='consumed'?session:null);
  files['database.sql']=restoreSql(db);files['wrangler.json']=JSON.stringify({name:'collect-platform-api',d1_databases:[{binding:'DB',database_name:'collect-platform',database_id:database}],vars:{BUILD_SOURCE_ID:source,DATA_KEY_ID:'synthetic-v1',...vars}});files['worker-secrets.json']=JSON.stringify({...core,...keys});
  return {format:'collect.platform.backup.v1',database_id:database,source_id:source,captured_at:'2026-10-19T01:00:00.000Z',files:Object.fromEntries(Object.entries(files).map(([n,v])=>{const b=Buffer.from(v);return[n,{sha256:sha(b),bytes:b.length,base64:b.toString('base64')}];}))};
 }finally{db.close();}
}

test('exact17 seals provider roles and native email adds no private role',async()=>{
 for(const config of [{},{vars:enabled,keys:{GOOGLE_CLIENT_SECRET:googleSecret}},{vars:{OTP_DELIVERY_URL:'https://relay.collect.example/send'},keys:{OTP_DELIVERY_TOKEN:relaySecret}},{vars:{...enabled,OTP_DELIVERY_URL:'https://relay.collect.example/send'},keys:{GOOGLE_CLIENT_SECRET:googleSecret,OTP_DELIVERY_TOKEN:relaySecret}}]){const p=await fixture(config),key=randomBytes(32);assert.deepEqual(unseal(seal(p,key),key),p);assert.deepEqual(Object.keys(JSON.parse(validatePayload(p)['worker-secrets.json'])).sort(),Object.keys({...core,...config.keys}).sort());}
});
for(const defect of ['missing Google secret','short Google secret','public Google secret','wrong callback','missing client','missing relay token','insecure relay','orphan relay token','future migration','changed0017','old profile'])test('provider recovery refuses '+defect,async()=>{
 const p=await fixture({vars:enabled,keys:{GOOGLE_CLIENT_SECRET:googleSecret}}),config=role(p,'wrangler.json'),keys=role(p,'worker-secrets.json');
 if(defect==='missing Google secret')delete keys.GOOGLE_CLIENT_SECRET;
 if(defect==='short Google secret')keys.GOOGLE_CLIENT_SECRET='short';
 if(defect==='public Google secret')config.vars.GOOGLE_CLIENT_SECRET=googleSecret;
 if(defect==='wrong callback')config.vars.GOOGLE_REDIRECT_URI='https://api.collect.ikanisa.com/wrong';
 if(defect==='missing client')delete config.vars.GOOGLE_CLIENT_ID;
 if(defect==='missing relay token')config.vars.OTP_DELIVERY_URL='https://relay.collect.example/send';
 if(defect==='insecure relay'){config.vars.OTP_DELIVERY_URL='http://relay.collect.example/send';keys.OTP_DELIVERY_TOKEN=relaySecret;}
 if(defect==='orphan relay token')keys.OTP_DELIVERY_TOKEN=relaySecret;
 if(defect==='future migration')replace(p,'migrations/0018_future.sql','-- future credential schema');
 if(defect==='changed0017')replace(p,'migrations/0017_admin_email_otp.sql','-- changed source');
 if(defect==='old profile'){delete p.files['migrations/0017_admin_email_otp.sql'];delete p.files['migrations/0016_google_auth.sql'];}
 replace(p,'wrangler.json',config);replace(p,'worker-secrets.json',keys);assert.throws(()=>validatePayload(p),e=>!e.message.includes(googleSecret)&&!e.message.includes(relaySecret));
});

test('auth17 quarantines pending credentials, retains consumed history and subject links, retries exactly',async()=>{
 const p=await fixture(),db=new DatabaseSync(':memory:');try{
  db.exec('BEGIN');installSql(db,Buffer.from(p.files['database.sql'].base64,'base64').toString());db.exec('COMMIT');
  const links=db.prepare('SELECT * FROM auth_google_identities').all(),consumed=db.prepare("SELECT * FROM auth_google_flows WHERE status='consumed'").all(),used=db.prepare('SELECT * FROM admin_email_otp_challenges WHERE used_at IS NOT NULL').all();
  assert.throws(()=>applyRecoveryQuarantine(db,recoveryQuarantinePlan({...identity,schemaProfile:'candidate15'})),/profile differs/);
  const plan=recoveryQuarantinePlan(identity);applyRecoveryQuarantine(db,plan);
  assert.equal(db.prepare("SELECT count(*) AS n FROM auth_google_flows WHERE status IN('pending','exchanging','ready')").get().n,0);
  assert.equal(db.prepare("SELECT count(*) AS n FROM admin_email_otp_challenges WHERE used_at IS NULL AND delivery_status IN('pending','accepted','unknown')").get().n,0);
  assert.deepEqual(db.prepare('SELECT * FROM auth_google_identities').all(),links);assert.deepEqual(db.prepare("SELECT * FROM auth_google_flows WHERE status='consumed'").all(),consumed);assert.deepEqual(db.prepare('SELECT * FROM admin_email_otp_challenges WHERE used_at IS NOT NULL').all(),used);
  assert.equal(db.prepare('SELECT access_status FROM users').get().access_status,'suspended');assert.equal(db.prepare('SELECT status FROM admin_users').get().status,'revoked');const before=restoreSql(db);applyRecoveryQuarantine(db,plan);assert.equal(restoreSql(db),before);
  assert.throws(()=>applyRecoveryQuarantine(db,recoveryQuarantinePlan({...identity,archiveSha256:'b'.repeat(64)})),/admin_bridge_state/);assert.equal(db.prepare('PRAGMA foreign_key_check').all().length,0);
 }finally{db.close();}
});

test('exact17 authenticated offline preparation and readback omit provider secrets from receipts',async()=>{
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-auth17-offline-')));try{
  const p=await fixture({vars:enabled,keys:{GOOGLE_CLIENT_SECRET:googleSecret}}),key=randomBytes(32),archive=join(dir,'archive.json'),keyPath=join(dir,'key.base64'),out=join(dir,'prepared');await writeFile(archive,JSON.stringify(seal(p,key)),{mode:0o600});await writeFile(keyPath,key.toString('base64'),{mode:0o600});const common=['--archive',archive,'--key',keyPath];
  await main(['prepare-quarantine',...common,'--operation',identity.operationId,'--at',identity.createdAt,'--out',out]);const receipt=JSON.parse(await readFile(join(out,'preparation.json')));assert.equal(receipt.schema_profile,'candidate17');assert.equal(receipt.google_pending_handoffs_disabled,true);assert.equal(receipt.full_system_recovery_accepted,false);assert.ok(!JSON.stringify(receipt).includes(googleSecret));
  await main(['verify-quarantine-readback',...common,'--plan',join(out,'quarantine-plan.json'),'--sql',join(out,'quarantined-restore.sql'),'--out',join(dir,'verified')]);const verified=JSON.parse(await readFile(join(dir,'verified/verification.json')));assert.equal(verified.authenticated_quarantined_snapshot_match,true);assert.equal(verified.production_cutover_accepted,false);assert.ok(verified.worker_secret_roles.includes('GOOGLE_CLIENT_SECRET'));assert.ok(!JSON.stringify(verified).includes(googleSecret));
 }finally{await rm(dir,{recursive:true,force:true});}
});

test('actual isolated D1 auth17 quarantine rolls back on failure and retires restored handoff authority once',{skip:!process.env.COLLECT_MINIFLARE_MODULE||!process.env.COLLECT_WRANGLER_MODULE},async t=>{
 const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE),{createRequire}=await import('node:module'),require=createRequire(import.meta.url),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE);const contents=await readFile(new URL('../cloudflare/recovery_quarantine.mjs',import.meta.url),'utf8');
 const worker=`import {validateRecoveryQuarantinePlan} from './recovery_quarantine.mjs'; export default {async fetch(request,env){try{const body=await request.json();const controls=(await env.DB.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND (name GLOB 'privacy_retention_*' OR name='auth_identity_rate_aliases' OR name GLOB 'assisted_sms_*' OR name GLOB 'momo_*' OR name='contribution_posting_snapshots' OR name IN('auth_google_flows','auth_google_identities','admin_email_otp_challenges')) ORDER BY name").all()).results.map(v=>v.name);validateRecoveryQuarantinePlan(body.plan,controls);const statements=body.plan.statements.map(s=>env.DB.prepare(s.sql).bind(...s.params));if(body.fail)statements.splice(statements.length-1,0,env.DB.prepare("INSERT INTO admin_bridge_guards(id,passed) VALUES('controlled-failure',0)"));await env.DB.batch(statements);return Response.json({ok:true});}catch{return Response.json({ok:false},{status:409});}}};`;
 const mf=new Miniflare((convertV4MiniflareOptions??(v=>v))({modules:[{type:'ESModule',path:'/auth17/worker.js',contents:worker},{type:'ESModule',path:'/auth17/recovery_quarantine.mjs',contents}],modulesRoot:'/auth17',compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,outboundService:()=>{throw new Error('Recovery test cannot send');}}));t.after(()=>mf.dispose());const db=await mf.getD1Database('DB'),p=await fixture();await db.batch(unstable_splitSqlQuery(Buffer.from(p.files['database.sql'].base64,'base64').toString()).map(sql=>db.prepare(sql)));const call=async(plan,fail=false)=>mf.dispatchFetch('https://synthetic-auth17-recovery.example/quarantine',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({plan,fail})});
 assert.equal((await call(recoveryQuarantinePlan({...identity,schemaProfile:'candidate15'}))).status,409);const links=(await db.prepare('SELECT * FROM auth_google_identities').all()).results,used=(await db.prepare('SELECT * FROM admin_email_otp_challenges WHERE used_at IS NOT NULL').all()).results,plan=recoveryQuarantinePlan(identity);
 assert.equal((await call(plan,true)).status,409);assert.equal((await db.prepare('SELECT access_status FROM users').first()).access_status,'active');assert.equal((await db.prepare("SELECT count(*) AS n FROM auth_google_flows WHERE status IN('pending','exchanging','ready')").first()).n,3);assert.equal((await db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='recovery.access.quarantined'").first()).n,0);
 assert.equal((await call(plan)).status,200);assert.equal((await call(plan)).status,200);assert.equal((await db.prepare("SELECT count(*) AS n FROM auth_google_flows WHERE status IN('pending','exchanging','ready')").first()).n,0);assert.equal((await db.prepare("SELECT count(*) AS n FROM admin_email_otp_challenges WHERE used_at IS NULL AND delivery_status IN('pending','accepted','unknown')").first()).n,0);assert.deepEqual((await db.prepare('SELECT * FROM auth_google_identities').all()).results,links);assert.deepEqual((await db.prepare('SELECT * FROM admin_email_otp_challenges WHERE used_at IS NOT NULL').all()).results,used);assert.equal((await db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='recovery.access.quarantined'").first()).n,1);assert.equal((await db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
});
