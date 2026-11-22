import {ApiError, digest, json, now, readJson} from './core.js';
import {encrypt, decrypt} from './encryption.js';

const AUTHORIZE = 'https://accounts.google.com/o/oauth2/v2/auth';
const TOKEN = 'https://oauth2.googleapis.com/token';
const JWKS = 'https://www.googleapis.com/oauth2/v3/certs';
const encoder = new TextEncoder();
const unix = () => Math.floor(Date.now() / 1000);
const b64 = value => {
  let binary = ''; for (const byte of new Uint8Array(value)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
};
const random = () => b64(crypto.getRandomValues(new Uint8Array(32)));
const fail = (code = 'invalid_google_sign_in', status = 401) => {
  throw new ApiError(status, code, 'Google sign-in could not finish. Please try again.');
};
function settings(env) {
  if (env.GOOGLE_AUTH_ENABLED !== 'true') fail('google_auth_unavailable', 503);
  if (typeof env.GOOGLE_CLIENT_ID !== 'string' || !/^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/.test(env.GOOGLE_CLIENT_ID) ||
      typeof env.GOOGLE_CLIENT_SECRET !== 'string' || env.GOOGLE_CLIENT_SECRET.length < 16) fail('google_auth_unavailable', 503);
  let redirect;
  try { redirect = new URL(env.GOOGLE_REDIRECT_URI); } catch { fail('google_auth_unavailable', 503); }
  if (redirect.protocol !== 'https:' || redirect.pathname !== '/v1/auth/google/callback' ||
      redirect.search || redirect.hash || redirect.username || redirect.password) fail('google_auth_unavailable', 503);
  return {clientId: env.GOOGLE_CLIENT_ID, secret: env.GOOGLE_CLIENT_SECRET, redirect: redirect.href};
}
function decode(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) fail();
  try {
    const bytes = Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
    if (b64(bytes) !== value) fail();
    return bytes;
  } catch { fail(); }
}
async function googleIdentity(token, config, flow, boundedReply) {
  if (typeof token !== 'string' || token.length > 16384 || token.split('.').length !== 3) fail();
  const [head, body, signature] = token.split('.'); let header, claims;
  try {
    header = JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(decode(head)));
    claims = JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(decode(body)));
  } catch { fail(); }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' || header.kid.length > 200 || header.crit) fail();
  const response = await fetch(JWKS, {redirect:'manual', signal:AbortSignal.timeout(10000)});
  if (!response.ok) fail('google_auth_unavailable',503);
  const keys = await boundedReply(response, 65536);
  const key = Array.isArray(keys.keys) && keys.keys.length <= 20 && keys.keys.find(k => k.kid === header.kid && k.kty === 'RSA' && k.alg === 'RS256' && k.use === 'sig');
  if (!key) fail();
  const imported = await crypto.subtle.importKey('jwk', key, {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
  if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5', imported, decode(signature), encoder.encode(`${head}.${body}`))) fail();
  const timestamp = unix();
  if (!['https://accounts.google.com','accounts.google.com'].includes(claims.iss) || claims.aud !== config.clientId ||
      (claims.azp !== undefined && claims.azp !== config.clientId) ||
      !Number.isSafeInteger(claims.exp) || claims.exp <= timestamp ||
      !Number.isSafeInteger(claims.iat) || claims.iat > timestamp+30 || claims.iat < flow.created_at-30 ||
      claims.nonce !== flow.nonce || typeof claims.sub !== 'string' || !/^[A-Za-z0-9_-]{1,255}$/.test(claims.sub) ||
      claims.email_verified !== true || typeof claims.email !== 'string' || claims.email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(claims.email)) fail();
  const email = claims.email.toLowerCase();
  // Google explicitly warns that email_verified alone is not authoritative for
  // third-party addresses. Those accounts must prove current mailbox ownership.
  if (!email.endsWith('@gmail.com') && !(typeof claims.hd === 'string' && claims.hd.length > 0 && email.endsWith(`@${claims.hd.toLowerCase()}`)))
    fail('google_use_email_sign_in', 403);
  return {subject:claims.sub, email};
}
function callbackResult(flow, data) {
  const target = flow.return_origin;
  if (!target) {
    const url = new URL('collect://auth/google');
    for (const [key,value] of Object.entries(data)) url.searchParams.set(key,value);
    return new Response(null,{status:302,headers:{Location:url.href,'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
  }
  // Only transient, PKCE-bound handoff data reaches the opener; never a session.
  const nonce = random();
  const payload = JSON.stringify({type:'collect-google-auth',...data}).replace(/</g,'\\u003c');
  const html = `<!doctype html><html><head><meta name="referrer" content="no-referrer"><title>Collect sign-in</title></head><body><p>You can return to Collect.</p><script nonce="${nonce}">if(window.opener){window.opener.postMessage(${payload},${JSON.stringify(target)});window.close();}</script></body></html>`;
  return new Response(html,{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'no-referrer',
    'Content-Security-Policy':`default-src 'none'; script-src 'nonce-${nonce}'; frame-ancestors 'none'; base-uri 'none'`,
    'X-Content-Type-Options':'nosniff'}});
}
export async function handleGoogleAuth(request, env, config, helpers) {
  const {primary, turnstile, sessionJson, randomCode, refreshToken, requireFields, mac, boundedReply} = helpers;
  const path = new URL(request.url).pathname;
  const google = settings(env), db = primary(env);
  if (path.endsWith('/start')) {
    const body = await readJson(request,8192);
    requireFields(body,['surface','captcha_token','code_challenge','client_state','return_origin']);
    if ((body.surface ?? 'member') !== 'member') fail('invalid_request',400);
    if (!/^[A-Za-z0-9_-]{43}$/.test(body.code_challenge ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(body.client_state ?? '')) fail('invalid_request',400);
    let returnOrigin = null;
    if (body.return_origin != null) {
      const allowed = (env.GOOGLE_WEB_ORIGINS ?? '').split(',').filter(Boolean);
      let url; try {url = new URL(body.return_origin);} catch {fail('invalid_request',400);}
      if (url.protocol !== 'https:' || url.origin !== body.return_origin || !allowed.includes(url.origin)) fail('origin_denied',403);
      returnOrigin = url.origin;
    }
    await turnstile(request,env,config,body);
    const id = crypto.randomUUID(), state = random(), nonce = random(), verifier = random(), timestamp = unix();
    const source = await mac(config.hashSecret, `collect-google-source:${request.headers.get('CF-Connecting-IP') ?? 'unknown'}`);
    const bucket = `google:${source}:${Math.floor(timestamp/3600)}`;
    const result = await db.batch([
      db.prepare('DELETE FROM auth_google_flows WHERE expires_at<=?').bind(timestamp),
      db.prepare(`INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at) VALUES(?,1,?)
        ON CONFLICT(bucket_key) DO UPDATE SET used=used+1 WHERE used<30 RETURNING used`).bind(bucket,timestamp+3600),
      db.prepare(`INSERT INTO auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,return_origin,registration_allowed,created_at,expires_at,status)
        SELECT ?,?,?,?,?,?,?,?,?,?,'pending' WHERE (SELECT used FROM auth_rate_buckets WHERE bucket_key=?)<30`).bind(id,await digest(state),nonce,
        await encrypt(env,encoder.encode(verifier),`google-flow:${id}`),body.code_challenge,body.client_state,returnOrigin,config.memberRegistration?1:0,timestamp,timestamp+300,bucket)
    ]);
    if (!result[2].meta.changes) fail('auth_rate_limited',429);
    const url = new URL(AUTHORIZE);
    url.search = new URLSearchParams({client_id:google.clientId,redirect_uri:google.redirect,response_type:'code',scope:'openid email',
      state,nonce,code_challenge:b64(await crypto.subtle.digest('SHA-256',encoder.encode(verifier))),code_challenge_method:'S256',prompt:'select_account'}).toString();
    return json({authorization_url:url.href,expires_in:300});
  }
  if (path.endsWith('/callback')) {
    const query = new URL(request.url).searchParams;
    const state = query.get('state');
    if (!/^[A-Za-z0-9_-]{43}$/.test(state ?? '') || query.getAll('state').length !== 1) fail();
    const flow = await db.prepare(`UPDATE auth_google_flows SET status='exchanging' WHERE state_hash=? AND status='pending' AND expires_at>? RETURNING *`)
      .bind(await digest(state),unix()).first();
    if (!flow) fail();
    try {
      if (query.has('error')) fail('google_cancelled',400);
      const code = query.get('code'); if (!code || code.length > 4096 || query.getAll('code').length !== 1) fail();
      const verifier = new TextDecoder().decode(await decrypt(env,flow.provider_verifier,`google-flow:${flow.id}`));
      const reply = await fetch(TOKEN,{method:'POST',redirect:'manual',signal:AbortSignal.timeout(10000),
        body:new URLSearchParams({code,client_id:google.clientId,client_secret:google.secret,redirect_uri:google.redirect,grant_type:'authorization_code',code_verifier:verifier})});
      if (!reply.ok) fail();
      const tokens = await boundedReply(reply,32768);
      const identity = await googleIdentity(tokens.id_token,google,flow,boundedReply);
      const handoff = random();
      const ready = await db.prepare(`UPDATE auth_google_flows SET status='ready',google_subject=?,email=?,handoff_hash=?
        WHERE id=? AND status='exchanging' AND expires_at>? RETURNING id`).bind(identity.subject,identity.email,await digest(handoff),flow.id,unix()).first();
      if (!ready) fail();
      return callbackResult(flow,{code:handoff,state:flow.client_state});
    } catch (error) {
      await db.prepare(`UPDATE auth_google_flows SET status='failed' WHERE id=? AND status='exchanging'`).bind(flow.id).run();
      return callbackResult(flow,{error:error instanceof ApiError && ['google_cancelled','google_use_email_sign_in'].includes(error.code)?error.code:'invalid_google_sign_in',state:flow.client_state});
    }
  }
  const body = await readJson(request,8192); requireFields(body,['code','code_verifier']);
  if (!/^[A-Za-z0-9_-]{43}$/.test(body.code ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(body.code_verifier ?? '')) fail();
  const hash = await digest(body.code), challenge = b64(await crypto.subtle.digest('SHA-256',encoder.encode(body.code_verifier)));
  const flow = await db.prepare(`SELECT * FROM auth_google_flows WHERE handoff_hash=? AND client_challenge=? AND status='ready' AND expires_at>?`).bind(hash,challenge,unix()).first();
  if (!flow) fail();
  const operation = crypto.randomUUID(), sessionId = crypto.randomUUID(), newUserId = crypto.randomUUID();
  const rawRefresh = refreshToken(), refreshHash = await digest(rawRefresh);
  for (let attempt=0;attempt<5;attempt++) {
    const timestamp = unix(), date = now();
    try {
      const results = await db.batch([
        db.prepare(`UPDATE auth_google_flows SET status='consumed',consumed_operation_id=? WHERE id=? AND status='ready' AND expires_at>?`).bind(operation,flow.id,timestamp),
        db.prepare(`INSERT INTO users(id,email,public_id,created_at,updated_at)
          SELECT ?,f.email,?,?,? FROM auth_google_flows f WHERE f.id=? AND f.consumed_operation_id=? AND f.registration_allowed=1
          AND NOT EXISTS(SELECT 1 FROM auth_google_identities WHERE subject=f.google_subject)
          AND NOT EXISTS(SELECT 1 FROM users WHERE lower(email)=f.email)`)
          .bind(newUserId,randomCode(),date,date,flow.id,operation),
        db.prepare(`INSERT INTO auth_google_identities(subject,user_id,created_at)
          SELECT f.google_subject,u.id,? FROM auth_google_flows f JOIN users u ON lower(u.email)=f.email
          WHERE f.id=? AND f.consumed_operation_id=? AND u.access_status='active'
          AND (SELECT count(*) FROM users WHERE lower(email)=f.email)=1
          AND NOT EXISTS(SELECT 1 FROM auth_google_identities WHERE subject=f.google_subject OR user_id=u.id)`)
          .bind(date,flow.id,operation),
        db.prepare(`INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
          SELECT ?,u.id,'member',?,?,? FROM auth_google_flows f JOIN auth_google_identities g ON g.subject=f.google_subject
          JOIN users u ON u.id=g.user_id WHERE f.id=? AND f.consumed_operation_id=? AND u.access_status='active'`)
          .bind(sessionId,timestamp,timestamp,timestamp+config.refreshSeconds,flow.id,operation),
        db.prepare(`INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at)
          SELECT ?,id,created_at,expires_at FROM auth_sessions WHERE id=?`).bind(refreshHash,sessionId),
        db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
          SELECT user_id,id,'auth.google.session.created','auth_session',id,?,'{}',? FROM auth_sessions WHERE id=?`).bind(operation,date,sessionId),
        db.prepare('SELECT * FROM auth_sessions WHERE id=?').bind(sessionId),
        db.prepare('SELECT u.* FROM users u JOIN auth_sessions s ON s.user_id=u.id WHERE s.id=?').bind(sessionId)
      ]);
      const session=results[6].results[0], user=results[7].results[0];
      if (!session || !user) fail('access_revoked');
      return json({...await sessionJson(config,db,session,user),refresh_token:rawRefresh});
    } catch(error) {
      if (!String(error?.message).includes('users.public_id') || attempt===4) throw error;
    }
  }
}
