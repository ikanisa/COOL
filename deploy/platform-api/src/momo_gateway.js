import {ApiError,json,readJson,first,now,id,digest,stableJson,uuid,integer,text} from './core.js';
import {encrypt,decrypt} from './encryption.js';
import {processingInsert} from './momo_pipeline.js';

const enc=new TextEncoder(),dec=new TextDecoder();
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const token=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),v=>v.toString(16).padStart(2,'0')).join('');
export const gatewayToken=token;
export function momoGuard(env,condition,args=[]){const key=id();return [env.DB.prepare(`INSERT INTO momo_processing_guards(id,passed) SELECT ?,CASE WHEN ${condition} THEN 1 ELSE 0 END`).bind(key,...args),env.DB.prepare('DELETE FROM momo_processing_guards WHERE id=?').bind(key)];}
function date(value,field,{nullable=false}={}){if(value==null&&nullable)return null;
 if(typeof value!=='string'||value.length>40||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(Z|[+-]\d\d:\d\d)$/.test(value)||!Number.isFinite(Date.parse(value)))fail(400,'invalid_capture',`Record a valid ${field}.`);
 const parts=value.slice(0,19).split(/[-T:]/).map(Number),calendar=new Date(0);calendar.setUTCFullYear(parts[0],parts[1]-1,parts[2]);calendar.setUTCHours(parts[3],parts[4],parts[5],0);
 if(calendar.getUTCFullYear()!==parts[0]||calendar.getUTCMonth()+1!==parts[1]||calendar.getUTCDate()!==parts[2]||calendar.getUTCHours()!==parts[3]||calendar.getUTCMinutes()!==parts[4]||calendar.getUTCSeconds()!==parts[5])fail(400,'invalid_capture',`Record a valid ${field}.`);return value;}
const credentialSql=`SELECT c.*,b.owner_user_id,b.receiving_account_id,b.version AS binding_version,b.status AS binding_status,b.subscription_evidence,b.created_at AS binding_created_at,
 a.provider,a.public_code,a.recipient_name,a.currency,a.timezone,a.receiver_hash,a.status AS account_status,p.originating_session_id
 FROM momo_gateway_credentials c JOIN momo_gateway_bindings b ON b.id=c.binding_id JOIN momo_receiving_accounts a ON a.id=b.receiving_account_id
 JOIN momo_gateway_pairings p ON p.id=c.pairing_id JOIN users u ON u.id=b.owner_user_id
 WHERE c.token_sha256=? AND c.revoked_at IS NULL AND b.status='active' AND a.status='active' AND u.access_status='active'
 AND EXISTS(SELECT 1 FROM admin_principal_links l JOIN admin_users owner ON owner.id=l.admin_user_id WHERE l.user_id=b.owner_user_id AND owner.status='active')`;
const activeCondition=`EXISTS(SELECT 1 FROM momo_gateway_credentials c JOIN momo_gateway_bindings b ON b.id=c.binding_id
 JOIN momo_receiving_accounts a ON a.id=b.receiving_account_id JOIN users u ON u.id=b.owner_user_id
 WHERE c.id=? AND c.token_sha256=? AND c.revoked_at IS NULL AND b.status='active' AND a.status='active' AND u.access_status='active'
 AND EXISTS(SELECT 1 FROM admin_principal_links l JOIN admin_users owner ON owner.id=l.admin_user_id WHERE l.user_id=b.owner_user_id AND owner.status='active'))`;
export function bindingJson(row){let subscription=null;try{subscription=JSON.parse(row.subscription_evidence??'null')?.subscription_id??null;}catch{}
 return {id:row.binding_id,version:row.binding_version,owner_user_id:row.owner_user_id,receiving_account_id:row.receiving_account_id,
 provider:row.provider,public_code:row.public_code,recipient_name:row.recipient_name,currency:row.currency,timezone:row.timezone,
 subscription_id:subscription,created_at:row.binding_created_at};}
async function authenticate(request,env){const raw=request.headers.get('Authorization')??'';if(!/^Bearer [a-f0-9]{64}$/.test(raw))fail(401,'gateway_unauthorized','Pair this incoming gateway again.');
 const sha=await digest(raw.slice(7)),row=await first(env,credentialSql,sha);if(!row)fail(401,'gateway_unauthorized','This gateway is no longer authorized.');return {...row,token_sha256:sha};}
