# Collect current-candidate rollout

Latest evidence: [3 September continuation](CONTINUATION_2026-09-03.md).
The actual production archives now pass isolated restore and all 14 pending
migrations pass against that restored copy. Temporary network access is removed.
Production migrations and operator activation have not been performed. The
immediate owner decision is the supported installed-client population at cutover;
the pending backup permission language below is historical and superseded.

The complete 111-migration local replay and 113-table synthetic restore now pass;
the latest production inventory is 97 deployed / 14 pending. Those results
supersede the older local-count limitations below, not the production recovery
or client-transition gates. Deployment work is authorized; a production recovery
copy is the immediate pending owner decision.

Status: **DEPLOYMENT WORK AUTHORIZED / RELEASE NO-GO**. The owner explicitly
authorized Google Drive credential retrieval and Supabase deployment/push work.
The verified recovery, platform-operator activation and client-transition gates
below remain unresolved. The owner has selected the first Admin identity; no
production mutation has occurred in this continuation.
See the [current hosted preflight](SUPABASE_ACCESS_AND_DEPLOYMENT_PREFLIGHT_2026-09-02.md).
This checklist supersedes interpreting a single migration's
"release before the app" comment as a complete installed-client rollout plan.

## Environment clarification

The owner confirms there is one hosted environment: production. The signed-in
app under review connects directly to that production Supabase project. There
has been no hosted staging deployment, and creating one is not a prerequisite
for this task.

The isolated local databases, fixture previews and simulator tests in this
packet are test tooling, not another deployed environment. They do not establish
that pending source changes are live: the last verified inventory still has 13
local migrations absent from production. Execute the authorized release against
the existing production project, with scoped changes and live readback. A backup
is a recovery copy of that same project, not a staging environment; the owner's
environment clarification does not itself authorize exporting production data.

## Verified baseline and candidate

- Source: dirty working tree at `40620f10ffbde3bcbd6a53cc0f493de6e948cc73`.
  Existing user work is preserved. No reviewed release commit exists yet.
- Target: COOL, Supabase project `lhbowpbcpwoiparwnwgt`. Google Drive-sourced
  credentials restored authorized Management API access. The read-only capture
  started at 2026-09-02T16:16:47Z confirms 97 migrations, a healthy project, nine
  active expected functions and 13 pending local migration files. Its backup
  inventory is empty and PITR disabled. Re-read before the eventual apply.
- Local member candidate: 107 migrations, including the additive group-admin
  contract `20260902134420_member_add_group_admin.sql`. The earlier 106-migration
  candidate passed clean bootstrap and full logical restore. The new additive
  migration passes isolated upgrade and SQL/API/concurrency regression; those
  older full-bootstrap/restore artifacts do not certify the 107th migration.
  Separate hybrid receipt/member-registry candidate files were not applied to
  this member UAT database and require their own rollout evidence.
- Member web and iOS simulator builds compile; these are not configured/signed
  production artifacts. The separate port-4176 fixture preview predates the
  latest pagination changes. Current store artifacts/approvals remain stale.
- Separate platform candidate `20260902140151_platform_admin_whatsapp_approval.sql`
  passes synthetic SQL, HTTP, concurrency, Flutter and scoped restore checks.
  It is applied only to explicit platform-access sandboxes cloned from the
  107-migration member schema. Those clones do not carry a new recorded application
  migration count. It pre-approves no real operator and requires the controlled
  first-operator procedure in `ADMIN_WHATSAPP_PREAPPROVAL_2026-09-02.md`.

## Compatibility decisions that must precede deployment

