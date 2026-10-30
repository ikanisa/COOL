# Admin oversight and approved-scope retention

The maintained local entry points use the fixed Admin origin, existing approved
Admin account, private cookie session and live capabilities. They do not use a
database/service key, import browser cookies or fall back to bearer/member
credentials. No operation in this document grants a release or policy approval.
The source and local synthetic tests do not establish hosted acceptance.

## Oversight through the read-only MCP server

The existing `npm start` catalogue has fifteen tools. Three cover operational
oversight:

| Tool | Live capability | Result |
| --- | --- | --- |
| `collect_admin_audit` | `audit.read` | One page of cross-operator domain or Admin account audit metadata, default 25 and maximum 100 rows |
| `collect_admin_health` | `system_health.read` | Queue state counts, age of oldest work, record timestamps and configured runtime bindings |
| `collect_admin_diagnostics` | `system_health.read` | At most 64 aggregate groups in the last 24 hours, safe event codes, release tags and counts |

Audit `source` is `domain` or `accounts`. Optional filters are exact `actor_id`,
`entity_id` and `action`. `actor_id` means canonical principal UUID for domain
records and Admin account UUID for account records. Domain cursors preserve the
PostgreSQL bigint identity as a decimal string. Account cursors pair the epoch
second with the last UUID. Supply the returned `next_cursor` unchanged in the
next `cursor`; do not increment it or use an offset. A page has no free-text
reason, details JSON, source body, actor session identifier or account secret.

Health returns observations, not a blanket healthy status. MoMo counts include
pending/retry/processing, expired leases, review/source failures, exhausted work
and error-marked records. Assisted SMS distinguishes queued, claimed, expired
claims, send-started, observed-sent, failed-no-send and uncertain. An uncertain
send is not automatically retryable. In-app notification states and legacy email
records are identified explicitly; their `pending` state does not prove provider
dispatch. Current invitation counts exclude replay aliases and distinguish
provider acceptance from delivery. Record timestamps are not worker heartbeats.
The durable push outbox has its own pending/retry/claimed/sending/accepted/rejected/
suppressed/unknown counts, due/expired-lease counts and oldest work ages. An accepted
request means provider acceptance; unknown dispatches are not automatically retried.
No health read probes an external provider or returns recipient information,
message text, provider identifiers, raw exceptions or credentials.

An optional `expected_source_revision` compares the observed build identity with
the operator's approved identity. An absent/unrecognized build stays `unknown`.
A configured binding is only configuration evidence. The separate diagnostics
read contains no raw error/stack or account, session or device identities.
Malformed, oversized, stale, reordered or unexpectedly expanded responses fail
closed; a missing route is not silently treated as an empty queue. Both the
backend read transaction and the local client's final session/grant check fence
results against revoked access.

## Retention prerequisites and supported scope

Use a supported Node runtime with `node:sqlite` (the local qualification used
Node 24.22.1). The durable journal reuses the repository's hardened SQLite
implementation. The normal session file and its directory must already pass the
existing owner-only and no-symlink checks.

Run the following from this package directory:

```sh
npm run login
npm run verify-email
npm run retention -- context
```

`verify-email` renews email proof in the **same** local Admin session. It does not
sign in again or rotate the original operation identity. Codes are entered in a
hidden terminal prompt. When required, the existing signed human-challenge
handoff supplies one token. No password, OTP or CAPTCHA token is accepted in
command arguments, pipes or environment variables. A lost verification response
causes one proof-status read, never an automatic code verification/resend.
A printed original challenge UUID can be resumed with:

```sh
npm run verify-email -- resume ORIGINAL_CHALLENGE_UUID
```

Every privacy request requires actual `privacy.review` and fresh, server-attested
email proof; a generic assurance level or MFA timestamp cannot replace it. The
client obtains and sends current CSRF proof on the fixed privacy RPCs. It checks
the same account, public session, principal, role and capabilities again before
returning results.

