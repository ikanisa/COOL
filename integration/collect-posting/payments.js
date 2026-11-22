import {appendContributionCollision,appendContributionEntry,appendContributionSnapshots} from './contribution-posting.mjs';
import {ApiError,first,rows,id,uuid,text,integer,now,digest,stableJson,requirePermission} from './core.js';
import {groupFor} from './groups.js';
import {mutation,retainedResponse} from './mutations.js';
import {encrypt} from './encryption.js';
import {memberHistoryPage} from './member_history.js';
function intentJson(row) {return {id:row.id,collection_id:row.collection_id,amount_minor:row.amount_minor,currency:row.currency,rail:row.rail,status:row.status,receiver_momo_number:row.receiver_momo_number,network:row.receiver_network??row.network,receiver_label:row.receiver_label??'',receiver_momo_number_hash:row.receiver_momo_number_hash??'',sender_phone_hash:row.sender_phone_hash??'',originating_session_id:row.originating_session_id,created_at:row.created_at,expires_at:row.expires_at};}
// Reuse the immutable creation projection when reviewing a retained receipt.
export {intentJson as contributionIntentJson};
// Match the client PhoneNormalizer exactly; only valid Rwanda mobile numbers
// can bind a protected contribution request. Never return the number in errors.
export function normalizeContributionSender(value) {
 if(typeof value!=='string')return null;
 let digits=value.trim().replace(/[^0-9+]/g,'');
 if(digits.startsWith('+'))digits=digits.slice(1);
 if(digits.startsWith('00'))digits=digits.slice(2);
 let normalized='';
 if(digits.startsWith('250')&&digits.length===12)normalized='+'+digits;
 else if(digits.startsWith('0')&&digits.length===10)normalized='+250'+digits.slice(1);
 else if(digits.length===9)normalized='+250'+digits;
 return /^\+2507[2389][0-9]{7}$/.test(normalized)?normalized:null;
}
export function boundCreationReceipt(row,senderHash) {
 if(typeof row?.creation_response_json!=='string'||row.creation_response_json.length>8192||new TextEncoder().encode(row.creation_response_json).length>8192||typeof senderHash!=='string'||!/^([a-f0-9]{64})$/.test(senderHash))return false;
 try {
  const saved=JSON.parse(row.creation_response_json);
  return JSON.stringify(saved)===row.creation_response_json&&stableJson(saved)===stableJson(intentJson({...row,status:'pending',sender_phone_hash:senderHash}));
 }catch{return false;}
}
function restoreOriginalSender(row,sessionId) {
 // Only the immutable, exact create receipt can supply this binding. A later
 // profile value or an unverified database projection is not original evidence.
 const raw=row.creation_response_json;
 if(row.originating_session_id===sessionId&&typeof raw==='string'&&raw.length<=8192&&new TextEncoder().encode(raw).length<=8192){
  try{
   const hash=JSON.parse(raw)?.sender_phone_hash;
   if(boundCreationReceipt(row,hash))return {...row,sender_phone_hash:hash};
  }catch{/* An unavailable receipt leaves this historical intent non-actionable. */}
 }
 return {...row,sender_phone_hash:''};
}
async function intentConfirmation(env,intent,actor){
 const linked=await first(env,`SELECT p.id,p.status,p.member_id,p.amount_minor,l.id AS entry_id,l.posted_at
 FROM payments p LEFT JOIN ledger_entries l ON l.payment_id=p.id AND l.kind='contribution'
 WHERE p.intent_id=? AND (p.member_id=? OR EXISTS(SELECT 1 FROM momo_financial_links f WHERE f.payment_id=p.id AND f.beneficiary_member_id=?))`,intent.id,actor.userId,actor.userId);
 if(!linked)return {...intentJson(intent),confirmation_status:'awaiting_confirmation'};
 const snapshot=linked.entry_id?await first(env,'SELECT * FROM contribution_posting_snapshots WHERE ledger_entry_id=?',linked.entry_id):null;
 const reference=await first(env,`SELECT t.provider_transaction_id,t.transaction_at FROM momo_financial_links f JOIN momo_transactions t ON t.id=f.transaction_id WHERE f.payment_id=?`,linked.id);
 return {...intentJson(intent),confirmation_status:linked.status==='reversed'?'reversed':linked.entry_id&&linked.member_id===actor.userId?'credited':'payment_received',
 payment_id:linked.id,contribution_entry_id:linked.entry_id??null,credited_amount_rwf:linked.entry_id?linked.amount_minor:null,posted_at:linked.posted_at??null,
 provider_transaction_reference:reference?.provider_transaction_id??null,provider_transaction_at:reference?.transaction_at??null,
 balance_after_contribution_rwf:snapshot?.member_balance_after_minor??null,group_balance_after_contribution_rwf:snapshot?.group_balance_after_minor??null};
}
export async function financialRpc(operation,body,env,actor,internal={}) {
 switch(operation) {
 case 'create_contribution_intent': {
  const requestId=uuid(body.p_request_id??id(),'request_id');
  const g=await groupFor(env,actor,body.collection??body.p_collection_id);
  const amount=integer(body.p_expected_amount_rwf??body.amount_minor,'amount',1);
  if(!g.receiver_momo_number||!['mtn_momo','airtel_money'].includes(g.receiver_network))throw new ApiError(409,'route_unavailable','The group payment route is unavailable.');
  const member=await first(env,'SELECT momo_number,country_code FROM users WHERE id=?',actor.userId);
  const sender=normalizeContributionSender(member?.momo_number);
  if(!sender||member?.country_code!=='RW')throw new ApiError(403,'profile_incomplete','Complete your MoMo profile first.');
  const senderHash=await digest(sender);
  if(typeof body.p_sender_phone_hash!=='string'||!/^([a-f0-9]{64})$/.test(body.p_sender_phone_hash)||body.p_sender_phone_hash!==senderHash)throw new ApiError(409,'contribution_sender_changed','Refresh your payment details before continuing.');
  const previous=await retainedResponse(env,actor,operation,requestId,body,{collectionId:g.id});
  if(previous.found){if(previous.value?.sender_phone_hash!==senderHash)throw new ApiError(409,'contribution_sender_changed','Refresh your payment details before continuing.');return {handled:true,value:previous.value};}
  const pending=await first(env,`SELECT p.*,r.response_json AS creation_response_json FROM payment_intents p LEFT JOIN request_receipts r ON r.user_id=p.member_id AND r.request_id=p.request_id AND r.operation='create_contribution_intent' AND r.session_id=p.originating_session_id AND r.body_sha256=p.request_sha256 WHERE p.member_id=? AND p.collection_id=? AND p.amount_minor=? AND p.originating_session_id=? AND p.status='pending' AND p.expires_at>? ORDER BY p.created_at DESC LIMIT 1`,actor.userId,g.id,amount,actor.sessionId,now());
  if(pending){if(!boundCreationReceipt(pending,senderHash))throw new ApiError(409,'contribution_sender_changed','Refresh your payment details before continuing.');return {handled:true,value:await mutation(env,actor,operation,requestId,body,intentJson({...pending,sender_phone_hash:senderHash}),[],{collectionId:g.id,expectedCollectionRevision:g.revision})};}
  const paymentId=id();const created=now();const expires=new Date(Date.now()+900000).toISOString();
  const value=intentJson({id:paymentId,collection_id:g.id,amount_minor:amount,currency:'RWF',rail:'rwanda_momo',status:'pending',receiver_momo_number:g.receiver_momo_number,network:g.receiver_network,receiver_label:g.receiver_display_label,sender_phone_hash:senderHash,created_at:created,expires_at:expires,originating_session_id:actor.sessionId});
  const stmt=env.DB.prepare(`INSERT INTO payment_intents(id,collection_id,member_id,amount_minor,receiver_momo_number,receiver_network,receiver_label,originating_session_id,created_at,expires_at,request_id,request_sha256) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`).bind(paymentId,g.id,actor.userId,amount,g.receiver_momo_number,g.receiver_network,g.receiver_display_label??'',actor.sessionId,created,expires,requestId,await digest(stableJson(body)));
  return {handled:true,value:await mutation(env,actor,operation,requestId,body,value,[stmt],{collectionId:g.id,expectedCollectionRevision:g.revision})};
 }
 case 'list_current_member_recent_intents': {
  const selected=body.p_intent_id==null?null:uuid(body.p_intent_id,'intent_id');
  const list=await rows(env,`SELECT p.*,CASE WHEN length(r.response_json)<=8192 THEN r.response_json ELSE NULL END AS creation_response_json FROM payment_intents p
   LEFT JOIN request_receipts r ON r.user_id=p.member_id AND r.request_id=p.request_id AND r.operation='create_contribution_intent'
    AND r.session_id=p.originating_session_id AND r.body_sha256=p.request_sha256
   WHERE p.member_id=? AND (? IS NULL OR p.id=?) ORDER BY p.created_at DESC,p.id LIMIT 50`,actor.userId,selected,selected);
  const count=await first(env,`SELECT count(*) AS n FROM payment_intents WHERE member_id=? AND status='pending' AND expires_at>?`,actor.userId,now());
  const pipeline=await first(env,"SELECT name FROM sqlite_master WHERE type='table' AND name='momo_financial_links'");
  const original=list.map(row=>restoreOriginalSender(row,actor.sessionId));
  return {handled:true,value:{items:pipeline?await Promise.all(original.map(row=>intentConfirmation(env,row,actor))):original.map(intentJson),pending_count:count.n}};
 }
 case 'list_current_member_collection_balances': {
  // Authority, all group totals and supporter counts share one MVCC snapshot.
  // SQL NUMERIC aggregates travel as decimal strings until exact-range checks.
  const list=await rows(env,`WITH authority AS MATERIALIZED(SELECT private.assert_actor() AS principal),
   groups AS MATERIALIZED(SELECT m.collection_id FROM app.memberships m CROSS JOIN authority a
    WHERE m.user_id=a.principal AND a.principal=? AND api.current_session_id()=? AND m.active=1),
   members AS(SELECT l.collection_id,l.member_id,sum(l.amount_minor) AS balance
    FROM app.ledger_entries l JOIN groups g ON g.collection_id=l.collection_id GROUP BY l.collection_id,l.member_id)
   SELECT g.collection_id,coalesce(sum(m.balance),0)::text AS total,
    coalesce(sum(m.balance) FILTER(WHERE m.member_id=?),0)::text AS own,
    count(m.collection_id) FILTER(WHERE m.balance>0)::text AS supporters
   FROM groups g LEFT JOIN members m ON m.collection_id=g.collection_id GROUP BY g.collection_id ORDER BY g.collection_id`,actor.userId,actor.sessionId,actor.userId);
  const exact=value=>{if(typeof value!=='string'||!/^\d+$/.test(value)||BigInt(value)>9007199254740991n)throw new ApiError(503,'balance_unavailable','Balances are unavailable.');return Number(value);};
  return {handled:true,value:list.map(row=>({collection_id:row.collection_id,currency:'RWF',
   balances:[{currency:'RWF',amount_raised_minor:exact(row.total),current_user_balance_minor:exact(row.own)}],supporter_count:exact(row.supporters)}))};
 }
 case 'list_current_member_history_page': {
  if(body.p_contract_version===2)return {handled:true,value:await memberHistoryPage(body,env,actor)};
  if(body.p_contract_version!==undefined&&body.p_contract_version!==1)throw new ApiError(400,'invalid_history_query','Use the supported history contract.');
  const selected=body.p_collection_id==null?null:uuid(body.p_collection_id,'collection_id');const search=typeof body.p_query==='string'?body.p_query.trim():'';
  if(search.length>80)throw new ApiError(400,'invalid_query','Invalid history search.');
  const order={newest:'l.posted_at DESC,p.id ASC',oldest:'l.posted_at ASC,p.id ASC',highest:'p.amount_minor DESC,l.posted_at DESC,p.id ASC',lowest:'p.amount_minor ASC,l.posted_at DESC,p.id ASC'}[body.p_sort??'newest'];if(!order)throw new ApiError(400,'invalid_sort','Invalid history sort.');
  const limit=integer(body.p_limit??50,'limit',1,50);
  const list=await rows(env,`SELECT p.id AS payment_id,p.collection_id,p.amount_minor,p.currency,p.rail,l.posted_at,p.payer_display_name AS supporter_label,CASE WHEN p.member_id=? THEN 1 ELSE 0 END AS own,p.revision FROM payments p JOIN ledger_entries l ON l.payment_id=p.id AND l.kind='contribution' JOIN memberships m ON m.collection_id=p.collection_id WHERE m.user_id=? AND m.active=1 AND p.status IN ('recorded','reconciled','confirmed') AND (? IS NULL OR p.collection_id=?) AND (?='' OR p.payer_display_name LIKE ? OR p.id=?) ORDER BY ${order} LIMIT 10001`,actor.userId,actor.userId,selected,selected,search,'%'+search+'%',search);
  if(list.length>10000)throw new ApiError(400,'history_filter_required','Choose a group or narrow the history search.');
  const revision=(await digest(stableJson(list.map(r=>[r.payment_id,r.revision,r.amount_minor])))).slice(0,32);
  let start=0;const cursor=body.p_cursor;
  if(cursor){if(cursor.revision!==revision || typeof cursor.after!=='string')throw new ApiError(409,'history_changed','History changed. Refresh before continuing.');start=list.findIndex(r=>r.payment_id===cursor.after)+1;if(start===0)throw new ApiError(409,'history_changed','History changed. Refresh before continuing.');}
  const total=list.reduce((s,r)=>s+r.amount_minor,0),own=list.reduce((s,r)=>s+(r.own?r.amount_minor:0),0);if(!Number.isSafeInteger(total)||!Number.isSafeInteger(own))throw new ApiError(503,'history_unavailable','History is unavailable.');
  const window=list.slice(start,start+limit);return {handled:true,value:{items:window.map(({own,revision,...r})=>({...r,is_current_user_contribution:own===1})),total_count:list.length,totals:{RWF:total},own_totals:{RWF:own},own_collection_ids:[...new Set(list.filter(r=>r.own).map(r=>r.collection_id))],revision,next_cursor:start+window.length<list.length?{revision,after:window.at(-1).payment_id}:null}};
 }
 case 'propose_payment_reconciliation_v2': {
  const permission=internal.permission??'payments.reconcile';
  if(!['payments.reconcile','reconciliations.propose'].includes(permission))throw new ApiError(403,'42501','This action is unavailable.');
  requirePermission(actor,permission);const paymentId=uuid(body.p_payment_id??body.payment_id,'payment_id');
  const reason=text(internal.reason??body.p_reason??body.reason,'reason',500);
  if(reason.length<8)throw new ApiError(400,'reason_required','Record a reason of at least eight characters.');
  const requestId=uuid(body.p_request_id,'request_id');
  const previous=await retainedResponse(env,actor,operation,requestId,body,{permission,minimumAssurance:2,freshSeconds:internal.freshSeconds});
  if(previous.found)return {handled:true,value:previous.value};
  const payment=await first(env,'SELECT * FROM payments WHERE id=?',paymentId);if(!payment)throw new ApiError(404,'payment_unavailable','Payment is unavailable.');
  if(!['recorded','ambiguous'].includes(payment.status)||payment.member_id!==null)throw new ApiError(409,'stale_state','This payment is no longer available for attribution.');
  const memberId=uuid(body.p_member_id??body.p_proposed_member_id,'member_id');
  const momoEnabled=await first(env,"SELECT name FROM sqlite_master WHERE type='table' AND name='momo_financial_links'");
  if(momoEnabled&&await first(env,`SELECT f.transaction_id FROM momo_financial_links f JOIN momo_transactions t ON t.id=f.transaction_id WHERE f.payment_id=? AND (f.beneficiary_member_id!=? OR t.has_conflict=1 OR t.allocation_state!='linked')`,paymentId,memberId))throw new ApiError(409,'momo_destination_changed','Review the retained MoMo destination and source conflict before attribution.');
  if(!await first(env,'SELECT id FROM memberships WHERE collection_id=? AND user_id=? AND active=1',payment.collection_id,memberId))throw new ApiError(400,'invalid_member','Choose a member of this group.');
  const reconciliationId=id(),checkId=id();
  const value={id:reconciliationId,payment_id:paymentId,status:'proposed',proposed_member_id:memberId,expected_payment_revision:payment.revision};
  return {handled:true,value:await mutation(env,actor,operation,requestId,body,value,[
   env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(SELECT 1 FROM payments p WHERE p.id=? AND p.status IN ('recorded','ambiguous') AND p.member_id IS NULL AND NOT EXISTS(SELECT 1 FROM ledger_entries l WHERE l.payment_id=p.id)) THEN 1 ELSE 0 END)`).bind(checkId,paymentId),
   env.DB.prepare(`INSERT INTO reconciliations(id,payment_id,proposed_member_id,proposed_by,proposed_session_id,expected_payment_revision,status,evidence_id,request_id,request_sha256,created_at) VALUES(?,?,?,?,?,?,'proposed',?,?,?,?)`).bind(reconciliationId,paymentId,memberId,actor.userId,actor.sessionId,payment.revision,payment.evidence_id,requestId,await digest(stableJson(body)),now()),
   env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(checkId)
  ],{permission,minimumAssurance:2,freshSeconds:internal.freshSeconds,paymentId,expectedPaymentRevision:payment.revision,recipientUserId:memberId,recipientCollectionId:payment.collection_id,entityType:'reconciliation',entityId:reconciliationId,auditDetails:{reason}})};
 }
 case 'approve_payment_reconciliation_v2':case 'reject_payment_reconciliation_v2': {
  const permission=internal.permission??'payments.reconcile',approved=operation==='approve_payment_reconciliation_v2';
  if(!['payments.reconcile','reconciliations.review'].includes(permission))throw new ApiError(403,'42501','This action is unavailable.');
  requirePermission(actor,permission);const requestId=uuid(body.p_request_id,'request_id');
  const reason=text(internal.reason??body.p_reason??body.reason,'reason',500);
  if(reason.length<8)throw new ApiError(400,'reason_required','Record a reason of at least eight characters.');
  const options={permission,minimumAssurance:2,freshSeconds:internal.freshSeconds,auditDetails:{reason}};
  const previous=await retainedResponse(env,actor,operation,requestId,body,options);if(previous.found)return {handled:true,value:previous.value};
  const reconciliation=await first(env,'SELECT * FROM reconciliations WHERE id=?',uuid(body.p_reconciliation_id,'reconciliation_id'));
  if(!reconciliation||reconciliation.status!=='proposed'){
   const committed=await retainedResponse(env,actor,operation,requestId,body,options);if(committed.found)return {handled:true,value:committed.value};
   throw new ApiError(409,'stale_state','This proposal is unavailable.');
  }
  if(reconciliation.proposed_by===actor.userId)throw new ApiError(403,'dual_review_required','Another reviewer must approve this proposal.');
  const p=await first(env,'SELECT * FROM payments WHERE id=?',reconciliation.payment_id);
  if(approved&&(p.revision!==reconciliation.expected_payment_revision||!['recorded','ambiguous'].includes(p.status)||p.member_id!==null)){
   const committed=await retainedResponse(env,actor,operation,requestId,body,options);if(committed.found)return {handled:true,value:committed.value};
   throw new ApiError(409,'stale_state','The payment changed.');
  }
  if(approved){
   const evidence=await first(env,'SELECT external_reference,receiver_network,receiver_momo_number,currency FROM payment_evidence WHERE id=?',p.evidence_id);
   if(!evidence||typeof evidence.external_reference!=='string'||!evidence.external_reference.trim()||
    !['mtn_momo','airtel_money'].includes(evidence.receiver_network)||!evidence.receiver_momo_number||evidence.currency!=='RWF'||p.currency!=='RWF'||p.rail!=='rwanda_momo')
    throw new ApiError(409,'independent_evidence_identity_required','Approval needs an independently reviewed event-specific evidence reference and receiving account. Recording and rejection remain available.');
  }
  const checkId=id(),status=approved?'approved':'rejected',reviewedAt=now();
  const writes=[env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(SELECT 1 FROM reconciliations r WHERE r.id=? AND r.status='proposed' AND r.proposed_by!=?) THEN 1 ELSE 0 END)`).bind(checkId,reconciliation.id,actor.userId),
   env.DB.prepare(`UPDATE reconciliations SET status=?,approved_by=?,approved_at=? WHERE id=? AND status='proposed'`).bind(status,actor.userId,reviewedAt,reconciliation.id)];
  if(approved)appendContributionCollision(writes,{env,p,checkId});
  if(approved)appendContributionEntry(writes,{env,p,reconciliation,actor,requestId,id,now});
  if(approved&&await first(env,"SELECT name FROM sqlite_master WHERE type='table' AND name='contribution_posting_snapshots'")){
   appendContributionSnapshots(writes,{env,p,reconciliation,actor,requestId,checkId,id,now});
  }
  writes.push(env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(checkId));
  return {handled:true,value:await mutation(env,actor,operation,requestId,body,{...reconciliation,status,approved_by:actor.userId,approved_at:reviewedAt,payment_revision:p.revision+(approved?1:0)},writes,
   {...options,paymentId:p.id,expectedPaymentRevision:p.revision,entityType:'reconciliation',entityId:reconciliation.id,...(approved?{recipientUserId:reconciliation.proposed_member_id,recipientCollectionId:p.collection_id}:{})})};
 }
 case 'get_payment_reconciliation_v2':case 'list_payment_reconciliations_v2': {
  requirePermission(actor,'payments.read');return {handled:true,value:operation.startsWith('get_')?await first(env,'SELECT * FROM reconciliations WHERE id=?',uuid(body.p_reconciliation_id,'reconciliation_id')):await rows(env,'SELECT * FROM reconciliations ORDER BY created_at DESC LIMIT 100')};
 }
 default:return {handled:false};
 }
}
