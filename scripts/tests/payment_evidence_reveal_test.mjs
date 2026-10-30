import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {test} from '../../supabase/functions/_shared/tests/helpers/fenced-node-test.js';
import {fixtureEnvironment} from '../../supabase/functions/_shared/tests/helpers/fenced-unit.js';
import {evidenceRoute} from '../../supabase/functions/_shared/domain/evidence.js';
import {evidenceSensitivitySql,evidenceSensitivity} from '../../supabase/functions/_shared/domain/evidence_provenance.js';
import {evidenceMetadataSql,evidenceMetadata} from '../../supabase/functions/_shared/domain/admin_records.js';
import {adminAccountSession,adminCanonicalActor,adminInternalRequest,accountDatabase} from '../../supabase/functions/_shared/domain/admin_accounts.js';
import {encrypt} from '../../supabase/functions/_shared/domain/encryption.js';
import {ApiError,digest} from '../../supabase/functions/_shared/domain/core.js';

// Actual route, crypto, BFF/session/email-policy and transactional guard builders.
// SQLite executes the shared classification SQL. The remaining PostgreSQL/Auth/
// private-object I/O is an explicit synthetic model; no hosted call is allowed.
const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`;
const IDS={principal:id(1),session:id(2),evidence:id(3),managed:id(4),account:id(5),public:id(6),proof:id(7),payment:id(8),group:id(9)};
const BODY='SYNTHETIC original SMS financial source. Never real personal information.';
const required=['payments.evidence.read','sms.read','sms.reveal'];
const failure=(code,status)=>error=>error instanceof ApiError&&(!code||error.code===code)&&(!status||error.status===status);

async function fixture({kind='raw_sms',grants=required,emailAge=1,bodyText=null}={}){
 const at=Math.floor(Date.now()/1000),origin='https://admin.synthetic.invalid',cookie='a'.repeat(64),tokenHash=await digest(cookie);
 const state={grants:new Set(grants),emailAt:emailAge===null?null:at-emailAge,active:true,role:'admin',authVersion:1,objectReads:0,audits:[],batches:[],networkCalls:0,providerModelCalls:0,committed:true,tombstone:false};
 const sql=new DatabaseSync(':memory:');
 sql.exec(`CREATE TABLE payment_evidence(id TEXT PRIMARY KEY,collection_id TEXT,owner_user_id TEXT,object_key TEXT,object_sha256 TEXT,size_bytes INTEGER,content_type TEXT,authenticity TEXT,amount_minor INTEGER,currency TEXT,external_reference TEXT,observed_at TEXT,created_at TEXT,retained_until TEXT,legal_hold INTEGER);
 CREATE TABLE payments(id TEXT PRIMARY KEY,collection_id TEXT,evidence_id TEXT,amount_minor INTEGER);
 CREATE TABLE momo_financial_links(payment_id TEXT);
 CREATE TABLE sms_receipts(body_sha256 TEXT);
 CREATE TABLE request_receipts(user_id TEXT,operation TEXT,response_json TEXT);`);
 const body=bodyText??(kind==='manual'?'SYNTHETIC manually recorded cash deposit receipt. No SMS source.':BODY);
 const payload=new TextEncoder().encode(body),sha=await digest(payload),stamp=new Date().toISOString();
 const row={id:IDS.evidence,collection_id:IDS.group,owner_user_id:IDS.principal,object_key:'evidence/'+IDS.evidence,object_sha256:sha,size_bytes:payload.length,content_type:'text/plain',authenticity:'operator_recorded',amount_minor:500,currency:'RWF',external_reference:'synthetic',observed_at:stamp,created_at:stamp,retained_until:null,legal_hold:0};
 sql.prepare(`INSERT INTO payment_evidence VALUES(${Object.keys(row).map(()=>'?').join(',')})`).run(...Object.values(row));
 sql.prepare('INSERT INTO payments VALUES(?,?,?,?)').run(IDS.payment,IDS.group,IDS.evidence,500);
 const receipt={id:IDS.payment,evidence_id:IDS.evidence,evidence_level:'operator_recorded',amount_minor:500,currency:'RWF'};
 const manual=()=>sql.prepare('INSERT INTO request_receipts VALUES(?,?,?)').run(IDS.principal,'payment.record',JSON.stringify(receipt));
 if(kind==='raw_sms')sql.prepare('INSERT INTO momo_financial_links VALUES(?)').run(IDS.payment);
 if(kind==='manual')manual();
 state.scope={ownerId:IDS.principal,purpose:'payment_evidence',entityId:IDS.evidence};
 const classify=()=>sql.prepare(`SELECT ${evidenceSensitivitySql} AS sensitivity FROM payment_evidence e WHERE id=?`).get(IDS.evidence)?.sensitivity;
 const currentRow=()=>({...sql.prepare('SELECT * FROM payment_evidence WHERE id=?').get(IDS.evidence)});
 const accountRow=()=>({id:IDS.account,email:'synthetic@example.invalid',role:state.role,status:'active',auth_version:state.authVersion,principal_id:IDS.principal,auth_user_id:IDS.managed,auth_session_id:IDS.session,token_hash:tokenHash,public_id:IDS.public,origin,expires_at:at+3600,issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,auth_at:at-3600,assurance_level:1,mfa_at:null,mfa_factor_id:null});
 const session=()=>({id:IDS.session,user_id:IDS.principal,surface:'admin',auth_at:at-3600,assurance_level:1,mfa_at:null,mfa_factor_id:null,expires_at:at+3600,revoked_at:state.active?null:at});
 const claims={sub:IDS.managed,session_id:IDS.session,aal:'aal1',role:'authenticated',aud:'authenticated',iat:at,exp:at+3600,iss:'https://auth.synthetic.invalid/auth/v1'};
 const token=btoa(JSON.stringify({alg:'ES256'}))+'.'+btoa(JSON.stringify(claims))+'.synthetic';
 const user={id:IDS.managed,email:'synthetic@example.invalid',email_confirmed_at:stamp};
 const env=fixtureEnvironment({ADMIN_ORIGIN:origin,SUPABASE_URL:'https://auth.synthetic.invalid',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',DATA_KEY_ID:'synthetic',DATA_ENCRYPTION_KEY:Buffer.alloc(32,17).toString('base64'),SESSION_KEY_ID:'synthetic-bff',SESSION_ENCRYPTION_KEY:Buffer.alloc(32,19).toString('base64')});
 const cipher=await encrypt(env,payload,`evidence:${IDS.evidence}:${sha}`);
 const bffCipher=await encrypt({...env,DATA_KEY_ID:env.SESSION_KEY_ID,DATA_ENCRYPTION_KEY:env.SESSION_ENCRYPTION_KEY},new TextEncoder().encode(JSON.stringify({access_token:token,refresh_token:'synthetic-refresh'})),`bff:${IDS.session}:${IDS.managed}`);
 const modelFetch=async(input,init)=>{
  const request=new Request(input,init);
  assert.equal(request.url,env.SUPABASE_URL+'/auth/v1/user','No network/provider call beyond the in-process Auth model');
  assert.equal(request.headers.get('Authorization'),'Bearer '+token);state.providerModelCalls++;
  return state.active?Response.json(user):Response.json({error_code:'access_revoked'},{status:401});
 };
 const db={setClaims(){},prepare(query){return {sql:query,values:[],bind(...values){this.values=values;return this;},async first(){
  if(query.startsWith('SELECT e.*,o.scope'))return {...currentRow(),retained_scope:structuredClone(state.scope),source_sensitivity:classify()};
  if(query.startsWith('SELECT b.*,s.expires_at'))return state.active?{auth_user_id:IDS.managed,auth_session_id:IDS.session,token_ciphertext:bffCipher,version:1,expires_at:at+3600}:null;
  if(query.startsWith('SELECT private.is_managed_session'))return {allowed:state.active};
  if(query.startsWith('SELECT user_id FROM private.auth_principal_links'))return {user_id:IDS.principal};
  if(query.startsWith('SELECT * FROM users'))return {id:IDS.principal,access_status:state.active?'active':'deleted',full_name:'Synthetic',public_id:'000001'};
  if(query.startsWith('SELECT * FROM auth_sessions'))return session();
  if(query.startsWith('SELECT a.id FROM admin_sessions'))return state.active?{id:IDS.account}:null;
  if(query.startsWith('SELECT a.*,s.public_id'))return state.active?accountRow():null;
  if(query.startsWith('SELECT private.admin_email_status'))return {result:{contract_version:1,public_session_id:IDS.public,email_verified_at:state.emailAt,proof_id:state.emailAt===null?null:IDS.proof}};
  throw Error('Unexpected synthetic read: '+query);
 },async all(){assert.match(query,/^SELECT [cg]\.permission/);return {results:[...state.grants].map(permission=>({permission}))};}};},
 async batch(statements){
  state.batches.push(statements);
  const revealing=statements.some(s=>s.sql.includes("'payment.evidence.revealed'"));
  if(revealing&&state.beforeAudit){const effect=state.beforeAudit;state.beforeAudit=null;await effect();}
  for(const s of statements){
   if(s.sql.startsWith('INSERT INTO admin_account_guards')){
    const v=s.values;
    if(!state.active||v[4]!==IDS.account||v[5]!==state.authVersion||v[6]!==state.role||v[7]!==IDS.principal||v[8]!==IDS.session||v[12]&&!state.grants.has(v[12]))throw Error('admin_account_guards');
    if(v[16]&&(!state.emailAt||Math.floor(Date.now()/1000)-state.emailAt>300))throw Error('recent_email_sign_in_required');
   }
   if(s.sql.startsWith('INSERT INTO mutation_guards')){
    if(!state.active||s.values[1]!==IDS.principal||s.values[2]!==IDS.session)throw Error('session_changed');
    if(s.values[6]&&!state.grants.has(s.values[6]))throw Error('permission_denied');
   }
   if(s.sql.startsWith('INSERT INTO admin_bridge_guards')){
    assert.match(s.sql,/to_jsonb\(e\)=\?::jsonb/);assert.match(s.sql,/p\.state='committed' AND NOT p\.delete_tombstone/);
    assert.ok(s.sql.includes(evidenceSensitivitySql),'Admission must reuse the actual classifier');
    if(JSON.stringify(s.values[2])!==JSON.stringify(currentRow())||s.values[3]!==classify()||!state.committed||state.tombstone||state.scope.ownerId!==row.owner_user_id||state.scope.entityId!==row.id||state.scope.purpose!=='payment_evidence')throw Error('admin_bridge_state');
   }
  }
  if(revealing&&state.auditFailure)throw Error('synthetic audit unavailable');
  for(const s of statements)if(s.sql.startsWith('INSERT INTO audit_log'))state.audits.push(s.values);
  if(revealing&&state.lostAuditReply)throw Error('synthetic lost commit reply');
  return statements.map(()=>({results:[]}));
 }};
 env.DB=db;env.PRIVATE_MEDIA={async get(){state.objectReads++;if(state.missingObject)return null;return {async text(){if(state.afterRead){const effect=state.afterRead;state.afterRead=null;await effect();}return state.corruptObject?'synthetic corrupt cipher':cipher;}};}};
 const request=(reason='Review the original retained receipt',query='')=>new Request(origin+'/api/admin/evidence/'+IDS.evidence+query,{headers:{Origin:origin,Cookie:'__Host-collect_admin='+cookie,...(reason===null?{}:{'X-Collect-Review-Reason':reason})}});
 async function call({reason='Review the original retained receipt',direct=false,query=''}={}){
  const oldFetch=globalThis.fetch;globalThis.fetch=modelFetch;
  try{
   const adminRequest=request(reason,query),account=await adminAccountSession(adminRequest,env),base=accountDatabase(env,account),actor=await adminCanonicalActor(adminRequest,base,account);
   const internal=await adminInternalRequest(adminRequest,base,account,'/v1/evidence/'+IDS.evidence,'GET');
   return await evidenceRoute(internal,base,actor,direct?{}:{adminRequest,account});
  }finally{globalThis.fetch=oldFetch;}
 }
 return {state,sql,env,db,row,body,receipt,manual,classify,request,call,close:()=>sql.close()};
}

test('payment evidence sensitivity is inherited and fails closed for legacy provenance',async t=>{
 const f=await fixture({kind:'unclassified'});try{
  assert.equal(f.classify(),'unclassified');
  assert.equal(evidenceSensitivity(undefined),'unclassified');assert.equal(evidenceSensitivity('caller_ordinary'),'unclassified');
  f.manual();assert.equal(f.classify(),'unclassified','A manual-entry receipt does not prove non-SMS content');
  const metadata=evidenceMetadata(f.sql.prepare(evidenceMetadataSql).get(IDS.payment));assert.equal(metadata.source_sensitivity,'unclassified');assert.equal(Object.hasOwn(metadata,'raw_body'),false);
  f.sql.prepare('INSERT INTO sms_receipts VALUES(?)').run(f.row.object_sha256);assert.equal(f.classify(),'raw_sms','Manual copies inherit the retained source classification');
  f.sql.exec('DELETE FROM sms_receipts');f.sql.prepare('INSERT INTO momo_financial_links VALUES(?)').run(IDS.payment);assert.equal(f.classify(),'raw_sms','Legacy immutable links preserve source sensitivity');
  f.sql.exec('DELETE FROM momo_financial_links; DELETE FROM request_receipts');
  for(const [operation,owner,receipt]of [['momo.assign',IDS.principal,f.receipt],['payment.record',id(77),f.receipt],['payment.record',IDS.principal,{...f.receipt,id:id(77)}],['payment.record',IDS.principal,{...f.receipt,evidence_id:id(77)}],['payment.record',IDS.principal,{...f.receipt,amount_minor:499}],['payment.record',IDS.principal,{...f.receipt,amount_minor:'500'}]]){
   f.sql.prepare('INSERT INTO request_receipts VALUES(?,?,?)').run(owner,operation,JSON.stringify(receipt));assert.equal(f.classify(),'unclassified');f.sql.exec('DELETE FROM request_receipts');
  }
 }finally{f.close();}
});

test('actual retained-evidence handler enforces fresh email, both SMS grants, reason and audit before plaintext', {concurrency:false},async t=>{
 async function run(options,fn){const f=await fixture(options);try{await fn(f);}finally{f.close();}}
 await t.test('raw and unclassified legacy evidence return after exactly one source-bound audit',async()=>{
  for(const kind of ['raw_sms','unclassified'])await run({kind},async f=>{
   const reply=await f.call({reason:'  Review the original retained receipt  '});
   assert.equal(f.state.audits.length,1,'Audit commits before the handler yields a body');assert.equal(reply.status,200);assert.equal(await reply.text(),BODY);
   assert.equal(reply.headers.get('X-Collect-Evidence-Sensitivity'),kind);assert.equal(reply.headers.get('Cache-Control'),'no-store');
   const audit=f.state.audits[0];assert.deepEqual(audit.slice(0,3),[IDS.principal,IDS.session,IDS.evidence]);
   assert.deepEqual(JSON.parse(audit[3]),{reason:'Review the original retained receipt',source_sensitivity:kind,owner_user_id:IDS.principal,source_sha256:f.row.object_sha256});assert(!audit[3].includes(BODY));
   const gate=f.state.batches.at(-1).find(s=>s.sql.startsWith('INSERT INTO mutation_guards'));assert.equal(gate.values[11],2);assert.equal(gate.values[12],null,'AAL1 email proof never invents MFA');
  });
 });
 await t.test('manual payment.record receipts never downgrade untyped or transformed SMS evidence',async()=>{
  for(const bodyText of ['SYNTHETIC manually recorded cash deposit receipt.',BODY.replaceAll(' ',' / ')]){
   await run({kind:'manual',bodyText,grants:['payments.evidence.read'],emailAge:null},async f=>{
    f.sql.prepare('INSERT INTO sms_receipts VALUES(?)').run(await digest(BODY));
    assert.equal(f.classify(),'unclassified');await assert.rejects(f.call({reason:null}),failure('permission_required',403));assert.equal(f.state.objectReads,0);assert.equal(f.state.audits.length,0);
   });
   await run({kind:'manual',bodyText},async f=>{const r=await f.call();assert.equal(r.status,200);assert.equal(await r.text(),bodyText);assert.equal(r.headers.get('X-Collect-Evidence-Sensitivity'),'unclassified');assert.equal(f.state.audits.length,1);});
  }
 });
 await t.test('original direct bearer bypass is denied for raw and unclassified sources before object access',async()=>{
  for(const kind of ['raw_sms','unclassified'])await run({kind,grants:['payments.evidence.read'],emailAge:null},async f=>{await assert.rejects(f.call({direct:true,reason:null}),failure('admin_session_required',403));assert.equal(f.state.objectReads,0);assert.equal(f.state.audits.length,0);});
 });
 await t.test('each missing grant, stale/missing email proof and missing/invalid reason returns no body or audit',async()=>{
  for(const permission of required)await run({grants:required.filter(p=>p!==permission)},async f=>{await assert.rejects(f.call(),failure(null,403));assert.equal(f.state.objectReads,0);assert.equal(f.state.audits.length,0);});
  for(const emailAge of [null,301])await run({emailAge},async f=>{await assert.rejects(f.call(),failure('recent_email_sign_in_required',403));assert.equal(f.state.objectReads,0);assert.equal(f.state.audits.length,0);});
  for(const reason of [null,'short','x'.repeat(1001),'invalid\u007freason'])await run({},async f=>{await assert.rejects(f.call({reason}),failure('reason_required',400));assert.equal(f.state.objectReads,0);assert.equal(f.state.audits.length,0);});
 });
 await t.test('review reasons and client sensitivity claims in URLs are rejected before object access',async()=>{
  for(const query of ['?reason=review-this-source','?source_sensitivity=ordinary'])await run({},async f=>{await assert.rejects(f.call({query}),failure('invalid_request',400));assert.equal(f.state.objectReads,0);assert.equal(f.state.audits.length,0);});
 });
 await t.test('grant revocation, proof expiry and session/account replacement after object read never release bytes',async()=>{
  const effects=[...required.map(p=>f=>f.state.grants.delete(p)),f=>{f.state.emailAt-=301;},f=>{f.state.active=false;},f=>{f.state.authVersion++;},f=>{f.state.role='staff';}];
  for(const effect of effects)await run({},async f=>{f.state.afterRead=()=>effect(f);await assert.rejects(f.call());assert.equal(f.state.objectReads,1);assert.equal(f.state.audits.length,0);});
 });
 await t.test('the final transaction rechecks each grant, source identity, storage custody and proof',async()=>{
  const effects=[...required.map(p=>f=>f.state.grants.delete(p)),f=>{f.state.emailAt-=301;},f=>{f.state.scope.ownerId=id(55);},f=>{f.state.tombstone=true;},f=>{f.state.committed=false;},f=>f.sql.prepare('UPDATE payment_evidence SET object_sha256=?').run('f'.repeat(64))];
  for(const effect of effects)await run({},async f=>{f.state.beforeAudit=()=>effect(f);await assert.rejects(f.call());assert.equal(f.state.audits.length,0);});
 });
 await t.test('a source-classification change invalidates an in-flight read before its audit',async()=>{
  await run({kind:'unclassified'},async f=>{f.state.afterRead=()=>f.sql.prepare('INSERT INTO sms_receipts VALUES(?)').run(f.row.object_sha256);await assert.rejects(f.call(),failure('stale_state',409));assert.equal(f.state.audits.length,0);});
 });
 await t.test('wrong scope, absent object and corrupted cipher yield no body or audit',async()=>{
  for(const effect of [f=>{f.state.scope.entityId=id(66);},f=>{f.state.missingObject=true;},f=>{f.state.corruptObject=true;}])await run({},async f=>{effect(f);await assert.rejects(f.call(),failure(null,503));assert.equal(f.state.audits.length,0);});
 });
 await t.test('failed or unacknowledged audit never releases plaintext',async()=>{
  await run({},async f=>{f.state.auditFailure=true;await assert.rejects(f.call(),/synthetic audit unavailable/);assert.equal(f.state.audits.length,0);});
  await run({},async f=>{f.state.lostAuditReply=true;await assert.rejects(f.call(),/synthetic lost commit reply/);assert.equal(f.state.audits.length,1);});
 });
});
