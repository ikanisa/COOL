/** Shared canonical posting statement builders extracted from Collect payments.js.
 * Upstream Git blob: 63f4ba68c2de7b4aa1cf3dc5523cf354aff5c643.
 * These functions only prepare statements; they DO NOT authorize or execute them.
 * The caller must retain its real transaction, mutation fence, current authority,
 * recipient guards, idempotency and rollback ownership. A prepared plan is not
 * evidence of a posted contribution. No fabricated reviewer is ever supplied.
 *
 * id/now are explicit to preserve legacy evaluation order and enable deterministic
 * equivalence testing. SQL, parameter ordering and original batch ordering are
 * preserved. This module is not an HTTP endpoint or standalone financial writer.
 */
export function appendContributionCollision(writes,{env,p,checkId}) {
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

export function appendContributionEntry(writes,{env,p,reconciliation,actor,requestId,id,now}) {
  writes.push(env.DB.prepare(`UPDATE payments SET member_id=?,status='reconciled',revision=revision+1 WHERE id=? AND revision=?`).bind(reconciliation.proposed_member_id,p.id,p.revision),env.DB.prepare(`INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)`).bind(id(),p.id,p.collection_id,reconciliation.proposed_member_id,p.amount_minor,p.evidence_id,actor.userId,requestId,now()));
}

export function appendContributionSnapshots(writes,{env,p,reconciliation,actor,requestId,checkId,id,now}) {
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
