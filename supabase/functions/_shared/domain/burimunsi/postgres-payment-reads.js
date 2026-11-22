import {pgInteger} from './postgres-values.js';
import {projectPayment} from './postgres-record-projections.js';

export const paymentReferenceSql="to_jsonb(p)->>'payment_reference'";
export const paymentsSql=(auto,includeReference=false)=>`SELECT t.id,x.collection_id,${includeReference?paymentReferenceSql+' AS display_reference,':''}
 ${auto?"coalesce(native.value->'facts'->>'counterparty_name',t.payer_name)":"t.payer_name"} AS payer_name,
 ${auto?"coalesce(native.value->'facts'->>'counterparty_identifier',t.payer_identifier)":"t.payer_identifier"} AS payer_identifier,
 ${auto?"coalesce((native.value->'facts'->>'amount_minor')::bigint,t.amount_minor)":"t.amount_minor"} AS amount_minor,
 ${auto?"coalesce(native.value->'facts'->>'transaction_at',t.transaction_at)":"t.transaction_at"} AS transaction_at,
 ${auto?"coalesce(native.value->'facts'->>'transaction_timezone',t.transaction_timezone)":"t.transaction_timezone"} AS transaction_timezone,
 ${auto?"coalesce(native.value->'facts'->>'transaction_datetime_raw',t.transaction_datetime_raw)":"t.transaction_datetime_raw"} AS transaction_datetime_raw,
 ${auto?"coalesce(native.value->'facts'->>'provider_transaction_id',t.provider_transaction_id)":"t.provider_transaction_id"} AS provider_transaction_id,
 t.allocation_state,t.has_conflict,t.version,t.created_at,t.event_kind AS canonical_event_kind,u.id AS member_id,u.full_name AS member_full_name,u.momo_number,p.status AS payment_status,credit.posted AS ledger_posted,
 EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AS source_conflict,
 (SELECT min(src.raw_sms_id) FROM app.momo_transaction_sources src WHERE src.transaction_id=t.id AND src.relation='accepted') AS source_id${auto?",x.native_source_id,coalesce(native.value->'facts'->>'event_kind',t.event_kind) AS event_kind,coalesce((native.value->'facts'->>'fee_minor')::bigint,t.fee_minor) AS fee_minor,coalesce((native.value->'facts'->>'wallet_balance_after_minor')::bigint,t.wallet_balance_after_minor) AS wallet_balance_after_minor,native.value AS native_meta":''}
 FROM private.burimunsi_transaction_scopes x
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
 LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
 LEFT JOIN app.memberships pm ON pm.collection_id=x.collection_id AND pm.user_id=coalesce(p.member_id,CASE WHEN p.id IS NOT NULL THEN f.beneficiary_member_id END)
 LEFT JOIN app.users u ON u.id=pm.user_id
 LEFT JOIN LATERAL (SELECT count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor
  AND p.amount_minor=t.amount_minor AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
  AND u.id=p.member_id),false) AS posted
  FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) credit ON true
 LEFT JOIN LATERAL (SELECT regexp_replace(coalesce(u.momo_number,''),'[ ()-]','','g') AS compact) phone_raw ON true
 LEFT JOIN LATERAL (SELECT CASE WHEN phone_raw.compact LIKE '00%' THEN '+'||substr(phone_raw.compact,3) ELSE phone_raw.compact END AS value) phone_input ON true
 LEFT JOIN LATERAL (SELECT CASE WHEN phone_input.value ~ '^0[0-9]{9}$' THEN '+250'||substr(phone_input.value,2)
   WHEN phone_input.value ~ '^[0-9]{9}$' THEN '+250'||phone_input.value
   WHEN phone_input.value ~ '^250[0-9]{9}$' THEN '+'||phone_input.value ELSE phone_input.value END AS normalized) member_phone ON true
 ${auto?'LEFT JOIN LATERAL (SELECT private.burimunsi_auto_projection(x.native_source_id) AS value WHERE x.native_source_id IS NOT NULL) native ON true':''}
 WHERE x.collection_id=$1`;
// Only an actual positive net ledger contribution in the same collection is a
// credit. A receipt, a payment status alone, or another group's ledger is not.
const CREDITED=`SELECT x.transaction_id,sum(l.amount_minor) AS credited_amount
 FROM private.burimunsi_transaction_scopes x
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 JOIN app.momo_financial_links f ON f.transaction_id=t.id
 JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
 JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=x.collection_id
 WHERE x.collection_id=$1 AND t.event_kind='incoming_receipt' AND t.has_conflict=0
  AND p.status IN ('reconciled','confirmed')
 GROUP BY x.transaction_id HAVING count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor
  AND p.amount_minor=t.amount_minor AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
  AND EXISTS(SELECT 1 FROM app.memberships m WHERE m.collection_id=x.collection_id AND m.user_id=p.member_id)),false)`;
