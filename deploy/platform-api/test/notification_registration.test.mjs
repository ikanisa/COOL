import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID,createHmac,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const root=new URL('../',import.meta.url),require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??'miniflare');
const {build}=await import(process.env.COLLECT_ESBUILD_MODULE??'esbuild');
const key=Buffer.from(Array.from({length:32},(_,i)=>i+1));
const jwtSecret='test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890';
const body={p_platform:'android',p_provider:'fcm',p_token:'controlled-private-device-token',p_environment:'test'};
const hash=value=>createHash('sha256').update(value).digest('hex');
const barrier=()=>{let release;return {promise:new Promise(resolve=>{release=resolve;}),resolve:()=>release()};};
let bundled;

async function fixture(t){
 const messages=[];let gate=async()=>{};
 // The pause/lost-reply hooks are test-only. Every authorization, registration,
 // SQL statement, trigger and transaction below executes in actual workerd/D1.
 bundled??=build({stdin:{resolveDir:fileURLToPath(root),contents:`
  import worker from './src/index.js';
  export default {async fetch(request,env,ctx){
   const metadata=new WeakMap();let paused=false;
   const wrap=(statement,query)=>{const proxy=new Proxy(statement,{get(target,key){
    if(key==='bind')return(...args)=>wrap(target.bind(...args),query);
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
   }});metadata.set(proxy,{statement,query});return proxy;};
   const pause=async phase=>{if(paused||request.headers.get('X-Test-Pause')!==phase)return;paused=true;
    await env.TEST_GATE.fetch('https://gate.test',{method:'POST',body:JSON.stringify({phase})});};
   const db=new Proxy(env.DB,{get(target,key){
    if(key==='prepare')return query=>wrap(target.prepare(query),query);
    if(key==='withSession')return()=>db;
    if(key==='batch')return async statements=>{
     const registration=statements.some(statement=>/INSERT INTO notification_devices/.test(metadata.get(statement)?.query??''));
     if(registration)await pause('before_commit');
     if(statements.some(statement=>(metadata.get(statement)?.query??'').includes('FROM notification_events')))await pause('before_read');
     const result=await target.batch(statements.map(statement=>metadata.get(statement)?.statement??statement));
     if(registration&&request.headers.get('X-Test-Pause')==='lost_reply'){
      await pause('lost_reply');throw new Error('controlled_lost_registration_reply');
     }
     return result;
    };
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
   }});
   return worker.fetch(request,{...env,DB:db},ctx);
  }};`},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022'});
 const script=(await bundled).outputFiles[0].text;
 const mf=new Miniflare(convertV4MiniflareOptions({modules:true,script,compatibilityDate:'2026-10-14',cf:false,
  d1Databases:{DB:randomUUID()},d1Persist:false,r2Buckets:{PRIVATE_MEDIA:randomUUID()},r2Persist:false,
  bindings:{APP_ENVIRONMENT:'test',AUTH_JWT_SECRET:jwtSecret,AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',AUTH_ISSUER:'collect-test',AUTH_AUDIENCE:'collect',AUTH_MEMBER_REGISTRATION_ENABLED:'true',
   OTP_DELIVERY_URL:'https://trusted-relay.example/otp',OTP_DELIVERY_TOKEN:'test-relay-token-123456789',TURNSTILE_REQUIRED:'true',TURNSTILE_SECRET:'test-turnstile-secret-123456',TURNSTILE_HOSTNAME:'collect.example',TURNSTILE_ACTION:'collect-login',ALLOWED_ORIGINS:'https://collect.example',DATA_ENCRYPTION_KEY:key.toString('base64'),DATA_KEY_ID:'notification-registration-test-v1'},
  serviceBindings:{TEST_GATE:async request=>{await gate(await request.json());return Response.json({ok:true});}},
  outboundService:async request=>{
   if(request.url==='https://challenges.cloudflare.com/turnstile/v0/siteverify')return Response.json({success:true,hostname:'collect.example',action:'collect-login',challenge_ts:new Date().toISOString()});
   assert.equal(request.url,'https://trusted-relay.example/otp');const value=await request.json();messages.push(value);return Response.json({accepted:true,request_id:value.request_id});
  }}));
 t.after(()=>mf.dispose());const db=await mf.getD1Database('DB');
 for(const name of(await readdir(new URL('migrations/',root))).filter(name=>/^\d+.*\.sql$/.test(name)).sort())
  for(const statement of unstable_splitSqlQuery(await readFile(new URL('migrations/'+name,root),'utf8')))await db.prepare(statement).run();
 const f={mf,db,setGate:callback=>{gate=callback;},bundle_sha256:hash(script)};
 f.call=async(path,data={},session=null,pause=null)=>{
  const response=await mf.dispatchFetch('https://api.collect.example'+path,{method:'POST',headers:{'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.1',...(session?{Authorization:'Bearer '+session.access_token}:{}),...(pause?{'X-Test-Pause':pause}:{})},body:JSON.stringify(data)});
  return {status:response.status,body:await response.json()};
 };
 f.login=async(phone='+250788123456')=>{
  await db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();
  const otp=await f.call('/v1/auth/otp',{phone,captcha_token:randomUUID()});assert.equal(otp.status,202,JSON.stringify(otp));
  const delivered=messages.find(message=>message.request_id===otp.body.challenge_id);
  const result=await f.call('/v1/auth/verify',{phone,captcha_token:randomUUID(),challenge_id:otp.body.challenge_id,code:delivered.code});assert.equal(result.status,200,JSON.stringify(result));return result.body;
 };
 f.register=(session,change={},pause=null)=>f.call('/v1/rpc/register_notification_device',{...body,...change},session,pause);
 f.events=async(session,pause=null)=>{
  const response=await mf.dispatchFetch('https://api.collect.example/v1/query/notification-events',{headers:{Authorization:'Bearer '+session.access_token,...(pause?{'X-Test-Pause':pause}:{})}});
  return {status:response.status,body:await response.json()};
 };
 return f;
}
const sessionId=session=>JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url')).session_id;
async function decryptToken(row){
 const cipher=JSON.parse(row.token_ciphertext),cryptoKey=await crypto.subtle.importKey('raw',key,'AES-GCM',false,['decrypt']);
 return new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:Buffer.from(cipher.iv,'base64'),additionalData:new TextEncoder().encode('notification:'+row.id)},cryptoKey,Buffer.from(cipher.data,'base64')));
}
function signed(claims){
 const header=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),payload=Buffer.from(JSON.stringify(claims)).toString('base64url');
 return header+'.'+payload+'.'+createHmac('sha256',jwtSecret).update(header+'.'+payload).digest('base64url');
}

