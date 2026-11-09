import {requireThat} from './errors.js';
import {requireId,requireRequestId} from './values.js';

export const COMMAND_OPERATIONS=Object.freeze(['burimunsi.allocate','burimunsi.enroll','burimunsi.membership',
  'burimunsi.staff.create','burimunsi.staff.edit','burimunsi.staff.reset','burimunsi.staff.disable',
  'burimunsi.staff.enable','burimunsi.staff.remove']);

/** Historical command success is not the current economic state. This SELECT
 * uses the SAME primary, authenticated snapshot as the caller. It reads no
 * historical balance, PIN, bearer or raw SMS into the public status response.
 * Old sessions may be revoked/expired, but their immutable principal snapshot
 * must still match the freshly authenticated principal. No session is rebound.
 */
export const COMMAND_OUTCOME_SQL=`SELECT r.collection_id,r.actor_id,r.request_id,r.operation,
 CASE WHEN r.operation <> 'burimunsi.allocate' THEN
   CASE WHEN jsonb_typeof(r.response)='object' THEN 'not_applicable' ELSE 'inconsistent' END
 WHEN jsonb_typeof(r.response)='object'
   AND t.event_kind='incoming_receipt' AND t.has_conflict=0 AND t.allocation_state='linked'
   AND t.currency='RWF' AND p.currency='RWF' AND l.currency='RWF' AND p.rail='rwanda_momo'
   AND t.amount_minor>0 AND p.amount_minor=t.amount_minor AND l.amount_minor=t.amount_minor
   AND r.response->'amountRwf'=to_jsonb(t.amount_minor)
   AND r.response->>'currency'='RWF' AND r.response->>'memberId'=l.member_id
   AND l.kind='contribution' AND l.evidence_id=p.evidence_id
   AND f.beneficiary_member_id=l.member_id
 THEN CASE
   WHEN p.status IN ('reconciled','confirmed') AND inv.n=0 AND p.member_id=l.member_id THEN 'posted'
   WHEN p.status='reversed' AND inv.n=1 AND inv.valid AND inv.kind='reversal' THEN 'reversed'
   WHEN p.status='corrected' AND inv.n=1 AND inv.valid AND inv.kind='correction' THEN 'corrected'
   ELSE 'inconsistent' END
 ELSE 'inconsistent' END AS financial_state
 FROM private.burimunsi_command_receipts r
 JOIN private.burimunsi_sessions origin ON origin.id=r.session_id
   AND origin.account_id=r.actor_id AND origin.collection_id=r.collection_id
   AND origin.principal_user_id=$4
 JOIN private.burimunsi_scopes scope ON scope.collection_id=r.collection_id
 LEFT JOIN private.burimunsi_transaction_scopes x ON r.operation='burimunsi.allocate'
   AND x.transaction_id=r.response->>'transactionId' AND x.collection_id=r.collection_id
   AND x.receiving_account_id=scope.receiving_account_id
 LEFT JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
 LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=r.collection_id
 LEFT JOIN app.ledger_entries l ON l.id=r.response->>'ledgerEntryId' AND l.payment_id=p.id AND l.collection_id=r.collection_id
 LEFT JOIN LATERAL (
   SELECT count(*) AS n,min(c.kind) AS kind,
     bool_and(c.kind IN ('reversal','correction') AND c.payment_id=l.payment_id
       AND c.collection_id=l.collection_id AND c.member_id IS NOT DISTINCT FROM l.member_id
       AND c.currency=l.currency AND c.evidence_id=l.evidence_id AND c.amount_minor=-l.amount_minor) AS valid
   FROM app.ledger_entries c WHERE c.reverses_entry_id=l.id
 ) inv ON true
 WHERE r.collection_id=$1 AND r.actor_id=$2::uuid AND r.request_id=$3::uuid
 LIMIT 2`;

export async function readCommandOutcome(sql,{groupId,actorId,requestId,principalUserId}) {
  requireId(groupId);requireRequestId(actorId);requireRequestId(requestId);requireId(principalUserId);
  const rows=await sql.unsafe(COMMAND_OUTCOME_SQL,[groupId,actorId,requestId,principalUserId]);
  requireThat(rows.length<=1,'command_outcome_inconsistent',503);
  if(!rows.length)return null; // Absence is UNKNOWN, never proof of rejection.
  const r=rows[0];
  requireThat(r.collection_id===groupId&&r.actor_id===actorId&&r.request_id===requestId&&
    COMMAND_OPERATIONS.includes(r.operation)&&
    ['posted','reversed','corrected','not_applicable'].includes(r.financial_state)&&
    (r.operation==='burimunsi.allocate')===(r.financial_state!=='not_applicable'),
    'command_outcome_inconsistent',503);
  return {groupId,actorId,requestId,operation:r.operation,state:'committed',financialState:r.financial_state};
}
