Task15 operational history is implemented in this private packet and ready for root review. No canonical file was written. Root alone promotes. `manifest.json` binds all37 proposed files and10 saved bases; `patches/existing-files.patch` contains only changes to existing files, while `promote/` contains the27 additive files and proposed modified files. All10 canonical modification paths still equal their saved bases at sealing. Preserve unrelated mixins and apply the patch after checking current bases rather than replacing shared files wholesale.

The closed read interface is:

| RPC | Scope | Cursor and bound |
| --- | --- | --- |
| `admin_list_receipt_operation_starts_v1` | retained begin requests, including refusals with no run | timestamp + request UUID,1..25, limit+1 |
| `admin_get_receipt_operation_run_v1` | one supported Rwandan run, original completion and reservation window | exact run UUID; partial/unavailable |
| `admin_list_receipt_operation_evidence_v1` | exactly `events`, `backlog_results`, `budget_refusals`, or `reservations` | timestamp + section-specific canonical ID,1..25, limit+1 in each branch before union/join |

Budget refusal identity is the complete canonical `requestUUID:snapshotUUID` with C collation and exact descending tie order. All cursor components are all-or-none. DTOs bind the echoed query, run, section, limit, identities, order and60-second sample window; nested values are immutable. RPCs authenticate twice through actual `collect_ops.actor(false)`: platform owner plus payments/notifications/system-health read. Reading requires no management permission. Audit links additionally require independent audit.read.

Events retain assignment/unprocessed, immutable per-run outcome, first durable handling and current mutable deferral as separate facts. A closed run can still retain deferred work. Historical caps come only from a single matching immutable configure revision whose recorded time precedes run start; absent/ambiguous old configuration remains unavailable. Original complete_run summary uses exact run/principal/fence and one retained matching original request; no arbitrary latest completion/config join. Lease is at most120 seconds and actual near-expiry principal fixture proves a shorter lease. Shared quota totals describe immutable reservations within the declared UTC-day/lease window, with device availability explicit.

The detail route is `/admin/automations/runs/:id`. Automations displays actual operational history. Actual automatic attempt cards navigate to operational runs. Supported source links use receipt IDs, `momo:raw_smsUUID` transaction identities and the actual scoped exception dialog. Existing `_AdminActionScope` protects captured link callbacks; new source/run links recheck sample expiry at click time. Stale samples hide identifiers/links. Full registered router deep link/reload is verified with the3 read permissions and no management/audit permission.

Joined operator audit now includes actual `collect_receipt_operations.owner_requests`, `enrollment_workflow_requests` and exact operational service requests, retaining separate source identities for repeated underlying/workflow request UUIDs. Policy and run kinds enforce the full operational read guard plus audit.read. Root expressly approved preserving preexisting supervisor_identity audit authority; its existing identity callers retain their original authority, and its newly joined enrollment lineage remains redacted. No producer/scanner/worker/transport definition, key, FK or journal is altered.

Existing modified paths:

- `contracts/collect-operator-entity-audit-v1.schema.json`
- `lib/admin/admin_router.dart`
- `lib/admin/core/admin_automatic_gateway_view.dart`
- `lib/admin/core/admin_automations_page.dart`
- `lib/admin/core/admin_entity_audit.dart`
- `lib/admin/core/admin_entity_audit_page.dart`
- `lib/admin/core/admin_receipt_repository.dart`
- `lib/admin/core/admin_repository_base.dart`
- `lib/admin/core/admin_runtime.dart`
- `test/admin_entity_audit_links_test.dart`

Additive source/test paths (plus19 actual fixture JSONs andSOURCE.json):

- `lib/admin/core/admin_receipt_operational_history_models.dart`
- `lib/admin/core/admin_receipt_operational_history_runtime.dart`
- `lib/admin/core/admin_receipt_operational_history_sdk.dart`
- `lib/admin/core/admin_receipt_operational_history_view.dart`
- `scripts/tests/admin_receipt_operational_history_test.dart`
- `supabase/migrations/20261002060000_admin_receipt_operational_history.sql`
- `test/admin_receipt_operational_history_test.dart`

