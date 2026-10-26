import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {passwordHash} from '../../src/admin_account_support/security.js';
import {totp} from '../support/auth_fixture.mjs';

const root=new URL('../../',import.meta.url),runtime=process.env.COLLECT_MINIFLARE_MODULE??'miniflare';
const {Miniflare,convertV4MiniflareOptions}=await import(runtime);
const install=new URL('../../',new URL(runtime.startsWith('/')?'file://'+runtime:import.meta.url));
const esbuild=process.env.COLLECT_ESBUILD_MODULE??'esbuild';
const {build}=await import(esbuild);
const require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
export const ORIGIN='https://admin-preview.collect.ikanisa.com';
export const PASSWORD='A strong collect password 2026';
export const NEW_PASSWORD='Another strong collect password 2026';
let passwordPromise,bundlePromise;
const encoder=new TextEncoder();

export async function fixture(t,overrides={}){
 const messages=[],mail=[],captchaSeen=new Set();let emailFailure=false,gate=async()=>{};
 // The only replacement capabilities are outbound provider acknowledgements
 // and explicitly selected pause/failure points. Every SQL/R2 call is real.
 bundlePromise??=build({stdin:{resolveDir:fileURLToPath(root),contents:`
  import {handleAdmin} from './src/admin_bridge.js';
  import worker from './src/index.js';
  export default {async fetch(request,env,ctx){
   const original=env.DB,meta=new WeakMap();let once=false;
   const wrapped=(stmt,query)=>{const proxy=new Proxy(stmt,{get(target,key){if(key==='bind')return(...args)=>wrapped(target.bind(...args),query);const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;}});meta.set(proxy,{stmt,query});return proxy;};
   const pause=async(phase,queries=[])=>{if(once||!request.headers.has('X-Test-Pause'))return;
    once=true;const reply=await env.TEST_GATE.fetch('https://gate.test',{method:'POST',body:JSON.stringify({phase,path:new URL(request.url).pathname,queries})});
    if(!reply.ok)throw new Error('controlled_gate_failed');return reply;};
   const db=new Proxy(original,{get(target,key){
    if(key==='prepare')return q=>wrapped(target.prepare(q),q);
    if(key==='withSession')return()=>db;
    if(key==='batch')return async statements=>{const queries=statements.map(s=>meta.get(s)?.query??'');
     if(request.headers.get('X-Test-Pause')==='sync_read'&&queries.some(q=>q.includes('SELECT id,entity_type,actor_user_id FROM audit_log')))await pause('sync_read',queries);
     if(request.headers.get('X-Test-Pause')==='before_commit'&&queries.some(q=>q.includes('INSERT INTO request_receipts')||q.includes('INSERT INTO auth_sessions')||q.includes('INSERT INTO auth_mfa_revocations')||q.includes('UPDATE admin_users SET password_hash')))await pause('before_commit',queries);
     const result=await target.batch(statements.map(s=>meta.get(s)?.stmt??s));
     if(request.headers.get('X-Test-Pause')==='lost_reply'&&queries.some(q=>q.includes('INSERT INTO request_receipts'))){await pause('lost_reply',queries);throw new Error('controlled_lost_reply_after_commit');}
     return result;};
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;}});
   const r2=new Proxy(env.PRIVATE_MEDIA,{get(target,key){if(key==='get')return async(...args)=>{if(request.headers.get('X-Test-Pause')==='evidence_read')await pause('evidence_read');return target.get(...args);};const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;}});
   const current={...env,DB:db,PRIVATE_MEDIA:r2,...(env.TEST_EMAIL?{EMAIL:{send:async value=>{const reply=await env.TEST_EMAIL.fetch('https://mail.test',{method:'POST',body:JSON.stringify(value)});if(!reply.ok)throw new Error('controlled_delivery_failure');return reply.json();}}}:{})};
   return await handleAdmin(request,current,ctx)??worker.fetch(request,current,ctx);
  }};`},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022'});
 const bundle=(await bundlePromise).outputFiles[0].text;
 const services={TEST_GATE:async request=>{await gate(await request.json());return Response.json({ok:true});}};
 if(overrides.TEST_EMAIL!==false)services.TEST_EMAIL=async request=>{const value=await request.json();mail.push(value);return emailFailure?new Response('refused',{status:503}):Response.json({messageId:randomUUID()});};
 const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script:bundle,compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,
  r2Buckets:{PRIVATE_MEDIA:randomUUID()},r2Persist:false,
  bindings:{APP_ENVIRONMENT:'test',ENVIRONMENT:'test',ADMIN_ORIGIN:ORIGIN,
   AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',AUTH_ISSUER:'collect-test',AUTH_AUDIENCE:'collect',AUTH_MEMBER_REGISTRATION_ENABLED:'true',
   OTP_DELIVERY_URL:'https://trusted-relay.example/otp',OTP_DELIVERY_TOKEN:'test-relay-token-123456789',TURNSTILE_REQUIRED:'true',TURNSTILE_SECRET:'test-turnstile-secret-123456',TURNSTILE_HOSTNAME:'collect.example',TURNSTILE_ACTION:'collect-login',
   ALLOWED_ORIGINS:ORIGIN+',https://collect.example',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DATA_KEY_ID:'admin-test-v1',...Object.fromEntries(Object.entries(overrides).filter(([k])=>k!=='TEST_EMAIL'))},
  serviceBindings:services,outboundService:async request=>{
   if(request.url==='https://challenges.cloudflare.com/turnstile/v0/siteverify'){const form=new URLSearchParams(await request.text()),token=form.get('response'),success=token&&!captchaSeen.has(token);captchaSeen.add(token);return Response.json({success,hostname:'collect.example',action:'collect-login',challenge_ts:new Date().toISOString()});}
   assert.equal(request.url,'https://trusted-relay.example/otp');const value=await request.json();messages.push(value);return Response.json({accepted:true,request_id:value.request_id});
  }}));
 t?.after(()=>mf.dispose());const db=await mf.getD1Database('DB');
 try{for(const name of (await readdir(new URL('migrations/',root))).filter(n=>/^\d+.*\.sql$/.test(n)).sort()){
  const source=await readFile(new URL('migrations/'+name,root),'utf8');
  for(const query of unstable_splitSqlQuery(source))try{await db.prepare(query).run();}catch(error){throw new Error(`Migration ${name}: ${query.slice(0,160)}`,{cause:error});}
 }}catch(error){await mf.dispose();throw error;}
 const f={mf,db,messages,mail,setEmailFailure:v=>{emailFailure=v;},setGate:fn=>{gate=fn;},close:()=>mf.dispose(),bundleSha256:createHash('sha256').update(bundle).digest('hex')};
 f.call=async(path,{method='POST',data={},cookie,origin=ORIGIN,headers={}}={})=>{
  const response=await mf.dispatchFetch(ORIGIN+path,{method,headers:{'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.1',...(origin?{Origin:origin}:{}),...(cookie?{Cookie:cookie}:{}),...headers},...(['GET','HEAD'].includes(method)?{}:{body:JSON.stringify(data)})});
  const text=await response.text();let body;try{body=JSON.parse(text);}catch{body=text;}return {status:response.status,body,cookie:response.headers.get('Set-Cookie')?.split(';')[0],headers:response.headers};
 };
 f.seedAccount=async({email='info@ikanisa.com',role='owner',status='active',linked=true}={})=>{
  const adminId=randomUUID(),userId=randomUUID(),timestamp=Math.floor(Date.now()/1000),date=new Date().toISOString(),publicId=String((await db.prepare('SELECT count(*) AS n FROM users').first()).n).padStart(6,'0');
  passwordPromise??=passwordHash(PASSWORD);const hash=await passwordPromise;
  await db.prepare('INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at,display_name) VALUES(?,?,?,?,?,?,?,?)').bind(adminId,email,role,status,status==='active'?hash:null,timestamp,timestamp,role+' operator').run();
  if(linked){await db.prepare("INSERT INTO users(id,public_id,member_type,full_name,created_at,updated_at) VALUES(?,?,'operator',?,?,?)").bind(userId,publicId,role+' operator',date,date).run();await db.prepare('INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(?,?,?,?)').bind(adminId,userId,'controlled-test-owner-bootstrap',date).run();}
  return {adminId,userId,email,role};
 };
 f.login=async account=>{const result=await f.call('/api/admin/auth/login',{data:{email:account.email,password:PASSWORD}});assert.equal(result.status,200,JSON.stringify(result));return result;};
 f.stepUp=async login=>{
  const enroll=await f.call('/api/admin/auth/mfa/enroll',{cookie:login.cookie});assert.equal(enroll.status,200,JSON.stringify(enroll));
  const challenge=await f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:enroll.body.id}});assert.equal(challenge.status,200,JSON.stringify(challenge));
  const verify=await f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:enroll.body.id,challenge_id:challenge.body.challenge_id,code:totp(enroll.body.totp.secret)}});assert.equal(verify.status,200,JSON.stringify(verify));
  return {...verify,factor:enroll.body};
 };
 f.nativeLogin=async(phone='+250788123456')=>{
  const challenge=await f.call('/v1/auth/otp',{origin:'https://collect.example',data:{phone,captcha_token:randomUUID()}});assert.equal(challenge.status,202,JSON.stringify(challenge));
  const message=messages.find(v=>v.request_id===challenge.body.challenge_id);
  const verify=await f.call('/v1/auth/verify',{origin:'https://collect.example',data:{phone,captcha_token:randomUUID(),challenge_id:challenge.body.challenge_id,code:message.code}});assert.equal(verify.status,200,JSON.stringify(verify));return verify.body;
 };
 f.seedMember=async({phone='+250788123456',name='Recorded Member'}={})=>{
  const userId=randomUUID(),date=new Date().toISOString(),publicId=String((await db.prepare('SELECT count(*) AS n FROM users').first()).n).padStart(6,'0');
  await db.prepare(`INSERT INTO users(id,public_id,phone,full_name,momo_provider,momo_number,created_at,updated_at) VALUES(?,?,?,?,'mtn_momo',?,?,?)`).bind(userId,publicId,phone,name,phone.replace(/^\+250/,'0'),date,date).run();return {id:userId,phone,public_id:publicId};
 };
 f.operation=(path,cookie,data,key=randomUUID(),extra={})=>f.call('/api/admin/operations/'+path,{cookie,data,headers:{'Idempotency-Key':key,'X-Collect-Review-Reason':data.reason??'Recorded test operation',...extra}});
 return f;
}
export function setupToken(message){const link=message.text.match(/https:\/\/\S+\/\#\/admin\/setup\?\S+/)?.[0];assert.ok(link);return new URLSearchParams(new URL(link).hash.split('?')[1]).get('token');}
export const hash=value=>createHash('sha256').update(value).digest('hex');
