# Collect local implementation register

Captured: 2026-09-30T15:14:31.471964+00:00. Revision 4.

**6 of24 local goals verified complete;18 remain open.** Closed: L02, L06, L09, L10, L11, L13. Original102 production criteria retain their acceptance scope.

The browser-token restriction is not met by the current SDK persistence. Reference-only roster bookmarks do not prove that restriction. Earlier cleanup/browser passes are dated after subsequent runtime/native edits.

| ID | Task | Status | Remaining scope or verified result |
| --- | --- | --- | --- |
| L01 | Roster browser-reload recovery | in_progress | Actual144 SQL/client and current browser reload/CAS/lost-response cases pass. Full unqualified token privacy acceptance CONTRADICTED: persistSession:true writes Supabase Auth tokens to localStorage. Roster bookmarks alone contain only references; browser Auth persistence/recovery architecture must be corrected. |
| L02 | Normal-owner bank scheduler retirement | complete | Complete local normal-owner143 acceptance: populated history/adversarial rollback, separate postcommit observation/final verification71.034822seconds,6 canary+9 verification races,32 role/immutability checks, source reapply and current inactive canonical readback. Original productionX02 hosted acceptance remains open. |
| L03 | Admin session isolation | in_progress | Dated scoped280-test/15-analysis pass with214 stable inputs; full per-item acceptance and final integration remain. |
| L04 | Operation acknowledgements | in_progress | Dated scoped280-test/15-analysis pass with214 stable inputs; full per-item acceptance and final integration remain. |
| L05 | Complete Admin route/action matrix | in_progress | Dated scoped280-test/15-analysis pass with214 stable inputs; full per-item acceptance and final integration remain. |
| L06 | Uncertain OTP recovery | complete | Corrected145 source;56 SQL rollback +9 v2-upgrade checks and6 real races; current signed-OTP handler in304 unit tests and actual71 frozen HTTP checks, with ambiguous outcomes never blind resent. |
| L07 | Error redaction | in_progress | Dated scoped280-test/15-analysis pass with214 stable inputs; full per-item acceptance and final integration remain. |
| L08 | Local role and cross-group authorization | pending | Run anonymous/member/operator/service and cross-group negative tests, raw-SMS isolation, effective grants/RLS and both concurrent revocation orders against final local definitions. |
| L09 | Full upload decoding safety | complete | 32 real Linux codec/auth/resource cases and actual signed adapter integrations coverPNG/JPEG/WebP/PDF/XLSX, malformed/spoofed/polyglot/animation/page/expansion limits and process sandbox. |
| L10 | Durable concurrent upload/extraction limits | complete | 146 normal-owner apply plus29 assertions and7 real two-session races, exact143-table restore; HTTP/handler budget ACK/replay/ambiguity tests, signed receipts before vendor work. |
| L11 | Trusted XLSX transformation | complete | Original bounded workbook bytes verified against derived TSV; substituted client TSV rejected; actual146-to142-to144 compatibility and signed decoder handler integrations. |
| L12 | Import/export and sensitive-action protection | pending | Test formula injection, row/resource bounds, data minimization, redaction, permission denial, accountable reasons and durable import/export/reveal/grant/retry audit. |
| L13 | Multilingual/adversarial evaluation tooling | complete | Labeled multilingual/scanned/malformed/duplicate/ambiguous/prompt-injection corpus;155 deterministic/response/evaluation checks,5 labeled deterministic measurements and3 contract probes. Live-provider accuracy remains explicitly unmeasured. |
| L14 | Generated-dataset query benchmarks | pending | Benchmark realistic generated volumes, all sorts/scopes/page depths and concurrent paging. Correct ordering, excessive scanning, whole-history reconstruction, aggregation growth and queue-shrink behavior. |
| L15 | Identity/totals/money/ID/date correctness | pending | Audit every consumer and modern/legacy RPC/cache/input path for immutable identity, collision/forgery denial, complete versus partial/absent/stale/zero totals, exact integer bounds, aliases, IDs and valid calendar/timezone behavior. |
| L16 | Cache/reconnect/session isolation | in_progress | Dated scoped280-test/15-analysis pass with214 stable inputs; full per-item acceptance and final integration remain. |
| L17 | Shared Revolut interface corrections | in_progress | Actual pixels show working Back arrows and group navigation, correcting inherited visual findings. Shared title/legal heading semantics fixes and meaningful prior-source failing tests implemented; actual browser found additional Security header gap being corrected. Full compact/enlarged/focus/wording coverage remains. |
| L18 | Actual local browser/PWA lifecycle | in_progress | Actual pinned normal browser packet passes37 assertions/16 lifecycle cases with no uncaught errors and557 stable inputs at capture. Subsequent UI/native changes and requiredL01 Auth-persistence correction need final current-source browser revalidation. |
| L19 | Redacted financial/receipt/push observability | in_progress | New148 redacted buckets/health/alerts source passes36 actual owner/API/permission/redaction/missing-stale/threshold checks inside rollback on146, all143 tables/catalog/cron unchanged. Source148 is not installed; receipt telemetry, client presentation and final runtime/race integration remain. |
| L20 | Mutable settings/copy governance | in_progress | 147 source governance for26 control families and frozen featureflag/preferences v2 contracts prepared; local source parse succeeds. Full normal-owner SQL/runtime/concurrency and client acceptance pending;147 not installed. |
| L21 | Proven asset/code/dependency cleanup | in_progress | Cleanup implementation remains in place, with prior complete source-bound certificate preserved. Later logout/shared UI/native/lock changes make that certificate dated; current reachability/asset/dependency rebind is pending. No current whole-source completion claim. |
| L22 | Locks/inventory/SBOM/build hygiene | in_progress | Deno2.5.6 full cached compiler uses immutable45-remote/5-npm production lock, rejects corrupted hashes;304 unit tests and71 actualHTTP checks pass with frozen lock enforced. Local caches combined without network calls. Remaining Android native locks/lint/unsigned builds/current SBOM and final Dart gates underway. |
| L23 | Final-set integrated local verification | in_progress | Exact live isolated146 registry and143 tables are quiet/restored.147/148 are staged source-only;148 probe rolls back. Last complete clean replay remains141; final frozen clean/populated upgrade and integrated acceptance remain. |
| L24 | Bound evidence and handover register | in_progress | Current five Edge/upload/OTP/evaluation local acceptance closures bind78 source hashes and23 evidence hashes. Dated failures, lock generation cache limitations and actual browser-token contradiction retained. Final remaining-runtime/native/browser source-set handover remains. |