function guarded(env,c,statements){const gate=momoGuard(env,activeCondition,[c.id,c.token_sha256]);return env.DB.batch([gate[0],...statements,gate[1]]);}
async function pair(body,env){const code=text(body.pairing_code,'pairing_code',100),installation=uuid(body.installation_id,'installation_id'),sha=await digest(code);
 const row=await first(env,`SELECT p.*,b.status AS binding_status,a.status AS account_status FROM momo_gateway_pairings p
 JOIN momo_gateway_bindings b ON b.id=p.binding_id JOIN momo_receiving_accounts a ON a.id=b.receiving_account_id JOIN users u ON u.id=b.owner_user_id
 WHERE p.code_sha256=? AND p.expires_at>unixepoch() AND u.access_status='active'
 AND EXISTS(SELECT 1 FROM admin_principal_links l JOIN admin_users owner ON owner.id=l.admin_user_id WHERE l.user_id=b.owner_user_id AND owner.status='active')`,sha);
 if(!row||row.binding_status!=='active'||row.account_status!=='active')fail(401,'pairing_unavailable','This pairing code is unavailable or has expired.');
 const prior=await first(env,'SELECT * FROM momo_gateway_credentials WHERE pairing_id=?',row.id);
 if(prior){if(prior.installation_id!==installation||prior.revoked_at)fail(409,'pairing_claimed','This code has already paired another installation.');
  const bytes=await decrypt(env,prior.token_ciphertext,`momo-gateway:${prior.id}`),secret=dec.decode(bytes);
  const current=await first(env,credentialSql,await digest(secret));if(!current)fail(401,'gateway_unauthorized','This binding was revoked.');
  const gate=momoGuard(env,activeCondition,[current.id,current.token_sha256]);await env.DB.batch([gate[0],gate[1]]);
  return {binding:bindingJson(current),gateway_token:secret};}
 const credentialId=id(),secret=token(),cipher=await encrypt(env,enc.encode(secret),`momo-gateway:${credentialId}`);
 const gate=momoGuard(env,`EXISTS(SELECT 1 FROM momo_gateway_pairings p JOIN momo_gateway_bindings b ON b.id=p.binding_id
 JOIN momo_receiving_accounts a ON a.id=b.receiving_account_id JOIN users u ON u.id=b.owner_user_id
 WHERE p.id=? AND p.code_sha256=? AND p.expires_at>unixepoch() AND p.claimed_installation_id IS NULL AND b.status='active' AND a.status='active' AND u.access_status='active'
 AND EXISTS(SELECT 1 FROM admin_principal_links l JOIN admin_users owner ON owner.id=l.admin_user_id WHERE l.user_id=b.owner_user_id AND owner.status='active'))`,[row.id,sha]);
 try{await env.DB.batch([gate[0],env.DB.prepare('UPDATE momo_gateway_pairings SET claimed_installation_id=? WHERE id=?').bind(installation,row.id),
  env.DB.prepare('INSERT INTO momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at,last_contact_at) VALUES(?,?,?,?,?,?,?,?)').bind(credentialId,row.binding_id,row.id,installation,await digest(secret),cipher,now(),now()),gate[1]]);}
 catch(error){const committed=await first(env,'SELECT * FROM momo_gateway_credentials WHERE pairing_id=?',row.id);
  if(committed?.installation_id===installation)return pair(body,env);throw new ApiError(409,'pairing_changed','This pairing changed. Check the gateway before trying another code.');}
 const current=await first(env,credentialSql,await digest(secret));if(!current)fail(401,'gateway_unauthorized','This binding was revoked.');return {binding:bindingJson(current),gateway_token:secret};}
