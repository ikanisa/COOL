// Isolated release candidate. Integrate into the Edge bundle only with the
// matching SQL, source-bound deployment and a reviewed scheduler cutover.
// The queue sees a per-dispatch MAC, never the signing key.
const PROJECT = 'rrlduytparvsjfmegalh';
const ORIGIN = `https://${PROJECT}.supabase.co`;
const SHA = /^[a-f0-9]{64}$/;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const encoder = new TextEncoder();
const MODEL = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;

export function dispatchMessage(source, id, expires) {
  if (!SHA.test(source ?? '') || !UUID.test(id ?? '') || !Number.isSafeInteger(expires) || expires < 1) throw new Error('invalid_dispatch_identity');
  return `collect.jobs.dispatch.v1\n${PROJECT}\n${source}\n${id}\n${expires}`;
}

// Call only after strict JSON parsing and the fixed POST/path checks. Fail
// closed if the mode, project, key, dispatch or signature is unsupported.
export async function verifyManagedJobSignature(env, payload, authorization) {
  if (env?.COLLECT_JOB_AUTH_MODE !== 'supabase_dispatch_hmac_v1' || env.SUPABASE_URL !== ORIGIN ||
      !SHA.test(env.BUILD_SOURCE_ID ?? '') || !SHA.test(env.COLLECT_JOB_SIGNING_KEY ?? '') ||
      !payload || typeof payload !== 'object' || Array.isArray(payload) || !UUID.test(payload.dispatch_id ?? '') ||
      !Number.isSafeInteger(payload.dispatch_expires_at) || payload.dispatch_expires_at <= Math.floor(Date.now()/1000) ||
      payload.dispatch_expires_at > Math.floor(Date.now()/1000)+185 ||
      typeof authorization !== 'string' || !/^Bearer [a-f0-9]{64}$/.test(authorization)) return false;
  const signature = authorization.slice(7).match(/../g).map(pair => parseInt(pair, 16));
  const key = await crypto.subtle.importKey('raw', encoder.encode(env.COLLECT_JOB_SIGNING_KEY),
    {name:'HMAC', hash:'SHA-256'}, false, ['verify']);
  return crypto.subtle.verify('HMAC', key, new Uint8Array(signature),
    encoder.encode(dispatchMessage(env.BUILD_SOURCE_ID, payload.dispatch_id, payload.dispatch_expires_at)));
}

// DB must be the existing fenced PostgresDatabase, after openApplicationWork
// has established a real `jobs` work tuple. A claim commits before any
// maintenance, AI, ledger or provider work; lost replies must never be retried.
export async function claimManagedJobDispatch(db, env, payload, authorization) {
  if (!(await verifyManagedJobSignature(env, payload, authorization))) return false;
  const row = await db.prepare('SELECT private.collect_managed_job_claim(?::uuid,?::text,?::text::jsonb,?::text) AS accepted')
    .bind(payload.dispatch_id, env.BUILD_SOURCE_ID, JSON.stringify(payload), authorization.slice(7)).first();
  return row?.accepted === true;
}

export async function completeManagedJobDispatch(db, env, id, response) {
  if (!UUID.test(id ?? '') || !SHA.test(env?.BUILD_SOURCE_ID ?? '') || !(response instanceof Response) || response.status !== 200) return false;
  const bytes=await response.clone().arrayBuffer();
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),byte=>byte.toString(16).padStart(2,'0')).join('');
  const row=await db.prepare('SELECT private.collect_managed_job_complete(?::uuid,?::text,?::text) AS accepted')
    .bind(id,env.BUILD_SOURCE_ID,digest).first();
  return row?.accepted === true;
}

// The native SMS lane is independent of the older managed receipt lane. A
// feature flag alone must not let a maintenance probe invoke it.
export function nativeSmsAdmission(env, payload) {
  const selected = payload?.native_sms_admission;
  if (env?.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED !== 'true')
    return selected === undefined ? {allowed:true, enabled:false} : {allowed:false};
  const names=['contract','source_sha256','approval_sha256','model_id','batch_limit'];
  if (!selected || typeof selected !== 'object' || Array.isArray(selected) ||
      Object.keys(selected).length !== names.length || Object.keys(selected).some(name=>!names.includes(name)) ||
      selected.contract !== 'collect.native-sms-automation.v1' || selected.batch_limit !== 1 ||
      !SHA.test(env.BUILD_SOURCE_ID ?? '') || selected.source_sha256 !== env.BUILD_SOURCE_ID ||
      !SHA.test(env.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256 ?? '') || selected.approval_sha256 !== env.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256 ||
      !MODEL.test(env.MOMO_AI_MODEL ?? '') || selected.model_id !== env.MOMO_AI_MODEL ||
      env.MOMO_AI_ENABLED !== 'true' || typeof env.OPENAI_API_KEY !== 'string' || !env.OPENAI_API_KEY.trim() ||
      typeof env.AI?.run !== 'function') return {allowed:false};
  return {allowed:true,enabled:true,admission:selected};
}
