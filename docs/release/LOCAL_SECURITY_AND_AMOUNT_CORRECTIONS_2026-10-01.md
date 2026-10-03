# Collect local security and amount corrections

## Scope and current status

The local implementation program remains **6 closed / 18 open**. The original
102 production criteria retain their original scope. These results establish
specific local implementation mechanics; they do not close the full program.

The restored shared QA database contains **154 migrations / 153 tables**. Its
normal `postgres` owner is not a superuser, cron launch is disabled, network
worker batch size is zero, and all application/Auth/migration rows and cron
jobs/history matched their preserved fingerprints after restoration. No staged
migration was installed into that shared database.

Eighteen newer migrations were applied to a unique disposable schema/ACL clone with
real synthetic member requests. The current combined test passed **56 assertions**,
preserved the two original pending requests and ten financial/delivery table
families at every migration, and verified the exact **21** new private tables
have RLS enabled with direct API DML denied. The clone was removed and all 153
shared tables, stronger catalog controls and cron evidence were preserved.

Evidence:

- [Current18 combined staged bundle with exact column ACL restoration](local-database-runtime-2026-09-30/staged-bundle154-attempt12-current18-cancel-integration/result.json),
  SHA-256 `07795cb27714975e25e19e70b5724b77763b959fc9352229d13753c83c798f9b`.
- [QA restoration readback](local-database-runtime-2026-09-30/local-qa-recovery-readback/restore-readback-attempt1.json).

This is a populated synthetic upgrade subset. A complete clean replay,
populated predecessor replay, compatibility rehearsal and final common source
verification remain separate acceptance requirements.

## Corrections and why they are required

| Correction | Observed problem and implementation | Required rationale and remaining acceptance |
| --- | --- | --- |
| Current Admin authority | `20260930233000_sensitive_admin_authority.sql` locks current session, account, approval, role and permission evidence for sensitive RPCs. Its RLS eligibility preserves the email/transition policy and rejects established non-Read-Committed snapshots with `40001`. | Committed revocation must prevent later sensitive access, including reads through RLS. An old transaction snapshot cannot preserve revoked rights. The dated two-migration test passed 19 cases with nine positive controls; the full current bundle and complete role/cross-group matrix require their own evidence. |
| Transitive Admin read volatility | The same additive migration explicitly marks 62 reviewed transitive readers VOLATILE while retaining their bodies and ACLs. Catalog comparisons preserve routine identities, results, defaults, owners and unrelated bodies. | Functions that depend on current authority locks must execute with an appropriate writable transaction and fresh statement visibility. The change is restricted to reviewed readers; it is not a blanket modification of every routine. |
| Sensitive reasons and audit | Current16 probes reproduced BOM-only reasons authorizing raw-SMS reveal and notification retry, plus untrimmed Unicode audit padding:122 passes/four failures. Additive235700 changes exactly two reason initializers to the private235500 normalizer, retaining original1..1000 bounds, authority, locks, API attributes, audit, retry and ACK behavior. | Private access and retries require a visible, bounded reason. The correction passes127 candidate checks and eight actual blocking authority races, including all26 whitespace codepoints and canonical stored audit reasons. Full current import/export/resource and action coverage remains. |
| Exact contribution requests and collection amounts | Installed154 accepted `9007199254740992` and bigint maximum as numeric JSON request amounts. `20260930234000_exact_request_amounts.sql` rejects unsafe requests before request mutation and validates upper-bound constraints on expected, target and suggested amounts. | Native and browser consumers share an exact numeric wire contract. An unrestricted positive bigint receipt can be rejected or rounded by that contract. The bound is transport precision, not a provider payment limit. Existing unsafe data aborts the migration atomically; no value is clamped, rounded or rewritten. Positive posted history, complete aggregates and every consumer still need verification. |
| Exact posted receipts and aggregate history | Actual synthetic maker/checker/service-finalizer calls admitted an unsafe posted amount and produced unsafe complete-history totals. Additive `20260930235000_exact_receipt_history_amounts.sql` validates posted amounts and numeric aggregates before conversion or JSON serialization. | Individual exact amounts can still sum to an inexact JSON total. The four-body candidate passes65 genuine positive-history/catalog checks; the current13-stage integration passes67. Both use69 real synthetic maker/checker/service-finalizer postings with triggers intact. Current18 integration and final consumer coverage remain separate. |
| Accountable email-action reasons | Actual approval, revocation and cutover RPCs accepted whitespace-only reasons in nine probes. `20260930235500_operator_reason_whitespace.sql` normalizes explicit native/browser whitespace before existing8..500 bounds and audit storage. | An accountable action cannot be justified by invisible whitespace. The current13-stage test passes133 checks, including26 whitespace codepoints, short visible reasons padded with Unicode, exact ACKs and canonical stored audit reasons. It proves exactly three existing routine bodies change while signatures, defaults, results, owners, ACLs and unrelated routines are preserved. It does not close all sensitive-action coverage. |
| Runtime-control reasons | Actual changing updates across all26 families accepted invisible reasons:575 passes/52 failures. Additive235600 normalizes the reason before existing8..500 bounds and audit hashing, preserving family/identity/parent/revision/publication/ACK/no-op rules. | Invisible padding must not satisfy minimum reason length. The correction passes1330 checks, including all26 whitespace codepoints, canonical hashes, permission/session/approval/role denial and exact current actor/session audits. Catalog comparison proves only the updater body changed; consumer-wide and concurrency acceptance remain. |
| Staged migration integration | The18-migration clone verifies current email, receipts, Gateway, exception v1/v2, shadow supervisor and absent unstarted-receipt action reads, pending request replay and exact amount rejection together. | Individually passing migrations can disagree about authority or schema. All21 private tables have RLS/no direct API DML. These empty/absent smoke controls do not prove real cancellation/dispatch, signed supervisor authentication, source completeness or whole-system acceptance. |

