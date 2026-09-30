# Runtime controls governance — 30 September 2026

**Local SQL and repository client acceptance pass; settings UI acceptance remains separate.** Root installed corrected migration147, passed110 rollback checks and11 actual blocking races, and independently verified restoration of145 tables/catalog/cron. The worker's final client packet passes205 tests and scoped analysis with332 captured sources unchanged. These results do not claim hosted activation or provider accuracy. The earlier source gate is grammar/contract evidence only.

## Scope and actual baseline

The authoritative read-only baseline is `inventory146-attempt1/inventory.json`: 25 actual tables and 15 selected routine definitions. Its values are deliberately omitted. Migration 147 governs all those tables plus the declared `collection_category_subtypes` omitted from that selection: 26 families in `source-candidate/control-spec.json`.

| Controls | Write authority |
|---|---|
| Feature flags | Existing `feature_flags.manage` |
| Public brand, support, payment routes, system settings, Admin navigation/queues, notification copy and catalogue/legal copy | Existing `settings.manage` |
| SMS receipt collection policy | Existing `notifications.manage` and `collections.moderate` |
| SMS receipt member consent | Existing `notifications.manage` and `users.read` |
| OTP policy | `settings.manage` and `notifications.manage`; no new public/provider endpoint |
| Roster resource policy | `settings.manage` and `collections.moderate` |
| Notification preferences | Live session user owns only their own four boolean choices; no Admin override |

Private Vault/dispatch configuration remains provisioned through its existing owner-only routines. Public read getters preserve their original permission/product boundaries and real copy. Selected inventory alias gaps were resolved against source: `list_account_request_reasons`, `admin_set_member_sms_receipt_consent`, and signed OTP v3 are the actual APIs. No substitute routine is invented.

## Source implementation

Two private tables store current content fingerprints/revisions and immutable change events. Historical content rows are not updated at migration application. Baseline fingerprints create no change events. Heads/events have RLS and no API table grants. Changes store actor/session/authority, revision, changed field names, hashes and reason length/hash. They do not store or return reason plaintext or old/new values. Sensitive setting and user preference audit events additionally omit old/new content hashes. Sensitive setting reads omit values and content hashes; operator edits are rejected and remain owner-provisioned.

Every operator change uses exact expected-revision comparison, the existing live Auth session/shared gate, the existing Admin roster gate and effective permissions. Both grants and database guards deny direct old API writes. User preferences use the same revision/history machinery with user ownership and live session enforcement. Inputs have exact identity keys, typed/non-null rules, bounded strings/numbers/JSON depth/arrays, finite timestamps, writable-field allowlists and fixed redacted validation errors. Navigation/queue wiring and private quota singleton creation remain owner provisioning; their existing mutable copy is governed.

Published policy/template versions retain their original copy and published marker; archival is allowed without resurrection. Published policy sections cannot be edited, moved to another document, or deleted. Published template parent locale/event interpretation is frozen. New draft/version identities preserve prior published rows. Parent physical row fences also reject stale repeatable-read publication snapshots after section edits. Supported template placeholder syntax is checked without replacing copy or inventing context keys.

Active payment entrypoints require the current Rwanda/RWF MTN merchant41258 route, a bounded positive amount and matching metadata. Non-Rwanda catalogue activation and retired foreign/bank payment features fail closed. Existing inactive historical records remain present. Parser/schema and payment mode settings retain their supported values.

The same-value physical UPDATE fences in migrations145/146 continue to write PostgreSQL row versions. Their no-op path emits no configuration revision/change event. This is tested using the actual signed OTP v3 and roster resource reservation APIs, without transmission/provider calls.

## Frozen client contracts and required integration

`contracts/client-contract-v2.json` defines exact requests, ACK/read keys, version2, typed revision/identity/session binding, unchanged-save semantics and conflict handling.

1. Admin `admin_list_feature_flags` rows provide `extra.runtime_revision`; submit it to `admin_set_feature_flag_v2`. The old three-argument RPC refuses unversioned edits.
2. Member preference loading uses `get_notification_preferences_v2`; saving uses `set_notification_preferences_v2` with all four booleans and the exact loaded revision. Existing direct table upserts must migrate.
3. A malformed/missing/stale ACK cannot update local state. Retain the saved state and intended edit on a conflict; reload the current revision explicitly before retry. Do not silently rebase an overwrite or acknowledge another Auth session's reply.
4. Legacy SMS receipt setters similarly refuse missing expected versions; governed edits use `admin_update_runtime_control_v1`. No current app caller of those setters was found in the reviewed source. Existing historical SQL packets must retain their original version scope.

The worker integrated the feature-toggle and notification-preference repository clients against the frozen contract. `CLIENT-ACCEPTANCE.md` describes the exact source packet and public helpers. Root owns the settings-screen refresh, pending-edit review and explicit retry UI, with separate acceptance.

## Root-only local SQL acceptance

Root remains the sole database writer. Run the existing full-table/catalog recorder before and after apply/UAT/races, with a verified backup. The dedicated harness checks exact project `collect_fin_concurrency_qa_20260929`, Docker provenance, port55722, exact147 registry, disabled cron and outbound queue, fresh9973 fixture namespace, no delivery/device rows and an unused absolute checkpoint. It persists/fsyncs a pre-seed checkpoint. No fixture can select a hosted target.

