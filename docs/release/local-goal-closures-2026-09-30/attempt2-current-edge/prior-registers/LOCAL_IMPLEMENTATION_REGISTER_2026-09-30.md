# Collect — 24 local implementation goals

All24 original local acceptance requirements remain. **L02 and L21 are locally complete;22 goal items remain open.** Production release remains NO-GO.

## Current verified progress

The [runtime consolidation](local-database-runtime-2026-09-30/attempt1/validation.json) binds21 actual database packets and222 inputs. The isolated registry is146 with143 tables. The last full clean replay is141; final integration remains. Source/build/test scopes are kept distinct.

## Acceptance requirements

### L01 / goal1 — Roster browser-reload recovery (A01/P07)

**State:** in_progress. Implement144 server/client recovery with session-bound reference-only browser storage, exact serialized payload hashes, bounded private drafts/intents, explicit save/recovery/resumption, request replay, expiry/purge and CAS conflict tests. No private rows, reasons, titles, bytes or Auth tokens in browser storage.

**Verified progress:** Actual144 receipts/adversarial/six blocking races restore136 tables;91 integrated roster,57 workbook and1 actual Chromium adapter tests pass in213-input dated packet. Full browser reload/tab/session lifecycle remains.

### L02 / goal2 — Normal-owner bank scheduler retirement (X02/D09)

**State:** complete. Implement143 using owner cron APIs with ordinary installer privileges, immutable pause and postcommit observation/verification, real blocking concurrency and unchanged unrelated jobs/history/business fingerprints.

**Verified progress:** Complete local normal-owner143 acceptance: populated history/adversarial rollback, separate postcommit observation/final verification71.034822seconds,6 canary+9 verification races,32 role/immutability checks, source reapply and current inactive canonical readback. Original productionX02 hosted acceptance remains open.

### L03 / goal3 — Admin session isolation (S09/U06)

**State:** in_progress. Fence every Admin provider, request and dialog with session generation, pinned request authorization, A-to-B-to-A sticky invalidation, expiry and Auth-stream error/done handling. Clear stale private state and suppress old success/freshness side effects.

### L04 / goal4 — Operation acknowledgements (S09/A09)

**State:** in_progress. Inventory every sensitive action and validate its exact response contract, typed fields, request-bound IDs/status and immutable route facts before success. Reject null/malformed/stale/mismatched responses and preserve uncertain outcomes.

### L05 / goal5 — Complete Admin route/action matrix (U06)

**State:** in_progress. Enumerate every local route/action/data source and prove allowed, denied, revoked, loading, empty, failure and durable audited-result behavior. Include grant/export/reveal/retry/reason flows.

### L06 / goal6 — Uncertain OTP recovery (S04)

**State:** in_progress. Implement durable single-send intent and evidence-bound accepted/not-sent/ambiguous/delivered recovery. Simulate timeout, response loss, late completion, replay and concurrent claims; unknown delivery must never trigger blind resend or release spent quota.

**Verified progress:** Corrected PostgreSQL hook-ID regex preserves valid256-character IDs.56 actual rollback checks,9 legacy-v2 upgrade checks and6 real races pass; failed-race graph recovered to exact139-table baseline. Final current Edge HTTP integration remains.

### L07 / goal7 — Error redaction (S07)

**State:** in_progress. Exercise secrets, phone/receipt data, provider/SQL details and malformed SDK errors across client/Edge/log/export surfaces. Verify only stable actionable messages and redacted structured telemetry reach users.

### L08 / goal8 — Local role and cross-group authorization (S08)

**State:** pending. Run anonymous/member/operator/service and cross-group negative tests, raw-SMS isolation, effective grants/RLS and both concurrent revocation orders against final local definitions.

### L09 / goal9 — Full upload decoding safety (A03)

**State:** in_progress. Implement full bounded image/PDF validation or a validated sandbox with page/object/animation/decompression limits. Test corrupt/spoofed/polyglot/page-heavy/expansion inputs before vendor calls.

**Verified progress:** Bounded five-format Linux parser, seccomp network denial, memory/CPU limits and32 actual codec/auth/expansion cases including compressed PDF object streams pass. Final current Edge HTTP integration remains.

### L10 / goal10 — Durable concurrent upload/extraction limits (A03)

**State:** in_progress. Implement actor/global concurrent and resource/cost reservations with idempotent recovery, timeouts, exhaustion, abuse and multiple-worker local tests.

**Verified progress:** Corrected146 applies as normal owner,139 old tables preserved→143;29 quota/permission checks and7 real resource races pass, including stale REPEATABLE READ40001. All143 baseline tables/controls restored. Current Edge budget integration remains.

### L11 / goal11 — Trusted XLSX transformation (A03/A09)

**State:** in_progress. Verify original workbook bytes against derived TSV using a trusted bounded parser. Reject inconsistent or substituted content and test workbook expansion, malformed relationships and row/cell limits.

**Verified progress:** Trusted original XLSX→TSV decoder and8 actual signed Deno integrations pass. Actual146 reservation/verification→142 preview/review/commit→144 reload and lost cleanup-ACK repair pass. Final Edge HTTP gate remains.

### L12 / goal12 — Import/export and sensitive-action protection (A09)

**State:** pending. Test formula injection, row/resource bounds, data minimization, redaction, permission denial, accountable reasons and durable import/export/reveal/grant/retry audit.

