# Platform Admin WhatsApp pre-approval — corrected scope

**3 September cutover update:** the reviewed migration is now deployed. The
exact owner-selected existing Collect ID 965511 is approved and activated;
independent readback confirms one active approval. A fresh WhatsApp sign-in is
still required. No other operator or group role was changed. Statements below
about local-only implementation are historical; see
[production cutover](PRODUCTION_CUTOVER_2026-09-03.md).

Status: group controls and platform-only WhatsApp approval are implemented and tested locally as separate contracts. The owner authorizes Supabase deployment work and has selected the first platform Admin identity. The selected account was verified read-only; its database approval/role activation and the recovery/client-transition gates remain open. No production approvals or roles changed.

## First-operator selection, 2 September 2026

The owner supplied the approved first platform Admin WhatsApp number in the
private task conversation. The 2026-09-02T16:20:26Z read-only Management API
lookup in COOL matched exactly one existing Auth account: Collect ID **965511**,
phone ending **8248**. Auth marks the phone confirmed; the account has a profile
and is not deleted, banned or anonymous. It does not currently hold the combined
platform Admin role, and the new approval schema is not deployed.

This resolves human selection of the first operator, not database activation.
Re-resolve and recheck the exact conversation-supplied number at execution time;
do not embed it in migration SQL, client code or public release evidence. After
the recovery/client-transition checks, use the controlled service-only approval
and role-bootstrap steps below, followed by a new WhatsApp sign-in. Do not
approve any other existing operator by inference. Group roles are unaffected.

The number-only reply did not authorize the separately requested production
backup export. No account creation, OTP send, verification override, approval,
role grant or production migration occurred during this identity check.

## Confirmed decision

On 2 September 2026 the owner clarified that **group admins do not require pre-approved WhatsApp numbers; anyone can create a group**. WhatsApp pre-approval applies to **platform Admin operators only**. An ordinary group owner/admin must not inherit platform Admin access.

| Context | Eligibility / authority |
| --- | --- |
| Group creation | Ordinary signed-in member; no platform Admin phone approval. Existing private-group/device/consent checks are unchanged. |
| Group ownership/admin | Separate group-scoped role; no platform Admin phone approval. Owner Add admin control uses a member Collect ID. |
| Platform Admin panel | Pre-approved verified WhatsApp identity; group ownership or membership does not confer this access. |

## Correction and remaining defects

The previous removal of the member Add admin control and its phone-preapproval error were based on the assistant's incorrect interpretation. Both are corrected. Prior evidence T123/T124 and manifest 52 are retained as historical tests of that wrong assumption, not product acceptance.

The original `create_collection_invite` backend was retired. Its replacement is `add_group_admin(collection, member_public_id)`: the current owner of a non-archived private group may promote an existing active member by six-digit Collect ID. This is a direct, audited group-role assignment, not an invitation or account creation. Outsiders, invited/left/removed members, group-admin callers, non-owner platform operators and sponsored/public groups cannot use it. Global account existence is not disclosed. Retries do not duplicate grants/audit events; actual overlapping transfer/archive/removal tests prove authority and membership are rechecked. Ownership, receiver, profile and platform grants remain unchanged.

The app verifies an exact four-field server receipt before showing success, then invalidates its roster. Malformed/failed responses and sign-out during the request cannot produce optimistic success. Fixture UI tests exercise the real local roster mutation, not a no-op. The new migration remains undeployed; the signed-in production-connected preview cannot use it yet.

## Implemented platform-only candidate

Migration `20260902140151_platform_admin_whatsapp_approval.sql` stores approvals in the non-exposed, RLS-protected `collect_admin_access` schema. It accepts only an existing Auth account's confirmed canonical international phone, not profile/MoMo fields or JWT user metadata. There is no anonymous approval-list lookup or account creation.

An approved current platform Admin, with an audit reason, can approve another verified identity, activate its combined Admin role, or revoke approval/access. Approval alone creates no role. Both approval and role activation require a subsequent Auth session; revocation, expiration, banned/deleted identity, changed phone, missing/expired session, or a session belonging to another user fail closed. Reactivation cannot revive an old session. Privileged mutations serialize and recheck the caller after waiting; an already-running request is not claimed to be retroactively cancelled.

The member/group role system is unchanged. The ordinary-member group lifecycle, contribution journey, and owner-only Add admin contract pass against the hardened platform sandbox without approving the member accounts. Only the synthetic platform-operator fixture receives the separate approval/session prerequisites.

