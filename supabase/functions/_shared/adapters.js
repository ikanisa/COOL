import {applicationWork,guardedFetch,noteUnknownEffect,reserveDatabaseConnection} from './application-fence.js';
import {ApiError,digest} from './domain/core.js';
import {createRosterDecoderBridge} from './roster_decoder_bridge.mjs';
import {decrypt} from './domain/encryption.js';
import {compileSql} from './postgres.js';
import {ProtectedStorageProtocol,StorageProtocolError,sha256,canonical} from './storage/protocol.js';
import {SupabaseNativeTransport} from './storage/supabase-transport.js';
import {PostgresStorageJournal} from './storage/postgres-journal.js';
import {createTransport} from 'npm:nodemailer@10.1.7';
import {createWorkspaceSmtpEmail} from './workspace-smtp-email.js';
const unavailable=name=>new ApiError(503,name+'_unavailable','The configured service is unavailable.');
// postgres.js serializes JSONB parameters using their inferred PostgreSQL type.
// Pre-stringifying here would store a JSON string instead of a JSON object.
const normalize=values=>values;
function storagePool(db){return{
 connect(){const work=db.applicationWork;if(!work)throw unavailable('application_fence');return work.waitUntil((async()=>{
  await work.assert();const raw=await reserveDatabaseConnection(db.sql);let released=false,inTransaction=false,settle;const ownership=new Promise(resolve=>{settle=resolve;});work.waitUntil(ownership);
  return{raw,query(text,values=[]){return work.waitUntil((async()=>{
   // Cleanup must still rollback a transaction after a failed lease proof.
   if(!/^ROLLBACK\b/i.test(text))await work.assert();if(/^BEGIN\b/i.test(text))inTransaction=true;let result;try{result=await raw.unsafe(text,normalize(values));}catch(error){if(/^ROLLBACK\b/i.test(text))work.abandon('work_lost');throw error;}if(/^(?:COMMIT|ROLLBACK)\b/i.test(text))inTransaction=false;
   if(/^BEGIN\b/i.test(text)){if(/^BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY$/i.test(text)){await db.readContext(raw);}else{await db.context(raw);await raw`select pg_advisory_xact_lock(734636924058501::bigint)`;}}
   return{rows:Array.from(result),rowCount:result.count??result.length};
  })());},release(){if(released)return;released=true;try{if(inTransaction)work.abandon('work_lost');else raw.release();}finally{settle();}}};
 })());},
 async query(text,values=[]){const c=await this.connect();try{await c.query('BEGIN');const r=await c.query(text,values);await c.query('COMMIT');return r;}catch(error){await c.query('ROLLBACK').catch(()=>{});throw error;}finally{c.release();}}
};}
export class SupabaseObjectBucket {
 constructor(env){this.env=env;this.bucket=env.COLLECT_PRIVATE_BUCKET??'collect-evidence';this.pool=storagePool(env.DB);this.namespace={origin:new URL(env.SUPABASE_URL).origin,bucket:this.bucket};this.journal=new PostgresStorageJournal(this.pool,{namespace:this.namespace});this.transport=new SupabaseNativeTransport({url:env.SUPABASE_URL,secretKey:env.SUPABASE_SECRET_KEY??env.SUPABASE_SERVICE_ROLE_KEY,bucket:this.bucket,allowInsecureLoopback:env.APP_ENVIRONMENT==='test',authorizeMutation:()=>applicationWork(env).assert(),fetchImpl:(url,options)=>guardedFetch(env,'storage',url,options)});this.protocol=new ProtectedStorageProtocol({transport:this.transport,journal:this.journal});}
 async checked(fn){try{return await fn();}catch(error){if(error instanceof StorageProtocolError){const wrapped=new ApiError(error.status,error.code,'Protected storage could not be confirmed. Keep the request pending.');wrapped.cause=error;throw wrapped;}throw error;}}
 async put(key,value,options={}){return this.checked(async()=>{
  if(typeof value!=='string'||!options.scope||typeof options.aad!=='string'||!/^[a-f0-9]{64}$/.test(options.sourceDigest??''))throw new ApiError(400,'storage_identity_required','A protected source identity is required.');
  const prior=await this.journal.getPayloadBinding(key),custom={...(options.customMetadata??{})};if(prior&&Object.hasOwn(custom,'key_id'))custom.key_id=prior.keyId;const plain=custom.sha256??custom.source_sha256;if(!/^[a-f0-9]{64}$/.test(plain??''))throw new ApiError(400,'storage_identity_required','A protected source digest is required.');
  const descriptor={scope:options.scope,aad:options.aad,keyId:prior?.keyId??this.env.DATA_KEY_ID,plaintextSha256:plain,requestDigest:options.sourceDigest,httpMetadata:options.httpMetadata??{},customMetadata:custom};
  const reservation=await this.journal.reservePayload(key,descriptor,value);
  if(reservation.sealedBody===null){const intent=await this.journal.getPutByKey(key);if(!intent||intent.customMetadata.source_fingerprint!==reservation.sourceFingerprint)throw unavailable('storage_reservation');return this.protocol.confirmCommitted(intent);}
  const retainedPlaintext=await decrypt(this.env,reservation.sealedBody,options.aad);if(await digest(retainedPlaintext)!==plain)throw unavailable('storage_plaintext_integrity');
  return this.protocol.put(key,reservation.sealedBody,{scope:options.scope,httpMetadata:options.httpMetadata??{},customMetadata:{...custom,source_fingerprint:reservation.sourceFingerprint}});
 });}
 async read(key){return this.checked(async()=>{const intent=await this.journal.getPutByKey(key),meta=await this.journal.getObject(key);if(!meta){const probe=await this.transport.probe(key);if(this.protocol.provesAbsent(probe)&&(!intent||intent.state==='erased'))return null;throw unavailable('storage_untracked');}if(!intent||intent.state!=='committed')throw unavailable('storage_metadata');const observed=await this.protocol.readAndVerify(intent);return{meta,observed};});}
 describe(read){const{meta,observed}=read;return{key:meta.key,size:meta.size,version:observed.etag??meta.sha256,etag:observed.etag??meta.sha256,sha256:meta.sha256,httpMetadata:meta.httpMetadata,customMetadata:meta.customMetadata};}
 async head(key){const r=await this.read(key);return r?this.describe(r):null;}
 async get(key){const r=await this.read(key);if(!r)return null;const bytes=r.observed.bytes;return{...this.describe(r),body:new Blob([bytes]).stream(),text:async()=>new TextDecoder().decode(bytes),arrayBuffer:async()=>bytes.buffer};}
 // Retention sees a distinct pending-absence observation, never a successful
 // download or an erasure receipt. Ordinary get/head remain strict and unchanged.
 async observeRetention(key){return this.checked(async()=>{
  const intent=await this.journal.getPutByKey(key),meta=await this.journal.getObject(key);
  if(!meta){const object=await this.get(key);return{kind:object?'present':'absence_verified',object};}
  if(!intent||intent.state!=='committed')throw unavailable('storage_metadata');
  const observed=await this.protocol.readAndVerify(intent,{allowMissing:true});
  if(observed){const bytes=observed.bytes;return{kind:'present',object:{...this.describe({meta,observed}),body:new Blob([bytes]).stream(),text:async()=>new TextDecoder().decode(bytes),arrayBuffer:async()=>bytes.buffer}};}
  const deletion=await this.journal.getDeleteByKey(key);
  const descriptor=deletion&&{key,operationId:deletion.operationId,scope:intent.scope,expectedSha256:intent.sha256};
  if(!deletion||deletion.state!=='pending'||deletion.key!==key||deletion.expectedSha256!==intent.sha256||!intent.deleteTombstone||intent.activeAttempt||intent.uploadUnresolved||meta.key!==intent.key||meta.operationId!==intent.operationId||meta.fingerprint!==intent.fingerprint||meta.size!==intent.size||meta.sha256!==intent.sha256||canonical(meta.scope)!==canonical(intent.scope)||canonical(deletion.scope)!==canonical(intent.scope)||deletion.fingerprint!==await sha256(canonical(descriptor)))throw unavailable('storage_pending_erasure_identity');
  return{kind:'pending_erasure_absence',object:null,operationId:deletion.operationId,sourceSha256:intent.sha256};
 });}
 async delete(key,options={}){return this.checked(async()=>{if(typeof options.guards!=='function')throw new ApiError(403,'delete_authority_required','Current retention authority is required.');const intent=await this.journal.getPutByKey(key);if(!intent)throw unavailable('storage_delete_identity');const guards=async(c,i,retain=false)=>{const statements=await options.guards(i),run=async list=>{for(const statement of list){const q=compileSql(statement.sql,statement.values);await c.query(q.text,q.values);}};if(retain){await run(statements.slice(0,-2));return()=>run(statements.slice(-2));}await run(statements);};const journal=new PostgresStorageJournal(this.pool,{namespace:this.namespace,deleteGuards:(c,i)=>guards(c,i,true)}),protocol=new ProtectedStorageProtocol({transport:this.transport,journal});return protocol.delete(key,{operationId:options.operationId??await sha256('collect.storage.retention.v1\n'+key),scope:intent.scope,expectedSha256:intent.sha256,requireAbsent:options.reconcileOnly===true,authorize:async()=>{const c=await this.pool.connect();try{await c.query('BEGIN');await guards(c,intent);await c.query('COMMIT');return true;}catch(error){await c.query('ROLLBACK').catch(()=>{});throw error;}finally{c.release();}}});});}
 async list({prefix='',cursor='',limit=1000}={}){return this.checked(async()=>{const inventory=await this.protocol.inventory();if(!inventory.complete)throw unavailable('storage_inventory');const all=inventory.objects.filter(o=>o.key.startsWith(prefix)&&o.key>cursor).sort((a,b)=>a.key.localeCompare(b.key)),items=all.slice(0,Math.min(limit,1000)),byKey=new Map(inventory.metadata.map(m=>[m.key,m]));return{objects:items.map(o=>({key:o.key,size:o.size,customMetadata:byKey.get(o.key)?.customMetadata??{},httpMetadata:byKey.get(o.key)?.httpMetadata??{},classification:o.classification})),truncated:all.length>items.length,cursor:all.length>items.length?items.at(-1)?.key:undefined,pending:inventory.puts.filter(i=>i.state==='pending'),anomalies:inventory.anomalies};});}
}
// Leave room for JSON escaping of the existing 65536-character content bound
// and provider metadata, without buffering an unbounded response envelope.
const MOMO_RESPONSE_BYTES=512*1024;
function boundedMomoResponse(env,response){
 const work=applicationWork(env);
 return work.local(async()=>{
  let reader,complete=false;
  try{
   const declared=response.headers.get('content-length');
   if(declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>MOMO_RESPONSE_BYTES))throw unavailable('ai_response');
   const chunks=[];let size=0;
   if(response.body){
    reader=response.body.getReader();
    while(true){const{done,value}=await reader.read();if(done){complete=true;break;}
     if(!(value instanceof Uint8Array)||value.byteLength>MOMO_RESPONSE_BYTES-size)throw unavailable('ai_response');
     size+=value.byteLength;if(value.byteLength)chunks.push(value);
    }
   }
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
   return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
  }catch(error){noteUnknownEffect(env,'ai');throw error;}
  finally{
   // Caller refusal does not acknowledge the original cancellation. Keep its
   // promise owned by the same admission, even when cancellation later fails.
   if(!complete&&response.body){
    try{const raw=reader?reader.cancel():response.body.cancel();work.waitUntil(Promise.resolve(raw).catch(()=>noteUnknownEffect(env,'ai')));}
    catch{noteUnknownEffect(env,'ai');}
   }
   reader?.releaseLock();
  }
 });
}
export function providerAdapters(env){
 const adapters={};
 if(env.OPENAI_API_KEY&&env.MOMO_AI_MODEL)adapters.AI={async run(_legacy,options){
  if(env.MOMO_AI_ENABLED!=='true')throw unavailable('ai');
  const reply=await guardedFetch(env,'ai','https://api.openai.com/v1/chat/completions',{method:'POST',redirect:'error',signal:AbortSignal.timeout(45000),headers:{'Content-Type':'application/json',Authorization:'Bearer '+env.OPENAI_API_KEY},body:JSON.stringify({model:env.MOMO_AI_MODEL,messages:options.messages,temperature:0,max_completion_tokens:options.max_tokens,store:false,response_format:{type:'json_schema',json_schema:{name:'collect_momo_extraction',strict:true,schema:options.response_format.json_schema}}})});
  if(!reply.ok)throw unavailable('ai');const result=await boundedMomoResponse(env,reply),content=result.choices?.[0]?.message?.content;if(typeof content!=='string'||content.length>65536)throw unavailable('ai_response');return {response:content};
 }};
 // Select only the signed supervisor protocol; a missing/invalid configuration
 // remains unavailable and never falls back to a Bearer or injected binding.
 try{adapters.ROSTER_DECODER=createRosterDecoderBridge({protocol:env.ROSTER_DECODER_PROTOCOL,endpoint:env.ROSTER_DECODER_URL,secret:env.ROSTER_DECODER_SECRET,approvedBuildSha256:env.ROSTER_DECODER_BUILD_SHA256,fetchImpl:(input,options)=>guardedFetch(env,'decoder',input,options),trackPromise:promise=>applicationWork(env).waitUntil(promise),onUncertain:()=>noteUnknownEffect(env,'decoder')});}
 catch{adapters.ROSTER_DECODER=Object.freeze({async fetch(){throw unavailable('decoder');}});}
 if(env.COLLECT_NOTICE_SMTP_PASSWORD!==undefined&&env.COLLECT_NOTICE_SMTP_PASSWORD!==null&&env.COLLECT_NOTICE_SMTP_PASSWORD!==''){
  try{adapters.AUTH_EMAIL=createWorkspaceSmtpEmail(env,{createTransport});adapters.AUTH_EMAIL_FROM='info@ikanisa.com';}
  catch{adapters.AUTH_EMAIL=Object.freeze({provider:'workspace_smtp_v1',unavailable:true});}
 }else if(env.TRANSACTIONAL_EMAIL_URL&&env.TRANSACTIONAL_EMAIL_TOKEN)adapters.AUTH_EMAIL={async send(message){const target=new URL(env.TRANSACTIONAL_EMAIL_URL);if(target.protocol!=='https:'||target.username||target.password)throw unavailable('email');const reply=await guardedFetch(env,'smtp',target,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+env.TRANSACTIONAL_EMAIL_TOKEN},body:JSON.stringify(message),redirect:'error',signal:AbortSignal.timeout(10000)});if(!reply.ok)throw unavailable('email');const data=await reply.json();return {messageId:data.messageId??data.id};}};
 return adapters;
}