### L13 / goal13 — Multilingual/adversarial evaluation tooling (A02)

**State:** in_progress. Create labeled multilingual/scanned/malformed/duplicate/ambiguous/prompt-injection fixtures and a reproducible local evaluation harness measuring error classes and safe rejection/correction.

**Verified progress:** Labeled multilingual/adversarial corpus and evaluation tooling implemented;155 deterministic/response/evaluation regressions,5 labeled deterministic measurements and3 contract probes pass. Live provider accuracy is explicitly unmeasured; current HTTP harness integration remains.

### L14 / goal14 — Generated-dataset query benchmarks (D01-D04/D07)

**State:** pending. Benchmark realistic generated volumes, all sorts/scopes/page depths and concurrent paging. Correct ordering, excessive scanning, whole-history reconstruction, aggregation growth and queue-shrink behavior.

### L15 / goal15 — Identity/totals/money/ID/date correctness (D05-D08)

**State:** pending. Audit every consumer and modern/legacy RPC/cache/input path for immutable identity, collision/forgery denial, complete versus partial/absent/stale/zero totals, exact integer bounds, aliases, IDs and valid calendar/timezone behavior.

### L16 / goal16 — Cache/reconnect/session isolation (D10/P07)

**State:** in_progress. Automate duplicate/missed Realtime events, reconnect/offline revocation, bounded refresh, stale completion and account/session switching. No wrong-account private cache or misleading freshness.

### L17 / goal17 — Shared Revolut interface corrections (U02/U04/U05)

**State:** in_progress. Fix compact320x568/enlarged2x text, keyboard reachability, focus, semantic labels and financial/recovery wording through shared components. Preserve Collect workflows and test meaningful affected states.

**Verified progress:** Current browser captures identify remaining heading semantics, empty group-detail navigation capsule and missing visible Security Back arrow; full shared-component corrections remain.

### L18 / goal18 — Actual local browser/PWA lifecycle (U07/U08)

**State:** in_progress. Build/serve distinct public/Admin artifacts and test route/auth/bundle isolation, updates/failures, offline, real multiple tabs, logout/revocation/session switch and cache invalidation in a local browser.

**Verified progress:** Normal actual Admin/public artifacts built; shipped CSP/configured-origin Auth rebuild/reference-only bookmark checks pass in dated browser attempt. Complete reload/input/multitab/cache/install/offline/logout acceptance remains; final builds must use pinned Flutter3.44.4.

### L19 / goal19 — Redacted financial/receipt/push observability (O06)

**State:** pending. Implement queue age, ACK/parse/unmatched/reconciliation/reversal and push lease/completion/scheduler health metrics. Test redaction, alert thresholds, missing/stale health and local response procedures.

### L20 / goal20 — Mutable settings/copy governance (A08)

**State:** pending. Inventory dynamic settings/copy, validate types/ranges/versions, enforce caller permissions and audit updates/conflicts. Preserve stable application strings as code.

### L21 / goal21 — Proven asset/code/dependency cleanup (A05/A07)

**State:** complete. Produce reachability evidence, reconcile seven indexed missing assets and remove only demonstrably unused code/assets/dependencies. Preserve licensed/provenance decisions and run affected local regressions.

**Verified progress:** Complete local cleanup acceptance:194/194 remaining runtime Dart files reachable;2 unused sources hash-preserved/removed;95 assets classified;174 approved images decoded/hash-verified;7 inactive-index paths reconciled; direct dependencies accounted for;76 affected tests and current public media/build checks pass. Native/design/license acceptance remains separate.

### L22 / goal22 — Locks/inventory/SBOM/build hygiene (Q01/Q02/Q07)

**State:** in_progress. Reconcile exact pinned-runtime locks and inventories, generate local SBOMs, fix formatting/analyzer/native lint including40 recorded warnings, and prove clean-checkout builds without undeclared ignored/private files.

**Verified progress:** Exact installed Flutter3.44.4 SDK identified; earlier3.44.3 captures are accurately dated. Source SBOM453 components generated; final native lint/locks/formatter/fatal analysis/resolved inventories/unsigned builds remain.

### L23 / goal23 — Final-set integrated local verification (D09/Q03/Q06)

**State:** in_progress. Run final frozen migration-set clean and populated upgrades, rollback/roll-forward and incompatible-client tests. Execute full local Dart/native/Edge/database/browser suites and critical auth/ACK/finality/reversal/session concurrency/mutation coverage. Preserve financial/receipt baselines.

**Verified progress:** Exact isolated registry now146, all143 tables restored after scoped tests. Last full clean migration replay remains141; final frozen clean/populated upgrade and whole-suite acceptance remain.

### L24 / goal24 — Bound evidence and handover register (G07/A10)

**State:** in_progress. Package source/lock/toolchain/build/test/log hashes and exact commands/exclusions against one final local source set. Preserve dated failures and earlier evidence, refresh this24-item register and reconcile historical versus current packets.

**Verified progress:** 21 actual143–146 runtime packets consolidated with222 bound inputs and fresh canonical registry hash readback. Eight recorder-corruption tests pass. Remaining application/native/browser/Edge/source-lock-build integration packets remain.

## Evidence limits

Local completion does not close original production IDs with hosted/provider/device/owner acceptance. Historical failures and source snapshots are preserved under the referenced packets. No production completion percentage is inferred.