The server must already contain a current, independently approved policy and
matching environment approval hash. That policy binds source and schema hashes,
reviewed subject/request, scope inventory, class rules/deadlines, writer drain,
copy inventory and approval expiry. The CLI accepts an existing policy hash; it
cannot create or approve policy, assert an absent hold, clear an unresolved
obligation, alter deadlines or repair an unknown external inventory.

| Class/action | Tool behavior |
| --- | --- |
| `access` / `quarantine` | Uses the existing approved access-barrier adapter; no invented account deletion |
| `notification_devices`, `notification_preferences`, `notification_events`, `support_requests` / `erase` | Uses existing bounded, exact-source SQL disposition adapters |
| `r2:upload_objects` / `erase` | Uses the existing generic catalog-object adapter, immutable effect identities and verified storage observations; no arbitrary key deletion |
| Approved `retain` on supported non-external classes | Uses existing server inventory/deadline checks and retained outcome receipts |
| Any `external:*` task | Refused locally; actual processor/backup/export inventory and adapter are required |
| Immutable financial/SMS/evidence or any other unimplemented erasure | Refused locally; no generic DELETE or SQL bridge |
| `blocked` rule or unsupported action/class pair | Refused locally and remains visible in plan status |

The additive diagnostic schema profile and subsequent delivery-outbox profile
change the approved schema inventory. Old approval hashes are not rewritten or
silently authorized for a new schema. Diagnostic reports have no subject link;
known subject-derived rate-limit hashes remain accounted for as retained rows.

## Review, confirm and execute one bounded step

Replace the uppercase references below with exact values from the reviewed
request and approved policy. The CLI validates every UUID, revision and hash.

```sh
npm run retention -- inspect REQUEST_UUID REVIEW_REVISION SOURCE_SHA256
npm run retention -- preview-plan REQUEST_UUID REVIEW_REVISION SOURCE_SHA256 POLICY_SHA256
npm run retention -- show PREVIEW_SHA256
npm run retention -- apply PREVIEW_SHA256
```

A preview reads actual current scope and refuses active holds or unresolved
in-flight obligations. It stores one immutable operation UUID, exact input,
source/snapshot expectations and authority binding in `retention.sqlite` beside
the private session file. The preview hash is a deterministic SHA-256 of that
saved content. The preview is review evidence, not policy approval. Apply prints
the exact saved preview and requires the operator to type `APPLY` followed by its
full hash. There is no `--yes`, non-terminal apply or MCP mutation tool.

After fresh authority/scope checks, a committed local `dispatching` record is
written **before** the single network request. On success, the receipt becomes
`observed`. If dispatch, response validation, final authority verification or
receipt persistence is uncertain, the original reference stays retained and the
state remains `unknown` or `dispatching`; neither is treated as failure-to-apply.
Concurrent confirmations cannot dispatch the same prepared preview twice.

Use the returned plan/task identities:

```sh
npm run retention -- status PLAN_UUID
npm run retention -- preview-claim PLAN_UUID TASK_UUID
npm run retention -- apply CLAIM_PREVIEW_SHA256
npm run retention -- preview-execute ORIGINAL_CLAIM_OPERATION_UUID
npm run retention -- apply EXECUTE_PREVIEW_SHA256
```

Claims have a maximum 120-second lease and a server-issued fence. Execute requires
an observed original claim, matching current task revision/fence and current
session. A stale task, changed policy/source, replaced session, unresolved claim,
unsupported class or expired lease stops the step. The server repeats current
policy/hold/source/lease checks at its actual effect boundary; the local preview
cannot bypass them. A completed task no longer blocks the next task merely
because its old lease timestamp has not elapsed.

## Unknown results, chunk continuation and recovery

List all original operation references and recover the exact original operation:

```sh
npm run retention -- list
npm run retention -- recover ORIGINAL_OPERATION_UUID
```

Recover performs only reads. `observed: false` means the original outcome is still
unknown; an earlier request may still arrive. It does not authorize a replacement
UUID. If the immutable receipt becomes available, the tool validates its exact
operation/claim/source/policy identity before recording it. The original request
body, binding and dispatch count survive process restart. The latest 20 readback
observations are kept without discarding the original operation.

