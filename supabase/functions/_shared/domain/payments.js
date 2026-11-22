import {ApiError,digest,first,id,now,requirePermission,rows,stableJson,text,uuid} from './core.js';
import {mutation,retainedResponse} from './mutations.js';
import {createContributionIntent,listMemberRecentIntents} from './member_contribution_intents.js';
import {listMemberCollectionBalances} from './member_collection_balances.js';
import {readMemberHistory} from './member_history.js';

export {boundCreationReceipt,contributionIntentJson,normalizeContributionSender} from './contribution_intent_dto.js';

export async function financialRpc(operation,body,env,actor,internal={}) {
 switch(operation) {
 case 'create_contribution_intent':return createContributionIntent(operation,body,env,actor);
 case 'list_current_member_recent_intents':return listMemberRecentIntents(body,env,actor);
 case 'list_current_member_collection_balances':return listMemberCollectionBalances(env,actor);
 case 'list_current_member_history_page':return {handled:true,value:await readMemberHistory(body,env,actor)};
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
  if(approved){
   // Recorded references form a collision scope, never provider authentication.
   // Evaluate inside the existing serialized PostgreSQL mutation batch, after
   // the advisory lock; an outside-batch preflight cannot prevent this race.
   const route=alias=>`(CASE WHEN substr(${alias},1,2)='07' AND length(${alias})=10 THEN '250'||substr(${alias},2) ELSE replace(${alias},'+','') END)`;
   writes.unshift(env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN EXISTS(
    SELECT 1 FROM payments current_payment JOIN payment_evidence current_evidence ON current_evidence.id=current_payment.evidence_id
    WHERE current_payment.id=? AND current_payment.revision=? AND current_payment.rail='rwanda_momo' AND current_payment.currency='RWF'
     AND current_evidence.currency='RWF' AND current_evidence.receiver_network IN('mtn_momo','airtel_money')
     AND current_evidence.external_reference IS NOT NULL AND length(trim(current_evidence.external_reference))>0
     AND current_evidence.receiver_momo_number IS NOT NULL AND length(trim(current_evidence.receiver_momo_number))>0
     AND NOT EXISTS(
      SELECT 1 FROM payments other_payment JOIN payment_evidence other_evidence ON other_evidence.id=other_payment.evidence_id
      JOIN ledger_entries original ON original.payment_id=other_payment.id AND original.kind='contribution'
      WHERE other_payment.id!=current_payment.id AND other_payment.rail=current_payment.rail AND other_payment.currency=current_payment.currency
       AND other_evidence.currency=current_evidence.currency AND other_evidence.receiver_network=current_evidence.receiver_network
       AND ${route('other_evidence.receiver_momo_number')}=${route('current_evidence.receiver_momo_number')}
       AND (other_evidence.external_reference=current_evidence.external_reference OR EXISTS(
        SELECT 1 FROM momo_transactions canonical JOIN momo_receiving_accounts receiving ON receiving.id=canonical.receiving_account_id
        WHERE canonical.event_kind='incoming_receipt' AND canonical.provider=current_evidence.receiver_network
         AND receiving.provider=canonical.provider AND canonical.currency=current_evidence.currency
         AND ${route('receiving.public_code')}=${route('current_evidence.receiver_momo_number')}
         AND current_evidence.external_reference IN(canonical.provider_transaction_id,receiving.id||':'||canonical.provider_transaction_id)
         AND other_evidence.external_reference IN(canonical.provider_transaction_id,receiving.id||':'||canonical.provider_transaction_id)))
       AND NOT EXISTS(SELECT 1 FROM ledger_entries inverse WHERE inverse.reverses_entry_id=original.id
        AND inverse.kind IN('reversal','correction') AND inverse.payment_id=original.payment_id AND inverse.collection_id=original.collection_id
        AND inverse.member_id IS NOT DISTINCT FROM original.member_id AND inverse.currency=original.currency AND inverse.amount_minor=-original.amount_minor
        AND inverse.evidence_id=original.evidence_id))) THEN 1 ELSE 0 END`).bind(checkId+':evidence-collision',p.id,p.revision));
   writes.push(env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(checkId+':evidence-collision'));
  }
  if(approved)writes.push(env.DB.prepare(`UPDATE payments SET member_id=?,status='reconciled',revision=revision+1 WHERE id=? AND revision=?`).bind(reconciliation.proposed_member_id,p.id,p.revision),env.DB.prepare(`INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)`).bind(id(),p.id,p.collection_id,reconciliation.proposed_member_id,p.amount_minor,p.evidence_id,actor.userId,requestId,now()));
  if(approved&&await first(env,"SELECT name FROM sqlite_master WHERE type='table' AND name='contribution_posting_snapshots'")){
   writes.unshift(env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN NOT EXISTS(
    SELECT 1 FROM momo_financial_links f JOIN momo_transactions t ON t.id=f.transaction_id
    WHERE f.payment_id=? AND (f.beneficiary_member_id!=? OR t.has_conflict=1 OR t.allocation_state!='linked')) THEN 1 ELSE 0 END`).bind(checkId+':momo',p.id,reconciliation.proposed_member_id));
   writes.push(env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(checkId+':momo'));
   // Snapshot and notification obligation share the existing financial batch.
   // SUM reads the committed-in-this-batch ledger, including other distinct
   // payments serialized by D1; the app never applies a balance increment.
   writes.push(env.DB.prepare(`INSERT INTO contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at)
    SELECT l.id,l.payment_id,(SELECT coalesce(sum(e.amount_minor),0) FROM ledger_entries e WHERE e.collection_id=l.collection_id AND e.member_id=l.member_id),
    (SELECT coalesce(sum(e.amount_minor),0) FROM ledger_entries e WHERE e.collection_id=l.collection_id),l.posted_at FROM ledger_entries l WHERE l.payment_id=? AND l.kind='contribution'`).bind(p.id),
    env.DB.prepare(`UPDATE payment_intents SET status='matched' WHERE id=(SELECT intent_id FROM payments WHERE id=?) AND member_id=?`).bind(p.id,reconciliation.proposed_member_id),
    env.DB.prepare(`INSERT INTO notification_events(id,user_id,event_type,title,body,data_json,status,created_at)
     SELECT ?,p.member_id,'contribution','Contribution credited',printf('RWF %d credited to %s.',p.amount_minor,g.title),
     json_object('payment_id',p.id,'collection_id',p.collection_id,'amount_rwf',p.amount_minor,'member_balance_after_contribution_rwf',s.member_balance_after_minor,
      'group_balance_after_contribution_rwf',s.group_balance_after_minor,'group_name',g.title,'posted_at',s.posted_at,'balance_basis','after_this_contribution'),'pending',?
     FROM payments p JOIN collections g ON g.id=p.collection_id JOIN contribution_posting_snapshots s ON s.payment_id=p.id
     WHERE p.id=? AND NOT EXISTS(SELECT 1 FROM momo_financial_links f JOIN momo_transactions t ON t.id=f.transaction_id WHERE f.payment_id=p.id AND t.mode='historical')
      AND coalesce((SELECT payment_updates FROM notification_preferences WHERE user_id=p.member_id),1)=1`).bind(id(),now(),p.id),
    env.DB.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
     VALUES(?,?,'payment.contribution.committed','payment',?,?,'{}',?)`).bind(actor.userId,actor.sessionId,p.id,requestId,now()));
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
