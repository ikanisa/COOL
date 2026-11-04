// Sensitivity follows server-established, retained provenance rather than a
// caller label, MIME type or the evidence's operator/provider authenticity.
// Existing MoMo assignments have immutable financial links. The body digest
// also protects copies of a retained SMS made through manual evidence entry.
// Manual payment.record evidence is untyped text: its immutable receipt proves
// who recorded it, not that the content is non-SMS. Even transformed/pasted SMS
// must not obtain ordinary access through that producer. No current producer
// establishes a non-SMS source, so all remaining legacy/manual rows are guarded.
export const evidenceSensitivitySql=`CASE
 WHEN EXISTS(SELECT 1 FROM payments ep JOIN momo_financial_links mf ON mf.payment_id=ep.id WHERE ep.evidence_id=e.id)
  OR EXISTS(SELECT 1 FROM sms_receipts sr WHERE sr.body_sha256=e.object_sha256)
 THEN 'raw_sms' ELSE 'unclassified' END`;

export function evidenceSensitivity(value){
 // 'ordinary' is reserved for a separately qualified, typed non-SMS producer;
 // the current source query intentionally never emits it.
 return ['raw_sms','ordinary','unclassified'].includes(value)?value:'unclassified';
}