| Contract | Candidate behavior | Required acceptance |
| --- | --- | --- |
| Profile read/ensure | New nine-field `get_current_member_profile` / `ensure_current_member_profile`; old full-row endpoints denied | Installed builds must use the name-free allowlist. Do not restore private names for backward compatibility. |
| Profile update | New five-argument `update_current_member_profile`; old name-writing endpoint denied | Update/save/country-switch acceptance using the selected supported client. |
| History | Additive bounded `list_current_member_history_page` with revision-bound cursor, full aggregates and server search | Current client depends on this RPC at bootstrap. Publish matching backend before activating that client. Retained legacy history is not permission to rely on unbounded payloads forever. |
| Pending intents | Latest 50 plus complete pending count and exact-ID lookup | Old active intents must remain accessible by ID and total pending count must not be derived from 50 rows. |
| Groups/roles | Private owner archive/transfer and scoped roster fixed; owner-only `add_group_admin` promotes an active member directly by Collect ID with idempotent audit and strict response validation. Official groups remain centrally managed | Group creation and group admins require NO platform WhatsApp pre-approval. Ordinary members may create groups. Local SQL/HTTP/concurrency and UI acceptance passes; deploy matching additive API before enabling the client. No group role grants platform permissions. |
| Platform Admin | Separate protected WhatsApp approval, combined-role activation and fresh-session checks; list/status and approval controls aligned | Local candidate verified, not deployed. Applying it denies legacy unapproved operators. Exact first-operator approval/bootstrap and new sign-in must be authorized and coordinated. Retained paginated list defaults support two-argument callers without an ambiguous overload. |
| Offline cache | v4 preserves complete aggregates separately from cached rows; v2/v3 import sanitized | Test upgrade, sign-out, account switch, offline restore and downgrade on supported devices. A rollback must not present partial totals as complete. |
| Realtime | MoMo and bank invalidation areas subscribed; awaited refresh allows coalescing | Verify deployed event delivery and refreshed balances on two clients. A source subscription test is not delivery evidence. |

No enforced minimum-client-version facility was found in the current client or
migrations. Do not claim old versions are blocked or silently add a minimum
version without an approved policy and an actual enforced mechanism. A client
with the new profile/paging contract cannot be deployed against the current
97-migration backend. Applying the profile revocations while older clients are
still in use also has a known compatibility impact. A supported-version and
transition plan is therefore a prerequisite, not an after-the-fact check.

## Approval packet

The owner must approve the exact source/artifact and migration hashes, supported
versions/transition, intended users and environment, recovery owner and isolated
restore target, private backup scope/destination/retention and RPO/RTO. Separately
confirm canonical Collect Auth callback URLs and reviewed, effective legal copy.
Do not export customer data, change roles/configuration, publish policies, make
payments, send provider messages or submit to stores through this checklist.

## Controlled sequence after approval

1. Refresh target/schema/provider state read-only. Freeze the reviewed release
   source and generate a version-matched artifact/migration manifest. Confirm
   two independent approved human operators for maker/checker acceptance.
2. Capture and verify the approved recoverable production snapshot, including
   separately recoverable Storage bytes and platform configuration. Use the
   [recovery runbook](../RECOVERY_RUNBOOK.md); stop if recovery is unaccepted.
3. Validate the selected installed-client transition with the existing isolated
   local test tooling and old/new client contracts; do not wait for or provision
   a hosted staging environment. Test startup, upgrade, profile changes, both
   rails, former-member history, cache migration and rollback behavior. Coordinate
   the actual client/API cutover directly against the production target and
   verify its deployed behavior in step 5.
   The clean setup requires a trusted platform owner before public-group seed
   migration `20260901134820`; never copy the synthetic owner into production.
4. Obtain action-specific release approval. Apply only the reviewed migration
   set and verify schema-cache readiness by calling the new RPCs. The generic
   `scripts/supabase_deploy.sh` also deploys Edge Functions and can remove retired
   functions: it is broader than a migration-only action and must not be used
   under a narrower approval. Stop on unexpected pending migrations or errors.
5. Run approved authenticated readbacks for every changed response contract,
   denied role, currency balance, roster and owner action. Confirm version
   compatibility before activating the new client.
6. Release the approved current signed artifacts to the approved test audience.
   Complete physical Android/iOS, OTP/session, SMS/USSD, push, accessibility,
   network/concurrency and independent security acceptance. Financial/provider
   tests require exact approved accounts, recipient, amount and send limits.
7. Record evidence and independent owner/operator acceptance, monitoring and
   on-call ownership. Declare GO only when the release criteria actually pass;
   then obtain the separate phased-release/store-publication approval.

## Stop and rollback rules

Stop activation on incompatible RPCs, unexpected identities/currencies, missing
ledger entries, duplicate posting, unauthorized access, stale balances or a
failed recovery check. Keep successful evidence and reconcile any consequential
action before retrying. Do not treat a failed HTTP response as proof that a
payment or provider send did not happen.

Do not automatically run down migrations, restore over live production, remove
new contracts already used by clients, reopen legacy name exposures, or replay
financial queues. Prefer a reviewed forward fix or an explicitly approved
compatible client rollback. Destructive restore is an incident/recovery action
requiring a fresh decision, exact target and reconciliation plan.
