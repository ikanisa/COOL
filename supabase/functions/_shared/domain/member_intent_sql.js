// The bounded intent window, its confirmation evidence and the full pending
// count belong to one verified member session and one database snapshot.
export function memberIntentSnapshot(db, actor, selected, expiresAfter) {
  return db.withLockedReadSnapshot(tx => tx.unsafe(`
    WITH current_actor AS MATERIALIZED (
      SELECT private.assert_actor() AS principal, api.current_session_id() AS session_id
    ), scope AS MATERIALIZED (
      SELECT principal FROM current_actor WHERE principal=$1 AND session_id=$2
    ), recent AS MATERIALIZED (
      SELECT i.*, CASE WHEN octet_length(r.response_json)<=8192 THEN r.response_json END AS creation_response_json
      FROM scope a JOIN app.payment_intents i ON i.member_id=a.principal
      LEFT JOIN app.request_receipts r ON r.user_id=i.member_id AND r.request_id=i.request_id
        AND r.operation='create_contribution_intent' AND r.session_id=i.originating_session_id
        AND r.body_sha256=i.request_sha256
      WHERE ($3::text IS NULL OR i.id=$3)
      ORDER BY i.created_at DESC,i.id LIMIT 50
    ), pending AS (
      SELECT count(*) AS pending_count FROM scope a JOIN app.payment_intents i ON i.member_id=a.principal
      WHERE i.status='pending' AND i.expires_at>$4
    )
    SELECT i.*, pending.pending_count,
      p.id AS payment_id, p.status AS payment_status, p.member_id AS payment_member_id,
      l.id AS contribution_entry_id, l.posted_at, CASE WHEN l.id IS NOT NULL THEN p.amount_minor END AS credited_amount_rwf,
      t.provider_transaction_id AS provider_transaction_reference, t.transaction_at AS provider_transaction_at,
      s.member_balance_after_minor AS balance_after_contribution_rwf,
      s.group_balance_after_minor AS group_balance_after_contribution_rwf
    FROM scope a CROSS JOIN pending LEFT JOIN recent i ON true
    LEFT JOIN LATERAL (
      SELECT p.*, f.transaction_id FROM app.payments p
      LEFT JOIN app.momo_financial_links f ON f.payment_id=p.id
      WHERE p.intent_id=i.id AND (p.member_id=a.principal OR f.beneficiary_member_id=a.principal)
    ) p ON true
    LEFT JOIN app.ledger_entries l ON l.payment_id=p.id AND l.kind='contribution'
    LEFT JOIN app.contribution_posting_snapshots s ON s.ledger_entry_id=l.id
    LEFT JOIN app.momo_transactions t ON t.id=p.transaction_id
    ORDER BY i.created_at DESC,i.id`, [actor.userId, actor.sessionId, selected, expiresAfter]));
}
