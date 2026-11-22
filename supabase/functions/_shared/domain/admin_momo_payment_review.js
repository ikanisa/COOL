import {ApiError,first,rows,now,digest,stableJson,uuid,integer,text} from './core.js';
import {mutation,retainedResponse} from './mutations.js';
import {encrypt,decrypt} from './encryption.js';
import {storageEntity} from '../storage-identity.js';
import {momoGuard} from './momo_gateway.js';
import {MOMO_UNCERTAIN_ERRORS} from './momo_pipeline.js';
import {MANAGED_MOMO_SOURCE_SQL} from './admin_momo_reads.js';

const enc=new TextEncoder(),dec=new TextDecoder(),fail=(s,c,m)=>{throw new ApiError(s,c,m);};
const keys=(body,allowed)=>{if(Object.keys(body).some(k=>!allowed.includes(k)))fail(400,'invalid_request','This action contains unsupported fields.');};

async function rawPayload(env,rawId){
 // accountDatabase validates current permission/MFA in batch. A standalone
 // prepare().first() would defer that check until AFTER decrypting the object.
 const [result]=await env.DB.batch([env.DB.prepare('SELECT * FROM sms_receipts WHERE id=?').bind(rawId)]),raw=result.results[0];if(!raw)fail(404,'source_unavailable','This retained source is unavailable.');
 const object=await env.PRIVATE_MEDIA.get(raw.object_key);if(!object)fail(503,'source_unavailable','Retained source storage is unavailable.');
 const bytes=await decrypt(env,await object.text(),`sms:${raw.id}:${raw.object_sha256}`);if(bytes.length!==raw.size_bytes||await digest(bytes)!==raw.object_sha256)fail(503,'source_integrity_failed','The retained source could not be verified.');return {raw,payload:JSON.parse(dec.decode(bytes))};}
