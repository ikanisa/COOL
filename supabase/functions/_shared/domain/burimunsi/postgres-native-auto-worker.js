// Native SMS processing is separate from the managed-gateway job queue. The
// scheduled caller must already hold an admitted Collect jobs fence; neither a
// PIN actor nor a gateway binding is fabricated for background processing.
import {applicationWorkTuple} from '../../application-fence.js';
import {digest} from '../core.js';
import {decrypt} from '../encryption.js';
import {MOMO_MODEL,validateProviderProfile} from '../momo_pipeline.js';
import {BuriError,requirePort,requireThat} from './errors.js';
import {canonicalJson,requireId,requireRequestId,sha256} from './values.js';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {lockCollectMutation} from '../../postgres-mutation-lock.js';
import {PostgresPostingCustody} from './postgres-posting-custody.js';
import {PostgresStorageWitnesses} from './postgres-storage-witnesses.js';
import {prepareNativeAutoExtraction,validateNativeAutoExtraction} from './native-auto-parser.js';
import {nativeSmsEventAliases} from './native-sms-event-identity.js';

const HASH=/^[a-f0-9]{64}$/;
const MODEL=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const encoder=new TextEncoder(),decoder=new TextDecoder('utf-8',{fatal:true});
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const check=(v,code='native_auto_unavailable',status=503)=>requireThat(v,code,status);
const target=r=>({ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`});
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.getPrototypeOf(v)===Object.prototype;

function checkSnapshot(value,groupId,sourceId){
 const p=value?.proof,a=value?.actor,profile=value?.profile;
 check(value?.kind==='jobs'&&plain(a)&&a.collectionId===groupId&&plain(p)&&p.id===sourceId&&p.sourceId===sourceId&&
  p.object_key==='sms/'+sourceId&&HASH.test(p.object_sha256??'')&&HASH.test(p.bodySha256??'')&&
  HASH.test(p.fingerprint??'')&&typeof p.principalUserId==='string'&&p.principalUserId.length>0&&
  Number.isSafeInteger(Number(p.size_bytes))&&Number(p.size_bytes)>=1&&Number(p.size_bytes)<=131072&&
  plain(profile)&&HASH.test(profile.profileSha256??'')&&plain(profile.profile)&&validateProviderProfile(profile.profile),
  'native_auto_source_changed',409);
 return value;
}

function checkPayload(source,record){
 check(plain(source)&&source.provenance==='native_observation_unverified'&&
  ((source.source_mode==='live'&&source.complete===true)||(source.source_mode==='catch_up'&&source.complete===false))&&
  typeof source.raw_sender==='string'&&source.raw_sender.length>0&&source.raw_sender.length<=96&&
  typeof source.raw_body==='string'&&source.raw_body.length>0&&encoder.encode(source.raw_body).length<=3000,
  'native_auto_source_changed',409);
 check(HASH.test(record.bodySha256),'native_auto_source_changed',409);
}

/** One work-admission-bound worker, for one existing server-selected group. */
export class PostgresNativeAutoWorker {
 constructor({env,groupId,clock=()=>Date.now()}){
  requireId(groupId);const db=env?.DB,work=db?.applicationWork,media=env?.PRIVATE_MEDIA;
  check(work?.kind==='jobs'&&typeof clock==='function'&&media?.namespace&&typeof media.get==='function');
  const namespace=media.namespace;
  const witnesses=new PostgresStorageWitnesses({db,groupId,namespace,media,applicationWorkTuple,clock});
  this.authority=new PostgresNativeAuthority({db,groupId});
  this.custody=new PostgresPostingCustody({db,groupId,namespace,decrypt:(sealed,aad)=>decrypt(env,sealed,aad),storageWitnesses:witnesses});
  this.witnesses=witnesses;this.env=env;this.groupId=groupId;
 }

 async plan(tx,sourceId){
  const rows=await tx.unsafe('SELECT private.burimunsi_auto_plan($1) AS result',[sourceId]);
  check(rows.length===1,'native_auto_source_changed',409);
  const snapshot=checkSnapshot(rows[0].result,this.groupId,sourceId),r=snapshot.proof,t=target(r);
  const namespace=(await tx.unsafe('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE'));
  check(namespace.length===1&&same(namespace[0],this.custody.namespace),'native_auto_source_changed',409);
  const journal=await this.custody.journal(tx,r.object_key,t),keyId=journal?.reservation?.key_id;
  const descriptor={scope:{ownerId:t.ownerId,purpose:t.purpose,entityId:t.entityId},aad:t.aad,keyId,
   plaintextSha256:r.object_sha256,requestDigest:r.fingerprint,httpMetadata:{contentType:'application/octet-stream'},
   customMetadata:{sha256:r.object_sha256,key_id:keyId}};
  check(typeof keyId==='string'&&keyId.length>0&&await sha256(canonicalJson(descriptor))===journal.reservation.source_fingerprint,
   'native_auto_source_changed',409);
  return {snapshot,journal};
 }

 async verify(tx,sourceId,initial,binding){
  const current=await this.plan(tx,sourceId);
  check(same(current.snapshot,initial.snapshot)&&this.custody.sameJournal(current.journal,initial.journal),
   'native_auto_source_changed',409);
  await this.witnesses.sealed(binding,current.snapshot.proof.object_key,current.journal);
 }

 async process(sourceId){
  requireRequestId(sourceId);let binding,bytes;
  try{
   const initial=await this.authority.write(async tx=>{
    const current=await this.plan(tx,sourceId);
    binding={kind:'native_auto_processing',groupId:this.groupId,requestId:crypto.randomUUID(),
     source:current.snapshot.proof,actor:current.snapshot.actor,profileSha256:current.snapshot.profile.profileSha256};
    const fetchPlan=await this.witnesses.stage(binding,[{key:current.snapshot.proof.object_key,journal:current.journal}]);
    return {...current,fetchPlan};
   });
   await this.witnesses.prefetch(initial.fetchPlan);
   const record=initial.snapshot.proof,profile=initial.snapshot.profile,account=profile.profile;
   bytes=await this.custody.decrypt(await this.witnesses.sealed(binding,record.object_key,initial.journal),target(record).aad);
   check(bytes instanceof Uint8Array&&bytes.length===Number(record.size_bytes)&&await digest(bytes)===record.object_sha256,
    'native_auto_source_changed',409);
   const source=JSON.parse(decoder.decode(bytes));checkPayload(source,record);
   check(await sha256(source.raw_body)===record.bodySha256,'native_auto_source_changed',409);
   const planned=prepareNativeAutoExtraction(source,account);
   check(['provider','security_message'].includes(planned.kind),'native_auto_source_changed',409);
   const lease=crypto.randomUUID(),values=[sourceId,lease,record.fingerprint,profile.profileSha256];
   const begun=await this.authority.write(async tx=>{
    await this.verify(tx,sourceId,initial,binding);
    const rows=await tx.unsafe('SELECT private.burimunsi_auto_begin($1,$2::uuid,$3,$4) AS result',values);
    check(rows.length===1&&rows[0].result?.sourceId===sourceId&&typeof rows[0].result?.started==='boolean');
    return rows[0].result;
   });
   if(!begun.started){
    check(['processing','completed','security_message','failed'].includes(begun.state));
    return {state:begun.state==='processing'?'not_claimed':begun.state};
   }
   if(planned.kind==='security_message'){
    const result=await this.authority.write(async tx=>{
     await this.verify(tx,sourceId,initial,binding);
     const rows=await tx.unsafe('SELECT private.burimunsi_auto_skip_security($1,$2::uuid,$3,$4) AS result',values);
     check(rows.length===1&&rows[0].result?.sourceId===sourceId&&rows[0].result.state==='security_message');return rows[0].result;
    });
    return {state:result.state};
   }
   // If COMMIT or its acknowledgement is uncertain this invocation does not
   // call the provider. Expired attempts are retried by the bounded SQL queue;
   // transaction commit remains idempotent even if an AI response was lost.
   await this.authority.write(async tx=>{
    await this.verify(tx,sourceId,initial,binding);
    const rows=await tx.unsafe('SELECT private.burimunsi_auto_dispatch($1,$2::uuid,$3,$4) AS result',values);
    check(rows.length===1&&rows[0].result===true);
   });
   const retry=async reason=>this.authority.write(async tx=>{
    await this.verify(tx,sourceId,initial,binding);
    const rows=await tx.unsafe('SELECT private.burimunsi_auto_retry($1,$2::uuid,$3,$4,$5) AS result',[...values,reason]);
    const result=rows[0]?.result;
    check(rows.length===1&&result?.sourceId===sourceId&&['retry','failed'].includes(result.state)&&
     Number.isSafeInteger(result.attemptCount)&&result.attemptCount>=1&&
     (result.nextAttemptAt===null||Number.isSafeInteger(result.nextAttemptAt)));
    return {state:result.state};
   });
   let output;
   try{
    const result=await this.env.AI.run(MOMO_MODEL,{...planned.request,provider_timeout_ms:8000});
    output=typeof result?.response==='string'?JSON.parse(result.response):result?.response;
   }catch{return await retry('provider_unavailable');}
   const extracted=validateNativeAutoExtraction(source,account,output);
   if(extracted.kind!=='parsed')return await retry('invalid_output');
   const eventIdentity=await nativeSmsEventAliases(source,record.bodySha256);
   const attempt=crypto.randomUUID();
   const done=await this.authority.write(async tx=>{
    await this.verify(tx,sourceId,initial,binding);
    const identity=await tx.unsafe('SELECT private.burimunsi_auto_event_bind($1,$2::uuid,$3,$4::jsonb) AS result',
     [sourceId,lease,record.fingerprint,eventIdentity]);
    check(identity.length===1&&identity[0].result===true,'native_auto_source_changed',409);
    const rows=await tx.unsafe('SELECT private.burimunsi_auto_finish($1,$2::uuid,$3,$4,$5::uuid,$6,$7::jsonb,$8::jsonb) AS result',
     [...values,attempt,this.env.MOMO_AI_MODEL,extracted.normalizedOutput??output,extracted.facts]);
    check(rows.length===1&&rows[0].result?.sourceId===sourceId&&rows[0].result.state==='completed'&&
     ['accepted','duplicate','conflict'].includes(rows[0].result.relation));return rows[0].result;
   });
   return {state:'completed',relation:done.relation};
  }catch(error){
   if(error instanceof BuriError)throw error;
   if(['40001','23505'].includes(error?.code))throw new BuriError('native_auto_source_changed',409);
   if(error?.code==='42501')throw new BuriError('access_denied',403);
   throw new BuriError('native_auto_unavailable',503);
  }finally{bytes?.fill(0);if(binding)this.witnesses.forget(binding);}
 }
}

/** Called from the existing authenticated scheduler, never from an HTTP
 * request body. Source IDs and groups come only from the database. */
export async function drainNativeAutoTransactions(env,{limit=1}={}){
 if(env?.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!=='true')return {status:'disabled',processed:0,results:[]};
 const db=env.DB,work=db?.applicationWork;
 check(limit===1&&work?.kind==='jobs'&&typeof work.assert==='function'&&typeof db?.transaction==='function'&&
  typeof db.context==='function'&&env.MOMO_AI_ENABLED==='true'&&MODEL.test(env.MOMO_AI_MODEL??'')&&
  typeof env.OPENAI_API_KEY==='string'&&env.OPENAI_API_KEY.length>0&&typeof env.AI?.run==='function',
  'native_auto_unconfigured',503);
 await work.assert();
 const collections=await db.transaction(async tx=>{
  check(db.applicationWork===work);await db.context(tx);
  await lockCollectMutation(tx);
  const rows=await tx.unsafe('SELECT private.burimunsi_auto_collections($1) AS result',[1]);
  await work.assert();check(rows.length===1&&Array.isArray(rows[0].result)&&rows[0].result.length<=1);
  return rows[0].result;
 });
 if(!collections.length)return {status:'complete',processed:0,results:[]};
 const groupId=requireId(typeof collections[0]==='string'?collections[0]:collections[0]?.collectionId);
 const worker=new PostgresNativeAutoWorker({env,groupId});
 const sources=await worker.authority.write(async tx=>{
  const rows=await tx.unsafe('SELECT private.burimunsi_auto_sources($1) AS result',[1]);
  check(rows.length===1&&Array.isArray(rows[0].result)&&rows[0].result.length<=1);return rows[0].result;
 });
 if(!sources.length)return {status:'complete',processed:0,results:[]};
 const value=sources[0];check(value?.collectionId===groupId);const sourceId=requireRequestId(value.sourceId);
 const result=await worker.process(sourceId);
 return {status:'complete',processed:1,results:[result]};
}
