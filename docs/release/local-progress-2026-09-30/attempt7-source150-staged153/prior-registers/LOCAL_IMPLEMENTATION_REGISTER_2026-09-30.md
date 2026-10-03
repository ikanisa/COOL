# Collect local implementation register

Captured: 2026-09-30T19:41:16.529928+00:00. Revision6.

**6 of24 local goals verified complete;18 remain open.** Original102 production criteria retain their acceptance scope.

Installed local registry:150 migrations/149 tables. 152 source files; staged versions: 20260930200000, 20260930210000. Final whole-source acceptance is pending.

| ID | Task | Status | Remaining scope or verified result |
| --- | --- | --- | --- |
| L01 | Roster browser-reload recovery | in_progress | 149 is installed with ordinary owner privileges;51 rollback assertions and36 fresh-Auth/lineage/quota scenarios with31 observed blocking races pass on150, restoring all149 tables/catalog/cron and leaving0 workers. Copied Auth acceptance passes123 tests and28 real Chrome privacy checks; its original receipt aggregation limitation is retained. Full normal Admin fresh-sign-in/reload dialogue protection and final browser integration remain. |
| L02 | Normal-owner bank scheduler retirement | complete | Complete local normal-owner143 acceptance: populated history/adversarial rollback, separate postcommit observation/final verification71.034822seconds,6 canary+9 verification races,32 role/immutability checks, source reapply and current inactive canonical readback. Original productionX02 hosted acceptance remains open. |
| L03 | Admin session isolation | in_progress | Retained focused Auth/read/expiry acceptance and actual17 SQL read receipts remain. Current protected-SMS permission A-to-B-to-A and explicit paging recovery pass7 tests with clean scoped analysis. Full same-session loading/role/capability/revocation coverage across every provider and dialog, including roster, remains. |
| L04 | Operation acknowledgements | in_progress | Strict actor/record/read contracts and149 transfer/commit receipts are verified in scoped SQL/Dart packets. Full operation-specific request/ACK/session/audit matrix and final-source aggregate acceptance remain. |
| L05 | Complete Admin route/action matrix | in_progress | Current route inventory declares25 Admin routes. Sensitive SMS and paging corrections pass their7-test packet; expanded aggregate matrices retain unresolved coverage and fixture findings. Complete route/action/state/permission/session/audit integration, including new navigation and shadow history, remains. |
| L06 | Uncertain OTP recovery | complete | Corrected145 source;56 SQL rollback +9 v2-upgrade checks and6 real races; current signed-OTP handler in304 unit tests and actual71 frozen HTTP checks, with ambiguous outcomes never blind resent. |
| L07 | Error redaction | in_progress | Scoped Admin redaction and current frozen Edge HTTP/unit checks pass at their captures. Full client/Edge/log/export negative coverage and final-source binding remain. |
| L08 | Local role and cross-group authorization | pending | 150 health access passes6 actual revocation races;149 roster recovery passes stale-snapshot session/approval/role/permission revocation in both directions within the36-scenario packet. Full local role, cross-group, raw-SMS, effective grants/RLS and final-definition negative matrix remains. |
| L09 | Full upload decoding safety | complete | 32 real Linux codec/auth/resource cases and actual signed adapter integrations coverPNG/JPEG/WebP/PDF/XLSX, malformed/spoofed/polyglot/animation/page/expansion limits and process sandbox. |
| L10 | Durable concurrent upload/extraction limits | complete | 146 normal-owner apply plus29 assertions and7 real two-session races, exact143-table restore; HTTP/handler budget ACK/replay/ambiguity tests, signed receipts before vendor work. |
| L11 | Trusted XLSX transformation | complete | Original bounded workbook bytes verified against derived TSV; substituted client TSV rejected; actual146-to142-to144 compatibility and signed decoder handler integrations. |
| L12 | Import/export and sensitive-action protection | pending | Test formula injection, row/resource bounds, data minimization, redaction, permission denial, accountable reasons and durable import/export/reveal/grant/retry audit. |
| L13 | Multilingual/adversarial evaluation tooling | complete | Labeled multilingual/scanned/malformed/duplicate/ambiguous/prompt-injection corpus;155 deterministic/response/evaluation checks,5 labeled deterministic measurements and3 contract probes. Live-provider accuracy remains explicitly unmeasured. |
| L14 | Generated-dataset query benchmarks | pending | Benchmark realistic generated volumes, all sorts/scopes/page depths and concurrent paging. Correct ordering, excessive scanning, whole-history reconstruction, aggregation growth and queue-shrink behavior. |
| L15 | Identity/totals/money/ID/date correctness | pending | Audit every consumer and modern/legacy RPC/cache/input path for immutable identity, collision/forgery denial, complete versus partial/absent/stale/zero totals, exact integer bounds, aliases, IDs and valid calendar/timezone behavior. |
| L16 | Cache/reconnect/session isolation | in_progress | Sticky session/read/expiry corrections and scoped SDK tests implemented. Full missed/duplicate-event, offline/reconnect/revocation/private-cache matrix and final-source acceptance remain. |
| L17 | Shared Revolut interface corrections | in_progress | Declared compact/shared correction is verified by120 widget tests,11 clean analyzer inputs and25 actual Chrome cases/205 assertions; 320x568 at1x/2x plus390x1x inspected. Prior-source whole-word negative reproduced. Remaining unsampled applicable local surface/state coverage and final integrated source bind remain. |
| L18 | Actual local browser/PWA lifecycle | in_progress | Prior actual normal browser/PWA37-check/16-case packet remains dated. Current memory-only Auth/fork and149 recovery require new normal multi-tab/reload/offline/logout/current-artifact acceptance. |
| L19 | Redacted financial/receipt/push observability | in_progress | 148 telemetry and150 authority correction are installed. Current150 acceptance passes180 alert assertions,5 metric-writer cases with4 blocking races and6 health-authority races; each restores all149 tables/catalog/cron. Retained39 health UI tests and76 HTTP/309 Edge checks remain scoped. Realistic performance, operator-response rehearsal and final interface integration remain. |
| L20 | Mutable settings/copy governance | in_progress | Corrected147 installed and source-bound:26 control families,110 actual SQL checks and11 blocking races. Retained client gate205 tests and notification recovery UI6 tests pass. Dynamic-control inventory, all consumer/audit coverage and current final integration remain. |
| L21 | Proven asset/code/dependency cleanup | in_progress | Current seven Public previews were captured, visually reviewed and published with preserved originals and exact source bindings. Subsequent authorized Admin safety corrections will require a new final bind; final reachability/dependency closure remains. |
| L22 | Locks/inventory/SBOM/build hygiene | in_progress | Retained export evidence proves unsigned Android production APK/lint/JVM acceptance and complete unsigned arm64 iOS compilation. The Firebase scene callback correction compiles in the complete app. The native provenance collector now covers Admin/local forks and passes7 mutation tests/111 assertions. These exports retain explicit live-checkout drift; final-source formatting/analysis/native/media/inventory/SBOM bind remains. |
| L23 | Final-set integrated local verification | in_progress | Exact quiet installed150 registry/149 tables and reviewed149/150 source matches are verified. Current source inventory and staged versions are recorded separately; navigation/shadow remain uninstalled. Last complete clean replay remains141. Final clean/populated/compatibility/full-suite/concurrency/mutation acceptance remains. |
| L24 | Bound evidence and handover register | in_progress | Every original24 local and102 production acceptance criterion is preserved. This revision binds14 newer scoped packets, a fresh150 readback, dynamic source/staged inventory and hashes of all five prior registers. One final source snapshot and complete handover remain pending. |

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
