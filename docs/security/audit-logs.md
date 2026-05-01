# Audit Logs

Auditability is a product and security requirement. Sensitive actions need durable, searchable records that identify the actor, target, action, source, and outcome without leaking private payloads.

## Required audit fields

- Actor id and actor role.
- Tenant, group, partner, or custodian scope when applicable.
- Action name and target entity id/type.
- Before/after status for state transitions where safe.
- Source: UI, Edge Function, RPC, scheduled job, agent tool, import, or manual review.
- Timestamp from the database/server.
- Correlation id or request id when available.
- Outcome: allowed, denied, failed validation, applied, rolled back, or queued.

## Audited domains

| Domain | Examples |
| --- | --- |
| Admin access | Role assignment, user creation/status, scoped admin changes. |
| Payments | Payment intent creation, evidence ingestion, manual confirmation, allocation, dispute, refund, cancellation. |
| Campaigns | Draft, approval, rejection, send, failure, opt-out skip. |
| App config | Feature flag and public app configuration changes. |
| BioPay | Enrollment, match, revocation, trust updates, abuse/rate-limit events. |
| MoMo SMS | Ingest, parse result, duplicate, manual review, allocation, sender inventory acknowledgement. |
| Agents | Tool call requested, permission checked, action result, human escalation. |
| Operations | Health events, migration safety checks, rate-limit events. |

## Logging safety

- Do not log service-role keys, JWTs, OTPs, private keys, biometric payloads, raw member files, or full SMS bodies beyond approved retention/redaction rules.
- Prefer ids, hashes, status, and summaries over raw private content.
- Denied actions should log enough to investigate abuse without disclosing another tenant's data.
- Audit inserts for sensitive actions should be server-owned or protected so clients cannot forge privileged audit trails.

## Review cadence

- During UAT, verify each sensitive journey produces an audit event.
- During launch week, review audit volume daily for denied access spikes, failed payment transitions, campaign sends, and admin role changes.
- After incidents, preserve relevant audit windows before cleanup or retention jobs run.