A human can explicitly request an identical retry:

```sh
npm run retention -- retry ORIGINAL_PREVIEW_SHA256
```

Retry requires typing `RETRY` and the full original preview hash. It first looks
up the original receipt. If present, no write occurs. If absent, it repeats only
the original input/UUID after all current preconditions still pass. It never
replaces a claim, silently retries a provider call or assumes a missing receipt
means rollback. Each original operation is bounded to 20 dispatch attempts.

Some object/row tasks require multiple bounded steps. An unknown or partial
object disposition can make the broad plan snapshot unconfirmed while the
backend's task-specific resume can verify the original immutable effect. Use the
explicit resume review, preserving the original outcome:

```sh
npm run retention -- preview-resume-claim ORIGINAL_EXECUTE_OPERATION_UUID
npm run retention -- apply RESUME_CLAIM_PREVIEW_SHA256
npm run retention -- preview-execute RESUME_CLAIM_OPERATION_UUID
npm run retention -- apply RESUME_EXECUTE_PREVIEW_SHA256
```

This requires an original dispatched execution, an observed original claim and
matching current task/fence/class. An unresolved execution must wait for that
known claim to expire. A committed partial result can continue after its task
leaves `claimed`. The preview states `requires_execution_recheck`; it does not
pretend an unconfirmed broad snapshot is current. A new explicit claim is
accepted only by the server's actual current policy. Execution again checks the
original effect identity, actual source/absence, holds, writer drain and new
lease. The previous unknown operation remains retained, without a fabricated
completion or automatic resend.

The original operation lookup is intentionally session-bound by the existing
backend. Keep the same session and renew email proof. If the original session
expires or is revoked, its journal/reference survives, but the CLI cannot
manufacture an original receipt or silently rebind ownership. A currently
approved reviewer can inspect plan status; further cross-session recovery or
changed-policy quarantine continuation needs the existing governed approval
process and actual backend authority. No synthetic approval is generated here.

`cancel PREVIEW_SHA256` marks only a never-dispatched preview as cancelled and
retains it. It cannot cancel an in-flight or unknown server operation. The
journal is owner-only, bounded to 1,000 original operation records and refuses
symlinks, broad permissions, incompatible schemas and corrupt preview hashes.
It never stores cookie, CSRF token, email code, message body or object key. Keep
unresolved journals; do not remove them to create replacement operations.

## Reconciliation and what completion means

```sh
npm run retention -- preview-reconcile PLAN_UUID
npm run retention -- apply RECONCILE_PREVIEW_SHA256
```

Reconciliation checks actual task states, holds, source and unchanged financial
journal using the existing API. This endpoint has no immutable operation-receipt
lookup. If its response is lost, `recover` records a current status observation
while preserving the original call as unknown. `retry` refuses that operation;
a new current-state reconciliation requires its own reviewed preview and explicit
confirmation.

An observed task can mean retained, quarantined, partially processed, blocked or
verified absent within the approved adapter scope. It does not prove account
closure, provider copy removal or all-data erasure. Outputs retain
`erasure_completed: false`, `all_data_erased: false` and no operational acceptance.
The financial journal is preserved. Full disposition remains dependent on
approved policy and coverage for actual external, backup/export, immutable and
unmapped copies.

## Local verification

```sh
npm run check
npm test
```

Tests exercise the actual stdio process, bounded cookie/CSRF transport, live grant
fences, strict audit/health/diagnostic DTOs, private SQLite restart/CAS behavior,
unknown-operation recovery, exact retry, explicit resume fences and confirmation
refusals against synthetic fixtures. Loopback HTTP fixtures need local socket
permission. No test uses a live Admin credential, calls a real provider, sends a
message or deletes real account data. Hosted actor sessions, approved policy
artifacts, provider acceptance and release adoption remain separate qualification.
