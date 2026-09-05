# Collect operator connection and legacy-sender preflight

**Current, 4 September Kigali:** the earlier access-only session expired. Queue
health/list access is blocked, not currently passing. Opt-in Keychain renewal
now passes local QA but requires a fresh normal OTP login and actual rotation
readback before live acceptance. The minute monitor remains no-send with only
two read tools. See [renewal evidence](HYBRID_SESSION_RENEWAL_2026-09-04.md).

The authenticated PASS statements below are historical observations.

**Latest continuation supersedes the earlier snapshot below:** normal approved
WhatsApp OTP authentication, scoped macOS Keychain provisioning, independent
live health/list and actual stdio MCP checks now PASS. The existing minute
heartbeat is ACTIVE in **read-only/no-send** mode. Only health/list tools are
enabled; all five hybrid flags remain OFF. The user reconfirmed deployment and
configuration authority. See [deployment and chosen handover plan](HYBRID_CONTINUATION_DEPLOYED_2026-09-03.md).
The short-lived session has no stored refresh token and reports expiry once;
it does not establish durable unattended authentication. Legacy services remain
active pending receiving-device readiness and the fresh-payment cutover.

**Later 3 September update:** fresh second-operator Admin login and reload
persistence now PASS. The separate MCP process still lacks its public key and
short-lived approved user token; its current safe preflight fails closed with
zero network or queue actions. Both receipt schedules remain PAUSED. See
[authenticated UAT](HYBRID_AUTHENTICATED_ADMIN_UAT_2026-09-03.md). Statements below
that Admin sign-in remains incomplete describe the earlier observation.

Observed: 3 September 2026, 19:26 UTC

Verdict: **LOCAL MCP REGISTERED READ-ONLY; AUTHENTICATION AND LEGACY CUTOVER OPEN**

## Completed

- Registered `collect-notifications` in the local Codex host configuration using
  absolute Node/server paths, the verified public production project URL and
  forwarded key/token environment-variable names only.
- Host allowlist exposes only `collect_notification_health` and
  `collect_list_pending_receipts`. The other seven queue-control tools are not
  enabled through this profile. The Collect heartbeat remains PAUSED.
- Actual stdio startup/initialize/list/call UAT passes. The server exposes exactly
  nine bounded tools and returns a controlled error when credentials are absent.
- TypeScript check and all 11 MCP/client/preflight tests pass. Requests reject
  action overrides, insecure or credential-bearing endpoints and redirects;
  a 15-second deadline is enforced without automatic retry.
- The focused Admin/release-document suite passes 40 tests and the repository
  whitespace check passes. The existing Collect heartbeat prompt now explicitly
  requires the approved legacy takeover and accepted pilot before recurring
  claims/sends; its saved status was read back as PAUSED.
- A no-network credential preflight reports only safe missing-variable names.
  With the host's public project URL supplied, the public key and approved user
  token remain missing. No token was read
  from a browser, printed, saved in Git or placed in the MCP configuration.
- A live in-app-browser check still shows that the existing account has no Admin
  access. The approved-operator WhatsApp sign-in screen is ready. No account
  identifier was entered and no OTP was requested by this run.

## Material finding: the old pipeline is still send-capable

Both Codex schedules are PAUSED, but these native LaunchAgents are active:

| Service | Observed PID | Role |
| --- | ---: | --- |
| `com.ikanisa.buri-munsi-messages-watcher` | 58347 | Five-second receipt processing and direct Mac Shortcuts dispatch path |
| `com.ikanisa.buri-munsi-nearby-receiver` | 1106 | Encrypted iPhone relay, legacy gateway and dispatch-response path |

The active configuration uses `GOOGLE_SHEETS` as its ledger and
`IPHONE_PRIMARY_WITH_MAC_SHORTCUTS_FALLBACK` as its outbound mode. The fallback
is enabled and invokes `Buri Munsi Receipt Flow`. The watcher source actually
calls `MacShortcutsDispatcher.dispatch`; its older introductory statement that
it never sends is not an accurate description of the current call path.

This is evidence of an active, send-capable legacy configuration, not evidence
that a particular SMS was sent during this inspection. No service was stopped,
no Shortcut was executed and no private message, queue packet or ledger row was
opened. PIDs are a point-in-time observation and must be refreshed at cutover.

Runtime source/config hashes (no secret values):

- Watcher: `aab84bcfebc44d10ef9e377e18e766930272fc88aac4f47d6d804b6815e1444b`
- Dispatcher: `ab7405fcf5d9515354df7e223af87f16822cda82e8ee985c38aa68cf6f2c31b8`
- Active configuration: `7f8763d9660b8b98bb990b02f9daff82759ec17f77d79b1767bdb750e8d047b2`

## Remaining gates

1. Complete a fresh approved Admin sign-in, then inject a short-lived user token
   and the public project configuration through an approved runtime-secret path.
   Refresh the Codex MCP inventory and run the authenticated read-only preflight.
2. Agree and record the legacy takeover window. At that window, pause or isolate
   both exact legacy service paths and the linked iPhone automation, retaining
   their recoverable configuration, queue state and receipt history. Do not
   simply enable Collect alongside the active legacy sender.
3. Reconcile old sent/uncertain receipt identities with the Collect pilot scope;
   no historical replay. Confirm only one sender owns each pilot receipt.
4. After the authenticated read-only check and legacy takeover pass, authorize
   the exact supervised pilot and enable its queue-control tools while keeping
   the heartbeat paused. Complete the physical Android receipt/payment and
   Mac-to-feature-phone test, including exact body, balances/reference and
   handset receipt evidence.
5. Only after that physical pilot is accepted, activate the one-minute heartbeat
   under the existing action-time confirmation and uncertain-no-retry policy.

This run performed no production financial write, provider send, flag activation,
service shutdown, store action or accountable release approval. Legacy services
continue independently until the owner-approved takeover.
