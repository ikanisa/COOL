import {ApiError,readJson,json,first,id,digest} from './core.js';
import {encrypt,decrypt} from './encryption.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {responseSession} from './auth.js';

export const GOOGLE_PROJECT_ORIGIN='https://rrlduytparvsjfmegalh.supabase.co';
export const GOOGLE_APPLICATION_CALLBACK='https://platform-admin.collect.ikanisa.com/functions/v1/collect-api/v1/auth/google/callback';
const GOOGLE_APPLICATION_CALLBACKS=new Set([GOOGLE_APPLICATION_CALLBACK,'https://admin-supabase-qa.collect.ikanisa.com/functions/v1/collect-api/v1/auth/google/callback']);
const unix=()=>Math.floor(Date.now()/1000);
const random=()=>btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
const b64=bytes=>btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
const opaque=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{43}$/.test(value);
const fail=(code='invalid_google_sign_in',status=400)=>{throw new ApiError(status,code,'Google sign-in could not finish.');};
const custody=env=>({...env,DATA_KEY_ID:env.SESSION_KEY_ID??'bff-v1',DATA_ENCRYPTION_KEY:env.SESSION_ENCRYPTION_KEY,DATA_DECRYPTION_KEYS_JSON:env.SESSION_DECRYPTION_KEYS_JSON});
const configured=env=>{
 if(env.GOOGLE_AUTH_ENABLED!=='true')fail('google_auth_unavailable',503);
 const callback=env.COLLECT_GOOGLE_CALLBACK_URL??env.SUPABASE_GOOGLE_CALLBACK_URL;
 if(env.COLLECT_GOOGLE_CALLBACK_URL!==undefined&&env.SUPABASE_GOOGLE_CALLBACK_URL!==undefined&&env.COLLECT_GOOGLE_CALLBACK_URL!==env.SUPABASE_GOOGLE_CALLBACK_URL)fail('google_auth_unavailable',503);
 if(env.SUPABASE_URL!==GOOGLE_PROJECT_ORIGIN||!GOOGLE_APPLICATION_CALLBACKS.has(callback))fail('google_auth_unavailable',503);
 return callback;
};
function origins(value='') {
 const result=value.split(',').map(v=>v.trim()).filter(Boolean);
 if(result.some(v=>{try{const u=new URL(v);return u.origin!==v||u.protocol!=='https:'||u.username||u.password;}catch{return true;}}))fail('google_auth_unavailable',503);
 return result;
}
function frontend(request,env,surface,returnOrigin,callback) {
 const origin=request.headers.get('Origin');
 const allowed=surface==='admin'?origins(env.ADMIN_ORIGINS??env.ADMIN_ORIGIN):origins(env.GOOGLE_WEB_ORIGINS);
 if(request.headers.get('Sec-Fetch-Site')==='cross-site')fail('origin_denied',403);
 if(surface==='admin'&&(!origin||!allowed.includes(origin)||request.headers.get('X-Collect-Requested-With')!=='collect-admin'||new URL(callback).origin!==origin))fail('origin_denied',403);
 if(origin&&(!allowed.includes(origin)||returnOrigin!==origin))fail('origin_denied',403);
 if(!origin&&returnOrigin!==null)fail('origin_denied',403);
 return origin;
}
function contextMatches(request,context,surface) {
 if(!context||context.surface!==surface)fail();
 if(request.headers.get('Sec-Fetch-Site')==='cross-site'||(request.headers.get('Origin')??null)!==context.request_origin)fail('origin_denied',403);
 if(surface==='admin'&&(!context.request_origin||request.headers.get('X-Collect-Requested-With')!=='collect-admin'))fail('origin_denied',403);
}
async function contextFor(env,flow,callback) {
 const context=await first(env,'SELECT surface,request_origin FROM private.google_flow_context WHERE flow_id=?',flow.id);
 if(!context||!['member','admin'].includes(context.surface)||context.surface==='admin'&&!context.request_origin||context.request_origin!==flow.return_origin)fail();
 const allowed=context.surface==='admin'?origins(env.ADMIN_ORIGINS??env.ADMIN_ORIGIN):origins(env.GOOGLE_WEB_ORIGINS);
 if(context.request_origin&&!allowed.includes(context.request_origin)||context.surface==='admin'&&new URL(callback).origin!==context.request_origin)fail('origin_denied',403);
 return context;
}
async function abandon(env,flow,session=null) {
 // Local scope revokes only the managed session created for this flow.
 if(session?.access_token)await authRequest(env,'/logout?scope=local',{token:session.access_token}).catch(()=>{});
 await env.DB.prepare("UPDATE auth_google_flows SET status='failed',provider_verifier='{}' WHERE id=? AND status IN('pending','exchanging','ready')").bind(flow.id).run().catch(()=>{});
}
function tokens(session,claims) {
 if(typeof session.access_token!=='string'||session.access_token.length>16384||typeof session.refresh_token!=='string'||!session.refresh_token||session.refresh_token.length>4096)fail();
 return {access_token:session.access_token,refresh_token:session.refresh_token,expires_at:claims.exp,expires_in:Math.max(1,claims.exp-unix()),token_type:'bearer'};
}
function googleIdentity(verified) {
 return Boolean(verified.user.email_confirmed_at&&typeof verified.user.email==='string'&&verified.user.identities?.some(identity=>identity.provider==='google'));
}

