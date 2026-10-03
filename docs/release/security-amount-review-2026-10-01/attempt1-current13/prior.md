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

Nine newer migrations were applied to a unique disposable schema/ACL clone with
real synthetic member requests. The combined test passed **27 assertions**,
preserved the two original pending requests and ten financial/delivery table
families at every migration, and verified the exact **13** new private tables
have RLS enabled with direct API DML denied. The clone was removed and all 153
shared tables, stronger catalog controls and cron evidence were preserved.

Evidence:

- [Combined staged bundle](local-database-runtime-2026-09-30/staged-bundle154-attempt3-exact-private-tables/result.json),
  SHA-256 `bb9ca4fddfdb7c33651b52087edacd5a9f4639d5afe684e2c9a6bef4a3adf363`.
- [QA restoration readback](local-database-runtime-2026-09-30/local-qa-recovery-readback/restore-readback-attempt1.json).

This is a populated synthetic upgrade subset. A complete clean replay,
populated predecessor replay, compatibility rehearsal and final common source
verification remain separate acceptance requirements.

## Corrections and why they are required

| Correction | Observed problem and implementation | Required rationale and remaining acceptance |
| --- | --- | --- |
| Current Admin authority | `20260930233000_sensitive_admin_authority.sql` locks current session, account, approval, role and permission evidence for sensitive RPCs. Its RLS eligibility preserves the email/transition policy and rejects established non-Read-Committed snapshots with `40001`. | Committed revocation must prevent later sensitive access, including reads through RLS. An old transaction snapshot cannot preserve revoked rights. The dated two-migration test passed 19 cases with nine positive controls; the full current bundle and complete role/cross-group matrix require their own evidence. |
| Transitive Admin read volatility | The same additive migration explicitly marks 62 reviewed transitive readers VOLATILE while retaining their bodies and ACLs. Catalog comparisons preserve routine identities, results, defaults, owners and unrelated bodies. | Functions that depend on current authority locks must execute with an appropriate writable transaction and fresh statement visibility. The change is restricted to reviewed readers; it is not a blanket modification of every routine. |
| Sensitive reasons and audit | Raw-SMS reveal and notification retry trim and bound nonblank reasons to 1..1000 Unicode characters. Successful actions record the current actor and reason; denied actions do not create success or queue mutations. | Private-data access and retry actions require an accountable, bounded reason. Client validation alone cannot prevent whitespace or oversized reasons reaching SQL. The dated candidate packet passed 71 cases and eight observed PostgreSQL blocking races. Full current import/export/resource and action coverage remains. |
| Exact contribution requests and collection amounts | Installed154 accepted `9007199254740992` and bigint maximum as numeric JSON request amounts. `20260930234000_exact_request_amounts.sql` rejects unsafe requests before request mutation and validates upper-bound constraints on expected, target and suggested amounts. | Native and browser consumers share an exact numeric wire contract. An unrestricted positive bigint receipt can be rejected or rounded by that contract. The bound is transport precision, not a provider payment limit. Existing unsafe data aborts the migration atomically; no value is clamped, rounded or rewritten. Positive posted history, complete aggregates and every consumer still need verification. |
| Staged migration integration | The nine-migration clone verifies current email approval reads, receipt Overview, the transaction list, pending request replay and oversized request rejection together. | Individually passing migrations can overwrite authority or disagree about schema/response shapes when combined. This catches integration regressions before an installation or broad acceptance claim. |

The email direction is retained. The exact-email request/approval policy belongs
to the current operator implementation. Member MoMo identity checks retain their
existing product meaning; changing operator login does not authorize changing a
member's payer identity contract.

## Dated candidate evidence

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
