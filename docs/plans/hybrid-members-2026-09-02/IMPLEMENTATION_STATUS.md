# Hybrid membership foundation — local implementation status

Date: 2 September 2026

Verdict: **FOUNDATION VALIDATED LOCALLY; FULL JOURNEY NOT PRODUCTION READY**

## Decision recorded

The owner answered yes to send-time confirmation. Codex must present the exact recipient and canonical receipt for confirmation immediately before an SMS send. This is not a blanket approval, and no SMS or schedule was activated.

## Implemented in this increment

- Deterministic receipt parser v2/schema v4: M-Money recognition, received-clause amount, separate wallet balance, private payer name, last3, optional provider reference, explicit Rwanda receipt time. Rejects ambiguous clauses, malformed/unsafe amounts and excluded messages.
- Android capture admits complete masked-name/wallet-balance receipts without a provider reference, retaining the receive-only permission boundary and encrypted queue. Raw body whitespace survives native capture, Flutter forwarding, Edge validation and SQL storage.
- Parsed-event persistence stores private matching facts; generic parsed JSON masks the full phone and payer name. Existing direct-USSD allocation is deliberately not claimed as complete.
- Raw ingestion verifies the exact body hash, rejects conflicting envelope retries, deduplicates the same observed receipt across envelope IDs, and keeps identical text with different original device times distinct. Original evidence is immutable. Existing receiver ownership/consent and rate limits remain.
- Private member registry independent of Auth. Existing app IDs are reserved/backfilled; new app and offline records use one transaction-serialized numeric-ID namespace. Deleting an account does not release its member record/ID.
- Private MoMo identities retain member name, registered MoMo name, canonical full number, normalized name, suffix and match key. No name/last3 account claim is implemented or permitted.
- Admin RPCs for private assisted savings-group drafts and atomic reviewed roster batches of 1–500 rows. Both use explicit request UUIDs for retry protection. Roster conflicts require review rather than silently changing identity.
- Exact, deterministic Buri Munsi acknowledgement renderer recovered from easyMO, with integer RWF grouping and strict snapshot/reference validation. Rendering alone neither enqueues nor sends.

The existing public-sponsored creation flow and mobile UI files were not changed by this increment. Assisted onboarding is OFF by default via `hybrid_member_onboarding`. This flag gates the new admin commands, not the parser, ID-reservation triggers or all schema effects: it is not permission to deploy this unfinished candidate.

## Migration and API inventory

- [Receipt capture migration](/Volumes/PRO-G40/COOL/supabase/migrations/20260902120435_hybrid_receipt_capture_contract.sql)
- [Member registry migration](/Volumes/PRO-G40/COOL/supabase/migrations/20260902120555_hybrid_member_registry.sql)
- `admin_create_assisted_group(p_title, p_reason, p_request_id)` creates a private savings draft with no invented payee.
- `admin_add_assisted_roster(p_collection_id, p_rows, p_request_id, p_reason)` accepts reviewed rows `{member_name, momo_name, momo_number}`; member_name can default to momo_name. It does not parse a file or call OpenAI.

The functions use existing authenticated admin permission checks; private tables expose no direct client access. New privileged helpers use an empty search path and qualified references. Country-scoped operator identities and fine-grained registrar roles still require the later authorization design/review.

## Actual local validation

Machine-readable [validation record and source hashes](evidence/foundation-validation.json); [post-fix parser characterization](evidence/parser-foundation-state.json). These records distinguish the local foundation from unfinished end-to-end UAT.

