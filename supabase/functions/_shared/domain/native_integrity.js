import {guardedFetch} from '../application-fence.js';
import {ApiError,digest,first,text,uuid,integer,id,now,stableJson,auditStatement} from './core.js';
import {encrypt,decrypt} from './encryption.js';
import {mutation} from './mutations.js';

const PACKAGE = 'app.cool.mobile';
const OAUTH = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/playintegrity';
const SHA = /^[a-f0-9]{64}$/;
const encoder = new TextEncoder();
const unix = () => Math.floor(Date.now()/1000);
const unavailable = () => {throw new ApiError(503,'play_integrity_unavailable','Android device verification is unavailable.');};
const denied = () => {throw new ApiError(403,'integrity_policy_rejected','Android device verification did not pass.');};
function object(value) {if(!value||Array.isArray(value)||typeof value!=='object')throw new ApiError(400,'invalid_integrity_request','Invalid device verification request.');return value;}
function hash(value,name) {const result=text(value,name,64);if(!SHA.test(result))throw new ApiError(400,'invalid_integrity_request','Invalid device verification binding.');return result;}
export function canonicalRwandaPhone(value) {
 const digits=text(value,'MoMo number',40).replace(/[^\d]/g,'');
 const number=digits.startsWith('250')&&digits.length===12?digits:digits.startsWith('0')&&digits.length===10?'250'+digits.slice(1):digits.length===9?'250'+digits:'';
 if(!/^2507[2389]\d{7}$/.test(number))throw new ApiError(400,'invalid_receiver','Enter a Rwanda MoMo number.');
 return '+'+number;
}
function groupPayload(value,receiverHash,{creation=false}={}) {
 const g=object(value);if(g.group_is_public!==false&&!(creation&&g.group_is_public==null))throw new ApiError(400,'invalid_integrity_request','Only private native groups are supported.');
 if(g.receiver_momo_number_hash!==receiverHash)throw new ApiError(400,'invalid_integrity_request','Receiver verification does not match.');
 return {group_name:text(g.group_name,'group_name',120),group_description:typeof g.group_description==='string'?textOrEmpty(g.group_description,2000):'',
  receiver_momo_number:text(g.receiver_momo_number,'receiver_momo_number',40),receiver_momo_number_hash:receiverHash,
  receiver_label:text(g.receiver_label,'receiver_label',80),group_collection_type:text(g.group_collection_type,'group_collection_type',64),
  group_category_subtype:nullable(g.group_category_subtype,128),group_purpose_label:nullable(g.group_purpose_label,128),group_is_public:false};
}
function textOrEmpty(value,limit) {if(typeof value!=='string'||value.length>limit||/[\u0000-\u001f]/.test(value.replace(/[\r\n\t]/g,'')))throw new ApiError(400,'invalid_integrity_request','Invalid request text.');return value.trim();}
const nullable=(v,max)=>v==null||v===''?null:text(v,'optional request text',max);
function smsPayload(value,receiverHash) {
 const s=object(value),at=s.received_at_device==null?null:text(s.received_at_device,'received_at_device',64);
 if(at&&!/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(at)||at&&!Number.isFinite(Date.parse(at)))throw new ApiError(400,'invalid_integrity_request','Invalid receipt timestamp.');
 return {client_envelope_id:uuid(s.client_envelope_id,'client_envelope_id'),raw_sender:text(s.raw_sender,'raw_sender',96),
  raw_body_sha256:hash(s.raw_body_sha256,'raw_body_sha256'),received_at_device:at};
}
/** Deliberate insertion order exactly matches Dart jsonEncode; sorted JSON does not. */
export async function integrityBinding(body,actor) {
 object(body);const action=body.action;
 if(!['group.create','sms.ingest'].includes(action)||body.subject_id!==actor.userId||body.sms_permission_granted!==true||body.sms_access_enabled!==true)
  throw new ApiError(400,'invalid_integrity_request','Invalid device verification request.');
 const nonce=uuid(body.nonce,'nonce'),receiverHash=hash(body.receiver_momo_number_hash,'receiver_hash');
 const payload=action==='group.create'?groupPayload(body.group_request,receiverHash):smsPayload(body.sms_request,receiverHash);
 if(action==='group.create'&&await digest(canonicalRwandaPhone(payload.receiver_momo_number))!==receiverHash)throw new ApiError(400,'invalid_integrity_request','Receiver verification does not match.');
 const ordered={action,subject_id:actor.userId,nonce,receiver_momo_number_hash:receiverHash,sms_permission_granted:true,sms_access_enabled:true,
  [action==='group.create'?'group_request':'sms_request']:payload};
 const requestHash=await digest(JSON.stringify(ordered));
 if(hash(body.request_hash,'request_hash')!==requestHash)throw new ApiError(400,'integrity_binding_mismatch','Device verification belongs to a different request.');
 return {action,nonce,receiverHash,payload,requestHash,payloadSha:await digest(stableJson(payload))};
}
async function configuration(env) {
 const snapshot={policy:env.PLAY_INTEGRITY_POLICY_JSON,sha:env.PLAY_INTEGRITY_POLICY_SHA256,account:env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON};
 try {
  if(typeof snapshot.policy!=='string'||snapshot.policy.length>16384||!SHA.test(snapshot.sha??''))return unavailable();
  const p=JSON.parse(snapshot.policy),a=JSON.parse(snapshot.account??'null');
  if(JSON.stringify(p)!==snapshot.policy.trim()||await digest(snapshot.policy)!==snapshot.sha||p.schema_version!==1||p.purpose!=='collect_native_admission'||p.status!=='approved'||p.enabled!==true||p.provider!=='google_play_integrity'||p.package_name!==PACKAGE)return unavailable();
  uuid(p.approval_id,'approval_id');hash(p.approval_evidence_sha256,'approval evidence');
  if(!/^[a-z][a-z0-9-]{4,62}$/.test(p.project_id??'')||!/^\d{6,20}$/.test(String(p.cloud_project_number??''))||!Array.isArray(p.certificate_sha256)||!p.certificate_sha256.length||p.certificate_sha256.length>8||p.certificate_sha256.some(c=>!/^[A-Za-z0-9_-]{43}=?$/.test(c)))return unavailable();
  integer(p.minimum_version_code,'version',1,2147483647);integer(p.capability_ttl_seconds,'capability TTL',15,180);
  integer(p.actor_hour_limit,'actor budget',1,100);integer(p.project_day_limit,'project budget',1,10000);
  const starts=Date.parse(p.approved_at),ends=Date.parse(p.valid_until);
  if(!Number.isFinite(starts)||!Number.isFinite(ends)||starts>Date.now()||ends<=Date.now()||starts>=ends)return unavailable();
  if(!a||a.type!=='service_account'||a.project_id!==p.project_id||a.client_email!==p.service_account_email||!String(a.client_email).endsWith('@'+p.project_id+'.iam.gserviceaccount.com')||typeof a.private_key!=='string'||a.private_key.length>16384||!a.private_key.startsWith('-----BEGIN PRIVATE KEY-----')||(a.token_uri&&a.token_uri!==OAUTH))return unavailable();
  return Object.freeze({snapshot:Object.freeze(snapshot),policy:Object.freeze(p),account:Object.freeze(a),starts,ends});
 }catch{return unavailable();}
}
function checkConfiguration(env,c) {if(c.snapshot.policy!==env.PLAY_INTEGRITY_POLICY_JSON||c.snapshot.sha!==env.PLAY_INTEGRITY_POLICY_SHA256||c.snapshot.account!==env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON||Date.now()<c.starts||Date.now()>=c.ends)unavailable();}
function base64url(bytes) {return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
async function responseJson(response,max=32768) {
 if(!response.ok)unavailable();const reader=response.body?.getReader();if(!reader)unavailable();
 let size=0;const chunks=[];
 try {while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max){await reader.cancel();unavailable();}chunks.push(value);}}finally{reader.releaseLock();}
 const data=new Uint8Array(size);let offset=0;for(const b of chunks){data.set(b,offset);offset+=b.length;}
 try{return {value:JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(data)),sha256:await digest(data)};}catch{unavailable();}
}
function translate(error) {
 if(error instanceof ApiError)return error;const message=String(error?.message??error);
 if(/native_.*budget/.test(message))return new ApiError(429,'integrity_budget_exhausted','Android device verification is temporarily limited.');
 if(/native_.*(?:denied|changed|required)/.test(message))return new ApiError(403,'integrity_session_unavailable','Verify your sign-in and SMS consent before continuing.');
 if(/UNIQUE constraint/.test(message))return new ApiError(409,'integrity_request_replayed','This verification request was already reserved.');
 return new ApiError(503,'play_integrity_unavailable','Android device verification is unavailable.');
}
async function verifiedReceiver(env,actor,receiverHash) {
 const u=await first(env,'SELECT phone,momo_number,country_code,currency_code FROM users WHERE id=? AND access_status=\'active\'',actor.userId);
 if(!u?.phone||u.country_code!=='RW'||u.currency_code!=='RWF'||await digest(canonicalRwandaPhone(u.phone))!==receiverHash||u.momo_number&&canonicalRwandaPhone(u.momo_number)!==canonicalRwandaPhone(u.phone))
  throw new ApiError(403,'integrity_receiver_unavailable','Verify the receiving MoMo number before continuing.');
 return u.phone;
}
function phaseStatement(env,reservationId,phase) {return env.DB.prepare('INSERT INTO native_phases(reservation_id,phase,started_seconds) VALUES(?,?,?)').bind(reservationId,phase,unix());}
// A capture scope is an ownership/consent identifier, never a receiving wallet
// or proof that this user's phone received money.
export const clientSmsCaptureScope=actor=>digest('collect.client-sms-capture.v1:'+actor.userId);
export async function nativeRpc(name,body,env,actor) {
 if(name!=='record_sms_access_consent')return {handled:false};
 if(typeof body.enabled!=='boolean'||actor.surface!=='member')throw new ApiError(400,'invalid_consent','Invalid SMS consent.');
 const general=body.momo_number_hash==null,channel=text(body.build_channel,'build_channel',64);
 if(general&&!/^android_[a-z0-9_]+$/.test(channel))throw new ApiError(400,'invalid_consent','Record Android SMS access consent.');
 const receiver=general?await clientSmsCaptureScope(actor):hash(body.momo_number_hash,'momo_number_hash');
 if(!general)await verifiedReceiver(env,actor,receiver);
 const requestId=uuid(body.request_id??id(),'request_id');
 return {handled:true,value:await mutation(env,actor,name,requestId,body,null,[env.DB.prepare('INSERT INTO native_consents(user_id,session_id,receiver_hash,enabled,created_seconds,build_channel,request_id) VALUES(?,?,?,?,?,?,?)').bind(actor.userId,actor.sessionId,receiver,body.enabled?1:0,unix(),channel,requestId)])};
}
export function validateIntegrityVerdict(value,requestHash,policy,nowMs=Date.now()) {
 const d=object(value),r=object(d.requestDetails),a=object(d.appIntegrity),c=object(d.accountDetails),v=object(d.deviceIntegrity);
 const timestamp=Number(r.timestampMillis),age=nowMs-timestamp;
 const version=/^\d{1,15}$/.test(String(a.versionCode??''))?Number(a.versionCode):NaN;
 const certs=Array.isArray(a.certificateSha256Digest)?a.certificateSha256Digest:[],labels=Array.isArray(v.deviceRecognitionVerdict)?v.deviceRecognitionVerdict:[];
 if(r.requestPackageName!==PACKAGE||a.packageName!==PACKAGE||r.requestHash!==requestHash||a.appRecognitionVerdict!=='PLAY_RECOGNIZED'||c.appLicensingVerdict!=='LICENSED'||!Number.isSafeInteger(version)||version<policy.minimum_version_code||!Number.isSafeInteger(timestamp)||timestamp<=0||age< -30000||age>300000||!certs.length||!certs.every(c=>typeof c==='string'&&policy.certificate_sha256.includes(c))||!labels.every(l=>typeof l==='string')||!labels.some(l=>l==='MEETS_DEVICE_INTEGRITY'||l==='MEETS_STRONG_INTEGRITY'))denied();
 return {packageName:PACKAGE,appVerdict:'PLAY_RECOGNIZED',deviceVerdicts:labels,timestampMillis:timestamp};
}
export async function functionRpc(name,body,env,actor) {
 if(name!=='verify-play-integrity')return {handled:false};
 const operation={phase:'binding',started:Date.now()};
 try{return await admitNative(body,env,actor,operation);}
 catch(error){
  const failure=translate(error);
  if(failure.status===429||failure.status===503){
   // Operational routing can select these fixed server fields. Never log the
   // request, actor, token, phone, nonce, provider response or exception text.
   const codes=new Set(['integrity_budget_exhausted','play_integrity_unavailable','storage_unavailable','key_unavailable']);
   const record={event:'native_admission_failure',schema_version:1,
    code:codes.has(failure.code)?failure.code:'native_admission_unavailable',
    phase:operation.phase,status:failure.status,duration_ms:Math.min(60000,Math.max(0,Date.now()-operation.started)),automatic_retry:false};
   try{console[failure.status===503?'error':'warn'](JSON.stringify(record));}catch{/* Logging never changes the admission decision. */}
  }
  throw failure;
 }
}
async function admitNative(body,env,actor,operation) {
 const binding=await integrityBinding(body,actor);operation.phase='configuration';
 const c=await configuration(env),token=text(body.integrity_token,'integrity_token',20000),tokenSha=await digest(token);
 operation.phase='receiver';
 const phone=await verifiedReceiver(env,actor,binding.receiverHash);
 operation.phase='reconciliation';
 const previous=await first(env,'SELECT * FROM native_reservations WHERE user_id=? AND nonce=?',actor.userId,binding.nonce);
 if(previous) {
  if(previous.session_id!==actor.sessionId||previous.request_hash!==binding.requestHash||previous.token_sha256!==tokenSha||previous.action!==binding.action||previous.payload_sha256!==binding.payloadSha)throw new ApiError(409,'integrity_request_conflict','This request ID belongs to a different verification.');
  const completion=await first(env,'SELECT * FROM native_completions WHERE reservation_id=?',previous.id);
  if(completion) {
   const guard=id();await env.DB.batch([env.DB.prepare('INSERT INTO mutation_guards(id,user_id,session_id,now_seconds) VALUES(?,?,?,?)').bind(guard,actor.userId,actor.sessionId,unix()),env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(guard)]);
   return {handled:true,value:JSON.parse(new TextDecoder().decode(await decrypt(env,completion.result_ciphertext,'native-admission:'+previous.id)))};
  }
  throw new ApiError(409,'integrity_request_replayed','This verification was already started. Do not repeat provider dispatch.');
 }
 const reservationId=id(),created=unix(),deadline=Date.now()+20000;
 operation.phase='retention';
 const cipher=await encrypt(env,encoder.encode(JSON.stringify(binding.payload)),'native-payload:'+reservationId);
 try {
  operation.phase='reservation';
  await env.DB.batch([env.DB.prepare(`INSERT INTO native_reservations(id,user_id,session_id,nonce,action,request_hash,token_sha256,receiver_hash,verified_phone,payload_sha256,payload_ciphertext,policy_sha256,approval_id,approval_evidence_sha256,project_id,created_seconds,expires_seconds,actor_hour_limit,project_day_limit) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(reservationId,actor.userId,actor.sessionId,binding.nonce,binding.action,binding.requestHash,tokenSha,binding.receiverHash,phone,binding.payloadSha,cipher,c.snapshot.sha,c.policy.approval_id,c.policy.approval_evidence_sha256,c.policy.project_id,created,created+30,c.policy.actor_hour_limit,c.policy.project_day_limit),auditStatement(env,actor,'native.admission.reserved','native_admission',reservationId,{action:binding.action,request_sha256:binding.requestHash,policy_sha256:c.snapshot.sha},binding.nonce)]);
  operation.phase='oauth';
  const keyBytes=Uint8Array.from(atob(c.account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,'')),x=>x.charCodeAt(0));
  const key=await crypto.subtle.importKey('pkcs8',keyBytes,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const head=base64url(encoder.encode(JSON.stringify({alg:'RS256',typ:'JWT'}))),issued=unix();
  const claim=base64url(encoder.encode(JSON.stringify({iss:c.account.client_email,scope:SCOPE,aud:OAUTH,iat:issued,exp:issued+3600})));
  const signature=base64url(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(head+'.'+claim))));
  await phaseStatement(env,reservationId,'oauth').run();checkConfiguration(env,c);
  const oauth=await responseJson(await guardedFetch(env,'integrity_oauth',OAUTH,{method:'POST',redirect:'manual',signal:AbortSignal.timeout(Math.max(1,Math.min(10000,deadline-Date.now()))),headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:head+'.'+claim+'.'+signature})}));
  if(typeof oauth.value.access_token!=='string'||oauth.value.access_token.length>8192||oauth.value.token_type!=='Bearer'||Date.now()>=deadline)unavailable();
  operation.phase='decode';
  await phaseStatement(env,reservationId,'decode').run();checkConfiguration(env,c);
  const started=Date.now();
  const decoded=await responseJson(await guardedFetch(env,'integrity_decode','https://playintegrity.googleapis.com/v1/'+PACKAGE+':decodeIntegrityToken',{method:'POST',redirect:'manual',signal:AbortSignal.timeout(Math.max(1,Math.min(10000,deadline-Date.now()))),headers:{'Content-Type':'application/json',Authorization:'Bearer '+oauth.value.access_token},body:JSON.stringify({integrity_token:token})}));
  if(Date.now()>=deadline)unavailable();checkConfiguration(env,c);
  operation.phase='completion';
  const verdict=validateIntegrityVerdict(decoded.value.tokenPayloadExternal,binding.requestHash,c.policy),capability=base64url(crypto.getRandomValues(new Uint8Array(32))),capId=id(),at=unix(),expires=at+c.policy.capability_ttl_seconds;
  const result={status:'pass',action:binding.action,request_hash:binding.requestHash,package_name:PACKAGE,app_verdict:verdict.appVerdict,device_verdicts:verdict.deviceVerdicts,native_capability:capability,capability_expires_at:new Date(expires*1000).toISOString()};
  const resultCipher=await encrypt(env,encoder.encode(JSON.stringify(result)),'native-admission:'+reservationId);checkConfiguration(env,c);if(Date.now()>=deadline)unavailable();
  await env.DB.batch([env.DB.prepare('INSERT INTO native_capabilities(id,token_sha256,reservation_id,user_id,session_id,action,receiver_hash,verified_phone,payload_sha256,created_seconds,expires_seconds,verdict_sha256) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').bind(capId,await digest(capability),reservationId,actor.userId,actor.sessionId,binding.action,binding.receiverHash,phone,binding.payloadSha,at,expires,decoded.sha256),env.DB.prepare('INSERT INTO native_completions(reservation_id,capability_id,result_ciphertext,provider_response_sha256,completed_seconds,decode_duration_ms) VALUES(?,?,?,?,?,?)').bind(reservationId,capId,resultCipher,decoded.sha256,at,Date.now()-started),env.DB.prepare("UPDATE native_reservations SET state='completed' WHERE id=? AND state='decode_started'").bind(reservationId),auditStatement(env,actor,'native.admission.completed','native_admission',reservationId,{request_sha256:binding.requestHash,provider_response_sha256:decoded.sha256},binding.nonce)]);
  return {handled:true,value:result};
 }catch(error) {
  try {await env.DB.prepare("UPDATE native_reservations SET state=? WHERE id=? AND state IN('reserved','oauth_started','decode_started')").bind(error instanceof ApiError&&error.code==='integrity_policy_rejected'?'rejected':'ambiguous',reservationId).run();}catch{}
  throw translate(error);
 }
}
/** Return this statement inside the same DB.batch as the authorized mutation. */
export async function consumeNativeCapability(env,actor,token,action,body) {
 const configurationNow=await configuration(env);
 const capability=await first(env,'SELECT c.*,r.policy_sha256 FROM native_capabilities c JOIN native_reservations r ON r.id=c.reservation_id WHERE c.token_sha256=?',await digest(text(token,'native_capability',128)));
 if(!capability||capability.user_id!==actor.userId||capability.session_id!==actor.sessionId||capability.action!==action||capability.expires_seconds<=unix())throw new ApiError(403,'native_capability_denied','Android verification is no longer available for this action.');
 if(capability.policy_sha256!==configurationNow.snapshot.sha)throw new ApiError(403,'native_capability_denied','Android verification uses a retired admission policy.');
 let payload;
 if(action==='group.create')payload=groupPayload(body,capability.receiver_hash,{creation:true});
 else if(action==='sms.ingest') {
  if(typeof body.raw_body!=='string'||encoder.encode(body.raw_body).length>16384||body.raw_body.length===0||body.raw_body.includes('\0'))throw new ApiError(400,'invalid_sms_request','Invalid receipt text.');
  payload=smsPayload({...body,raw_body_sha256:await digest(body.raw_body)},capability.receiver_hash);
 }
 else throw new ApiError(403,'native_capability_denied','Invalid native action.');
 if(action==='sms.ingest'&&await digest(canonicalRwandaPhone(body.receiver_momo_number))!==capability.receiver_hash||action==='group.create'&&await digest(canonicalRwandaPhone(payload.receiver_momo_number))!==capability.receiver_hash||await digest(stableJson(payload))!==capability.payload_sha256)throw new ApiError(403,'native_capability_denied','Android verification belongs to a different request.');
 checkConfiguration(env,configurationNow);
 return env.DB.prepare('INSERT INTO native_capability_claims(id,capability_id,user_id,session_id,action,payload_sha256,receiver_hash,claimed_seconds) VALUES(?,?,?,?,?,?,?,?)').bind(id(),capability.id,actor.userId,actor.sessionId,action,capability.payload_sha256,capability.receiver_hash,unix());
}
