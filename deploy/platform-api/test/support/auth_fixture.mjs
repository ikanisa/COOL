import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID, createHmac} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');

// Only outbound delivery/Turnstile acknowledgements are controlled fixtures.
// All SQL, transactions, trigger constraints and auth code run in workerd/D1.
const {Miniflare, convertV4MiniflareOptions} = await import(process.env.COLLECT_MINIFLARE_MODULE ?? 'miniflare');
const root = new URL('../../', import.meta.url);
const jwtSecret = 'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890';
const tokenSecret = 'test-identity-hashing-key-unique-isolated-runtime-only-0987654321';
const dataKey = Buffer.from(Array.from({length:32}, (_,i)=>i+1)).toString('base64');


async function fixture(overrides={}, {entrypoint=null,extraModules=[],identityEpochs=null,migrationsThrough=null,outbound=null,emailBinding=false}={}) {
  if(entrypoint && identityEpochs)throw new Error('Identity epoch selection belongs only to the controlled Auth test entrypoint');
  const messages=[], captchaSeen=new Set(), trace=[]; let delivery='accepted', captcha='valid';
  async function bundledModules(folder,prefix=''){const found=[];for(const entry of await readdir(folder,{withFileTypes:true})){if(entry.isDirectory())found.push(...await bundledModules(new URL(entry.name+'/',folder),prefix+entry.name+'/'));else if(!entry.name.startsWith('._')&&entry.name.endsWith('.js'))found.push(prefix+entry.name);}return found;}
  const bundled=entrypoint?await bundledModules(new URL('src/',root)):[];
  const moduleNames=[...new Set(['auth.js','core.js','encryption.js','identity_keys.js','google_auth.js','email_delivery.js',...extraModules,...bundled])].filter(name=>name!==entrypoint);
  const modules=[entrypoint ? {type:'ESModule',path:fileURLToPath(new URL(`src/${entrypoint}`,root)),contents:await readFile(new URL(`src/${entrypoint}`,root),'utf8')} : {type:'ESModule',path:fileURLToPath(new URL('test/entry.mjs',root)), contents:`
    import {handleAuth,requireSession} from '../src/auth.js';
    import {ApiError,json} from '../src/core.js';
    export default {async fetch(request,env) {
      if(${JSON.stringify(emailBinding)})env={...env,AUTH_EMAIL:{send:async message=>{
        const reply=await fetch('https://cloudflare-email.test/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(message)});
        if(!reply.ok)throw new Error('Controlled email failure');return reply.json();
      }}};
      const epochs=${JSON.stringify(identityEpochs)},epoch=request.headers.get('X-Test-Identity-Epoch');
      if(epoch){if(!epochs||!Object.hasOwn(epochs,epoch))throw new Error('Unknown controlled identity epoch');env={...env,...epochs[epoch]};}
      if(new URL(request.url).pathname==='/__actor') {
        try {const actor=await requireSession(request,env); return json({...actor,permissions:[...actor.permissions]});}
        catch(e) {if(e instanceof ApiError)return json({error:{code:e.code}},e.status);throw e;}
      }
      return await handleAuth(request,env) ?? new Response('missing',{status:404});
    }};
  `}, ...await Promise.all(moduleNames.map(async name=>({type:'ESModule',path:fileURLToPath(new URL(`src/${name}`,root)),contents:await readFile(new URL(`src/${name}`,root),'utf8')})))];
  const mf=new Miniflare((convertV4MiniflareOptions ?? (value=>value))({modules,modulesRoot:fileURLToPath(root),compatibilityDate:'2026-10-14',
    d1Databases:{DB:randomUUID()},d1Persist:false,r2Buckets:{PRIVATE_MEDIA:randomUUID()},r2Persist:false, cf:false,
    bindings:{APP_ENVIRONMENT:'test',AUTH_JWT_SECRET:jwtSecret,AUTH_TOKEN_HASH_SECRET:tokenSecret,AUTH_ISSUER:'collect-test',AUTH_AUDIENCE:'collect',
      AUTH_MEMBER_REGISTRATION_ENABLED:'true',OTP_DELIVERY_URL:'https://trusted-relay.example/otp',OTP_DELIVERY_TOKEN:'test-relay-token-123456789',
      TURNSTILE_REQUIRED:'true',TURNSTILE_SECRET:'test-turnstile-secret-123456',TURNSTILE_HOSTNAME:'collect.example',TURNSTILE_ACTION:'collect-login',
      ALLOWED_ORIGINS:'https://collect.example,https://admin.collect.example',DATA_ENCRYPTION_KEY:dataKey,DATA_KEY_ID:'auth-test-v1',...overrides},
    outboundService:async request=>{
      const url=new URL(request.url);trace.push({url:url.href,method:request.method});
      if(outbound){const reply=await outbound(request);if(reply)return reply;}
      if(url.href==='https://challenges.cloudflare.com/turnstile/v0/siteverify') {
        if(captcha==='outage')return new Response('unavailable',{status:503});
        const form=new URLSearchParams(await request.text()), token=form.get('response');
        const success=token && !captchaSeen.has(token) && captcha==='valid'; captchaSeen.add(token);
        return Response.json({success,hostname:captcha==='wrong_host'?'evil.example':'collect.example',action:'collect-login',challenge_ts:new Date().toISOString()});
      }
      assert.equal(url.href,'https://trusted-relay.example/otp','Unexpected outbound network');
      assert.equal(request.headers.get('authorization'),'Bearer test-relay-token-123456789');
      const body=await request.json();messages.push(body);
      if(delivery==='unacknowledged')return new Response('lost acknowledgement',{status:502});
      if(delivery==='wrong_id')return Response.json({accepted:true,request_id:randomUUID()});
      return Response.json({accepted:true,request_id:body.request_id});
    }}));
  let db;
  try {
  db=await mf.getD1Database('DB');
  // Use the installed Wrangler SQL splitter, including top-level seed INSERTs and complete trigger bodies.
  for(const name of (await readdir(new URL('migrations/',root))).filter(name=>/^\d+.*\.sql$/.test(name)).sort()) {
    if(migrationsThrough!==null && Number(name.slice(0,4))>migrationsThrough)continue;
    const sql=await readFile(new URL(`migrations/${name}`,root),'utf8');
    for(const statement of unstable_splitSqlQuery(sql))
      try {await db.prepare(statement).run();} catch(error) {throw new Error(`Migration ${name}: ${statement.slice(0,100)}`,{cause:error});}
  }
  } catch(error) {await mf.dispose();throw error;}
  const f={mf,db,messages,trace,setDelivery(value){delivery=value;},setCaptcha(value){captcha=value;},async close(){await mf.dispose();}};
  f.call=async(path,body={},headers={})=>{
    const method=path==='/v1/auth/user'||path==='/__actor'?'GET':'POST';
    const response=await mf.dispatchFetch(`https://api.collect.example${path}`,{method,headers:{'content-type':'application/json','CF-Connecting-IP':'192.0.2.1',...headers},
      ...(method==='POST'?{body:JSON.stringify(body)}:{})});
    return {status:response.status,body:await response.json(),headers:response.headers};
  };
  f.otp=async(identity={phone:'+250788123456'},extra={})=>f.call('/v1/auth/otp',{...identity,captcha_token:randomUUID(),...extra});
  f.verify=async(response,identity={phone:'+250788123456'},extra={})=>{
    const message=messages.find(value=>value.request_id===response.body.challenge_id);assert.ok(message,'Test relay observed delivery');
    return f.call('/v1/auth/verify',{...identity,challenge_id:response.body.challenge_id,code:message.code,captcha_token:randomUUID(),...extra});
  };
  f.login=async(identity,extra={})=>{const otp=await f.otp(identity);assert.equal(otp.status,202,JSON.stringify(otp.body));const result=await f.verify(otp,identity,extra);assert.equal(result.status,200,JSON.stringify(result.body));return result.body;};
  f.actor=async(session)=>f.call('/__actor',{}, {Authorization:`Bearer ${session.access_token}`});
  return f;
}
async function using(t,overrides={}) {const f=await fixture(overrides);t.after(()=>f.close());return f;}
const authorization=session=>({Authorization:`Bearer ${session.access_token}`});
const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString());
function signed(claimsValue,header={alg:'HS256',typ:'JWT'}) {
  const h=Buffer.from(JSON.stringify(header)).toString('base64url'),b=Buffer.from(JSON.stringify(claimsValue)).toString('base64url');
  return `${h}.${b}.${createHmac('sha256',jwtSecret).update(`${h}.${b}`).digest('base64url')}`;
}
async function admin(f,{grant=true,enrollment=true,email='operator@example.com'}={}) {
  const id=randomUUID(),date=new Date().toISOString(),publicId=String(100000+(await f.db.prepare('SELECT count(*) AS n FROM users').first()).n);
  await f.db.prepare('INSERT INTO users(id,email,public_id,created_at,updated_at) VALUES(?,?,?,?,?)').bind(id,email,publicId,date,date).run();
  if(grant)await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(id,'payments.reconcile',date).run();
  if(enrollment)await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(id,'auth.mfa.enroll',date).run();
  return {id,identity:{email,surface:'admin'}};
}
function decode32(value) {let bits=0,n=0;const bytes=[];for(const char of value){n=(n<<5)|'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(char);bits+=5;while(bits>=8){bits-=8;bytes.push((n>>>bits)&255);}}return Buffer.from(bytes);}
function totp(secret,counter=Math.floor(Date.now()/30000)) {
  const bytes=Buffer.alloc(8);bytes.writeBigUInt64BE(BigInt(counter));
  const mac=createHmac('sha1',decode32(secret)).update(bytes).digest(),offset=mac[19]&15;
  return ((mac.readUInt32BE(offset)&0x7fffffff)%1000000).toString().padStart(6,'0');
}
async function setupMfa(f,session) {
  const enroll=await f.call('/v1/auth/mfa/enroll',{},authorization(session));assert.equal(enroll.status,200,JSON.stringify(enroll.body));
  const challenge=await f.call('/v1/auth/mfa/challenge',{factor_id:enroll.body.id},authorization(session));assert.equal(challenge.status,200);
  return {factor:enroll.body,challenge:challenge.body};
}


export {fixture,using,authorization,claims,signed,admin,totp,setupMfa};
