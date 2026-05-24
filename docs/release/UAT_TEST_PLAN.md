# Collect UAT Test Plan

Audit date: 2026-05-24

Decision context: **NO-GO**. Execute human UAT only as staging or
rollback-only release evidence until the latest Supabase release refresh no
longer reports `database_connectivity`, CAPTCHA/bot protection and HIBP
leaked-password protection are resolved, and any remaining Free-plan or PITR
risk is validly accepted where allowed.

Current automated evidence to attach before live persona walkthroughs:

- `.cache/supabase_go_live_evidence/20260524T085150Z`
- `make supabase-acceptance-matrix-json`: `7` pass / `5` blocked
- `make supabase-edge-auth-uat`: local Edge Function auth contract pass
- `flutter test --no-pub --concurrency=1`: `87` tests pass
- Android emulator integration smoke UAT on `Pixel_5_API_34_Lite`: `2` tests
  pass

Evidence must not expose raw SMS, phone/MOMO numbers, tokens, service-role
keys, OpenAI keys, WhatsApp/SMS hook secrets, CAPTCHA provider secrets, or
production customer data. Use synthetic users, synthetic Rwanda-format phone
numbers, sanitized SMS bodies, screenshots with secrets redacted, and
rollback-only linked database scripts wherever database evidence is needed.

| ID | Persona | Steps | Expected | Automated evidence | Status |
| --- | --- | --- | --- | --- | --- |
| UAT-01 | Contributor | Sign in, open approved public collection, create payment intent, view MOMO/USSD instructions, mark paid with sanitized reference, and verify public identity choice. | Contributor sees manual MOMO instructions only; no payment API; no raw receiver data leak; public identity choice is respected. | `scripts/collect_linked_uat.sh`, repository/widget tests. | Automated partial pass; human signoff pending. |
| UAT-02 | Creator | Create private collection with receiver MOMO, request public listing, share QR/link, and verify default privacy. | Collection starts private; public listing awaits admin approval; share link/QR exposes no private MOMO/raw SMS data. | `scripts/collect_linked_uat.sh`, repository tests. | Automated partial pass; human signoff pending. |
| UAT-03 | Recurring group admin | Create recurring collection and inspect period/obligation behavior plus member/admin visibility. | Recurring period exists; visibility is correct for members and admins. | `scripts/collect_linked_uat.sh`. | Automated partial pass; human signoff pending. |
| UAT-04 | Public supporter | Visit public directory and contribution flow without membership. | Only approved public collections are visible; receiver MOMO details appear only at contribution step. | `scripts/collect_linked_uat.sh`, widget tests. | Automated partial pass; human signoff pending. |
| UAT-05 | Receiver/SMS operator | Enter sanitized receiver MOMO SMS manually, verify consent-gated handling, parse/review path, and no public raw-SMS exposure. | Raw SMS stays private; parsed event enters review/allocation path; unauthorized receiver submissions fail. | `scripts/collect_linked_uat.sh`, `scripts/collect_admin_security_uat.sh`. | Automated partial pass; trusted DB rerun and human signoff pending. |
| UAT-06 | Moderator | Review public listing request and moderation queues through permitted admin lane. | Moderator can perform only permitted actions; public approval/rejection creates audit evidence. | `scripts/collect_admin_security_uat.sh`. | Automated partial pass; human signoff pending. |
| UAT-07 | Payments admin | Review unallocated/ambiguous payment event and perform manual allocation with reason. | Allocation is reason-required, idempotent, audited, and posts the ledger exactly once. | `scripts/collect_admin_security_uat.sh`, `scripts/collect_linked_uat.sh`. | Automated partial pass; trusted DB rerun and human signoff pending. |
| UAT-08 | Compliance admin | Reveal raw SMS through controlled flow with reason. | Raw SMS is masked by default; reveal is permission-gated, reason-required, and audited. | `scripts/collect_admin_security_uat.sh`, privacy contract tests. | Automated partial pass; human signoff pending. |
| UAT-09 | Non-admin | Attempt admin routes/functions and protected raw-SMS/payment actions. | Access is denied client-side and server-side without sensitive data leakage. | Android integration smoke UAT, `scripts/collect_admin_security_uat.sh`. | Automated partial pass; human signoff pending. |
| UAT-10 | Edge-case user | Test duplicate SMS/transaction, invalid amount, non-Rwanda phone, expired intent, ambiguous amount, missing receiver authorization, failed Edge Function auth, and retry/idempotency behavior. | No double-post; invalid inputs fail safely; expired/ambiguous cases remain unallocated; missing receiver auth is denied; failed Edge Function auth returns `401`; retry behavior is idempotent and no raw phone/SMS/provider secret leaks. | `scripts/collect_linked_uat.sh`, `scripts/collect_edge_auth_contract_uat.sh`, `test/core/phone_and_public_id_test.dart`, `test/shared/collect_repository_test.dart`, `test/supabase_contract_test.dart`. | Automation present; trusted DB rerun and human signoff pending. |

Minimum GO evidence:

1. `make supabase-ready-strict` passes from trusted linked query mode or an
   allow-listed database path.
2. `make supabase-go-live-gate-json` reports `go_live_approved=true`.
3. `make supabase-go-live-evidence` is regenerated after platform and UAT
   fixes.
4. `docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md` records release-owner
   signoff for all ten personas.
