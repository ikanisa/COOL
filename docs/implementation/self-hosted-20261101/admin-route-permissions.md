# Admin route and permission map

This inventory covers every route declared by `lib/admin/cloudflare_admin_app.dart`, including the six generated core areas. It describes actual UI admission and operation permissions; a visible route never replaces server authorization. Supabase validates the canonical Auth session, Admin account/session link, current grants and resource scope again in each protected database batch. Sensitive actions use the independent recent-email proof; they do not relabel an email-verified AAL1 session as MFA/AAL2.

## Route admission

| Route | Admission and available authority |
| --- | --- |
| `/` | Redirect to `/admin`; session handling then applies |
| `/admin/session` | Session recovery/return-location boundary; no business permission granted |
| `/admin/login` | Authentication entry; exact configured origin, PKCE and provider callback validation |
| `/admin/forgot-password` | Account recovery entry; server anti-abuse and recovery controls |
| `/admin/setup` | Invitation/setup entry; server invitation identity and one-use setup controls |
| `/admin` | Authenticated account overview; each requested oversight resource checks its own permission |
| `/admin/groups`, `/:id` | `collections.read`; record scope also checked by backend |
| `/admin/groups/new` | `collections.read` plus `collections.create` |
| `/admin/groups/:id/edit` | `collections.read` plus `collections.manage` |
| `/admin/users`, `/:id` | `users.read` |
| `/admin/users/new`, `/:id/edit` | `users.read` plus `users.manage` |
| `/admin/members`, `/:id` | `users.read`; group membership details remain resource-scoped |
| `/admin/members/new`, `/:id/edit` | `users.read` plus `users.manage` |
| `/admin/payees`, `/:id` | `receivers.read` |
| `/admin/payees/new`, `/:id/edit` | `receivers.read` plus `receivers.manage` |
| `/admin/transactions`, `/:id` | `payments.read` |
| `/admin/transactions/new`, `/:id/edit` | `payments.read` plus `payments.manage`; operation support depends on the returned source model |
| `/admin/ledgers`, `/:id` | `ledger.read` |
| `/admin/ledgers/new`, `/:id/edit` | `ledger.read` plus `ledger.manage`; canonical evidence views cannot invent unsupported mutations |
| `/admin/ledger-accounts/:id` | `ledger.read` |
| `/admin/ledger-accounts/:id/edit` | `ledger.read` plus `ledger.manage` |
| `/admin/momo-receipts` and child path | Either `sms.read` or `payments.read`; the selected receipt surface checks its applicable data grant |
| `/admin/reconciliations`, `/:id` | `reconciliations.read`; proposal/review require separate `reconciliations.propose` / `reconciliations.review` and current sensitive authority |
| `/admin/sms-receipts`, `/:kind/:id` | `sms.read`; revealing raw SMS additionally requires `sms.reveal` and current recent-email proof |
| `/admin/notification-settings` | Owner role plus `admin_users.manage` for workspace admission; owner-email identity and recent email are enforced by backend. Access management uses `admin_users.manage`; policy/batch operations require `assisted_sms.manage` |
| `/admin/notification-operator` | `assisted_sms.read`; claims, content, confirmation, send-start, outcome, gateway dispatch/reconciliation require `assisted_sms.manage` and recent email |
| `/admin/email` | `email.read`; management controls additionally require `email.manage` |
| `/admin/member-receipts`, `/:id` | `payments.read`; receipt decisions use separate transaction actions and exact record revisions |
| `/admin/gateway`, `/:id` | `gateway.read`; management actions additionally require `gateway.manage` |
| `/admin/gateway/new` | `gateway.read` plus `gateway.manage` |
| `/admin/gateway/receiver-grants`, `/:id` | `gateway.read`; page/API action admission adds `gateway.manage` where needed |
| `/admin/requests` | Authenticated original-operation status workspace; a request key supplies no new action authority. Server checks the original actor/session, operation and current permission |
| `/admin/admin-users` | `admin_users.read`; staff/invitation/grant mutation requires `admin_users.manage`, supported role capability, owner restrictions and recent email |
| `/admin/privacy-requests` | `privacy.review`; review/retention operations require current sensitive authority, exact policy/source/schema and original operation identity |
| `/admin/security` | Current authenticated account/session; security actions are scoped to that account |
| `/admin/security/verify-email` | Current Admin account/session; exact email proof is established on the server and tied to this session |
| `/admin/security/authenticator` | Supabase mode redirects to `/admin/security/verify-email`; legacy surface does not establish modern Admin authority |
| `/admin/licenses` | Authenticated informational route; no mutation authority |