test('racing accounts never receive acknowledgement for a device another account owns',async t=>{
 const f=await fixture(t),one=await f.login(),two=await f.login('+250789123456'),entered=barrier(),resume=barrier();
 f.setGate(async()=>{entered.resolve();await resume.promise;});
 const losing=f.register(one,{},'before_commit');await entered.promise;
 const winner=await f.register(two);resume.resolve();const rejected=await losing;
 assert.equal(winner.status,200,JSON.stringify(winner));assert.equal(rejected.status,409,JSON.stringify(rejected));assert.equal(rejected.body.code,'device_owned');
 const row=await f.db.prepare('SELECT * FROM notification_devices').first();assert.equal(row.id,winner.body);assert.equal(row.user_id,two.user.id);assert.equal(row.owner_session_id,sessionId(two));
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='register_notification_device'").first()).n,1);
});

test('same-session concurrent registration returns the retained device ID and preserves decryptable ciphertext',async t=>{
 const f=await fixture(t),session=await f.login(),entered=barrier(),resume=barrier();f.setGate(async()=>{entered.resolve();await resume.promise;});
 const delayed=f.register(session,{},'before_commit');await entered.promise;const first=await f.register(session);resume.resolve();const second=await delayed;
 assert.equal(first.status,200,JSON.stringify(first));assert.equal(second.status,200,JSON.stringify(second));assert.equal(first.body,second.body);
 const row=await f.db.prepare('SELECT * FROM notification_devices').first();assert.equal(row.id,first.body);assert.equal(await decryptToken(row),body.p_token);assert.ok(!row.token_ciphertext.includes(body.p_token));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM notification_devices').first()).n,1);
});

test('a delayed earlier session cannot take registration back from a newer same-second session',async t=>{
 const f=await fixture(t),login=await f.login(),at=Math.floor(Date.now()/1000),sessions=[];
 // Server-authenticated fixture sessions have deliberately identical seconds;
 // the generated UUID's lexical order must never determine session priority.
 for(let index=0;index<2;index++){
  const id=randomUUID();await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(id,login.user.id,at,at,at+3600).run();
  const claims=JSON.parse(Buffer.from(login.access_token.split('.')[1],'base64url'));sessions.push({...login,access_token:signed({...claims,session_id:id,auth_time:at,iat:at,exp:at+900})});
 }
 const [old,current]=sessions,entered=barrier(),resume=barrier();f.setGate(async()=>{entered.resolve();await resume.promise;});
 const delayed=f.register(old,{},'before_commit');await entered.promise;const first=await f.register(current);resume.resolve();const rejected=await delayed;
 assert.equal(first.status,200,JSON.stringify(first));assert.equal(rejected.status,409,JSON.stringify(rejected));assert.equal(rejected.body.code,'notification_registration_session_stale');
 assert.equal((await f.db.prepare('SELECT owner_session_id FROM notification_devices').first()).owner_session_id,sessionId(current));
 assert.equal((await f.call('/v1/rpc/unregister_notification_device',{p_token:body.p_token,p_provider:body.p_provider},old)).status,200);
 assert.equal((await f.db.prepare('SELECT active FROM notification_devices').first()).active,1);
});

