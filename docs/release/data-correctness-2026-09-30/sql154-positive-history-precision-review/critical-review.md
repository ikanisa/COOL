# Positive history SQL and precision review

## Evidence

`sql154-positive-history-attempt2` completed 39 passing cases and 4 failed assertions. Result SHA-256: `36b17dfef5357a778e2a8bbd9b65aff18e3b3afaac775cd4d771e955530691d0`.

All 69 synthetic REVIEW inputs were posted through the actual authenticated maker/checker proposal/approval and service finalization APIs. Production confirmation, balanced journal, ledger, notification and balance triggers remained active. The fixture supplied source-defined notification catalog seed rows because a schema-only clone contains no migration seed data; attempt1's missing-template failure is retained.

Four complete sorts, repeated date/amount ties, paging beyond 50, own/peer/anonymous labels, hidden private references, title/search scoping, exact matched counts, full sums, stale/forged continuation denials and exact maximum controls passed. Eight wrapper EXPLAIN measurements retain actual server execution time for 69 synthetic postings. They do not expose nested function plans or certify production scale.

The clone was removed. All 153 shared tables, the strengthened catalog fingerprint and cron state matched; recorder/source hashes remained unchanged. After legitimate fixture setup, every read preserved payments, allocations, ledger, provider confirmation/finality, journal lines, balance snapshots, inbox/delivery, reconciliation review and audit fingerprints. Every unsafe precision probe ran in a transaction and rolled back all rows and controls.

## Required root-owned server corrections

| Item | Actual result | Correction and reason |
| --- | --- | --- |
| Individual reviewed payment | A REVIEW amount of 9007199254740992 passed proposal, independent approval and actual service finalization. History serialized the amount as a JSON number. | Validate the exact numeric bound at the canonical payment admission/posting boundary, preserving positive rules, API signatures and grants. The client rejects this real receipt and JavaScript cannot represent all unrestricted bigint values. This is an interoperable wire requirement, not a provider limit. |
| Extreme bigint | 9223372036854775807 was refused only when the existing balance projection added it to another payment and raised 22003 arithmetic overflow. | An incidental aggregate overflow is not a stable exact-amount policy. Validate the bound before mutation and provide an intentional input/constraint denial; preserve atomicity and finality idempotency. |
| Complete numeric aggregates | Posting an otherwise exact amount 1 made the full actor-visible total 9007199254740992. `list_current_member_history_page` returned that unsafe JSON total. | Guard complete sums before numeric serialization, including own totals and group balance serializers. Individual bounds alone cannot make sums exact. Reject an unavailable numeric aggregate explicitly; never clamp, round, omit a receipt or fabricate zero. |

The additional failed balance assertion is a **fixture shape error**, not a runtime defect: the actual current Rwanda-only summary returns an explicit `[{currency:RWF,amount_raised_minor:0,current_user_balance_minor:0}]` for the known empty readable group. The harness expected an empty list. Its updated expectation retains explicit zero and unknown supporter-count semantics; the failed original packet remains unchanged.

## Minimum active route and source owners

Actual captured bodies and application ACLs are in `actual-minimum-functions.json`; each body identifies its captured source file/hash.

- Owner-seeded `public.payments.amount_rwf` has its original positive constraint (`202605230001_collect_baseline.sql:173`). This fixture inserts REVIEW only, not posted/confirmed state.
- Authenticated `public.propose_payment_reconciliation_v2(uuid,text,text,timestamptz,text)` checks positive RWF amount but no exact upper bound (`20260929170000_governed_reconciliation_workflow.sql:116`). `approve_payment_reconciliation_v2(uuid,text)` binds independent current maker/checker authority and immutable payment fingerprint.
- Service-only `public.finalize_approved_reconciliation_v2(uuid)` passes the reviewed amount unchanged into private finality (`20260929180000_notification_registration_sessions.sql:657`). No direct private EXECUTE bypass is used.
- Private `public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)` binds canonical request content and delegates confirmation (`20260929130000_provider_finality_content_binding.sql:235`).
- Private `public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)` checks positive amount and equality with the reviewed payment, then inserts confirmation/ledger and updates status through active posting triggers (`20260929130000_provider_finality_content_binding.sql:25`).
- `collect_hybrid.post_momo_receipt(uuid)` projects the confirmed balance and balanced journal (`20260903084000_hybrid_direct_ussd_financial_core.sql:918`). A projection overflow is not proof of the missing admission bound.
- Authenticated public history wrapper delegates `collect_member_actions.history_page(uuid,text,text,jsonb,integer)`. Its complete bigint sums and numeric item/totals JSON currently have no upper-bound guard (`20260928150000_relational_member_history_pages.sql:54`).
- `public.list_current_member_collection_balances()` serializes confirmed group/member numeric balances (`20260925190000_rwanda_momo_only.sql:481`). The exact zero shape is preserved in the actual definition.

Related exposed legacy serializers (`collect_member_actions.payment_history`, `list_current_member_payment_history`, `list_current_user_contributions`) also deserve root validation of the canonical per-payment bound. They are not proven current foreground dispatch merely because the functions exist.

## Scope

This is explicitly synthetic reconciliation mechanics. Digest/reference strings are not independent provider truth. No hosted service, signed-JWT verification, native/device attestation or settlement acceptance is inferred. The shared baseline remains 154 with latest 20260930230000;234000 was applied only in the clone. Root owns additive 235000 and its acceptance. The receipt bridge must consume terminal hashed SQL artifacts and retain server failures separately from client decoder acceptance.
