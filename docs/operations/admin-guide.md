# Admin Operations Guide

The admin app is an operational surface for authorized users. It must never be treated as the authorization layer. Supabase RLS, RPCs, and Edge Functions enforce permissions.

## Daily checks

- Review operational health dashboard for Edge Function failures, OTP issues, MoMo SMS parsing backlog, and rate-limit spikes.
- Review manual review queues for ambiguous payment evidence and stale allocations.
- Review audit logs for role changes, payment status changes, app config edits, campaign approvals, and denied access spikes.
- Confirm no support workflow requires service-role credentials in a browser.

## User and role operations

- Assign roles only through approved admin flows backed by role assignment tables/RPCs.
- Scope bank/admin roles to the smallest partner, custodian, group, or tenant boundary possible.
- Record reason and ticket/reference for privileged role changes.
- Remove roles immediately when access is no longer needed.

## Payment and MoMo operations

- Treat USSD/QR/MoMo instructions as instructions only.
- Treat SMS records as evidence only until verified or manually confirmed by an authorized actor.
- Manual payment status changes must capture actor, timestamp, source, method, amount where relevant, previous status, next status, and target id.
- Disputed, refunded, cancelled, and failed states must not be collapsed into paid/fulfilled.

## Campaign and notification operations

- Campaign sends require consent/eligibility checks, approval where required, and audit events.
- Failed sends should be retried only through approved retry paths.
- Opt-out and notification preferences must be respected by backend logic.

## Support operations

- Verify user identity before discussing private data.
- Use scoped searches and avoid exporting broad datasets.
- Prefer audit/event ids over raw private payloads in support tickets.
- Escalate payment disputes, suspected fraud, data deletion, and cross-tenant visibility reports immediately.

## Emergency containment

- Disable affected app config/feature flag if available.
- Suspend campaign sends or manual payment writes if audit/permission checks are suspect.
- Preserve audit logs and production evidence before cleanup.
- Follow [rollback](../release/rollback.md) for deployment rollback or database repair.
