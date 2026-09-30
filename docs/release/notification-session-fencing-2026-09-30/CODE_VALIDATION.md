# Notification registration session fencing — local code evidence

Date: 2026-09-30. This supplement records worker-owned source, mocked code tests and Ruby syntax checks. **The notification worker has not executed these SQL migrations or fixtures.** Root-owned isolated database results must be evaluated separately. No hosted mutations, real Auth requests, provider sends or scheduler activation were performed.

## Frozen source

Migration `supabase/migrations/20260929180000_notification_registration_sessions.sql`:
`b8335e9b70339a1a67d50db245147b483610a3a4c76f223bd7a17cfc4876a2bb`.

`code-validation.json` retains SHA-256 values before/after validation for the migration, staged installer, SQL/Ruby fixtures, Edge handlers, provider helpers and tests. All captured source hashes remained unchanged during those checks. Dated 139 evidence has not been rewritten as 141 evidence.

## Implemented controls

- Registration and unregistration validate the JWT session ID against the live matching Auth session, verified nonanonymous user, assurance, ban/deletion state and expiry. Normal AAL1 device registration remains supported.
- Token rows retain the verified registration session ID and its Auth-created timestamp. Existing unbound tokens are disabled without guessing historical sessions. History and live claim expiry fences survive.
- A different session may replace a token only when its verified creation timestamp is strictly newer. Older or equal-time replacements return `notification_registration_session_stale` (42501), including delayed A requests arriving after newer B registration while A remains live. Same-session refresh remains valid. Switching back to an older cached session requires a fresh login.
- Unregister matches the exact current user/session binding. Session deletion, invalidating session updates and invalidating user updates disable only tokens still owned by that revoked identity/session. User banning cancels current queued/processing work through the existing fenced device guard.
- Claims, preflight, completion and approved Admin retry require current session eligibility. Preflight reserves 30 seconds before Auth/claim expiry. Generic recipient-bound protocol2 push content is retained; authorized in-app event text is unchanged.

## Lock order and concurrency boundary

Advisory namespace `(193517,141)` is distinct from scheduler namespace `(193517,139)`. Notification operations share this gate **before** Auth, Admin roster, device, delivery and event locks. Reconciliation actor authorization/finalization and Admin approval/access helpers enter the same shared gate before their existing row/roster locks.

Auth users/sessions take an exclusive gate in BEFORE STATEMENT triggers for deletion or relevant identity/session updates. Bulk logout therefore owns the gate before its first row. Ordinary Auth inserts/updates also enter a shared activity gate before row/FK locks, without disabling tokens. Alphabetical trigger ordering takes an applicable exclusive gate first.

A mixed Auth transaction that already holds a shared gate must not wait to upgrade it: contention raises `notification_auth_revocation_retry` (40001), rolling back rather than forming a shared-reader/user-row cycle. A caller must retry the complete transaction. **Actual GoTrue logout, refresh, metadata-update and ban transaction/retry behavior still requires staging verification.** Trusted owner/service SQL that bypasses RPCs, disables triggers or locks rows before entering these functions is outside the client API guarantee. Provider HTTP is outside SQL transactions.

## Checks actually executed

Pinned runtime: `.cache/roster-deno-2.5.6-20260929/deno`, version 2.5.6 (aarch64 macOS), binary SHA-256 `a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0`.

- **40/40** mocked notification tests pass: dispatcher 12, enqueue handler 8, FCM 14, APNs 3, retry policy 3.
- Deno typecheck passes for both notification Edge entrypoints and FCM/APNs helpers.
- Ruby syntax passes for the 139 and 141 concurrency harnesses.
- Commands, exit codes and complete stdout/stderr are stored in `code-validation.json` and `logs/`.

These checks validate TypeScript behavior and Ruby syntax. They do not parse or execute PL/pgSQL or establish SQL lock behavior.

## SQL fixtures prepared for root execution

| Fixture | Scope |
| --- | --- |
| `scripts/tests/notification_session_upgrade_seed.sql` + `_verify.sql` | Guarded 140→141 unbound live-claim transition; no guessed session/timestamp; preserve attempt/expiry; remove exact synthetic graph. |
| `scripts/tests/notification_registration_sessions_uat.sql` | Rollback-only actual registration RPCs, missing/revoked/wrong/equal-time/older sessions, current-owner logout, user ban, lease fencing, expiry and privileges. |
| `scripts/tests/notification_delivery_sessions_uat.sql` | Rollback-only full notification delivery/Admin retry assertions adapted to real Auth sessions and timestamp binding. |
| `scripts/tests/notification_delivery_session_concurrency_uat.rb` | Real two-session overlap: double claim, in-flight replacement rejection, logout both orders, live older A vs newer B, bulk logout, invalidating UPDATE, user ban and mixed Auth metadata/reconciliation upgrade requiring 40001. |

The 141 Ruby harness requires the exact task-owned Docker project/port, migration141, disabled cron, `pg_net.batch_size=0`, empty push tables and unused `99730000` synthetic IDs. It snapshots **20 table families**, including Auth sessions and trigger-created member records, and checks exact restoration after worker connections exit. Member cleanup checks incoming FK references and deletes only exact newly seeded unlinked members. The corrected 139 harness uses fresh `99860000` IDs, protocol metadata2 and **19 table families**; pre-existing `99880000` orphan members are preserved.

## Deployment order / remaining acceptance

The canonical current installation is the ordered numbered migration chain through 141. Quiesce Auth, notification and reconciliation traffic during the schema transition: PostgreSQL acquires DML relation locks before BEFORE STATEMENT triggers, so the runtime row-lock ordering does not establish a contention-free live DDL rollout. The historical `deploy/hardening/reconciliation_approval_v2.sql` installer now takes the deployment gate and refuses an installed 141 helper or registry version≥141 **before replacing any definition**. It is intentionally no longer byte-identical to140; numbered140 is unchanged. Installer SHA-256: `0371a10c99d28fa7cd24fbc03421a83c84914b55ae2e621f61ddec0e25a1e552`. Root must prove that refusal on141 leaves definitions, privileges and data unchanged.

Remaining acceptance for S10/O05/P07/M08 includes:

1. Execute guarded upgrade, rollback, concurrent logout/rebind and cross-workflow regression suites at exact current schema; preserve hashes and cleanup proof. Resolve any failures before promotion.
2. Verify real GoTrue transaction boundaries and retry handling for40001, old-session account switching/fresh-login guidance, login/session creation and Auth user deletion without changing account cascade semantics.
3. Verify both platform builds on devices across foreground/background/terminated states, logout/account switching, async delivery/display/navigation races and native callback payload parsing. Local SQL/code tests cannot prove device privacy.
4. Stage the version2 SQL/Edge/client contract in the required order; old workers fail closed. Re-register legacy devices with verified live sessions and confirm monitoring rather than backfilling assumed ownership.
5. Verify actual FCM/APNs credentials, recipient-bound generic content, response/retry/error handling, uncertain accepted-send recovery and operator dead-letter workflow under approved provider tests.
6. Provision existing verified Vault values, review and activate the initially inactive minute scheduler, test wake-up loss/stale recovery, and evidence queue/retry/terminal-failure alerts and ownership. No live credentials were invented or configured here.

Revoking a session cannot recall a message already accepted by a provider or atomically span a subsequent external send. The generic payload and client recipient/version checks limit disclosure; provider/device validation remains required. This packet closes no whole production acceptance ID by itself.
