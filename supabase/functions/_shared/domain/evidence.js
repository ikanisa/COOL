import {requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError,first,rows,uuid,id,text,integer,now,digest,readJson,requirePermission,requireFreshAuth,stableJson} from './core.js';
import {storageEntity} from '../storage-identity.js';
import {mutation,retainedResponse,assertMutationAdmission} from './mutations.js';
import {requireSession} from './auth.js';
import {accountDatabase,adminAccountSession,adminCanonicalActor} from './admin_accounts.js';
import {evidenceSensitivitySql,evidenceSensitivity} from './evidence_provenance.js';
import {encrypt,decrypt} from './encryption.js';
const deniedEvidence=(status,code,message)=>{throw new ApiError(status,code,message);};
const sameAdmin=(before,after)=>['id','principal_id','auth_user_id','auth_session_id','token_hash','public_id','origin','auth_version','role'].every(key=>before[key]===after[key]);
function protectedEvidence(env,account,actor){
 for(const permission of ['payments.evidence.read','sms.read','sms.reveal']){
  if(!actor.permissions.has(permission)||!account.permissions.includes(permission))deniedEvidence(403,'permission_required','Original evidence access is unavailable for this account.');
  env=accountDatabase(env,account,permission,{mfa:true,fresh:true});
 }
 requireFreshAdminEmail(actor);requireFreshAdminEmail(account);return env;
}
export async function evidenceRoute(request,env,actor,{adminRequest=null,account=null}={}) {
 const path=new URL(request.url).pathname;
 if(path==='/v1/evidence'&&request.method==='POST'){
  requirePermission(actor,'payments.write');if(actor.surface==='admin')requireFreshAdminEmail(actor);else{requireFreshAuth(actor);if(actor.assuranceLevel!==2)throw new ApiError(403,'mfa_required','Complete two-step verification.');}
  const body=await readJson(request,2097152);const collectionId=uuid(body.collection_id,'collection_id');
  const group=await first(env,`SELECT * FROM collections WHERE id=? AND status='active'`,collectionId);if(!group)throw new ApiError(404,'group_unavailable','The group is unavailable.');
  const amount=integer(body.amount_minor,'amount',1),requestId=uuid(body.request_id,'request_id');
  const reason=text(body.reason,'reason',500,{optional:true});
  const raw=text(body.evidence,'evidence',1048576);const bytes=new TextEncoder().encode(raw);const sha=await digest(bytes);
  const reference=text(body.external_reference,'external_reference',200,{optional:true});
  if(!env.PRIVATE_MEDIA)throw new ApiError(503,'evidence_storage_unavailable','Evidence storage is unavailable.');
  const previous=await first(env,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?',actor.userId,requestId);
  if(previous)return Response.json(await mutation(env,actor,'payment.record',requestId,body,null,[],{permission:'payments.write',minimumAssurance:2}));
  const evidenceId=await storageEntity('payment.evidence',actor.userId,requestId),paymentId=await storageEntity('payment.record',actor.userId,requestId),key=`evidence/${evidenceId}`;
  const cipher=await encrypt(env,bytes,`evidence:${evidenceId}:${sha}`);
  await env.PRIVATE_MEDIA.put(key,cipher,{scope:{ownerId:actor.userId,purpose:'payment_evidence',entityId:evidenceId},aad:`evidence:${evidenceId}:${sha}`,sourceDigest:await digest(stableJson(body)),httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:sha,key_id:env.DATA_KEY_ID}});
  const value={id:paymentId,evidence_id:evidenceId,status:'recorded',evidence_level:'operator_recorded',amount_minor:amount,currency:'RWF'};
  const writes=[env.DB.prepare(`INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,amount_minor,observed_at,created_at,receiver_network,receiver_display_label) VALUES(?,?,?,?,?,?,?,'operator_recorded',?,?,?,?,?,?,?)`).bind(evidenceId,group.id,actor.userId,key,sha,bytes.length,'text/plain',reference,group.receiver_momo_number,amount,text(body.observed_at??now(),'observed_at',30),now(),group.receiver_network,group.receiver_display_label),env.DB.prepare(`INSERT INTO payments(id,collection_id,evidence_id,amount_minor,status,payer_display_name,created_at) VALUES(?,?,?,?,'recorded',?,?)`).bind(paymentId,group.id,evidenceId,amount,body.payer_display_name?text(body.payer_display_name,'payer_display_name',100):'',now())];
  if(reference&&await first(env,"SELECT name FROM sqlite_master WHERE type='table' AND name='momo_transactions'")){
   // The canonical receipt route owns an already-known economic identity.
   // Evaluate after R2 work, inside the same financial admission transaction.
   const sourceGuard=id();
   writes.unshift(env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN NOT EXISTS(
    SELECT 1 FROM momo_transactions t JOIN momo_receiving_accounts a ON a.id=t.receiving_account_id
    WHERE t.provider=? AND t.event_kind='incoming_receipt' AND (?=t.provider_transaction_id OR ?=a.id||':'||t.provider_transaction_id)
    AND (CASE WHEN a.public_code GLOB '07*' AND length(a.public_code)=10 THEN '250'||substr(a.public_code,2) ELSE replace(a.public_code,'+','') END)=
    (SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route))) THEN 1 ELSE 0 END`).bind(sourceGuard,group.receiver_network,reference,reference,group.receiver_momo_number));
   writes.push(env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(sourceGuard));
  }
  try{const committed=await mutation(env,actor,'payment.record',requestId,body,value,writes,{permission:'payments.write',minimumAssurance:2,targetCollectionId:group.id,expectedTargetCollectionRevision:group.revision,entityType:'payment',entityId:paymentId,auditDetails:reason?{reason}:{}});return Response.json(committed);}
  catch(error){
   // Pending objects remain journaled for exact retry/retention reconciliation.
   throw error;
  }
 }
 const match=/^\/v1\/evidence\/([0-9a-f-]{36})$/.exec(path);
 if(match&&request.method==='GET'){
  if(new URL((adminRequest??request).url).search)deniedEvidence(400,'invalid_request','Evidence review does not accept query parameters.');
  requirePermission(actor,'payments.evidence.read');
  const selected=await first(env,`SELECT e.*,o.scope AS retained_scope,${evidenceSensitivitySql} AS source_sensitivity
   FROM payment_evidence e LEFT JOIN private.storage_objects o ON o.object_key=e.object_key WHERE e.id=?`,uuid(match[1],'evidence_id'));
  if(!selected)deniedEvidence(404,'evidence_unavailable','Evidence is unavailable.');
  const {retained_scope:scope,source_sensitivity:sensitivity,...row}=selected,classification=evidenceSensitivity(sensitivity),protectedSource=classification!=='ordinary';
  let scoped=env,reason=null;
  if(protectedSource){
   // A bearer or metadata value cannot stand in for the current BFF account
   // and its independently established email proof. Unknown legacy provenance
   // receives the same protection as a positively identified SMS derivative.
   if(!adminRequest||!account||actor.surface!=='admin'||actor.userId!==account.principal_id||actor.sessionId!==account.auth_session_id)
    deniedEvidence(403,'admin_session_required','Open the Admin workspace to review original evidence.');
   scoped=protectedEvidence(env,account,actor);
   const supplied=adminRequest.headers.get('X-Collect-Review-Reason');
   if(typeof supplied!=='string'||supplied.trim().length<8||supplied.trim().length>1000||/[\u0000-\u001f\u007f]/.test(supplied))
    deniedEvidence(400,'reason_required','Record a review reason of 8 to 1000 characters.');
   reason=supplied.trim();
   await assertMutationAdmission(scoped,actor,[],{permission:'sms.reveal',minimumAssurance:2,freshSeconds:300});
  }
  const integrity=()=>deniedEvidence(503,'evidence_integrity_failed','Retained evidence verification failed.');
  if(scope?.ownerId!==row.owner_user_id||scope?.entityId!==row.id||scope?.purpose!=='payment_evidence'||
   !Number.isSafeInteger(row.size_bytes)||row.size_bytes<1||row.size_bytes>4194304||!/^[a-f0-9]{64}$/.test(row.object_sha256??''))integrity();
  const object=await scoped.PRIVATE_MEDIA?.get(row.object_key);if(!object)deniedEvidence(503,'evidence_unavailable','Retained evidence is unavailable.');
  let bytes;try{bytes=await decrypt(scoped,await object.text(),`evidence:${row.id}:${row.object_sha256}`);if(bytes.byteLength!==row.size_bytes||await digest(bytes)!==row.object_sha256)integrity();}catch{integrity();}
  // Re-resolve current authority after the asynchronous object read/decrypt,
  // then bind the same source/classification, all grants and audit to one batch.
  let current;
  if(adminRequest&&account){
   const latest=await adminAccountSession(adminRequest,env);
   if(!sameAdmin(account,latest))deniedEvidence(403,'admin_access_changed','Evidence access changed. Refresh before continuing.');
   current=await adminCanonicalActor(adminRequest,env,latest);
   scoped=protectedSource?protectedEvidence(env,latest,current):accountDatabase(env,latest,'payments.evidence.read');
  }else current=await requireSession(request,env);
  if(current.userId!==actor.userId||current.sessionId!==actor.sessionId)deniedEvidence(403,'session_changed','Evidence access changed. Sign in again.');
  requirePermission(current,'payments.evidence.read');
  const guardId=id(),writes=[scoped.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN EXISTS(
   SELECT 1 FROM payment_evidence e JOIN private.storage_objects o ON o.object_key=e.object_key
   JOIN private.storage_put_intents p ON p.object_key=o.object_key
   WHERE e.id=? AND to_jsonb(e)=?::jsonb AND o.scope->>'ownerId'=e.owner_user_id
    AND o.scope->>'entityId'=e.id AND o.scope->>'purpose'='payment_evidence'
    AND p.state='committed' AND NOT p.delete_tombstone AND (${evidenceSensitivitySql})=?) THEN 1 ELSE 0 END`).bind(guardId,row.id,row,classification)];
  if(protectedSource)writes.push(scoped.DB.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at)
   VALUES(?,?,'payment.evidence.revealed','payment_evidence',?,?,?)`).bind(current.userId,current.sessionId,row.id,
    JSON.stringify({reason,source_sensitivity:classification,owner_user_id:row.owner_user_id,source_sha256:row.object_sha256}),now()));
  writes.push(scoped.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guardId));
  await assertMutationAdmission(scoped,current,writes,{permission:protectedSource?'sms.reveal':'payments.evidence.read',...(protectedSource?{minimumAssurance:2,freshSeconds:300}:{})});
  return new Response(bytes,{headers:{'Content-Type':row.content_type,'Content-Disposition':'attachment','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','X-Collect-Evidence-Sensitivity':classification}});
 }
 return null;
}
export async function compensationRpc(operation,body,env,actor) {
 if(!['admin_reverse_payment_v1','admin_record_full_payment_compensation_v1'].includes(operation))return {handled:false};
 requirePermission(actor,'payments.reconcile');const requestId=uuid(body.p_request_id??body.request_id,'request_id');
 const previous=await retainedResponse(env,actor,operation,requestId,body,{permission:'payments.reconcile',minimumAssurance:2,freshSeconds:300});if(previous.found)return {handled:true,value:previous.value};
 const payment=await first(env,'SELECT * FROM payments WHERE id=?',uuid(body.p_payment_id??body.payment_id,'payment_id'));
 if(!payment)throw new ApiError(404,'payment_unavailable','Payment is unavailable.');
 const expected=integer(body.p_expected_revision??body.expected_revision,'revision',1);if(payment.revision!==expected)throw new ApiError(409,'stale_state','The payment changed.');
 const original=await first(env,`SELECT * FROM ledger_entries WHERE payment_id=? AND kind='contribution'`,payment.id);
 if(!original)throw new ApiError(409,'not_posted','This payment has no posted contribution.');
 if(await first(env,'SELECT id FROM ledger_entries WHERE reverses_entry_id=?',original.id))throw new ApiError(409,'already_reversed','This contribution was already reversed.');
 const reason=text(body.p_reason??body.reason??body.p_reason_code,'reason',500);
 const value={payment_id:payment.id,status:'reversed',revision:expected+1,request_id:requestId};
 return {handled:true,value:await mutation(env,actor,operation,requestId,body,value,[env.DB.prepare(`INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'reversal',?,?,?,?,?)`).bind(id(),payment.id,payment.collection_id,original.member_id,-original.amount_minor,original.id,original.evidence_id,actor.userId,requestId,now()),env.DB.prepare(`UPDATE payments SET status='reversed',revision=revision+1 WHERE id=? AND revision=?`).bind(payment.id,expected)],{permission:'payments.reconcile',minimumAssurance:2,freshSeconds:300,paymentId:payment.id,expectedPaymentRevision:expected,entityType:'payment',entityId:payment.id,auditDetails:{reason}})};
}