export async function assignMomoPayment(env,actor,txId,body,rid,source){
 keys(body,['group_id','member_id','intent_id','expected_version','reason']);const options={permission:'payments.write',minimumAssurance:2,freshSeconds:300};
 const prior=await retainedResponse(env,actor,'momo.assign',rid,source,options);if(prior.found)return prior.value;
 const tx=await first(env,`SELECT t.* FROM momo_transactions t WHERE t.id=? AND ${MANAGED_MOMO_SOURCE_SQL}`,txId);if(!tx)fail(404,'not_found','This payment was not found.');
 if(tx.version!==integer(body.expected_version,'expected_version',1)||tx.has_conflict||tx.event_kind!=='incoming_receipt'||tx.allocation_state!=='unallocated')fail(409,'payment_changed','Review the current payment before assigning it.');
 const groupId=uuid(body.group_id,'group_id'),memberId=uuid(body.member_id,'member_id'),reason=text(body.reason,'reason',500);if(reason.length<8)fail(400,'reason_required','Record the evidence supporting this destination.');
 const destination=await first(env,`SELECT g.*,m.revision AS membership_revision,u.revision AS member_revision,u.full_name AS member_name
 FROM collections g JOIN memberships m ON m.collection_id=g.id JOIN users u ON u.id=m.user_id
 WHERE g.id=? AND u.id=? AND g.status='active' AND m.active=1 AND u.access_status='active'`,groupId,memberId);
 if(!destination)fail(409,'destination_unavailable','Choose an active member of this group.');
 const account=await first(env,'SELECT * FROM momo_receiving_accounts WHERE id=?',tx.receiving_account_id);
 const route=value=>/^07[2389]\d{7}$/.test(value??'')?'250'+value.slice(1):(value??'').replace(/^\+/,'');
 if(account.provider!==destination.receiver_network||route(account.public_code)!==route(destination.receiver_momo_number))fail(409,'receiver_mismatch','This group uses a different receiving account. Review the verified payment destination before attribution.');
 const intentId=body.intent_id==null?null:uuid(body.intent_id,'intent_id');
 if(intentId&&!await first(env,`SELECT id FROM payment_intents WHERE id=? AND member_id=? AND collection_id=? AND amount_minor=? AND currency='RWF' AND status IN('pending','expired')`,intentId,memberId,groupId,tx.amount_minor))fail(409,'intent_unavailable','This intent does not match the verified destination and amount.');
 // Historical/operator records can predate this pipeline. Link exact retained
 // evidence first; never treat absence from the new table as proof of no credit.
 const existing=await rows(env,`SELECT p.* FROM payments p JOIN payment_evidence e ON e.id=p.evidence_id
 WHERE e.external_reference IN(?,?) AND e.receiver_network=? AND (CASE WHEN e.receiver_momo_number GLOB '07*' AND length(e.receiver_momo_number)=10 THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=(SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route))`,tx.provider_transaction_id,`${account.id}:${tx.provider_transaction_id}`,account.provider,account.public_code);
 if(existing.length>1||existing.some(p=>p.amount_minor!==tx.amount_minor||p.collection_id!==groupId||(p.member_id!==null&&p.member_id!==memberId)))fail(409,'historical_overlap_conflict','Existing financial evidence needs reconciliation before another record can be linked.');
 if(tx.mode==='historical'&&!existing.length)fail(409,'historical_reconciliation_required','Reconcile historical evidence before enabling a new historical contribution.');
 const paymentId=existing[0]?.id??await storageEntity('momo.assign.payment',actor.userId,rid),evidenceId=await storageEntity('momo.assign.evidence',actor.userId,rid),key='evidence/'+evidenceId;
 const sourceRow=await first(env,`SELECT raw_sms_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='accepted' ORDER BY created_at LIMIT 1`,tx.id);if(!sourceRow)fail(409,'source_unavailable','Review the original source first.');
 const {payload}=await rawPayload(env,sourceRow.raw_sms_id);let bytes,sha;
 if(!existing.length){bytes=enc.encode(payload.raw_body);sha=await digest(bytes);await env.PRIVATE_MEDIA.put(key,await encrypt(env,bytes,`evidence:${evidenceId}:${sha}`),{scope:{ownerId:actor.userId,purpose:'payment_evidence',entityId:evidenceId},aad:`evidence:${evidenceId}:${sha}`,sourceDigest:await digest(stableJson(source)),httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:sha,key_id:env.DATA_KEY_ID}});}
 const gate=momoGuard(env,`EXISTS(SELECT 1 FROM momo_transactions t WHERE t.id=? AND t.version=? AND t.has_conflict=0 AND t.allocation_state='unallocated' AND ${MANAGED_MOMO_SOURCE_SQL})
 AND EXISTS(SELECT 1 FROM collections g JOIN memberships m ON m.collection_id=g.id JOIN users u ON u.id=m.user_id
 WHERE g.id=? AND g.revision=? AND g.status='active' AND u.id=? AND u.revision=? AND u.access_status='active' AND m.active=1 AND m.revision=?)`,[tx.id,tx.version,groupId,destination.revision,memberId,destination.member_revision,destination.membership_revision]);
 const overlapGate=momoGuard(env,existing.length?`EXISTS(SELECT 1 FROM payments p JOIN payment_evidence e ON e.id=p.evidence_id
  WHERE p.id=? AND p.amount_minor=? AND p.collection_id=? AND (p.member_id IS NULL OR p.member_id=?) AND e.external_reference IN(?,?) AND e.receiver_network=? AND (CASE WHEN e.receiver_momo_number GLOB '07*' AND length(e.receiver_momo_number)=10 THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=(SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route)))`:
  `NOT EXISTS(SELECT 1 FROM payments p JOIN payment_evidence e ON e.id=p.evidence_id
  WHERE e.external_reference IN(?,?) AND e.receiver_network=? AND (CASE WHEN e.receiver_momo_number GLOB '07*' AND length(e.receiver_momo_number)=10 THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=(SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route)))`,
  existing.length?[paymentId,tx.amount_minor,groupId,memberId,tx.provider_transaction_id,`${account.id}:${tx.provider_transaction_id}`,account.provider,account.public_code]:[tx.provider_transaction_id,`${account.id}:${tx.provider_transaction_id}`,account.provider,account.public_code]);
 const writes=[gate[0],overlapGate[0],overlapGate[1]];
 if(intentId){const intentGate=momoGuard(env,`EXISTS(SELECT 1 FROM payment_intents WHERE id=? AND member_id=? AND collection_id=? AND amount_minor=? AND status IN('pending','expired'))`,[intentId,memberId,groupId,tx.amount_minor]);writes.push(intentGate[0],intentGate[1]);}
 if(!existing.length)writes.push(env.DB.prepare(`INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,amount_minor,observed_at,created_at,receiver_network,receiver_display_label) VALUES(?,?,?,?,?,?,'text/plain','operator_recorded',?,?,?,?,?,?,?)`).bind(evidenceId,groupId,actor.userId,key,sha,bytes.length,`${account.id}:${tx.provider_transaction_id}`,destination.receiver_momo_number,tx.amount_minor,tx.transaction_at??tx.created_at,now(),destination.receiver_network,destination.receiver_display_label),
 env.DB.prepare(`INSERT INTO payments(id,collection_id,evidence_id,intent_id,amount_minor,status,payer_display_name,created_at) VALUES(?,?,?,?,?,'recorded',?,?)`).bind(paymentId,groupId,evidenceId,intentId,tx.amount_minor,tx.payer_name??'',now()));
 else if(intentId&&existing[0].intent_id!==intentId)fail(409,'historical_intent_conflict','An existing payment cannot be silently reassigned to a new intent.');
 writes.push(env.DB.prepare('INSERT INTO momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at) VALUES(?,?,?,?,?,?,?)').bind(tx.id,paymentId,memberId,actor.userId,reason,Number(existing.length>0),now()),
 env.DB.prepare(`UPDATE momo_transactions SET allocation_state='linked',version=version+1,updated_at=? WHERE id=?`).bind(now(),tx.id),gate[1]);
 const value={transaction_id:tx.id,payment_id:paymentId,status:existing.length&&existing[0].member_id?'linked_existing':'awaiting_review',version:tx.version+1,requires_independent_review:!existing.length||!existing[0].member_id};
 return mutation(env,actor,'momo.assign',rid,source,value,writes,{...options,entityType:'payment',entityId:paymentId,auditDetails:{momo_transaction_id:tx.id,reason}});
}
export async function reviewMomoConflict(env,actor,txId,body,rid,source){
 keys(body,['expected_version','expected_conflicting_attempt_ids','decision','evidence_reference','reason']);
 if(body.decision!=='retain_original'||!Array.isArray(body.expected_conflicting_attempt_ids)||body.expected_conflicting_attempt_ids.length<1||body.expected_conflicting_attempt_ids.length>100)
  fail(400,'invalid_conflict_review','Review the exact bounded conflict set and retain the original immutable facts.');
 const expected=[...new Set(body.expected_conflicting_attempt_ids.map(value=>uuid(value,'parse attempt')))].sort();
 if(expected.length!==body.expected_conflicting_attempt_ids.length)fail(400,'invalid_conflict_review','Each conflicting attempt must be named once.');
 const version=integer(body.expected_version,'expected_version',1),evidence=text(body.evidence_reference,'supporting evidence',500);
 if(evidence.length<8)fail(400,'evidence_required','Record supporting evidence for the conflict decision.');
 const options={permission:'payments.write',minimumAssurance:2,freshSeconds:300},operation='momo.conflict.reviewed';
 const prior=await retainedResponse(env,actor,operation,rid,source,options);if(prior.found)return prior.value;
 const tx=await first(env,`SELECT t.* FROM momo_transactions t WHERE t.id=? AND ${MANAGED_MOMO_SOURCE_SQL}`,txId),conflicts=await rows(env,"SELECT DISTINCT parse_attempt_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' ORDER BY parse_attempt_id LIMIT 101",txId);
 if(!tx||tx.version!==version||!tx.has_conflict||tx.allocation_state!=='needs_review'||stableJson(conflicts.map(row=>row.parse_attempt_id))!==stableJson(expected)||
  await first(env,'SELECT 1 AS found FROM momo_financial_links WHERE transaction_id=?',txId))fail(409,'conflict_changed','Refresh the unlinked payment and its complete conflict set.');
 const slots=expected.map(()=>'?').join(','),guard=momoGuard(env,`EXISTS(SELECT 1 FROM momo_transactions t WHERE t.id=? AND t.version=? AND t.has_conflict=1 AND t.allocation_state='needs_review' AND ${MANAGED_MOMO_SOURCE_SQL})
  AND NOT EXISTS(SELECT 1 FROM momo_financial_links WHERE transaction_id=?)
  AND (SELECT count(DISTINCT parse_attempt_id) FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict')=?
  AND NOT EXISTS(SELECT 1 FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' AND parse_attempt_id NOT IN(${slots}))`,[txId,version,txId,txId,expected.length,txId,...expected]);
 const value={transaction_id:txId,version:version+1,status:'needs_allocation',financial_effects:0};
 return mutation(env,actor,operation,rid,source,value,[guard[0],
  env.DB.prepare("UPDATE momo_transactions SET has_conflict=0,allocation_state='unallocated',version=version+1,updated_at=? WHERE id=?").bind(now(),txId),
  env.DB.prepare(`UPDATE momo_processing_jobs SET state='completed',last_error=NULL,updated_at=? WHERE state='needs_review' AND last_error IS NOT NULL AND last_error NOT IN(${MOMO_UNCERTAIN_ERRORS.map(()=>'?').join(',')}) AND raw_sms_id IN
   (SELECT raw_sms_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' AND parse_attempt_id IN(${slots}))
   AND (SELECT id FROM momo_parse_attempts a WHERE a.raw_sms_id=momo_processing_jobs.raw_sms_id ORDER BY attempt_number DESC LIMIT 1) IN(${slots})`).bind(now(),...MOMO_UNCERTAIN_ERRORS,txId,...expected,...expected),guard[1]],
  {...options,entityType:'payment',entityId:txId,auditDetails:{decision:'retain_original',reason:body.reason,evidence_reference:evidence,dismissed_parse_attempt_ids:expected}});
}
