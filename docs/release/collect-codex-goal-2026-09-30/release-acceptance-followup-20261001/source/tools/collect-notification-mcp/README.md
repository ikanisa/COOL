# Collect notification MCP bridge

This local stdio server exposes the governed Collect SMS receipt queue and
redacted Admin operations reads, plus an explicit manual shadow telemetry check.
It never posts payments, changes balances, chooses recipients, or sends through
Apple Messages. The Supabase Edge boundary independently authenticates the
operator and enforces current admin permissions.

Runtime requirements:

- `COLLECT_SUPABASE_URL`: deployed Supabase project URL (HTTPS; loopback HTTP is accepted for local tests).
- `COLLECT_SUPABASE_ANON_KEY`: public project anon key.
- `COLLECT_OPERATOR_ACCESS_TOKEN`: short-lived access token for the currently approved Admin PWA operator. Do not write it to this repository or an MCP JSON file.

The configured Mac now also supports `COLLECT_OPERATOR_KEYCHAIN_HELPER`. When
explicit environment credentials are absent, the server reads only its dedicated
device-local Keychain item at call time. The owner-selected email OTP sign-in through
`src/operator_login.ts request` / `verify` is fixed to `info@ikanisa.com`, authenticates
an existing enrolled approved operator without signup, and verifies health/list.
Hosted email delivery and account authority must actually be available. OTP input is hidden. No
browser store or service key is used. By default only the short-lived access
token is saved and expiry requires normal reauthentication.

The configured host now opts into `COLLECT_OPERATOR_SESSION_RENEWAL=keychain`.
New OTP logins in that environment retain the rotating refresh token in the
same device-local Keychain item, not in environment variables, output, files or
MCP config. The earlier access-only item cannot be upgraded without a fresh
login. Local renewal tests pass; production rotation still requires provisioning
and independent live evidence. This is not an unlimited service identity.

Renewal happens within two minutes of access expiry, using the normal Auth
refresh endpoint and preserving the original user and session identity. An
atomic private-directory lock serializes all readers, refreshers and login
writers across MCP/preflight processes. A durable non-secret pending marker is
saved before refresh; a crash, timeout, revoked session, malformed response,
denied current Admin permission or failed rotation save leaves the session
blocked for normal reauthentication. The old refresh token is never blindly
retried. There is no change to server session policies or Admin permissions.

After a fresh login, `src/operator_login.ts renew` provides an explicit real
rotation test before expiry; it does not alter timestamps or tokens to simulate
live acceptance. It calls Auth refresh, the current GoTrue `/user` read and
operator health/list. Before saving the rotated token, the explicit email renew
path requires the selected verified email and the same UUID subject from current
GoTrue. Wrong-email, legacy-phone, unconfirmed, malformed, future-confirmation or
unavailable identity results retain the pending marker and require fresh sign-in.
The identity read refuses redirects and bounds its response/deadline; decoded
JWT email claims do not establish this identity. A
leftover `.session-lock` is never stolen or auto-deleted: inspect the exact
operator processes, establish that no refresh/login is active, then remove only
the empty lock directory. Never print the Keychain item to diagnose a failure.

`src/stdio_preflight.ts` verifies the real MCP initialize/health/list exchange
and prints only aggregate status. The 3 September setup notes recorded passing
production stdio and Keychain-backed preflights with a read-only/no-send
heartbeat. Those historical checks do not verify the current session, scheduled
run, host allowlist or receipt feature flags; verify each before making a live
connection or sending claim.

Both connection preflights require a boolean queue-enabled flag and all six
nonnegative integer queue counts before reading the bounded pending page.
Malformed successful responses remain blocked. Local transport regressions
exercise the registered tool mappings, input rejection, redirect refusal and a real
15-second timeout against isolated HTTP fixtures with synthetic credentials.
Those tests do not access Keychain, invoke Messages, prove SQL persistence or
establish current production authorization or delivery.

Install and verify locally:

```sh
pnpm install
pnpm check
pnpm test
```

Start it with `pnpm start` from this directory. Configure the Codex MCP host to
launch that command and inject the three variables through the host's governed
secret/runtime environment. Do not place keys in command arguments. The Edge
Function and SQL migration must be deployed before connection testing.

## Read-only connection preflight

The local Codex profile `collect-notifications` is registered with an absolute
Node/server path, the verified production project URL, key/token environment-variable forwarding, a 15-second startup timeout
and a 45-second tool timeout (including bounded renewal). Its initial read-only
allowlist contained `collect_notification_health` and
`collect_list_pending_receipts`; later read-tool additions require explicit host
configuration. No credential
value is saved in the host configuration. Registration is not authentication
or proof that the current task has reloaded the MCP inventory.

Run `pnpm preflight` in the same governed runtime environment. This performs no
network request and reports only missing variable names or safe issue codes.
It does not refresh credentials in offline mode. It rejects service-role/secret
API keys, non-user tokens, a mismatched issuer and tokens with less than 60
seconds remaining. These local claim checks do not
verify a signature or grant access; the deployed Edge validates the session and
current permissions independently.

