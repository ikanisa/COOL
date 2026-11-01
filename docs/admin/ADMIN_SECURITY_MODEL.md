# Collect Admin security model

This document describes source boundaries to verify for the candidate under
review. It is not evidence that a particular Admin frontend or backend is deployed,
that providers are configured, or that a release is approved.

## Authentication and authorization

The active Admin workspace uses a server-backed, cookie-authenticated account
and session; member bearer authentication is a separate admission path. The
Admin frontend's transport can use a selected managed or self-hosted Supabase
profile. Frontend route guards are conveniences: protected reads and mutations
must enforce current server-side account, session and capability authority.
Configuration and permission checks must fail closed; do not substitute a
legacy fallback for an authorization or transient service failure.

The current read-only SMS oversight endpoint requires `system_health.read`. It
reports only recorded queue states; worker heartbeat and receipt-gate status are
not recorded in that contract. The older bearer-based notification-operator
health route is not registered in the selected backend and remains unavailable.
Do not infer delivery or a healthy worker from missing data.

## Sensitive records and audit

Raw receipt bodies, phone numbers, operator notes, message bodies and device
tokens require the actual scoped access, purpose, retention and audit controls.
List, synchronization and invalidation responses must not disclose sensitive
payloads outside their authorized purpose. Payment or evidence changes and
privileged administration require their server-side permissions, mutation
controls and audit evidence.

Raw-evidence routes require route-by-route verification. The direct bearer
`GET /v1/receipts/{id}` route now returns 410 before accessing receipt data.
The separate Admin capture-content path requires scoped permissions and a reason,
revalidates the session and records an audit event. Its local tests do not by
themselves establish current deployed behavior or actual PostgreSQL coverage.

## Secrets, recovery and verification

Flutter-visible configuration must contain only public client values. Service
role keys, provider credentials, authentication secrets and encryption keys
belong in the appropriate server-side secret store, not the app bundle or source
control. Public URL or key configuration is not proof that the corresponding
service is available.

Account/session revocation, cross-account access, raw-evidence authorization,
mutations, retention, backup restoration and key custody require isolated tests
and authorized deployed readback. A restored archive does not itself authorize
restored accounts, sessions or credentials. Provider delivery, real MFA, hosted
behavior and accountable release approval need separate evidence.