Accepted proof is finite and source-bound:

- `proof/sql-attempt11/result.json`:44 passing checks,165 exact command receipts, SQL SHA `918a20bb19a8dca6b5de7701bd13f963c5fd25c65f0229bc7d5e13d82238eeff`. Fresh network-none/no-published-port target. Actual added DDL installs after demotion to NOSUPERUSER with explicit row-free platform-owner bootstrap and inherited installer roles recorded. All original producer bodies/owners/ACLs and operational/financial rows remain exact.
- Retained synthetic192 checkpoint SHA `0adc7a22e376e48cfc2e889fe17900697f617f9a5c2ddc5d0c22ad0c42b89e5a`, plus10 exact current additions:160,2330,2340,2350,2355,300,315,400,410,500, then600. Source bindings and complete exact inputs are retained. This reuses the selected setup from the accepted terminal-source-projection packet and ordinary-current201 rehearsal. It does not attest complete203 replay,420 or private430/700 coverage.
- `proof/decoder-accepted.log`:40 actual-fixture/strict DTO/SDK checks, including immutable quota refusals with supported exceptions, mutable deferrals, original snapshot reservation, exact tied composite pages and frozen nested historical caps. `proof/analyze-decoder-accepted.log` has no issues.
- `proof/flutter-fresh-links-attempt1.log`:39 passing tests =22 new history caller tests +17 existing automatic receipt/device tests, after the final click-time freshness guard. `proof/flutter-final-route-closure-attempt1.log` additionally contains44 passing joined audit link tests and the earlier20 history tests.
- Other affected consumer verification is retained without giant reruns: ten-file closure attempt1 passed250 tests and failed44 solely on absent files in the private validation copy; copied exact retained fixtures repaired these. Attempt2 rechecked51 audit DTO +33 audit page cases (84 pass;43 link fixture failures retained). Final joined-route closure repaired all44 link cases. Automations, telemetry, real SDK repository and independent audit authority tests passed in attempt1 and were not changed afterward. Repeated counts are not added as independent coverage.
- `proof/analyze-final.log`: no issues across all affected Admin source files, explicitly including part files and caller tests. `proof/revolut-authority-final.log` andJSON: required make hygiene and selected skill revision verification pass. Existing shared theme/components adapt the selected Revolut Business/operator references. Full visual comparator/route-state fidelity is unverified.

All SQL attempts1..11, input bindings, commands/stdout/stderr and failures are retained. All11 owned Docker targets were removed, as each receipt confirms. The inherited helper target metadata refers to the schema-only checkpoint/bootstrap normalization; application DDL installation is separately proved NOSUPERUSER and inherited roles are explicitly recorded.

Declared fixture limits: trusted-edge Auth claims are synthetic, JWT and vault crypto verification are not proved; no provider SMS, hosted, device, store or deployment action occurred. The normal producer enrollment API requires at least10 minutes expiry, so the shorter lease uses an explicitly declared installer-only immutable identity near-expiry fixture before invoking the actual begin producer. Missing old config and timestamp ties use explicit rollback-only retained evidence fixtures; ordinary run/events/results/refusals are from actual supported producer/API calls. Test doubles only present those retained DTOs; adversarial decoder mutations are labelled boundary tests.

Retain the preexisting producer limitation as open task06/18: later reconciliation can select an already globally reserved backlog snapshot and raise `operations_budget_conflict`. Original snapshot reservation/run anchors remain untouched. The refusal rolls back, leaving no immutable request/refusal row to read. Failed real calls remain in `proof/sql-attempt5/commands/00115.stderr` and attempt6/00117.stderr with their exact inputs.600 shows the original retained snapshot reservation and explicitly states unavailable rolled-back refusal history; it does not claim reconciliation recovery or deferred completion.

Root review/promotion, combined later source graph admission and external release/design acceptance remain outstanding. This packet makes no complete candidate or full visual claim.