After the approved operator has signed in and the short-lived token is injected
securely, run `pnpm preflight --live-read-only`. It calls health and one bounded
pending-list read only. Its output contains aggregate counts, no receipt rows,
phones, amounts, job IDs or credentials. Exit code 2 means blocked, not success.
The preflight never claims work, records a heartbeat, posts money or sends SMS.

Requests reject command overrides and credential-bearing/path/query URLs, refuse
redirects and time out after 15 seconds without retry. A timeout on a future
mutating command does not prove that the server made no change: reconcile the
durable state before acting again. A short-lived token needs the opt-in renewal path;
there is no persistent service-role fallback or browser-session extraction.

Expand queue-control tools only for an explicitly approved supervised pilot
after the authenticated read-only check and legacy-sender takeover pass. Keep
the sending phase disabled until that physical pilot is accepted. Read-only
monitoring may run independently before handover. See
`docs/release/HYBRID_OPERATOR_PREFLIGHT_2026-09-03.md` in the repository root.

The workflow is deliberately split:

1. Health and list return aggregates or masked destinations.
2. Claim returns a fencing token.
3. Exact receipt read returns the full destination/body only for that claim.
4. The user must confirm the exact destination/body at action time.
5. Send-start consumes that confirmation but does not send.
6. Computer Use sends once in Apple Messages and re-reads the conversation.
7. Outcome records `observed_sent`, `failed_no_send`, or `uncertain`; uncertain is never auto-retried.

## Admin operations reads

The bridge now also registers three narrow read-only tools using the same
governed current-user environment or dedicated Keychain session:

| Tool | Backend RPC | Bounded inputs |
| --- | --- | --- |
| `get_collect_health` | `public.admin_system_health` | No arguments; `p_id` is always `system`. |
| `get_notification_status` | `public.admin_get_hybrid_sms_receipt` | One opaque `notification_id` UUID. |
| `list_notification_failures` | `public.admin_list_hybrid_sms_receipts` | `failed_no_send` or `uncertain`, limit 1–25, offset 0–10000; no search. |

The host must explicitly include these tool names in its read-only allowlist
before exposing them to Codex. The server still registers the existing queue
control tools for the separate supervised operator workflow; this change does
not authorize or add any of them to a host allowlist.

The new tools call allowlisted public RPCs with the current authenticated user
bearer token and public project key. Local token checks reject non-user roles,
wrong-project issuers, missing user/session IDs and expiry within 60 seconds.
These checks are credential hygiene: the backend independently verifies the
signature, current Admin session and each RPC's permission. They do not create
an Admin grant. Existing locked Keychain renewal and reauthentication policies
continue to apply. Production uses HTTPS; loopback HTTP is supported only for
the isolated synthetic fixtures.

Operational reads refuse redirects, have a 15-second network/body deadline,
bound JSON responses to 256 KiB and return fixed safe failure codes. There is no
automatic retry. Their results project only validated states, opaque receipt
IDs, timestamps, bounded counters and fixed reason codes. Member names, Collect
IDs, telephone numbers (including masks), receipt bodies, amounts, balances,
transaction references and arbitrary backend diagnostic text are removed.
The fixed receipt template accepts only integer versions 1 (immutable legacy)
and 2 (governed recorded-savings snapshot). Its content/version never becomes an
assertion of carrier delivery or external settlement, and receipt text remains
omitted from these operational projections.

`get_collect_health` requires version 1 of the contract in
`supabase/migrations/20260930160000_redacted_operational_health.sql`. It verifies
the complete metric set, aliases, timestamp window, thresholds, alert states and
evidence limits. The 60-second sample becomes `unknown` at expiry or excessive
future clock skew, with metric values cleared to null; missing age measurements
remain unknown. This is a database
sample and does not invent gateway connectivity, Codex supervisor telemetry,
provider configuration, successful sends or handset delivery. An absent or
older deployed contract fails validation. Existing queue/stdio preflight
success does not establish this newer RPC's deployed availability.

For a current live check in the configured governed environment, run:

```sh
node --experimental-strip-types src/stdio_preflight.ts --operations
```

This performs the existing queue health/list reads, the new operational health
read, one failure-list read and, when that page contains a receipt, its status
read. It prints only aggregate status and tool names, never credentials or row
identifiers. An empty failure page leaves the exact status read unverified. A
successful connection can still report operational health as `unknown` or
`attention`; connectivity is independent of measured operational health.

Run `pnpm check` and `pnpm test` for the local synthetic tests. New tests cover
actual MCP initialization, discovery, strict input schemas and public RPC reads
through an isolated loopback fixture, plus current-session hygiene, stale and
malformed samples, reason-code redaction, authorization errors, redirects,
oversized JSON and stalled response bodies. They never use production
credentials, Keychain or a real payment/notification provider.