| Check | Result | Boundary |
| --- | --- | --- |
| Deno parser/raw-input/receipt-template tests | 29 passed, 0 failed | Synthetic pure modules, including 2 legacy tests |
| Edge Function typecheck | Passed | Both changed Edge entrypoints; not HTTP deployment |
| Deno format and lint | Passed | Six changed/new TypeScript files |
| Original 8-check parser diagnostic | 8/8 passed | Original saved baseline remains unchanged |
| PostgreSQL migrations + UAT | 33 assertions passed | Isolated schema-only database, synthetic fixture transaction rolled back |
| Android internal_receiver unit tests | 8 passed, 0 failures/errors/skips | Debug JVM unit tests; no physical SMS/handset capture |
| Focused Flutter regression suite | 64 passed | Four existing test files; not new admin screen UAT |
| Flutter analyze | No issues | Current dirty worktree |
| Supabase security advisors | No warning/error findings | Isolated local schema, not production/provider approval |
| Git whitespace check | Passed | Tracked diff; new files reviewed separately |

Local database: `collect_hybrid_uat_20260902` in the existing local `supabase_db_collect` container. The runner copied schema only from the existing synthetic UAT database; no user data was copied and the shared mobile UAT database was not modified. The clone keeps actual grants/RLS, omitting only foreign-owner future default ACL declarations that the local postgres role cannot apply. The empty failed setup was rebuilt during preparation. No production backup or restore was performed.

Reproduce from the repository:

~~~sh
deno test supabase/functions/_shared/momo_sms_parser_test.ts supabase/functions/_shared/momo_sms_hybrid_test.ts
deno check supabase/functions/parse-payment-sms/index.ts supabase/functions/ingest-payment-sms/index.ts
node scripts/tests/hybrid_receipt_unit.mjs
ruby scripts/tests/hybrid_backend_uat.rb
flutter test test/supabase_contract_test.dart test/shared/member_roster_test.dart test/shared/group_owner_controls_test.dart test/core/rwanda_momo_number_test.dart --reporter expanded
flutter analyze --no-pub
~~~

Use Node 24+ for the compatibility runner. The native Android check was `:app:testInternal_receiverDebugUnitTest` with Android Studio's bundled JDK. Its pre-existing Kotlin/AGP/Gradle deprecation warnings remain; the build succeeded. Setup/migration switches in the Ruby runner target only the explicitly named isolated database, refuse to overwrite an existing database, and do not write migration-history entries.

## QA review and remaining gates

1. **Frontend and extraction remain unimplemented.** Add assisted-group/roster screens, validation preview, file row accounting and reviewed OpenAI PDF/image extraction. Preserve private-by-default and current numeric member-facing identity. No new frontend screenshot/UAT is claimed.
2. **Receiving assignments and direct-USSD posting remain unimplemented.** The old allocator still requires its intent/provider-reference path. New masked receipts can be captured/parsed but must not be described as automatically allocated. Implement deterministic route resolution, true balanced RWF journal, receipt snapshots and conflicts/reversals before activation.
3. **Offline reads and account claiming remain incomplete.** Existing member roster reads still filter to app-linked profiles. Retention of an ID after deletion is not proof of the complete account-deletion/financial-retention journey. Verified full-number claiming, history continuity and link auditing need implementation/UAT.
4. **No durable SMS outbox, MCP bridge or schedule cutover exists yet.** Implement claim fencing, current confirmation, send-start markers, observed/uncertain outcomes and safe recovery. Do not place unrestricted SQL or service-role credentials in the operator.
5. **No physical sending-line or feature-phone test.** Confirm intended iPhone/SIM and a specific recipient before an authorized pilot. Actual send, delivery, segment cost, latency and recovery remain unverified.
6. **Integration/concurrency/release gates remain.** Test old/new clients against migration backfill, concurrent imports and allocations, source aliases, revoked permissions, restoration, full 89-case UAT and final review. New index semantics require a forward-repair rollback plan; blindly restoring the former body-only unique index after distinct receipts exist can fail.

All work is local and uncommitted. No Git push, production migration, deployment, customer data mutation, OpenAI roster request, schedule activation or real SMS send occurred.

Next: implement the assisted admin roster/import journey and receiving-assignment/direct-USSD posting path, then the no-send outbox/operator dry run.