Admin user details now provide separate approval and activation controls, audited confirmation, disabled pending actions, self-change protection, failed-response handling and authoritative state refresh. Only `admin_users` permissions expose these controls; they are not member-profile or group-management UI. Lists distinguish approval-required, awaiting activation, active and revoked access. The retired two-argument list overload is removed because it caused PostgREST HTTP 300; the retained paginated signature's defaults support the same older two-argument request.

## Rollout prerequisites — not executed

**This migration intentionally pre-approves nobody.** Applying it without an explicitly approved first-operator procedure will deny existing platform operators. It must not be deployed as an unattended generic migration batch.

1. Confirm exact production account UUID, verified international WhatsApp number, combined role and approval reason through the authorized private channel. Never put the raw number in public release evidence.
2. After approved recovery/compatibility checks, apply the reviewed candidate in the controlled release window.
3. Use the service-only `admin_bootstrap_whatsapp_approval` for the reviewed first operator, then `admin_bootstrap_platform_owner` if its role needs creation. Approval bootstrap refuses when a valid approved Admin already exists. Browser bootstrap remains inaccessible. These steps are not permission to provision a real operator now.
4. Complete a **new** WhatsApp sign-in. An existing session or token refresh is deliberately insufficient after approval or reactivation.
5. Verify deny/allow and current identity on the deployed API. A second operator must be separately approved and activated before independent maker/checker acceptance. Test revocation with an old JWT under specific authorization.

## Acceptance checklist

- Store platform approval in protected server-owned records. Do not embed the number list in the app or expose an anonymous eligibility lookup. Never require these records for group creation or group-admin eligibility.
- Match canonical country-code-qualified WhatsApp identity verified by Auth, not editable profile country, MoMo number, client input or user-editable metadata.
- Require an authorized platform approver and an audited reason; reject member/group-admin attempts to approve platform access.
- Recheck current approval on privileged operations; expired/revoked approval and stale sessions must not retain effective admin access.
- Review platform activation/reactivation and bootstrap. Separately verify that group creation, group-admin roles, ownership transfer and former-owner retention cannot confer platform permissions; do not apply platform approval requirements to those group actions.
- Test approved/unapproved/mismatched numbers, wrong approver, anonymous/member/group-admin callers, revocation, concurrent grant/revoke and direct API bypass. Use synthetic local records; no provider messages or real role grants.
- Verify the approval-management UI and signed-in deployed deny/allow paths only after explicit rollout authorization.

The platform login still requests OTP without creating users. The new server gate, not a client-side number list, decides platform eligibility. Real WhatsApp delivery, deployed session/provider behavior, signed-in browser acceptance and human operator approval remain open.

## Evidence boundaries

Corrected tests and screen captures are recorded after T124 in the current UAT packet. The subsequent API repair is T127 onward. A rollback-only local SQL journey verifies an ordinary account without platform Admin roles creates a group and becomes owner without acquiring platform access. Local SQL, real local PostgREST and overlapping-transaction tests verify the new admin assignment. Only the explicit disposable database `collect_uat_20260902` received this migration; older native/web artifacts in manifests 50/51 predate the change. No production schema/roles, existing browser preview, installed simulator app or deployment changed.

Platform continuation: 54 rollback SQL assertions, four verified overlapping transaction scenarios, 29 local HTTP checks, 39 focused Flutter tests and 552 full-suite tests pass. Analysis is clean. Real-font 390/1184px and 1x/2x UI captures were inspected. The exact local schema-only baseline plus candidate was tested separately from the original/member databases. A scoped logical restore preserves five access-state tables and relevant functions, RLS, grants and ownership; restored approved, revoked and unapproved identities keep their correct access. This is same-cluster synthetic evidence, not a production financial/Storage/global-role restore.

The connector's earlier permission denial was resolved for authorized operations by the owner's Google Drive credential instruction. The new Management API readback confirms a healthy COOL project, 97 deployed migrations, one active platform role grant and no approval table. See the [hosted preflight](SUPABASE_ACCESS_AND_DEPLOYMENT_PREFLIGHT_2026-09-02.md). No production apply, number approval, role change, original preview replacement, commit/push or store action occurred.

The [Supabase RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security), [function privilege guidance](https://supabase.com/docs/guides/database/functions) and [session guidance](https://supabase.com/docs/guides/auth/sessions) inform these local controls. They do not certify deployed or provider acceptance.
