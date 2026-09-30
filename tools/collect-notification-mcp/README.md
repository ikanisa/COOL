# Collect notification MCP bridge

This local stdio server exposes the governed Collect SMS receipt queue and
redacted Admin operations reads.
It never posts payments, changes balances, chooses recipients, or sends through
Apple Messages. The Supabase Edge boundary independently authenticates the
operator and enforces current admin permissions.

Runtime requirements:

- `COLLECT_SUPABASE_URL`: deployed Supabase project URL (HTTPS; loopback HTTP is accepted for local tests).
- `COLLECT_SUPABASE_ANON_KEY`: public project anon key.
- `COLLECT_OPERATOR_ACCESS_TOKEN`: short-lived access token for the currently approved Admin PWA operator. Do not write it to this repository or an MCP JSON file.

The configured Mac now also supports `COLLECT_OPERATOR_KEYCHAIN_HELPER`. When
explicit environment credentials are absent, the server reads only its dedicated
device-local Keychain item at call time. Normal WhatsApp OTP sign-in through
`src/operator_login.ts request` / `verify` authenticates the existing approved
second Admin without signup and verifies health/list. OTP input is hidden. No
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
live acceptance. It calls only Auth refresh and operator health/list. A
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
exercise all nine tool mappings, input rejection, redirect refusal and a real
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
supervisor and pause/resume tools require separate backend controls, rollout
evidence and authorization before any future implementation or enablement.
