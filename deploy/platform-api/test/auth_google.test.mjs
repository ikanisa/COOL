import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,createSign,createHash,randomBytes,randomUUID} from 'node:crypto';
import {fixture} from './support/auth_fixture.mjs';
import {retentionSnapshot} from '../src/privacy_retention_catalog.js';

const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const jwk={...publicKey.export({format:'jwk'}),kid:'controlled-google-key',alg:'RS256',use:'sig'};
const clientId='controlled-client.apps.googleusercontent.com';
const hash=value=>createHash('sha256').update(value).digest('base64url');
const random=()=>randomBytes(32).toString('base64url');
function jwt(claims,header={alg:'RS256',kid:jwk.kid}) {
  const head=Buffer.from(JSON.stringify(header)).toString('base64url'),body=Buffer.from(JSON.stringify(claims)).toString('base64url');
  return `${head}.${body}.${createSign('RSA-SHA256').update(`${head}.${body}`).sign(privateKey).toString('base64url')}`;
}
async function setup(t,overrides={},options={}) {
  const codes=new Map(); let alter=claims=>claims,tokenTransform=value=>value;
  const f=await fixture({GOOGLE_AUTH_ENABLED:'true',GOOGLE_CLIENT_ID:clientId,GOOGLE_CLIENT_SECRET:'controlled-google-secret',
    GOOGLE_REDIRECT_URI:'https://api.collect.example/v1/auth/google/callback',GOOGLE_WEB_ORIGINS:'https://collect.example',...overrides},
    {...options,outbound:async request=>{
      if(request.url==='https://www.googleapis.com/oauth2/v3/certs')return Response.json({keys:[jwk]});
      if(request.url!=='https://oauth2.googleapis.com/token')return null;
      const body=new URLSearchParams(await request.text()), pending=codes.get(body.get('code'));
      assert.ok(pending); codes.delete(body.get('code'));
      assert.equal(body.get('client_secret'),'controlled-google-secret');
      assert.equal(hash(body.get('code_verifier')),pending.url.searchParams.get('code_challenge'));
      const timestamp=Math.floor(Date.now()/1000);
      return Response.json({id_token:tokenTransform(jwt(alter({iss:'https://accounts.google.com',aud:clientId,sub:'google-subject-1',
        email:'member@gmail.com',email_verified:true,iat:timestamp,exp:timestamp+3600,nonce:pending.url.searchParams.get('nonce')})))});
    }});
  t.after(()=>f.close());
  f.alter=change=>{alter=change;};
  f.transformToken=change=>{tokenTransform=change;};
  f.start=async(extra={})=>{
    const verifier=random(),state=random();
    const started=await f.call('/v1/auth/google/start',{surface:'member',code_challenge:hash(verifier),client_state:state,captcha_token:randomUUID(),...extra});
    return {verifier,state,started,url:started.status===200?new URL(started.body.authorization_url):null};
  };
  f.callback=async flow=>{
    const code=random(); codes.set(code,flow);
    const response=await f.mf.dispatchFetch(`https://api.collect.example/v1/auth/google/callback?${new URLSearchParams({code,state:flow.url.searchParams.get('state')})}`,
      {headers:{'Sec-Fetch-Site':'cross-site'},redirect:'manual'});
    if(response.status!==302)return {response,text:await response.text()};
    const target=new URL(response.headers.get('location'));
    return {response,target,code:target.searchParams.get('code'),error:target.searchParams.get('error')};
  };
  f.exchange=(callback,flow)=>f.call('/v1/auth/google/exchange',{code:callback.code,code_verifier:flow.verifier});
  return f;
}

test('Google authorization code + PKCE creates one member session; callback and handoff cannot replay',async t=>{
  const f=await setup(t),flow=await f.start(); assert.equal(flow.started.status,200,JSON.stringify(flow.started.body));
  assert.equal(flow.url.searchParams.get('scope'),'openid email');
  const callback=await f.callback(flow); assert.equal(callback.response.status,302); assert.equal(callback.target.searchParams.get('state'),flow.state);
  assert.ok(callback.code); assert.equal(callback.target.host,'auth');
  const session=await f.exchange(callback,flow);assert.equal(session.status,200,JSON.stringify(session.body));
  const actor=await f.actor(session.body);assert.equal(actor.status,200);assert.equal(actor.body.surface,'member');assert.deepEqual(actor.body.permissions,[]);
  assert.equal((await f.exchange(callback,flow)).status,401);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_sessions').first()).n,1);
  assert.equal((await f.callback(flow)).response.status,401);
  const rotated=await f.call('/v1/auth/refresh',{refresh_token:session.body.refresh_token});assert.equal(rotated.status,200);
  assert.equal((await f.call('/v1/auth/logout',{}, {Authorization:`Bearer ${rotated.body.access_token}`})).status,200);
  assert.equal((await f.actor(rotated.body)).status,401);
});

test('Google refuses wrong PKCE without consuming the correct handoff; concurrent exchanges issue one session',async t=>{
  const f=await setup(t),flow=await f.start(),callback=await f.callback(flow);
  assert.equal((await f.exchange(callback,{verifier:random()})).status,401);
  const results=await Promise.all([f.exchange(callback,flow),f.exchange(callback,flow)]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,401]);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_sessions').first()).n,1);
});

test('existing Gmail user is reused, suspension denies Google, and Google never acquires Admin permissions',async t=>{
  const f=await setup(t),original=await f.login({email:'member@gmail.com'});
  await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(original.user.id,'payments.reconcile',new Date().toISOString()).run();
  let flow=await f.start(),callback=await f.callback(flow),session=await f.exchange(callback,flow);
  assert.equal(session.status,200);assert.equal(session.body.user.id,original.user.id);
  assert.deepEqual((await f.actor(session.body)).body.permissions,[]);
  await f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(original.user.id).run();
  flow=await f.start();callback=await f.callback(flow);assert.equal((await f.exchange(callback,flow)).status,401);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,1);
});

