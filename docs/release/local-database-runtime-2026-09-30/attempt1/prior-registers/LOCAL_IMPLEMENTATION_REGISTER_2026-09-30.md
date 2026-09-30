# Collect — 24 local implementation goals

This register preserves the complete active local implementation scope. The original production register and its external acceptance criteria remain separate. No local goal item is declared fully closed yet.

## Verified progress

Migration142 recovery,11 concurrent scenarios, actual SQL-to-Dart receipts and roster terminal/status recovery are completed dependencies. Admin attempt5 passes280 tests and15-file analysis with214 unchanged input hashes, including reconciliation generation and redaction checks. Its tested source snapshot is retained; later changes require new matching evidence.

## Acceptance requirements

### L01 / goal1 — Roster browser-reload recovery (A01/P07)

**State:** in_progress. Implement144 server/client recovery with session-bound reference-only browser storage, exact serialized payload hashes, bounded private drafts/intents, explicit save/recovery/resumption, request replay, expiry/purge and CAS conflict tests. No private rows, reasons, titles, bytes or Auth tokens in browser storage.

### L02 / goal2 — Normal-owner bank scheduler retirement (X02/D09)

**State:** in_progress. Implement143 using owner cron APIs with ordinary installer privileges, immutable pause and postcommit observation/verification, real blocking concurrency and unchanged unrelated jobs/history/business fingerprints.

### L03 / goal3 — Admin session isolation (S09/U06)

**State:** in_progress. Fence every Admin provider, request and dialog with session generation, pinned request authorization, A-to-B-to-A sticky invalidation, expiry and Auth-stream error/done handling. Clear stale private state and suppress old success/freshness side effects.

### L04 / goal4 — Operation acknowledgements (S09/A09)

**State:** in_progress. Inventory every sensitive action and validate its exact response contract, typed fields, request-bound IDs/status and immutable route facts before success. Reject null/malformed/stale/mismatched responses and preserve uncertain outcomes.

### L05 / goal5 — Complete Admin route/action matrix (U06)

**State:** in_progress. Enumerate every local route/action/data source and prove allowed, denied, revoked, loading, empty, failure and durable audited-result behavior. Include grant/export/reveal/retry/reason flows.

### L06 / goal6 — Uncertain OTP recovery (S04)

**State:** in_progress. Implement durable single-send intent and evidence-bound accepted/not-sent/ambiguous/delivered recovery. Simulate timeout, response loss, late completion, replay and concurrent claims; unknown delivery must never trigger blind resend or release spent quota.

### L07 / goal7 — Error redaction (S07)

**State:** in_progress. Exercise secrets, phone/receipt data, provider/SQL details and malformed SDK errors across client/Edge/log/export surfaces. Verify only stable actionable messages and redacted structured telemetry reach users.

### L08 / goal8 — Local role and cross-group authorization (S08)

**State:** pending. Run anonymous/member/operator/service and cross-group negative tests, raw-SMS isolation, effective grants/RLS and both concurrent revocation orders against final local definitions.

### L09 / goal9 — Full upload decoding safety (A03)

**State:** pending. Implement full bounded image/PDF validation or a validated sandbox with page/object/animation/decompression limits. Test corrupt/spoofed/polyglot/page-heavy/expansion inputs before vendor calls.

### L10 / goal10 — Durable concurrent upload/extraction limits (A03)

**State:** pending. Implement actor/global concurrent and resource/cost reservations with idempotent recovery, timeouts, exhaustion, abuse and multiple-worker local tests.

### L11 / goal11 — Trusted XLSX transformation (A03/A09)

**State:** pending. Verify original workbook bytes against derived TSV using a trusted bounded parser. Reject inconsistent or substituted content and test workbook expansion, malformed relationships and row/cell limits.

### L12 / goal12 — Import/export and sensitive-action protection (A09)

**State:** pending. Test formula injection, row/resource bounds, data minimization, redaction, permission denial, accountable reasons and durable import/export/reveal/grant/retry audit.

### L13 / goal13 — Multilingual/adversarial evaluation tooling (A02)

**State:** pending. Create labeled multilingual/scanned/malformed/duplicate/ambiguous/prompt-injection fixtures and a reproducible local evaluation harness measuring error classes and safe rejection/correction.

### L14 / goal14 — Generated-dataset query benchmarks (D01-D04/D07)

**State:** pending. Benchmark realistic generated volumes, all sorts/scopes/page depths and concurrent paging. Correct ordering, excessive scanning, whole-history reconstruction, aggregation growth and queue-shrink behavior.

### L15 / goal15 — Identity/totals/money/ID/date correctness (D05-D08)

**State:** pending. Audit every consumer and modern/legacy RPC/cache/input path for immutable identity, collision/forgery denial, complete versus partial/absent/stale/zero totals, exact integer bounds, aliases, IDs and valid calendar/timezone behavior.

### L16 / goal16 — Cache/reconnect/session isolation (D10/P07)

**State:** in_progress. Automate duplicate/missed Realtime events, reconnect/offline revocation, bounded refresh, stale completion and account/session switching. No wrong-account private cache or misleading freshness.

### L17 / goal17 — Shared Revolut interface corrections (U02/U04/U05)

**State:** in_progress. Fix compact320x568/enlarged2x text, keyboard reachability, focus, semantic labels and financial/recovery wording through shared components. Preserve Collect workflows and test meaningful affected states.

### L18 / goal18 — Actual local browser/PWA lifecycle (U07/U08)

**State:** pending. Build/serve distinct public/Admin artifacts and test route/auth/bundle isolation, updates/failures, offline, real multiple tabs, logout/revocation/session switch and cache invalidation in a local browser.

### L19 / goal19 — Redacted financial/receipt/push observability (O06)

**State:** pending. Implement queue age, ACK/parse/unmatched/reconciliation/reversal and push lease/completion/scheduler health metrics. Test redaction, alert thresholds, missing/stale health and local response procedures.

### L20 / goal20 — Mutable settings/copy governance (A08)

**State:** pending. Inventory dynamic settings/copy, validate types/ranges/versions, enforce caller permissions and audit updates/conflicts. Preserve stable application strings as code.

### L21 / goal21 — Proven asset/code/dependency cleanup (A05/A07)

**State:** pending. Produce reachability evidence, reconcile seven indexed missing assets and remove only demonstrably unused code/assets/dependencies. Preserve licensed/provenance decisions and run affected local regressions.

### L22 / goal22 — Locks/inventory/SBOM/build hygiene (Q01/Q02/Q07)

**State:** pending. Reconcile exact pinned-runtime locks and inventories, generate local SBOMs, fix formatting/analyzer/native lint including40 recorded warnings, and prove clean-checkout builds without undeclared ignored/private files.

### L23 / goal23 — Final-set integrated local verification (D09/Q03/Q06)

**State:** pending. Run final frozen migration-set clean and populated upgrades, rollback/roll-forward and incompatible-client tests. Execute full local Dart/native/Edge/database/browser suites and critical auth/ACK/finality/reversal/session concurrency/mutation coverage. Preserve financial/receipt baselines.

### L24 / goal24 — Bound evidence and handover register (G07/A10)

**State:** in_progress. Package source/lock/toolchain/build/test/log hashes and exact commands/exclusions against one final local source set. Preserve dated failures and earlier evidence, refresh this24-item register and reconcile historical versus current packets.

## Evidence handling

The companion JSON records per-item criteria and dated evidence. Preserve prior failed attempts; recapture source/toolchain/lock hashes and actual logs after source changes. Browser, database, concurrency and full-suite claims require their actual executions.
