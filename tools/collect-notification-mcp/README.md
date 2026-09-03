# Collect notification MCP bridge

This local stdio server exposes only the governed Collect SMS receipt queue.
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
second Admin without signup, verifies health/list, then saves only the public
config and short-lived user access token. OTP input is hidden. No browser store,
service key or refresh token is used. Expiry fails closed and requires a normal
reauthentication; this is not an indefinitely renewable operator identity.

`src/stdio_preflight.ts` verifies the real MCP initialize/health/list exchange
and prints only aggregate status. On 3 September this and the separate
Keychain-backed live preflight both passed against production. The existing
minute heartbeat is now ACTIVE in read-only/no-send mode; seven queue-control
tools remain excluded from the host allowlist and receipt flags remain OFF.

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
and a 20-second tool timeout. Its initial allowlist contains only
`collect_notification_health` and `collect_list_pending_receipts`. No credential
value is saved in the host configuration. Registration is not authentication
or proof that the current task has reloaded the MCP inventory.

Run `pnpm preflight` in the same governed runtime environment. This performs no
network request and reports only missing variable names or safe issue codes.
It rejects service-role/secret API keys, non-user tokens, a mismatched issuer and
tokens with less than 60 seconds remaining. These local claim checks do not
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
durable state before acting again. A short-lived token needs approved renewal;
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