## Original local acceptance criteria

### L01 — Roster browser-reload recovery

Implement144 server/client recovery with session-bound reference-only browser storage, exact serialized payload hashes, bounded private drafts/intents, explicit save/recovery/resumption, request replay, expiry/purge and CAS conflict tests. No private rows, reasons, titles, bytes or Auth tokens in browser storage.

### L02 — Normal-owner bank scheduler retirement

Implement143 using owner cron APIs with ordinary installer privileges, immutable pause and postcommit observation/verification, real blocking concurrency and unchanged unrelated jobs/history/business fingerprints.

### L03 — Admin session isolation

Fence every Admin provider, request and dialog with session generation, pinned request authorization, A-to-B-to-A sticky invalidation, expiry and Auth-stream error/done handling. Clear stale private state and suppress old success/freshness side effects.

### L04 — Operation acknowledgements

Inventory every sensitive action and validate its exact response contract, typed fields, request-bound IDs/status and immutable route facts before success. Reject null/malformed/stale/mismatched responses and preserve uncertain outcomes.

### L05 — Complete Admin route/action matrix

Enumerate every local route/action/data source and prove allowed, denied, revoked, loading, empty, failure and durable audited-result behavior. Include grant/export/reveal/retry/reason flows.

### L06 — Uncertain OTP recovery

Implement durable single-send intent and evidence-bound accepted/not-sent/ambiguous/delivered recovery. Simulate timeout, response loss, late completion, replay and concurrent claims; unknown delivery must never trigger blind resend or release spent quota.