async function ingest(body,env,c){
 const envelope=uuid(body.client_envelope_id,'client_envelope_id');
 if(body.gateway_binding_id!==c.binding_id||body.gateway_binding_version!==c.binding_version)fail(403,'gateway_binding_mismatch','The capture belongs to a different receiving binding.');
 if(typeof body.raw_body!=='string'||body.raw_body.length===0||enc.encode(body.raw_body).length>16384||body.raw_body.includes('\0'))fail(400,'invalid_capture','Invalid source SMS.');
 const sender=text(body.raw_sender,'raw_sender',96),captured=date(body.captured_at,'capture time'),service=date(body.service_centre_at,'service-centre time',{nullable:true}),inbox=date(body.inbox_received_at,'inbox time',{nullable:true});
 if(!['live','catch_up'].includes(body.source_mode)||typeof body.complete!=='boolean')fail(400,'invalid_capture','Record capture completeness and mode.');
 const subscription=body.subscription_id==null?null:integer(body.subscription_id,'subscription_id',0,2147483647),binding=bindingJson(c);
 if(binding.subscription_id!==null&&subscription!==binding.subscription_id)fail(403,'gateway_source_unresolved','The receiving SIM could not be verified.');
 // A historic inbox timestamp predating enrollment cannot inherit today's wallet.
 if(body.source_mode==='catch_up'&&(!inbox||Date.parse(inbox)<Date.parse(c.binding_created_at)))fail(409,'historical_source_unresolved','This historical message needs an account-scoped source review.');
 const payload={raw_sender:body.raw_sender,normalized_sender:sender,raw_body:body.raw_body,received_at_device:service,
  receiver_momo_number:c.public_code,service_centre_at:service,captured_at:captured,inbox_received_at:inbox,source_mode:body.source_mode,
  gateway_binding_id:c.binding_id,gateway_binding_version:c.binding_version,subscription_id:subscription,completeness:body.complete?'complete':'incomplete'};
 const bodySha=await digest(body.raw_body),identity=await digest(stableJson(payload));
 const original=await first(env,`SELECT s.*,g.identity_sha256 FROM sms_receipts s JOIN momo_gateway_captures g ON g.raw_sms_id=s.id WHERE s.owner_user_id=? AND s.client_envelope_id=?`,c.owner_user_id,envelope);
 const ack=row=>({ok:true,receipt:{contract_version:2,stored:true,raw_sms_id:row.id,owner_user_id:c.owner_user_id,client_envelope_id:envelope,body_sha256:bodySha}});
 if(original){if(original.identity_sha256!==identity)fail(409,'capture_conflict','This capture ID has different retained content.');await guarded(env,c,[]);return ack(original);}
 const rawId=id(),key='sms/'+rawId,bytes=enc.encode(JSON.stringify(payload)),objectSha=await digest(bytes),cipher=await encrypt(env,bytes,`sms:${rawId}:${objectSha}`);
 await env.PRIVATE_MEDIA.put(key,cipher,{httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:objectSha,key_id:env.DATA_KEY_ID}});
 try{await guarded(env,c,[env.DB.prepare(`INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)`).bind(rawId,c.owner_user_id,c.originating_session_id,envelope,bodySha,c.receiver_hash,key,objectSha,bytes.length,service,now()),
  env.DB.prepare(`INSERT INTO momo_gateway_captures(raw_sms_id,credential_id,identity_sha256,service_centre_at,captured_at,inbox_received_at,subscription_id,completeness,source_mode,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)`).bind(rawId,c.id,identity,service,captured,inbox,subscription,payload.completeness,body.source_mode,now()),
  processingInsert(env,rawId,{bindingId:c.binding_id,bindingVersion:c.binding_version,mode:'live'}),
  env.DB.prepare('UPDATE momo_gateway_credentials SET last_contact_at=?,last_sms_at=? WHERE id=?').bind(now(),captured,c.id)]);
  return ack({id:rawId});
 }catch(error){const committed=await first(env,`SELECT s.*,g.identity_sha256 FROM sms_receipts s JOIN momo_gateway_captures g ON g.raw_sms_id=s.id WHERE s.owner_user_id=? AND s.client_envelope_id=?`,c.owner_user_id,envelope);
  if(!await first(env,'SELECT id FROM sms_receipts WHERE id=?',rawId))await env.PRIVATE_MEDIA.delete(key);
  if(committed){if(committed.identity_sha256!==identity)fail(409,'capture_conflict','This capture ID has different retained content.');await guarded(env,c,[]);return ack(committed);}
  throw new ApiError(503,'gateway_capture_unavailable','Keep this capture pending and retry after checking the connection.');}
}
export async function momoGatewayRoute(request,env){const path=new URL(request.url).pathname;if(!path.startsWith('/v1/momo/gateway/'))return null;
 if(path==='/v1/momo/gateway/pair'&&request.method==='POST')return json(await pair(await readJson(request,2048),env));
 const c=await authenticate(request,env);
 if(path==='/v1/momo/gateway/ingest'&&request.method==='POST')return json(await ingest(await readJson(request,32768),env,c));
 if(path==='/v1/momo/gateway/status'&&request.method==='GET'){
  const gate=momoGuard(env,activeCondition,[c.id,c.token_sha256]);const result=await env.DB.batch([gate[0],env.DB.prepare(`SELECT count(*) AS n FROM momo_processing_jobs WHERE binding_id=? AND state IN('pending','processing','retry')`).bind(c.binding_id),env.DB.prepare('UPDATE momo_gateway_credentials SET last_contact_at=? WHERE id=?').bind(now(),c.id),gate[1]]);
  return json({binding:bindingJson(c),pending_processing:result[1].results[0].n,last_contact_at:now(),last_sms_at:c.last_sms_at});}
 if(path==='/v1/momo/gateway/heartbeat'&&request.method==='POST'){const body=await readJson(request,2048),pending=integer(body.pending_count,'pending_count',0,1000000),oldest=date(body.oldest_pending_at,'oldest pending time',{nullable:true}),last=date(body.last_sms_at,'last capture time',{nullable:true});
  await guarded(env,c,[env.DB.prepare('UPDATE momo_gateway_credentials SET last_contact_at=?,pending_count=?,oldest_pending_at=?,last_sms_at=coalesce(?,last_sms_at) WHERE id=?').bind(now(),pending,oldest,last,c.id)]);return json({ok:true});}
 fail(404,'not_found','This incoming gateway operation is unavailable.');}