Rollback UAT command shape (root supplies its existing exact fixture):

```sh
PGOPTIONS='-c collect.runtime_controls_qa=isolated_clone' psql ... -v ON_ERROR_STOP=1 -f scripts/tests/runtime_control_governance_uat.sql
```

Race command shape:

```sh
COLLECT_RUNTIME_CONTROLS_QA=isolated_clone \
COLLECT_RUNTIME_CONTROL_MIGRATION_SHA=<reviewed147SHA> \
COLLECT_RUNTIME_CONTROL_CHECKPOINT=<new-absolute-checkpoint-path> \
ruby scripts/tests/runtime_control_concurrency_uat.rb
```

The rollback packet checks all26 family grants/guards/fingerprint bindings, typed/null/bounds/secret/route rejection, exact ACKs, publication/version immutability, live preferences ownership and expiry, and unchanged quota fences. Its synthetic mutations all roll back.

The race packet uses two actual sessions and observes a lock wait for all11 scenarios: same expected configuration revision; stale repeatable-read configuration; publication before late section edit; draft edit before publication; stale repeatable-read publication after section edit; published template parent reinterpretation; same-user preference conflicting insert; actual146 quota fence; actual145 quota fence; effective Admin role revocation; Auth logout before preference edit.

The committed race fixtures have narrowly identified rows/XIDs and fail-closed restoration. It disables only the exact expected owned cleanup guards, removes scoped synthetic rows/events, restores original singleton/flag rows and heads, reenables the guards, and compares every captured application/Auth/Realtime/migration table plus columns/routines/grants/RLS/policies/triggers/constraints/cron before cleanup COMMIT. A mismatch rolls back cleanup, retains the checkpoint and reports failure. Sequence counters are not reset. Root's broader recorder remains an independent final preservation gate.

## Evidence and outstanding work

`source-candidate/source-validation-v4.json` records ten source/dependency hashes before/after, pglast7.7 grammar results and Ruby/guard results. Run with the task-owned Python:

```sh
.cache/roster-decoder-20260930/venv/bin/python scripts/tests/runtime_control_source_gate.py --output <new-source-receipt.json>
```

Root's actual147 packets are `uat147-rollback-attempt2` and `concurrency147-root-attempt2`:110 rollback checks and11 observed lock-wait races pass, all145 captured tables/catalog/cron restored, no workers left. Root preserved the initial installed source and failed rollback attempt: `(receipt->'value')` required parentheses in the preference-read JSON expression. Corrected147 SHA256 is `8029f6de3cd8618a32b6b68a1a312624b0a7d585a07c43056ecc5046dc345a1f`; the client contract is unchanged.

Remaining local work in this packet: settings-screen explicit refresh/review/discard/retry acceptance and the final aggregate current-source review after root's UI changes. The repository/feature integration gate is `client-runtime-attempt2`, with205 tests and clean analysis. Hosted activation, real provider results and production approval are outside this local packet.

The earlier f22e source candidate and source-validation receipt remain retained for review; neither was applied. The current v2 candidate adds explicit ownership checks at both generic RPCs and the trigger before any lookup/no-op, plus 18 generic cross-user negative checks across member, combined operator and platform-owner contexts, using identical errors for existing and absent target users.

Internal write contexts must have exactly seven typed fields with bounded numeric revision/reason length, exact family/identity/actor/session bindings and a SHA256 reason hash; malformed contexts reject before casts/head lookup. The rollback UAT temporarily grants one synthetic row an UPDATE policy and privilege (both rolled back) to exercise the real trigger against 15 malformed contexts.

Feature list row IDs use `md5(UTF8("collect.runtime-control.row.v1:feature_flags:" + immutable key))::uuid`. This is a deterministic presentation identifier namespace, never a security/content digest. Security and content fingerprints continue to use SHA256. Refreshes retain the same row UUID; saves remain bound to key and runtime revision.

## Root local SQL acceptance update

Migration147 was installed by the ordinary owner, preserving all143 prior tables and adding two private governance tables. Actual rollback UAT exposed a JSON operator precedence error in the preference reader; the failed transaction restored all145 tables. The root correction changed one parenthesized expression, kept function metadata and all other scoped catalog rows exact, and atomically bound the migration registry to corrected source `8029f6de3cd8618a32b6b68a1a312624b0a7d585a07c43056ecc5046dc345a1f`. Installed original source and failed run remain retained.

Corrected runtime acceptance:110 actual rollback assertions and11 observed blocking two-session races, exact145-table/catalog/cron restoration and no remaining workers. The first outer race launch failed before seeding because a scrubbed locale caused Ruby US-ASCII decoding; the fresh UTF-8 launch passed. See `sql-runtime-acceptance-attempt1/validation.json` and its exact operation packets. The local fixture subsequently advanced to148, with146 tables. Client integration and final corrected-source clean replay remain open; this SQL acceptance is not fullL20 or production acceptance.
