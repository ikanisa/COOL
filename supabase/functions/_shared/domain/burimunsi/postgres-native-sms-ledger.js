// Automatic native SMS posting through Collect's existing financial tables.
// No managed gateway, provider-confirmation API, or additional service is used.
import {digest} from '../core.js';
import {encrypt} from '../encryption.js';
import {MOMO_MODEL} from '../momo_pipeline.js';
import {storageEntity} from '../../storage-identity.js';
import {appendContributionCollision,appendContributionEntry,appendContributionSnapshots} from '../contribution-posting.mjs';
import {BuriError,requireThat} from './errors.js';
import {canonicalJson,requireId,requireRequestId,sha256} from './values.js';
import {PostgresNativeAutoWorker} from './postgres-native-auto-worker.js';
import {prepareNativeAutoExtraction,validateNativeAutoExtraction,hasStrongNativeTransactionIdentity} from './native-auto-parser.js';
import {matchNativeSmsMember} from './native-sms-member-match.js';

const check=(ok,code='native_sms_posting_unavailable',status=503)=>requireThat(ok,code,status);
const enc=new TextEncoder(),dec=new TextDecoder('utf-8',{fatal:true});
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const one=rows=>{check(Array.isArray(rows)&&rows.length===1&&rows[0]?.result);return rows[0].result;};
const isHash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const exact=v=>{const n=typeof v==='string'&&/^[0-9]+$/.test(v)?Number(v):v;check(Number.isSafeInteger(n)&&n>=0);return n;};
const sourceTarget=r=>({ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`});
const safeStates=new Set(['posted','unmatched','already_posted','not_financial']);
const invalidOutputDelayMs=24*60*60*1000;

function factsComplete(f,row,source,profile,output){
 return ['incoming_receipt','outgoing'].includes(f?.event_kind)&&f.payment_outcome==='successful'&&f.currency==='RWF'&&
  Number.isSafeInteger(f.amount_minor)&&f.amount_minor>0&&(row.amount_minor===null||f.amount_minor===exact(row.amount_minor))&&
  (row.event_kind==='unknown'||row.event_kind===f.event_kind)&&
  (f.event_kind!=='incoming_receipt'||Number.isSafeInteger(f.wallet_balance_after_minor)&&f.wallet_balance_after_minor>=0||
   f.wallet_balance_after_minor===null&&typeof f.provider_transaction_id==='string'&&f.provider_transaction_id.length>0&&
    f.provider_transaction_id.length<=160&&!/\s/u.test(f.provider_transaction_id)&&
    f.provider_transaction_id===row.provider_transaction_id&&hasStrongNativeTransactionIdentity(source,profile,output))&&
  f.source_mode===source.source_mode;
}
function sameSource(a,b){
 return ['collection_id','source_id','source_fingerprint','principal_user_id','capture_session_id','body_sha256',
  'object_sha256','object_key','size_bytes','transaction_id','receiving_account_id','provider','provider_transaction_id','amount_minor','currency',
  'event_kind','mode','version','has_conflict','allocation_state','public_code'].every(k=>same(a[k],b[k]));
}
async function rowsForMembers(tx,groupId){
 const rows=await tx.unsafe(`SELECT u.id,u.full_name,u.momo_number,u.member_type,u.access_status,m.collection_id,m.active
  FROM app.memberships m JOIN app.users u ON u.id=m.user_id
  WHERE m.collection_id=$1 ORDER BY u.id LIMIT 100001 FOR UPDATE OF m,u`,[groupId]);
 check(Array.isArray(rows)&&rows.length<=100000);
 return rows.map(r=>({id:r.id,groupId:r.collection_id,name:r.full_name,momoNumber:r.momo_number,
  memberType:r.member_type,active:exact(r.active)===1,eligible:r.access_status==='active'}));
}

export class PostgresNativeSmsLedger {
 constructor({env,groupId}){
  this.worker=new PostgresNativeAutoWorker({env,groupId});this.env=env;this.groupId=requireId(groupId);
  this.authority=this.worker.authority;this.db=env.DB;
 }
 async snapshot(tx,sourceId){return one(await tx.unsafe('SELECT private.burimunsi_native_sms_post_snapshot($1) AS result',[sourceId]));}
 async defer(sourceId,delayMs=60000){
  return this.authority.write(async tx=>{
   const rows=await tx.unsafe('SELECT private.burimunsi_native_sms_post_defer($1,$2) AS result',[sourceId,delayMs]);
   check(rows.length===1&&rows[0].result===true);return {state:'unmatched'};
  });
 }
 async backoff(sourceId,reason){
  try{return await this.authority.write(async tx=>{
   const rows=await tx.unsafe('SELECT private.burimunsi_native_sms_post_retry($1,$2) AS result',[sourceId,reason]);
   const result=rows[0]?.result;
   check(rows.length===1&&typeof result?.deferred==='boolean'&&
    (result.deferred?Number.isSafeInteger(result.failureCount)&&result.failureCount>=1&&result.failureCount<=16&&
     Number.isSafeInteger(result.nextAttemptAt)&&result.nextAttemptAt>=0:result.state==='not_eligible'),
    'native_sms_posting_retry_unavailable',503);
   return result;
  });}catch(error){
   if(['request_not_admitted','application_fenced','application_fence_unavailable'].includes(error?.code))throw error;
   throw new BuriError('native_sms_posting_retry_unavailable',503);
  }
 }
 async unresolved(sourceId){
  await this.backoff(sourceId,'source_unavailable');return {state:'unmatched'};
 }
 async process(sourceId){
  requireRequestId(sourceId);let binding,plaintext,body,phase='source';
  try{
   const initial=await this.authority.write(async tx=>{
    const plan=await this.worker.plan(tx,sourceId),row=await this.snapshot(tx,sourceId),proof=plan.snapshot.proof;
    check(row.collection_id===this.groupId&&row.source_id===sourceId&&row.principal_user_id===proof.principalUserId&&
     row.object_key===proof.object_key&&row.object_sha256===proof.object_sha256&&row.body_sha256===proof.bodySha256&&
     row.source_fingerprint===proof.fingerprint&&isHash(row.body_sha256)&&
     ['incoming_receipt','outgoing','unknown'].includes(row.event_kind)&&
     (row.currency===null||row.currency==='RWF')&&exact(row.has_conflict)===0);
    binding={kind:'native_auto_processing',groupId:this.groupId,requestId:crypto.randomUUID(),source:proof,
     actor:plan.snapshot.actor,profileSha256:plan.snapshot.profile.profileSha256};
    const fetchPlan=await this.worker.witnesses.stage(binding,[{key:proof.object_key,journal:plan.journal}]);
    return {plan,row,fetchPlan};
   });
   if(initial.row.has_link===true){check(initial.row.link_posted===true);return {state:'already_posted'};}
   await this.worker.witnesses.prefetch(initial.fetchPlan);
   const record=initial.plan.snapshot.proof;
   plaintext=await this.worker.custody.decrypt(await this.worker.witnesses.sealed(binding,record.object_key,initial.plan.journal),sourceTarget(record).aad);
   check(plaintext instanceof Uint8Array&&plaintext.length===exact(record.size_bytes)&&await digest(plaintext)===record.object_sha256);
   const source=JSON.parse(dec.decode(plaintext));
   check(source?.provenance==='native_observation_unverified'&&typeof source.raw_body==='string'&&
    typeof source.raw_sender==='string'&&['live','catch_up'].includes(source.source_mode)&&
    (source.source_mode==='live'?initial.row.mode==='live':initial.row.mode==='historical')&&
    await sha256(source.raw_body)===record.bodySha256);
   const profile=initial.plan.snapshot.profile.profile;
   let output=initial.row.posting_output??(typeof initial.row.output_json==='string'?JSON.parse(initial.row.output_json):initial.row.output_json);
   let extracted=validateNativeAutoExtraction(source,profile,output);
   if(!factsComplete(extracted?.facts,initial.row,source,profile,output)){
    const planned=prepareNativeAutoExtraction(source,profile);
    if(planned.kind!=='provider')return await this.unresolved(sourceId);
    check(this.env.MOMO_AI_ENABLED==='true'&&typeof this.env.AI?.run==='function');
    const response=await this.env.AI.run(MOMO_MODEL,{...planned.request,provider_timeout_ms:8000});
    try{output=typeof response?.response==='string'?JSON.parse(response.response):response?.response;}catch{return await this.defer(sourceId,invalidOutputDelayMs);}
    extracted=validateNativeAutoExtraction(source,profile,output);
    if(!factsComplete(extracted?.facts,initial.row,source,profile,output))return await this.defer(sourceId,invalidOutputDelayMs);
   }
   const facts={...extracted.facts,transaction_time_source:extracted.facts.transaction_at?'sms_body_and_provider_profile':null,
    transaction_timezone:extracted.facts.transaction_at?profile.timezone:null};
   if(initial.row.posting_facts!==null)check(same(initial.row.posting_facts,facts)&&same(initial.row.posting_output,output));
   const memberId=await this.authority.write(async tx=>{
    await this.worker.verify(tx,sourceId,initial.plan,binding);
    const row=await this.snapshot(tx,sourceId);check(sameSource(initial.row,row));
    const saved=await tx.unsafe('SELECT private.burimunsi_native_sms_post_facts($1,$2,$3::jsonb,$4::jsonb) AS result',
     [sourceId,row.source_fingerprint,output,facts]);check(saved.length===1&&saved[0].result===true);
    if(facts.event_kind!=='incoming_receipt')return null;
    const members=await rowsForMembers(tx,this.groupId);
    return matchNativeSmsMember({groupId:this.groupId,payerName:facts.counterparty_name,payerIdentifier:facts.counterparty_identifier,members});
   });
   if(facts.event_kind==='outgoing')return {state:'not_financial'};
   if(initial.row.event_kind!=='incoming_receipt')return await this.defer(sourceId);
   if(!memberId)return await this.defer(sourceId);
   requireId(memberId);
   const owner=initial.row.principal_user_id,evidenceId=await storageEntity('burimunsi.native.sms.evidence',owner,sourceId),
    paymentId=await storageEntity('burimunsi.native.sms.payment',owner,sourceId),objectKey='evidence/'+evidenceId;
   const bodySha=record.bodySha256,aad=`evidence:${evidenceId}:${bodySha}`;
   body=enc.encode(source.raw_body);check(body.length>0&&body.length<=16384&&await digest(body)===bodySha);
   const sourceDigest=await sha256(canonicalJson({kind:'burimunsi.native.sms.v1',groupId:this.groupId,sourceId,
    transactionId:initial.row.transaction_id,bodySha256:bodySha}));
   const cipher=await encrypt(this.env,body,aad);
   const ack=await this.env.PRIVATE_MEDIA.put(objectKey,cipher,{scope:{ownerId:owner,purpose:'payment_evidence',entityId:evidenceId},
    aad,sourceDigest,httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:bodySha,key_id:this.env.DATA_KEY_ID}});
   check(ack?.stored===true&&ack.metadataCommitted===true&&ack.key===objectKey);
   phase='posting';
   return await this.authority.write(async tx=>{
    await this.worker.verify(tx,sourceId,initial.plan,binding);
    const row=await this.snapshot(tx,sourceId);
    if(row.has_link===true){check(row.link_posted===true);return {state:'already_posted'};}
    check(sameSource(initial.row,row)&&same(row.posting_facts,facts)&&same(row.posting_output,output)&&
     ['unallocated','not_applicable'].includes(row.allocation_state));
    const members=await rowsForMembers(tx,this.groupId);
    check(matchNativeSmsMember({groupId:this.groupId,payerName:facts.counterparty_name,payerIdentifier:facts.counterparty_identifier,members})===memberId,
     'native_sms_member_changed',409);
    const now=new Date().toISOString(),observed=row.transaction_at??row.created_at,reference='sms:'+bodySha+':'+sourceId;
    const evidence=await tx.unsafe(`INSERT INTO app.payment_evidence
     (id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,
      receiver_momo_number,amount_minor,currency,observed_at,created_at,receiver_network,receiver_display_label)
     VALUES($1,$2,$3,$4,$5,$6,'text/plain','operator_recorded',$7,$8,$9,'RWF',$10,$11,$12,$13) RETURNING id`,
     [evidenceId,this.groupId,owner,objectKey,bodySha,body.length,reference,row.public_code,exact(row.amount_minor),observed,now,row.provider,row.receiver_display_label]);
    check(evidence.length===1&&evidence[0].id===evidenceId);
    const payments=await tx.unsafe(`INSERT INTO app.payments(id,collection_id,evidence_id,intent_id,member_id,amount_minor,currency,rail,revision,status,payer_display_name,created_at)
     VALUES($1,$2,$3,NULL,NULL,$4,'RWF','rwanda_momo',1,'recorded',$5,$6) RETURNING id`,
     [paymentId,this.groupId,evidenceId,exact(row.amount_minor),facts.counterparty_name??'',now]);
    check(payments.length===1&&payments[0].id===paymentId);
    const links=await tx.unsafe(`INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at)
     VALUES($1,$2,$3,$4,'Automatic SMS member match',0,$5) RETURNING transaction_id`,
     [row.transaction_id,paymentId,memberId,owner,now]);
    check(links.length===1&&links[0].transaction_id===row.transaction_id);
    const changed=await tx.unsafe(`UPDATE app.momo_transactions SET allocation_state='linked',version=version+1,updated_at=$1
     WHERE id=$2 AND version=$3 AND allocation_state IN ('unallocated','not_applicable') AND has_conflict=0 RETURNING id`,
     [now,row.transaction_id,exact(row.version)]);check(changed.length===1);
    const writes=[],cmd={env:{DB:{prepare:text=>this.db.prepare(text)}},p:{id:paymentId,collection_id:this.groupId,
     amount_minor:exact(row.amount_minor),revision:1,evidence_id:evidenceId},checkId:crypto.randomUUID(),
     actor:{userId:owner,sessionId:String(row.capture_session_id)},reconciliation:{proposed_member_id:memberId},
     requestId:sourceId,now:()=>new Date().toISOString(),id:()=>crypto.randomUUID()};
    appendContributionCollision(writes,cmd);appendContributionEntry(writes,cmd);appendContributionSnapshots(writes,cmd);
    for(const statement of writes)await this.db.statement(tx,statement);
    const read=await tx.unsafe(`SELECT p.id,p.member_id,p.amount_minor,p.currency,p.status,l.amount_minor AS ledger_amount,
     l.currency AS ledger_currency,l.evidence_id,s.member_balance_after_minor,s.group_balance_after_minor
     FROM app.payments p JOIN app.ledger_entries l ON l.payment_id=p.id AND l.kind='contribution'
     JOIN app.contribution_posting_snapshots s ON s.payment_id=p.id AND s.ledger_entry_id=l.id
     JOIN app.momo_financial_links f ON f.payment_id=p.id AND f.transaction_id=$3
     WHERE p.id=$1 AND p.collection_id=$2 AND f.beneficiary_member_id=p.member_id`,[paymentId,this.groupId,row.transaction_id]);
    check(read.length===1&&read[0].member_id===memberId&&read[0].status==='reconciled'&&
     read[0].currency==='RWF'&&read[0].ledger_currency==='RWF'&&read[0].evidence_id===evidenceId&&
     exact(read[0].amount_minor)===facts.amount_minor&&exact(read[0].ledger_amount)===facts.amount_minor);
    await this.worker.verify(tx,sourceId,initial.plan,binding);
    return {state:'posted'};
   });
  }catch(error){
   const mapped=error instanceof BuriError?error:['40001','23505'].includes(error?.code)?new BuriError('native_sms_posting_changed',409):
    error?.code==='42501'?new BuriError('access_denied',403):new BuriError('native_sms_posting_unavailable',503);
   // The financial transaction has completed or rolled back before this
   // separate, admission-bound metadata write. Never retry money in the catch.
   if(!['request_not_admitted','application_fenced','application_fence_unavailable','native_sms_posting_retry_unavailable'].includes(mapped.code)){
    const reason=mapped.code==='access_denied'?'access_denied':mapped.status===409?'posting_changed':phase==='posting'?'posting_failed':'source_unavailable';
    try{await this.backoff(sourceId,reason);}catch(retryError){
     if(['request_not_admitted','application_fenced','application_fence_unavailable'].includes(retryError?.code))throw retryError;
     throw new BuriError('native_sms_posting_retry_unavailable',503);
    }
   }
   throw mapped;
  }finally{body?.fill(0);plaintext?.fill(0);if(binding)this.worker.witnesses.forget(binding);}
 }
}

export async function drainNativeSmsLedger(env,{limit=1}={}){
 if(env?.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!=='true')return {status:'disabled',processed:0,results:[]};
 const db=env.DB,work=db?.applicationWork;
 check(limit===1&&work?.kind==='jobs'&&typeof work.assert==='function'&&typeof db?.transaction==='function'&&typeof db.context==='function');
 await work.assert();
 const selected=await db.transaction(async tx=>{
  check(db.applicationWork===work);await db.context(tx);
  const rows=await tx.unsafe('SELECT private.burimunsi_native_sms_post_candidates($1) AS result',[1]);
  await work.assert();check(rows.length===1&&Array.isArray(rows[0].result)&&rows[0].result.length<=1);return rows[0].result;
 });
 if(!selected.length)return {status:'complete',processed:0,results:[]};
 const {groupId,sourceId}=selected[0];requireId(groupId);requireRequestId(sourceId);
 const result=await new PostgresNativeSmsLedger({env,groupId}).process(sourceId);
 check(safeStates.has(result.state));return {status:'complete',processed:1,results:[{state:result.state}]};
}