The generic core route uses `area.path == /admin/<enum-name>` and nested `new`, `:id` and `:id/edit` routes. These are generated routes, not omitted entries.

## Operating API mutation map

These paths are relative to `/api/admin/operations`. Every mutation retains its operation ID and required version; a transport timeout is not permission to generate a replacement command.

| Method and path | Required operation permission |
| --- | --- |
| `POST groups` | `collections.create` through the dedicated new-group path; owner/resource checks still apply |
| `PATCH groups/:id` | `collections.manage` |
| `POST users`, `PATCH users/:id` | `users.manage` |
| `POST memberships`, `PATCH memberships/:collection/:user` | `users.manage` |
| `POST payees`, `PATCH payees/:id` | `receivers.manage` |
| `POST accounts`, `PATCH accounts/:id` | `ledger.manage` |
| `POST transactions`, `POST transactions/:id/evidence`, `/verification`, `/allocations` | `payments.manage` |
| `POST transactions/:id/reverse` | `payments.reconcile` |
| `POST journals`, `PATCH journals/:id`, `POST journals/:id/post` | `ledger.manage` |

Backend source models can expose a smaller allowed-operation set. The UI must respect that set as well as the nominal permission. Canonical receipt evidence, ledger entries and historical status are not interchangeable with editable legacy transaction/journal records.

## Receipt SMS API map

All routes below are under `/api/admin/notification-operator`. They require the configured browser origin and authenticated Admin session. Sensitive operations require the same current recent-email proof in the protected database boundary. Source facts, consent, privacy barriers and revisions are checked separately.

| Endpoint/action | Required authority and effect |
| --- | --- |
| `GET/POST access` and `GET access/operations/:request` | Exact primary owner + `admin_users.manage`; enables/disables the two assisted SMS grants or reads the original decision |
| `GET/POST policies/:collection`, `GET policies/operations/:request` | Exact primary owner + `assisted_sms.manage`; policy revision CAS or immutable decision readback |
| `GET operations` | Exact primary owner, current applicable management permission; original-session history only; no command reconstruction |
| `POST materialize`, `GET materialize/:request` | Exact primary owner + `assisted_sms.manage`; one bounded original batch of at most ten source entries, or read-only status. Creates jobs, not provider sends |
| `POST` action `list_pending` | `assisted_sms.read`; bounded queue metadata |
| `claim`, `get_claimed`, `confirm`, `record_send_start`, `record_outcome`, `release_claim`, `get_operation` | `assisted_sms.manage`; original account/principal/session/claim/fence binding, exact current proof and source checks |
| `dispatch_gateway` | `assisted_sms.manage`, original send-start grant, matching token hash, expiry and a successful one-use final CAS; one provider submission |
| `inspect_gateway` | `assisted_sms.manage`, original attempted dispatch; GET readback only, never another submission |

Source references: `cloudflare_admin_app.dart`; `cloudflare_admin_repository_models.dart`; `cloudflare_admin_repository_operating.dart`; `cloudflare_canonical_reconciliation_api.dart`; `admin_accounts.js`; `admin_sms_receipts.js`; `notification_operator.js`; `notification_operator_management.js`; `assisted_sms_dispatch.js`. The separate OpenSMS gateway uses application scopes, device ownership or staff permissions from its inspected `src/auth.ts`; these credentials are never a substitute for Collect Admin authority.