The email direction is retained. The exact-email request/approval policy belongs
to the current operator implementation. Member MoMo identity checks retain their
existing product meaning; changing operator login does not authorize changing a
member's payer identity contract.

## Dated candidate evidence

- [Current18 RLS revocation packet](import-export-protection-2026-10-01/admin-rls-current18-attempt1/result.json):
  19 passes/nine positive controls; all established snapshots are refused with40001
  after committed grant/session/approval revocation in legacy transition, email
  transition and email cutover cohorts. The clone is removed and shared evidence
  is unchanged. SHA-256 `af012213137cfb88dfbfb617ae43283ce370d1f2ea807cdbf639f7284f61071c`.
- [Current16 sensitive reason reproduction](import-export-protection-2026-10-01/sensitive-current16-unicode-attempt1/result.json):
  122 passes/four failures. Only BOM-only rejection and canonical audit trimming
  fail for each action. Every unexpected success rolls back; all shared rows,
  catalog/cron evidence and recorder bytes are preserved.
- [Sensitive reason correction](import-export-protection-2026-10-01/sensitive-current16-unicode-attempt2-candidate/result.json):
  127 passes/eight observed blocking authority races; exactly reveal/retry bodies
  change, with every signature/default/result/owner/ACL/attribute and unrelated
  routine preserved. SHA-256 `56c51ec4327b4f780f678ef16ab782f88bcc03a87593643cd16b1ec6313524a2`.
- [Runtime reason reproduction](runtime-controls-2026-10-01/full26-current13-attempt1/result.json):
  575 passes/52 failures from invisible reasons across all26 actual changing
  family updates, with every probe rolled back and shared evidence preserved.
- [Runtime reason correction](runtime-controls-2026-10-01/full26-current13-attempt2-reason-candidate/result.json):
  1330 passes; only the updater body changes. Byte-identical235600 is now a source
  migration, and the ordinary-owner current18 bundle applies it successfully.
  This packet does not prove blocking races or every client consumer.
- [Genuine posted-history candidate](data-correctness-2026-09-30/sql154-positive-history-attempt5-candidate235000/result.json):
  65 passes, SHA-256 `4ba0576df7222c21e315d39adc85cf7deb02fdec395afd5b1df8d5922259763d`.
  Exhaustive catalog/column ACL comparison and unsafe-POSTED atomic abort retain
  the original four API bodies except reviewed exact-numeric enforcement.
- [Genuine posted-history current13 integration](data-correctness-2026-09-30/sql154-positive-history-attempt6-full-current167/result.json):
  67 passes, SHA-256 `b7cf118a6db0bfb3e62af5135d74ea379dfbddaa83b8215acad8d006d193075a`.
  Both history packets preserve shared153 tables/catalog/cron and remove both
  disposable clones; neither is promoted to current18 acceptance.
- [RLS revocation packet](import-export-protection-2026-09-30/admin-rls154-attempt3-email-integration/result.json):
  19 cases / nine positive controls; candidate233000 with the captured earlier
  email213000 source. This is not final current-bundle evidence.
- [Sensitive authority packet](import-export-protection-2026-09-30/admin-sensitive154-attempt3-rls-audit-effects/result.json):
  71 cases / eight actual blocking authority races. Raw-body column ACLs are
  denied, while authenticated audit DELETE is allowed to execute but removes
  zero rows under RLS. Protection is established by actual effects, not an
  assumed SQL error code.
- [Installed amount defect](data-correctness-2026-09-30/sql154-attempt2/result.json):
  55 passes / two unsafe amount failures, retained as prior evidence.
- [Exact amount candidate](data-correctness-2026-09-30/sql154-attempt4-candidate234000/result.json):
  80 passes, API preservation and three unsafe-data atomic aborts. Candidate
  applied only to the disposable clone; shared154 was unchanged.