const NO_CONFLICT=`t.has_conflict=0 AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict')`;
const IS_POSTED=`coalesce(p.status IN ('reconciled','confirmed'),false) AND credit.posted`;
const UNPOSTED_READABLE=`${NO_CONFLICT} AND p.status IS DISTINCT FROM 'reversed' AND p.status IS DISTINCT FROM 'corrected' AND NOT (${IS_POSTED})`;
const UNALLOCATED_INCOMING=`t.event_kind='incoming_receipt' AND t.allocation_state='unallocated' AND ${UNPOSTED_READABLE}`;
const managedOnly=auto=>auto?' AND x.native_source_id IS NULL':'';

export function paymentAllocationFilterSql(auto,filter) {
  switch(filter){
    case 'unallocated': return managedOnly(auto)+' AND '+UNALLOCATED_INCOMING;
    case 'allocated': return ` AND ${NO_CONFLICT} AND p.status IN ('reconciled','confirmed') AND credit.posted`;
    case 'processing': return managedOnly(auto)+` AND t.allocation_state<>'unallocated' AND ${UNPOSTED_READABLE}`;
    default: return '';
  }
}

export async function readCanonicalHome(sql,g,at,auto) {
  const totals=(await sql.unsafe('SELECT coalesce(sum(amount_minor),0) AS balance FROM app.ledger_entries WHERE collection_id=$1',[g]))[0];
  // A missing, malformed or timezone-less receipt timestamp never
  // becomes today's receipt by substituting posting or capture time.
  const today=(await sql.unsafe(`SELECT coalesce(sum(c.credited_amount),0) AS today FROM (${CREDITED}) c
            JOIN app.momo_transactions t ON t.id=c.transaction_id
            WHERE CASE WHEN t.transaction_at ~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
             AND pg_input_is_valid(t.transaction_at,'timestamp with time zone')
             AND EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name=t.transaction_timezone)
            THEN t.transaction_at::timestamptz >= (date_trunc('day',$2::timestamptz AT TIME ZONE t.transaction_timezone) AT TIME ZONE t.transaction_timezone)
             AND t.transaction_at::timestamptz < ((date_trunc('day',$2::timestamptz AT TIME ZONE t.transaction_timezone)+interval '1 day') AT TIME ZONE t.transaction_timezone)
             AND t.transaction_at::timestamptz <= $2::timestamptz ELSE false END`,[g,at]))[0];
  const [counts]=await sql.unsafe(`SELECT
    (SELECT count(*) FROM app.memberships WHERE collection_id=$1 AND active=1) AS members,
    count(*) AS unallocated,coalesce(sum(t.amount_minor),0) AS unallocated_amount
    FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id
    LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
    LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
    LEFT JOIN LATERAL (SELECT count(*)=1 AND coalesce(bool_and(l.kind='contribution' AND l.amount_minor=t.amount_minor AND p.amount_minor=t.amount_minor
     AND l.evidence_id=p.evidence_id AND l.member_id=p.member_id AND p.member_id=f.beneficiary_member_id
     AND EXISTS(SELECT 1 FROM app.memberships m WHERE m.collection_id=x.collection_id AND m.user_id=p.member_id)),false) AS posted
     FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.collection_id=x.collection_id) credit ON true
    WHERE x.collection_id=$1${managedOnly(auto)} AND ${UNALLOCATED_INCOMING}`,[g]);
  // Only project ledger-verified credits; keep the lateral lookup
  // correlated before the role-checked native source projection.
  const recent=await sql.unsafe(`WITH credited AS MATERIALIZED (${CREDITED})
            SELECT q.*,c.credited_amount FROM credited c
            JOIN LATERAL (${paymentsSql(auto)} AND t.id=c.transaction_id OFFSET 0) q ON true
            WHERE CASE WHEN q.transaction_at ~ '(Z|[+-][0-9]{2}:[0-9]{2})$' AND pg_input_is_valid(q.transaction_at,'timestamp with time zone')
              AND EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name=q.transaction_timezone)
              THEN q.transaction_at::timestamptz <= $2::timestamptz ELSE false END
            ORDER BY q.transaction_at::timestamptz DESC,q.id DESC LIMIT 3`,[g,at]);
  return {
    groupBalanceRwf:pgInteger(totals.balance),
    todayRwf:pgInteger(today.today),
    memberCount:pgInteger(counts.members),
    unallocatedCount:pgInteger(counts.unallocated),
    unallocatedAmountRwf:pgInteger(counts.unallocated_amount),
    recentPayments:recent.map(row=>projectPayment({...row,amount_minor:row.credited_amount})),
    asOf:at,
  };
}