test('a newer current login can retain the original device ID and safely replace its previous session',async t=>{
 const f=await fixture(t),old=await f.login(),initial=await f.register(old);assert.equal(initial.status,200,JSON.stringify(initial));
 const current=await f.login(),replacement=await f.register(current);assert.equal(replacement.status,200,JSON.stringify(replacement));assert.equal(replacement.body,initial.body);
 const row=await f.db.prepare('SELECT * FROM notification_devices').first();assert.equal(row.owner_session_id,sessionId(current));assert.equal(await decryptToken(row),body.p_token);
 const stale=await f.register(old);assert.equal(stale.status,409,JSON.stringify(stale));assert.equal(stale.body.code,'notification_registration_session_stale');
 assert.equal((await f.db.prepare('SELECT owner_session_id FROM notification_devices').first()).owner_session_id,sessionId(current));
});

test('revocation during registration rolls back without touching the predecessor device',async t=>{
 const f=await fixture(t),old=await f.login();assert.equal((await f.register(old)).status,200);const before=await f.db.prepare('SELECT * FROM notification_devices').first(),current=await f.login();
 f.setGate(async()=>{await f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='controlled_logout' WHERE id=?").bind(sessionId(current)).run();});
 const rejected=await f.register(current,{},'before_commit');assert.ok([401,403].includes(rejected.status),JSON.stringify(rejected));
 assert.deepEqual(await f.db.prepare('SELECT * FROM notification_devices').first(),before);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='register_notification_device'").first()).n,1);
});

test('a device token cannot silently change its provider or platform identity',async t=>{
 const f=await fixture(t),session=await f.login();assert.equal((await f.register(session)).status,200);const before=await f.db.prepare('SELECT * FROM notification_devices').first();
 const rejected=await f.register(session,{p_provider:'apns',p_platform:'ios'});assert.equal(rejected.status,409,JSON.stringify(rejected));assert.equal(rejected.body.code,'notification_device_mismatch');
 assert.deepEqual(await f.db.prepare('SELECT * FROM notification_devices').first(),before);
});

test('lost registration response reconciles only a current, actually stored registration',async t=>{
 const f=await fixture(t),session=await f.login(),reply=await f.register(session,{},'lost_reply');assert.equal(reply.status,200,JSON.stringify(reply));
 const row=await f.db.prepare('SELECT * FROM notification_devices').first();assert.equal(reply.body,row.id);assert.equal(row.owner_session_id,sessionId(session));assert.equal(await decryptToken(row),body.p_token);
});

test('revocation after a committed registration never yields stale success through reconciliation',async t=>{
 const f=await fixture(t),session=await f.login();f.setGate(async()=>{await f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='controlled_lost_reply_logout' WHERE id=?").bind(sessionId(session)).run();});
 const reply=await f.register(session,{},'lost_reply');assert.ok([401,403].includes(reply.status),JSON.stringify(reply));
 const row=await f.db.prepare('SELECT * FROM notification_devices').first();assert.ok(row);assert.equal(row.owner_session_id,sessionId(session));assert.equal(await decryptToken(row),body.p_token);
});

test('session expiry during a paused commit is evaluated by D1 current time',async t=>{
 const f=await fixture(t),session=await f.login(),at=Math.floor(Date.now()/1000),id=randomUUID(),expires=at+2;
 await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(id,session.user.id,at,at,expires).run();
 const claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url'));const short={...session,access_token:signed({...claims,session_id:id,auth_time:at,iat:at,exp:expires})};
 f.setGate(async()=>{await new Promise(resolve=>setTimeout(resolve,Math.max(1,expires*1000-Date.now()+100)));});
 const result=await f.register(short,{},'before_commit');assert.ok([401,403].includes(result.status),JSON.stringify(result));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM notification_devices').first()).n,0);
});

test('notification HTTP records preserve the actual app event type and account boundary',async t=>{
 const f=await fixture(t),owner=await f.login(),other=await f.login('+250789123456'),id=randomUUID();
 await f.db.prepare("INSERT INTO notification_events(id,user_id,event_type,title,body,data_json,created_at) VALUES(?,?,'contribution_confirmed','Contribution recorded','Open your private record.','{}',?)").bind(id,owner.user.id,new Date().toISOString()).run();
 const result=await f.events(owner);assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.length,1);assert.equal(result.body[0].id,id);assert.equal(result.body[0].type,'contribution_confirmed');assert.equal(result.body[0].event_type,'contribution_confirmed');
 assert.deepEqual((await f.events(other)).body,[]);
});

test('notification reads recheck session revocation in the same D1 batch as private rows',async t=>{
 const f=await fixture(t),session=await f.login();
 await f.db.prepare("INSERT INTO notification_events(id,user_id,event_type,title,body,data_json,created_at) VALUES(?,?,'security_notice','Private','Controlled private event.','{}',?)").bind(randomUUID(),session.user.id,new Date().toISOString()).run();
 f.setGate(async()=>{await f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='controlled_notification_read_logout' WHERE id=?").bind(sessionId(session)).run();});
 const result=await f.events(session,'before_read');assert.equal(result.status,403,JSON.stringify(result));assert.equal(result.body.code,'notification_access_changed');assert.ok(!JSON.stringify(result.body).includes('Controlled private event.'));
});