Earlier failed attempts remain available. They include malformed harness SQL,
SQL-null decoding and an incorrect expectation that RLS-protected audit DELETE
must raise an ACL error. Those failures required harness corrections and do not
establish additional runtime defects. The staged bundle's second attempt also
retains an incorrect hardcoded table count of14; its captured catalog proves13
protected tables. The corrected third attempt checks their exact identities.

The current13-stage rehearsal additionally restores the exact two notification
permission catalog rows from baseline migration
`20260815062536_complete_admin_operations_control_plane.sql` before staged
navigation installation. A schema-only clone omits those seeded rows: attempt5
therefore failed the navigation foreign key, while the production migration
remained unchanged. The fixture grants no actor authority and copies no source
rows. The baseline source is pinned to SHA-256
`33116a8b778fe7fefdb22e41885796c250c79e6718299a4eae605e9f5b1804f5`.

Current18 also restores the exact original payments.read reference row from
baseline `202605230008_admin_panel.sql`, SHA-256
`cd579d24bc9b092fff80476533e1242bf99439e281931485f6504444a31af783`.
Attempt9 retained a23503 failure because schema-only capture omitted that row.
The correction restores catalog fixtures and grants no actor authority; migration003
remains unchanged. Attempts8 and11 retained fail-closed inventory checks as new
peer migrations arrived. Current18 covers every captured uninstalled source and
checks that no unreviewed source appears before completion.

The exhaustive source-to-clone catalog comparison found an actual recorder gap:
`pg_dump --no-privileges` omitted selected-column ACLs, and the old clone helper
reconstructed only schema, relation and routine grants. The corrected helper
also reconstructs explicit API/PUBLIC column grants and original grant options.
The shared database grants were unchanged. The recorder now includes `attacl`
in its column fingerprint; older packets do not retroactively cover that field.

[Exact column-ACL acceptance](local-schema-acl-correction-2026-10-01/attempt3-exact-contracts/result.json)
passes seven checks across all1,631 columns, including29 with explicit API grants.
Actual anonymous/authenticated SQL reads permit the intended profile columns
while denying raw SMS with42501. The earlier test's guessed minimum30 was
corrected to the actual required column identities; its failing packet remains.
Both the current bundle and column test removed their clones and preserved all
shared rows, stronger catalog controls, cron evidence and recorder sources.

[Current email-action acceptance](import-export-protection-2026-09-30/email-action-bounds154-attempt2-current13-unicode-catalog/result.json)
has133 passes, SHA-256
`517a00009323f53be542eef726659443eb84b188540694592c3e9ff0cd169f1a`.
Every action probe rolls back. The helper is unavailable to API/PUBLIC callers;
the clone is removed and the shared source and staged inputs remain unchanged.

Additional retained observations:

- [Positive history defect packet](data-correctness-2026-09-30/sql154-positive-history-attempt2/result.json)
  has39 passes/four failures. Three failures concern real unsafe individual or
  aggregate money behavior; the fourth expected an empty balance array where
  the actual API returns an explicit zero-RWF row. Only that expectation was
  corrected in the harness. All69 baseline fixture payments were posted through
  the real maker/checker/finalizer chain with production triggers intact.
- [Prior email-action bounds](import-export-protection-2026-09-30/email-action-bounds154-attempt1-prior-nine/result.json)
  has34 passes/nine whitespace-reason failures. Every probe was rolled back.
- Stage attempt4 retains a generated235000 candidate missing four outer SQL
  terminators. The candidate correction adds those terminators without changing
  its four function bodies. The13-stage attempt6 subsequently applied it as an
  ordinary clone owner.
- The reviewed current exception-source refresh orders batch UUIDs before
  acquiring source locks. This preserves the existing source/action contract
  while giving concurrent batches a consistent lock order. Its own batch/race
  acceptance belongs to the exception implementation owner.

## QA recovery and diagnostic exposure

The Docker engine interruption stopped the QA container with exit137. Its
existing container and persisted data were restored without recreation or
reset. Persisted cron/network quiet settings were inspected before startup and
revalidated after readiness. The stronger restored catalog fingerprint is
`e00dd6fe9c852535bcc31438b0ef34c127e8e033d2319d484da2c1a59c178823`.

A prior container diagnostic exposed a QA encryption bootstrap key in tool
output. The [exposure record](local-database-runtime-2026-09-30/local-qa-recovery-readback/bootstrap-exposure.json)
retains only its hash and records that replacement is incomplete. The actual
key is not copied into this report. Restoration and row-integrity checks do not
establish that the exposed bootstrap key has been replaced.

## Completion requirements still open

Complete the current-bundle authorization and RLS checks; genuine synthetic
reconciliation/history mechanics and exact aggregate boundaries; current client
and normal-browser acceptance; the full current clean/populated migration and
compatibility rehearsals; and one reproducible final source/build/test package.
Retain every failure and source drift. Do not use any scoped candidate pass as a
whole-item or whole-program closure.