test('Google registration policy, Admin surface and arbitrary web return origins fail closed',async t=>{
  const f=await setup(t,{AUTH_MEMBER_REGISTRATION_ENABLED:'false'});
  for(const extra of [{surface:'admin'},{return_origin:'https://evil.example'},{return_origin:'https://collect.example/path'}])
    assert.ok([400,403].includes((await f.start(extra)).started.status));
  const flow=await f.start(),callback=await f.callback(flow);
  assert.equal((await f.exchange(callback,flow)).status,401);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,0);
});

test('Google rejects incorrect audience, issuer, nonce, expiry and unverified or third-party email',async t=>{
  const f=await setup(t);
  for(const change of [c=>({...c,aud:'attacker-client'}),c=>({...c,iss:'https://evil.example'}),c=>({...c,nonce:random()}),
    c=>({...c,exp:1}),c=>({...c,email_verified:false}),c=>({...c,email:'member@example.com'})]) {
    f.alter(change);const flow=await f.start(),callback=await f.callback(flow);
    assert.ok(callback.error); assert.equal(callback.code,null);
  }
  assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,0);
});

test('web callback only posts PKCE handoff to the approved opener origin without session tokens',async t=>{
  const f=await setup(t),flow=await f.start({return_origin:'https://collect.example'}),callback=await f.callback(flow);
  assert.equal(callback.response.status,200); assert.match(callback.text,/window.opener.postMessage/);
  assert.match(callback.text,/https:\/\/collect.example/);assert.doesNotMatch(callback.text,/access_token|refresh_token|controlled-google-secret/);
  assert.match(callback.response.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);
  assert.equal(callback.response.headers.get('cache-control'),'no-store');
});

test('Google cancellation, expired state, unknown state and missing provider configuration create no session',async t=>{
  const f=await setup(t),flow=await f.start();
  const cancelled=await f.mf.dispatchFetch(`https://api.collect.example/v1/auth/google/callback?${new URLSearchParams({error:'access_denied',state:flow.url.searchParams.get('state')})}`,{redirect:'manual'});
  assert.equal(new URL(cancelled.headers.get('location')).searchParams.get('error'),'google_cancelled');
  const expired=await f.start();await f.db.prepare('UPDATE auth_google_flows SET expires_at=created_at-1,created_at=created_at-400').run();
  assert.equal((await f.callback(expired)).response.status,401);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_sessions').first()).n,0);
  const disabled=await setup(t,{GOOGLE_AUTH_ENABLED:'false'});assert.equal((await disabled.start()).started.status,503);
});


test('privacy inventory covers Google subject and verified pending handoffs for the current member only',async t=>{
  const f=await setup(t),flow=await f.start(),callback=await f.callback(flow),session=await f.exchange(callback,flow);
  assert.equal(session.status,200);
  const pending=await f.start();await f.callback(pending);
  const snapshot=await retentionSnapshot({DB:f.db},session.body.user.id);
  assert.equal(snapshot.rows.auth_google_identities.length,1);
  assert.equal(snapshot.rows.auth_google_flows.length,2);
  assert.equal(snapshot.summary.in_flight_unresolved,true);
  const other=await f.login({email:'other@example.com'});
  const isolated=await retentionSnapshot({DB:f.db},other.user.id);
  assert.equal(isolated.rows.auth_google_identities.length,0);
  assert.equal(isolated.rows.auth_google_flows.length,0);
});


test('Google signature tampering cannot create a handoff',async t=>{
  const f=await setup(t);f.transformToken(token=>{const parts=token.split('.');const sig=Buffer.from(parts[2],'base64url');sig[0]^=1;parts[2]=sig.toString('base64url');return parts.join('.');});
  const flow=await f.start(),callback=await f.callback(flow);assert.equal(callback.code,null);assert.ok(callback.error);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,0);
});

test('stable Google subject survives changed email while a second subject cannot take over a bound account',async t=>{
  const f=await setup(t);let flow=await f.start(),callback=await f.callback(flow),session=await f.exchange(callback,flow);
  assert.equal(session.status,200);const owner=session.body.user.id;
  f.alter(c=>({...c,email:'changed@gmail.com'}));flow=await f.start();callback=await f.callback(flow);session=await f.exchange(callback,flow);
  assert.equal(session.status,200);assert.equal(session.body.user.id,owner);
  f.alter(c=>({...c,sub:'google-subject-2'}));flow=await f.start();callback=await f.callback(flow);session=await f.exchange(callback,flow);
  assert.equal(session.status,401);assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,1);
});


test('email and Google sessions read their actual member profile and collection routes through the full API',async t=>{
  const f=await setup(t,{}, {entrypoint:'index.js'});
  const email=await f.login({email:'email-member@example.com'});
  const flow=await f.start(),callback=await f.callback(flow),google=await f.exchange(callback,flow);assert.equal(google.status,200);
  for(const session of [email,google.body]){
    const headers={Authorization:`Bearer ${session.access_token}`};
    const profile=await f.call('/v1/rpc/get_current_member_profile',{},headers);
    assert.equal(profile.status,200,JSON.stringify(profile.body));assert.equal(profile.body.id,session.user.id);
    assert.equal(profile.body.whatsapp_phone,null);
    const groups=await f.call('/v1/rpc/list_current_user_collections',{},headers);
    assert.equal(groups.status,200,JSON.stringify(groups.body));assert.deepEqual(groups.body,[]);
  }
});
