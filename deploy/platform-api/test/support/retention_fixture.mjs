import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {admin,setupMfa,totp,authorization} from './auth_fixture.mjs';
const require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??'miniflare');
const root=new URL('../../',import.meta.url),sha=value=>createHash('sha256').update(value).digest('hex');
export const sourceId='f'.repeat(64);
// This entry exists only in the isolated test runtime. Production has no
// test route, policy-pin override, provider fault or source-race hook.
const entry=`
import {handleAuth,requireSession} from '../src/auth.js';
import {ApiError,json,digest} from '../src/core.js';
import {privacyRpc} from '../src/privacy.js';
import {retentionSchema,retentionSnapshot} from '../src/privacy_retention_catalog.js';
import {inspectRetentionScope,planRetention,claimRetentionTask,executeRetentionTask,retentionStatus,reconcileRetentionPlan,resolveRetentionOperation,inspectQuarantineContinuation} from '../src/privacy_retention.js';
export default {async fetch(request,env){
 try{
  const path=new URL(request.url).pathname;
  const auth=await handleAuth(request,env);if(auth)return auth;
  const actor=await requireSession(request,env);
  if(path==='/__actor')return json({...actor,permissions:[...actor.permissions]});
  if(path==='/__retention/schema')return json(await retentionSchema(env));
  const body=await request.json();
  if(path.startsWith('/v1/rpc/'))return json((await privacyRpc(path.split('/').pop(),body,env,actor)).value);
  let raced=false;const db=env.DB,media=env.PRIVATE_MEDIA;
  const observed=(statement,query)=>new Proxy(statement,{get(target,key){
   if(key==='bind')return(...args)=>observed(target.bind(...args),query);
   if(key==='all')return async(...args)=>{const result=await target.all(...args);
    if(!raced&&request.headers.get('x-test-revoke-after-inventory')==='true'&&query.includes('SELECT * FROM "users" WHERE')){
     raced=true;await db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='controlled_read_race' WHERE id=?").bind(actor.sessionId).run();
    }return result;};
   const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
  }});
  const testEnv={...env,PRIVACY_RETENTION_APPROVAL_SHA256:request.headers.get('x-test-policy-pin')??undefined,
   DB:{prepare:query=>observed(db.prepare(query),query),async batch(statements){
    if(!raced&&statements.length>10&&['support','user'].includes(request.headers.get('x-test-source-race'))){
     raced=true;const sql=request.headers.get('x-test-source-race')==='support'?"UPDATE support_requests SET message='CONCURRENT SOURCE CHANGE' WHERE user_id=?":"UPDATE users SET full_name='CONCURRENT SOURCE CHANGE' WHERE id=?";await db.prepare(sql).bind(request.headers.get('x-test-subject')).run();
    }
    return db.batch(statements);
   }},
   PRIVATE_MEDIA:{get:key=>media.get(key),async head(key){
    if(!raced&&request.headers.get('x-test-r2-race')==='hold'){
     raced=true;await db.prepare("INSERT INTO privacy_holds(id,user_id,category,reason_code,created_at) VALUES(?,?,'test','new_hold',?)").bind(crypto.randomUUID(),request.headers.get('x-test-subject'),new Date().toISOString()).run();
    }
    if(!raced&&request.headers.get('x-test-r2-race')==='replace'){raced=true;await media.put(key,'CONCURRENT REPLACEMENT');}
    return media.head(key);
   },async delete(key){if(request.headers.get('x-test-r2-fail-before-delete')==='true')throw new Error('Controlled outage before actual R2 delete');await media.delete(key);if(request.headers.get('x-test-r2-lost-ack')==='true')throw new Error('Controlled lost acknowledgement after actual R2 delete');}}
  };
  const actions={inspect:inspectRetentionScope,plan:planRetention,claim:claimRetentionTask,execute:executeRetentionTask,status:retentionStatus,reconcile:reconcileRetentionPlan,resolve:resolveRetentionOperation,continuation:inspectQuarantineContinuation,snapshot:(e,a,b)=>retentionSnapshot(e,b.subject_id).then(s=>s.summary)};
  const action=actions[path.split('/').pop()];if(!action)return json({code:'missing'},404);
  return json(await action(testEnv,actor,body));
 }catch(error){return json({code:error instanceof ApiError?error.code:'test_internal_error',detail:String(error.message)},error instanceof ApiError?error.status:500);}
}};`;
export async function retentionFixture(t,{identityBindings={}}={}){
 assert.ok(identityBindings&&typeof identityBindings==='object'&&!Array.isArray(identityBindings)&&Object.entries(identityBindings).every(([key,value])=>['AUTH_IDENTITY_KEY_ID','AUTH_IDENTITY_HASH_KEY','AUTH_IDENTITY_PREVIOUS_KEYS_JSON'].includes(key)&&typeof value==='string'),'Only the three test identity bindings may be overridden');
 const names=[];async function walk(folder,prefix=''){for(const e of await readdir(folder,{withFileTypes:true})){if(e.isDirectory())await walk(new URL(e.name+'/',folder),prefix+e.name+'/');else if(e.name.endsWith('.js')&&!e.name.startsWith('._'))names.push(prefix+e.name);}}
 await walk(new URL('src/',root));
 const modules=[{type:'ESModule',path:fileURLToPath(new URL('test/retention_entry.mjs',root)),contents:entry},...await Promise.all(names.map(async name=>({type:'ESModule',path:fileURLToPath(new URL('src/'+name,root)),contents:await readFile(new URL('src/'+name,root),'utf8')})))];
 const messages=[];
 const mf=new Miniflare((convertV4MiniflareOptions??(v=>v))({modules,modulesRoot:fileURLToPath(root),compatibilityDate:'2026-10-14',cf:false,
  d1Databases:{DB:randomUUID()},d1Persist:false,r2Buckets:{PRIVATE_MEDIA:randomUUID()},r2Persist:false,
  bindings:{APP_ENVIRONMENT:'test',BUILD_SOURCE_ID:sourceId,AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',AUTH_ISSUER:'collect-test',AUTH_AUDIENCE:'collect',AUTH_MEMBER_REGISTRATION_ENABLED:'true',OTP_DELIVERY_URL:'https://trusted-relay.example/otp',OTP_DELIVERY_TOKEN:'test-relay-token-123456789',TURNSTILE_REQUIRED:'true',TURNSTILE_SECRET:'test-turnstile-secret-123456',TURNSTILE_HOSTNAME:'collect.example',TURNSTILE_ACTION:'collect-login',ALLOWED_ORIGINS:'https://collect.example,https://admin.collect.example',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DATA_KEY_ID:'auth-test-v1',...identityBindings},
  outboundService:async request=>{
   if(request.url==='https://challenges.cloudflare.com/turnstile/v0/siteverify')return Response.json({success:true,hostname:'collect.example',action:'collect-login',challenge_ts:new Date().toISOString()});
   assert.equal(request.url,'https://trusted-relay.example/otp');const body=await request.json();messages.push(body);return Response.json({accepted:true,request_id:body.request_id});
  }}));
 t.after(()=>mf.dispose());const db=await mf.getD1Database('DB'),bucket=await mf.getR2Bucket('PRIVATE_MEDIA');
 for(const name of (await readdir(new URL('migrations/',root))).filter(n=>/^\d+.*\.sql$/.test(n)).sort())for(const statement of unstable_splitSqlQuery(await readFile(new URL('migrations/'+name,root),'utf8')))await db.prepare(statement).run();
 const f={mf,db,bucket,messages,policySha:null};
 f.call=async(path,body={},headers={})=>{const get=['/v1/auth/user','/__actor','/__retention/schema'].includes(path);const response=await mf.dispatchFetch('https://api.collect.example'+path,{method:get?'GET':'POST',headers:{'content-type':'application/json','CF-Connecting-IP':'192.0.2.1',...(f.policySha?{'x-test-policy-pin':f.policySha}:{}),...headers},...(get?{}:{body:JSON.stringify(body)})});return {status:response.status,body:await response.json()};};
 f.otp=(identity={phone:'+250788123456'})=>f.call('/v1/auth/otp',{...identity,captcha_token:randomUUID()});
 f.verify=(r,identity)=>{const message=messages.find(m=>m.request_id===r.body.challenge_id);assert.ok(message,'controlled relay delivery');return f.call('/v1/auth/verify',{...identity,challenge_id:r.body.challenge_id,code:message.code,captcha_token:randomUUID()});};
 f.login=async(identity={phone:'+250788123456'})=>{const otp=await f.otp(identity);assert.equal(otp.status,202,JSON.stringify(otp.body));const result=await f.verify(otp,identity);assert.equal(result.status,200,JSON.stringify(result.body));return result.body;};
 f.operator=async({mfa=true,grant=true,email='operator@example.com'}={})=>{const a=await admin(f,{email}),session=await f.login(a.identity);f.aal1Session=session;if(grant)await db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,'privacy.review',new Date().toISOString()).run();if(!mfa)return session;const {factor,challenge}=await setupMfa(f,session),result=await f.call('/v1/auth/mfa/verify',{factor_id:factor.id,challenge_id:challenge.id,code:totp(factor.totp.secret)},authorization(session));assert.equal(result.status,200,JSON.stringify(result.body));return result.body;};
 f.policy=async(operator,changes={})=>{const schema=await f.call('/__retention/schema',{},authorization(operator));assert.equal(schema.status,200,JSON.stringify(schema.body));f.retentionClasses=schema.body.classes;const scopeResult=await f.retention(operator,'inspect',{request_id:f.scopeRequest,expected_review_revision:0,expected_source_id:sourceId});assert.equal(scopeResult.status,200,JSON.stringify(scopeResult.body));const past=new Date(Date.now()-60000).toISOString(),future=new Date(Date.now()+3600000).toISOString();const policy={contract_version:1,policy_id:randomUUID(),version:'synthetic-test-policy-only',environment:'test',synthetic_test_only:true,approval_evidence_sha256:sha('SYNTHETIC TEST APPROVAL'),approved_by:operator.user.id,approved_at:past,expires_at:future,source_id:sourceId,schema_sha256:schema.body.sha256,scope:{request_id:f.scopeRequest,subject_id:scopeResult.body.subject_id,snapshot_sha256:scopeResult.body.snapshot_sha256},rules:Object.fromEntries(schema.body.classes.map(name=>[name,{action:name==='access'?'quarantine':'retain',basis_reference:'SYNTHETIC ISOLATED TEST ONLY',deadline:future}])),writer_fence:{source_id:sourceId,evidence_sha256:sha('SYNTHETIC NO EXTERNAL WRITERS'),generic_upload_catalog_only:true,unknown_in_flight:false},external_inventory:{status:'synthetic_empty',evidence_sha256:sha('SYNTHETIC EMPTY COPY FIXTURE')},...changes};const raw=JSON.stringify(policy);f.policySha=sha(raw);await db.prepare("INSERT INTO runtime_config(key,value_json,updated_at) VALUES('privacy:retention:approved:v1',?,?) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,revision=revision+1,updated_at=excluded.updated_at").bind(raw,new Date().toISOString()).run();return policy;};
 f.retention=(operator,action,body={},headers={})=>f.call('/__retention/'+action,body,{...authorization(operator),...headers});
 return f;
}
export {authorization,sha};