This remains a local stdio bridge, with no remote MCP/OAuth server or generic
SQL/RPC dispatch. Registering it and passing synthetic tests do not prove a
current authenticated production connection. Live read-only RPC verification
and the deployed contract are required for that claim. Automated send/retry,
scheduled supervision and pause/resume tools require separate backend controls,
rollout evidence and authorization before future implementation or enablement.

## Explicit manual shadow check

The bridge registers these four fixed public RPC mappings for the manual check:

| Tool | RPC | Effect |
| --- | --- | --- |
| `begin_supervisor_run` | `begin_collect_shadow_run_v1` | Acquire a server-fixed 120-second lease and create private run telemetry for one supplied request UUID. |
| `sample_supervisor_run` | `sample_collect_shadow_run_v1` | Persist one server-derived health/SMS aggregate sample under the original session and fence. |
| `complete_supervisor_run` | `finish_collect_shadow_run_v1` | Record completion from the persisted sample while the original lease, session and fence are valid. |
| `get_supervisor_run` | `get_collect_shadow_run_v1` | Read the original actor's run by request UUID for manual reconciliation, including after normal reauthentication. |

The three lifecycle tools declare `readOnlyHint: false`. Their writes are limited
to private operational run, lease and sample telemetry. They do not change
payments, balances, notification outboxes, claims, attempts, sender settings,
device heartbeats or scheduling, and cannot send a message. Scope is the Collect
platform, derived by the backend; there is no caller-provided tenant, recipient,
message, amount, result or completion count. The backend requires a current
approved platform owner with both `system_health.read` and `notifications.read`.
Lifecycle calls also require the original user/session and current unexpired
fence; a changed session cannot restart or resume an old request.

The Codex host keeps its five-read allowlist: `collect_notification_health`,
`collect_list_pending_receipts`, `get_collect_health`, `get_notification_status`
and `list_notification_failures`. None of the four shadow tools is enabled in
that profile. The explicit CLI opens its own isolated stdio connection to the
same bridge and current-user credential resolver; it neither changes the host
allowlist nor signs in or requests an OTP. Existing opt-in Keychain renewal
rules still apply, including blocking after an uncertain refresh.

From the repository root, use a retained request UUID:

```sh
python3 scripts/collect_operator_login.py shadow --request-id UUID
python3 scripts/collect_operator_login.py shadow-status --request-id UUID
```

Equivalent bridge-directory commands in the governed environment are:

```sh
node --experimental-strip-types src/shadow_supervisor.ts --once --request-id UUID
node --experimental-strip-types src/shadow_supervisor.ts --status --request-id UUID
```

Generate and retain the request UUID before running. Missing, conflicting,
duplicate or unknown arguments fail before starting the bridge or loading
credentials. `--once` makes exactly one begin, one sample and one completion
call, stopping earlier on BUSY, a terminal replay, refusal, stale health or
uncertainty. It has a 60-second total deadline and 15-second request deadlines,
including bounded stdio replies; there is no automatic retry, repeated scan or
scheduler. BUSY creates no run for that request. Replaying a completed or expired
request does not restart it. Backend serialization conflicts, deadlocks, expired
leases and lost fences terminate for manual reconciliation.

A timeout, disconnect, redirect, oversized response, unknown backend failure or
malformed lifecycle success returns `SHADOW_OUTCOME_UNKNOWN` and retains the
request ID. This cannot establish whether private telemetry committed. Use
`--status` with that same ID to reconcile; do not blindly replay the lifecycle
or substitute a new ID to bypass unresolved state. Status performs one read,
never acquires a lease, and labels summaries as historical evidence. Run sample
timestamps alone cannot establish current health freshness. Output contains
only fixed aggregate statuses, check/sample counts, opaque run/request IDs,
fences and timestamps; raw diagnostics, credentials, phones, receipt content
and amounts are absent. Exit code 2 means blocked or reconciliation required.

The adapter validates the exact versioned contract, bounded fence and counts,
120-second lease, state/timestamp consistency, 13 alert classifications and
zero business/provider counts. Sample parsing also validates the complete
health contract and the server aggregate SMS queue before projecting a bounded
summary. A 60-second source sample cannot become fresh merely because it was
read again, and explicit false freshness cannot become true in transit.
The backend-owned lifecycle fixtures are synthetic; their placeholder digest
does not prove database persistence.

This requires the deployed `20260930210000_shadow_supervisor_runs.sql` contract
and its authority/health prerequisites. Source implementation and synthetic
tests do not demonstrate a live completed run, durable production telemetry,
a scheduled Codex run or a working sender. No live shadow lifecycle is performed
by local verification tests. The tests cover real SDK stdio and CLI subprocesses
against synthetic loopback backends, strict inputs, BUSY/replay, authority
revocation, expired/stale fences and source health, malformed responses,
redaction, transport limits and retained-ID uncertainty without retries.