export function callbackResult(flow,data) {
 const target=flow.return_origin;
 if(!target){
  if(flow.surface==='admin')fail();
  const url=new URL('collect://auth/google');for(const[key,value]of Object.entries(data))url.searchParams.set(key,value);
  return new Response(null,{status:302,headers:{Location:url.href,'X-Collect-Document':'collect.google.native.v1','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
 }
 // Only transient PKCE-bound handoff data reaches the opener, never a session.
 const nonce=random(),payload=JSON.stringify({type:'collect-google-auth',...data}).replace(/</g,'\\u003c');
 const targetJson=JSON.stringify(target).replace(/</g,'\\u003c');
 const html=`<!doctype html><html><head><meta name="referrer" content="no-referrer"><title>Collect sign-in</title></head><body><p>You can return to Collect.</p><script nonce="${nonce}">if(window.opener){window.opener.postMessage(${payload},${targetJson});window.close();}</script></body></html>`;
 return new Response(html,{headers:{'Content-Type':'text/html; charset=utf-8','X-Collect-Document':'collect.google.callback.v1','Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':`default-src 'none'; script-src 'nonce-${nonce}'; frame-ancestors 'none'; base-uri 'none'`,'X-Content-Type-Options':'nosniff'}});
}

export async function startGoogleFlow(request,env,{surface='member'}={}) {
 const callback=configured(env);if(request.method!=='POST')fail('method_not_allowed',405);
 if(!['member','admin'].includes(surface))fail();
 const body=await readJson(request,8192);
 if(body.surface!==undefined&&body.surface!==surface||!opaque(body.code_challenge)||!opaque(body.client_state))fail('invalid_request');
 const returnOrigin=body.return_origin??null,requestOrigin=frontend(request,env,surface,returnOrigin,callback);
 const fid=id(),state=random(),verifier=random(),at=unix();
 const cipher=await encrypt(custody(env),new TextEncoder().encode(verifier),'google-flow:'+fid);
 // The immutable private surface/origin context and public-shape flow are one transaction.
 await env.DB.batch([
  env.DB.prepare("INSERT INTO auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,return_origin,registration_allowed,created_at,expires_at,status) VALUES(?,?,?,?,?,?,?,?,?,?,'pending')").bind(fid,await digest(state),random(),cipher,body.code_challenge,body.client_state,returnOrigin,Number(surface==='member'&&env.AUTH_MEMBER_REGISTRATION_ENABLED==='true'),at,at+300),
  env.DB.prepare('INSERT INTO private.google_flow_context(flow_id,surface,request_origin) VALUES(?,?,?)').bind(fid,surface,requestOrigin),
 ]);
 const redirect=new URL(callback);redirect.searchParams.set('state',state);
 const target=new URL(GOOGLE_PROJECT_ORIGIN+'/auth/v1/authorize');
 target.search=new URLSearchParams({provider:'google',redirect_to:redirect.href,code_challenge:b64(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))),code_challenge_method:'s256',scopes:'openid email profile',prompt:'select_account'}).toString();
 return json({authorization_url:target.href,expires_in:300});
}

async function googleCallback(request,env,callback) {
 const params=new URL(request.url).searchParams,state=params.get('state');
 if(!opaque(state)||new URL(request.url).search.length>12288||['state','code','error','error_code','error_description'].some(k=>params.getAll(k).length>1)||params.has('code')&&params.has('error'))fail();
 const flow=await first(env,"SELECT * FROM auth_google_flows WHERE state_hash=? AND status='pending' AND expires_at>?",await digest(state),unix());if(!flow)fail();
 const context=await contextFor(env,flow,callback);
 const claimed=await env.DB.prepare("UPDATE auth_google_flows SET status='exchanging' WHERE id=? AND status='pending' AND expires_at>? RETURNING id").bind(flow.id,unix()).first();if(!claimed)fail();
 let session;
 try {
  if(params.has('error')){await abandon(env,flow);return callbackResult({...flow,surface:context.surface},{error:'google_cancelled',state:flow.client_state});}
  const code=params.get('code');if(!code||code.length>4096)fail();
  const verifier=new TextDecoder('utf-8',{fatal:true}).decode(await decrypt(custody(env),flow.provider_verifier,'google-flow:'+flow.id));if(!opaque(verifier))fail();
  session=await authRequest(env,'/token?grant_type=pkce',{body:{auth_code:code,code_verifier:verifier}});
  const verified=await verifyToken(env,session.access_token);if(!googleIdentity(verified))fail('google_use_email_sign_in',403);
  const managed=tokens(session,verified.claims),handoff=random(),hash=await digest(handoff);
  const cipher=await encrypt(custody(env),new TextEncoder().encode(JSON.stringify(managed)),'google-handoff:'+flow.id);
  let ready;
  try {ready=await env.DB.prepare("UPDATE auth_google_flows SET status='ready',provider_verifier=?,handoff_hash=? WHERE id=? AND status='exchanging' RETURNING id").bind(cipher,hash,flow.id).first();}
  catch(error){const check=await first(env,'SELECT status,handoff_hash FROM auth_google_flows WHERE id=?',flow.id).catch(()=>null);if(check?.status==='ready'&&check.handoff_hash===hash)ready={id:flow.id};else throw error;}
  if(!ready)fail();
  return callbackResult({...flow,surface:context.surface},{code:handoff,state:flow.client_state});
 }catch(error){
  await abandon(env,flow,session);
  const code=error instanceof ApiError&&error.status<500?error.code==='google_use_email_sign_in'?'google_use_email_sign_in':'invalid_google_sign_in':'google_sign_in_unconfirmed';
  return callbackResult({...flow,surface:context.surface},{error:code,state:flow.client_state});
 }
}

/** @param {Request} request
 * @param {any} env
 * @param {{surface?:'member'|'admin',admit?:null|((request:Request,env:any,tokens:any)=>Promise<Response>)}} options */
export async function exchangeGoogleFlow(request,env,{surface='member',admit=null}={}) {
 const callback=configured(env);if(request.method!=='POST')fail('method_not_allowed',405);
 if(surface==='admin')frontend(request,env,surface,request.headers.get('Origin'),callback);
 const body=await readJson(request,8192);if(!opaque(body.code)||!opaque(body.code_verifier)||body.client_state!==undefined&&!opaque(body.client_state))fail();
 const flow=await first(env,"SELECT * FROM auth_google_flows WHERE handoff_hash=? AND status='ready' AND expires_at>?",await digest(body.code),unix());if(!flow)fail();
 const context=await contextFor(env,flow,callback);contextMatches(request,context,surface);
 if(body.client_state!==undefined&&body.client_state!==flow.client_state||surface==='admin'&&body.client_state!==flow.client_state)fail();
 const challenge=b64(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(body.code_verifier)));if(challenge!==flow.client_challenge)fail();
 const operation=id();let claimed;
 try {claimed=await env.DB.prepare("UPDATE auth_google_flows SET status='consumed',consumed_operation_id=?,provider_verifier='{}' WHERE id=? AND client_challenge=? AND status='ready' AND expires_at>? RETURNING id").bind(operation,flow.id,challenge,unix()).first();}
 catch(error){const check=await first(env,'SELECT status,consumed_operation_id FROM auth_google_flows WHERE id=?',flow.id).catch(()=>null);if(check?.status==='consumed'&&check.consumed_operation_id===operation)claimed={id:flow.id};else throw new ApiError(503,'google_sign_in_unconfirmed','Check your session before starting a fresh sign-in.');}
 if(!claimed)fail();
 let session;
 try {
  session=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(await decrypt(custody(env),flow.provider_verifier,'google-handoff:'+flow.id)));
  const verified=await verifyToken(env,session.access_token);if(!googleIdentity(verified))fail('google_use_email_sign_in',403);
  const managed=tokens(session,verified.claims);
  if(surface==='admin'){
   if(typeof admit!=='function')fail('admin_cookie_required',403);
   // The caller's exact Origin already matches the immutable approved flow.
   return await admit(request,env,managed);
  }
  const result=await responseSession({...env,AUTH_MEMBER_REGISTRATION_ENABLED:flow.registration_allowed?'true':'false'},managed,{surface:'member'});
  return json(result);
 }catch(error){
  await abandon(env,flow,session);
  if(error instanceof ApiError&&error.status<500)throw error;
  throw new ApiError(503,'google_sign_in_unconfirmed','Check your session before starting a fresh sign-in.');
 }
}

export async function handleGoogleAuth(request,env) {
 const path=new URL(request.url).pathname;
 if(!['/v1/auth/google/start','/v1/auth/google/callback','/v1/auth/google/exchange'].includes(path))fail('not_found',404);
 const callback=configured(env);if(request.method!==(path.endsWith('/callback')?'GET':'POST'))fail('method_not_allowed',405);
 if(path.endsWith('/start'))return startGoogleFlow(request,env);
 if(path.endsWith('/callback'))return googleCallback(request,env,callback);
 return exchangeGoogleFlow(request,env);
}
