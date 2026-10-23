import {ApiError,first,rows,uuid,id,text,integer,now,digest,readJson,requirePermission,requireFreshAuth} from './core.js';
import {mutation,retainedResponse} from './mutations.js';
import {requireSession} from './auth.js';
import {encrypt,decrypt} from './encryption.js';
export async function evidenceRoute(request,env,actor) {
 const path=new URL(request.url).pathname;
 if(path==='/v1/evidence'&&request.method==='POST'){
  requirePermission(actor,'payments.write');requireFreshAuth(actor);if(actor.assuranceLevel!==2)throw new ApiError(403,'mfa_required','Complete two-step verification.');
  const body=await readJson(request,2097152);const collectionId=uuid(body.collection_id,'collection_id');
  const group=await first(env,`SELECT * FROM collections WHERE id=? AND status='active'`,collectionId);if(!group)throw new ApiError(404,'group_unavailable','The group is unavailable.');
  const amount=integer(body.amount_minor,'amount',1),requestId=uuid(body.request_id,'request_id');
  const reason=text(body.reason,'reason',500,{optional:true});
  const raw=text(body.evidence,'evidence',1048576);const bytes=new TextEncoder().encode(raw);const sha=await digest(bytes);
  const reference=text(body.external_reference,'external_reference',200,{optional:true});
  if(!env.PRIVATE_MEDIA)throw new ApiError(503,'evidence_storage_unavailable','Evidence storage is unavailable.');
  const previous=await first(env,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?',actor.userId,requestId);
  if(previous)return Response.json(await mutation(env,actor,'payment.record',requestId,body,null,[],{permission:'payments.write',minimumAssurance:2}));
  const evidenceId=id(),paymentId=id(),key=`evidence/${evidenceId}`;
  const cipher=await encrypt(env,bytes,`evidence:${evidenceId}:${sha}`);
  await env.PRIVATE_MEDIA.put(key,cipher,{httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:sha,key_id:env.DATA_KEY_ID}});
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
  try{const committed=await mutation(env,actor,'payment.record',requestId,body,value,writes,{permission:'payments.write',minimumAssurance:2,targetCollectionId:group.id,expectedTargetCollectionRevision:group.revision,entityType:'payment',entityId:paymentId,auditDetails:reason?{reason}:{}});if(committed.evidence_id!==evidenceId&&!await first(env,'SELECT id FROM payment_evidence WHERE id=?',evidenceId))await env.PRIVATE_MEDIA.delete(key);return Response.json(committed);}
  catch(error){
   const retained=await first(env,'SELECT id FROM payment_evidence WHERE id=?',evidenceId);
   if(!retained)await env.PRIVATE_MEDIA.delete(key);throw error;
  }
 }
 const match=/^\/v1\/evidence\/([0-9a-f-]{36})$/.exec(path);
 if(match&&request.method==='GET'){
  requirePermission(actor,'payments.evidence.read');const row=await first(env,'SELECT * FROM payment_evidence WHERE id=?',uuid(match[1],'evidence_id'));if(!row)throw new ApiError(404,'evidence_unavailable','Evidence is unavailable.');
  const object=await env.PRIVATE_MEDIA.get(row.object_key);if(!object)throw new ApiError(503,'evidence_unavailable','Retained evidence is unavailable.');
  const bytes=await decrypt(env,await object.text(),`evidence:${row.id}:${row.object_sha256}`);
  if(bytes.byteLength!==row.size_bytes||await digest(bytes)!==row.object_sha256)throw new ApiError(503,'evidence_integrity_failed','Retained evidence verification failed.');
  const current=await requireSession(request,env);requirePermission(current,'payments.evidence.read');
  return new Response(bytes,{headers:{'Content-Type':row.content_type,'Content-Disposition':'attachment','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
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