### L07 — Error redaction

Exercise secrets, phone/receipt data, provider/SQL details and malformed SDK errors across client/Edge/log/export surfaces. Verify only stable actionable messages and redacted structured telemetry reach users.

### L08 — Local role and cross-group authorization

Run anonymous/member/operator/service and cross-group negative tests, raw-SMS isolation, effective grants/RLS and both concurrent revocation orders against final local definitions.

### L09 — Full upload decoding safety

Implement full bounded image/PDF validation or a validated sandbox with page/object/animation/decompression limits. Test corrupt/spoofed/polyglot/page-heavy/expansion inputs before vendor calls.

### L10 — Durable concurrent upload/extraction limits

Implement actor/global concurrent and resource/cost reservations with idempotent recovery, timeouts, exhaustion, abuse and multiple-worker local tests.

### L11 — Trusted XLSX transformation

Verify original workbook bytes against derived TSV using a trusted bounded parser. Reject inconsistent or substituted content and test workbook expansion, malformed relationships and row/cell limits.

### L12 — Import/export and sensitive-action protection

Test formula injection, row/resource bounds, data minimization, redaction, permission denial, accountable reasons and durable import/export/reveal/grant/retry audit.

### L13 — Multilingual/adversarial evaluation tooling

Create labeled multilingual/scanned/malformed/duplicate/ambiguous/prompt-injection fixtures and a reproducible local evaluation harness measuring error classes and safe rejection/correction.

### L14 — Generated-dataset query benchmarks

Benchmark realistic generated volumes, all sorts/scopes/page depths and concurrent paging. Correct ordering, excessive scanning, whole-history reconstruction, aggregation growth and queue-shrink behavior.

### L15 — Identity/totals/money/ID/date correctness

Audit every consumer and modern/legacy RPC/cache/input path for immutable identity, collision/forgery denial, complete versus partial/absent/stale/zero totals, exact integer bounds, aliases, IDs and valid calendar/timezone behavior.

### L16 — Cache/reconnect/session isolation

Automate duplicate/missed Realtime events, reconnect/offline revocation, bounded refresh, stale completion and account/session switching. No wrong-account private cache or misleading freshness.

### L17 — Shared Revolut interface corrections

Fix compact320x568/enlarged2x text, keyboard reachability, focus, semantic labels and financial/recovery wording through shared components. Preserve Collect workflows and test meaningful affected states.

### L18 — Actual local browser/PWA lifecycle

Build/serve distinct public/Admin artifacts and test route/auth/bundle isolation, updates/failures, offline, real multiple tabs, logout/revocation/session switch and cache invalidation in a local browser.

### L19 — Redacted financial/receipt/push observability

Implement queue age, ACK/parse/unmatched/reconciliation/reversal and push lease/completion/scheduler health metrics. Test redaction, alert thresholds, missing/stale health and local response procedures.

### L20 — Mutable settings/copy governance

Inventory dynamic settings/copy, validate types/ranges/versions, enforce caller permissions and audit updates/conflicts. Preserve stable application strings as code.

### L21 — Proven asset/code/dependency cleanup

Produce reachability evidence, reconcile seven indexed missing assets and remove only demonstrably unused code/assets/dependencies. Preserve licensed/provenance decisions and run affected local regressions.

### L22 — Locks/inventory/SBOM/build hygiene

Reconcile exact pinned-runtime locks and inventories, generate local SBOMs, fix formatting/analyzer/native lint including40 recorded warnings, and prove clean-checkout builds without undeclared ignored/private files.

### L23 — Final-set integrated local verification

Run final frozen migration-set clean and populated upgrades, rollback/roll-forward and incompatible-client tests. Execute full local Dart/native/Edge/database/browser suites and critical auth/ACK/finality/reversal/session concurrency/mutation coverage. Preserve financial/receipt baselines.

### L24 — Bound evidence and handover register

Package source/lock/toolchain/build/test/log hashes and exact commands/exclusions against one final local source set. Preserve dated failures and earlier evidence, refresh this24-item register and reconcile historical versus current packets.

