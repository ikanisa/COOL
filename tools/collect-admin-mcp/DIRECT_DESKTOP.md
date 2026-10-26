# Local Direct-Desktop Operations

This is the native desktop entrypoint inside the current Collect MCP package.
Dot remains the supervisor. It uses a local reliability core, not a replacement
assistant. The entrypoint imports no Admin API/session client, opens no network
listener, and exposes no database, hidden endpoint or communications API tool.
The existing read-only Admin server is a separate entrypoint and catalogue.

The executable runtime supports **dry run only**. No native application adapter
has passed host acceptance. Configuration cannot enable a mock or manufacture
native dispatch, source observation, calls, voice or Admin writeback. Those
operations return a blocked/unavailable result. Tests inject synthetic adapters
directly into the core; their observations are labelled `mock`, never Mac proof.

## Run And Verify

Use Node 24.19 or later for this entrypoint's built-in `node:sqlite` journal.
There are no new package dependencies or installation step.

```sh
cd '/Volumes/T7/01 Projects/COLLECT/tools/collect-admin-mcp'
npm run check
npm run desktop:test
npm test
node src/direct-desktop/server.mjs
```

The last command is an MCP STDIO process, not an HTTP server or interactive CLI.
Stdout contains JSON-RPC only. Use Node directly in an MCP host rather than a
package manager that may print non-protocol text. No dev server is necessary.

The journal defaults to:

```text
/Users/jeanbosco/Library/Application Support/Collect Direct Desktop/journal.sqlite
```

The actual default uses the current user's home directory. An absolute
`COLLECT_DESKTOP_JOURNAL` can select another private path outside the repository.
Its parent must be owned by the current POSIX user with mode `0700`; the regular
file must be owned with mode `0600`, one hard link and no symlinked ancestors.
Existing permissions are checked, not silently repaired. Keep operational data
off the exFAT checkout and outside shared/synced folders. A filesystem's truthful
durability and available storage remain host obligations.

`COLLECT_DESKTOP_POLICY` optionally names an absolute JSON policy file. The
file is reread and validated around operations. No tool edits it or clears Stop.
`config/operator.example.json` is **project-owned configuration**, not an official
ChatGPT/Codex configuration format. Its machine contract is `POLICY_SCHEMA` in
`src/direct-desktop/contract.mjs`. The owner-confirmed specification is the
version 1.0 `Dot on Mac mini: direct-desktop operations` prose supplied in chat.
No former ZIP is required; separately referenced machine schemas were not
supplied for verbatim comparison. The later `Collect-MoMo.md` attachment covers
an Android/Cloudflare payment pipeline and does not change this runtime's scope.

A reviewed host configuration can launch this separate entrypoint using the
official [Codex STDIO settings](https://learn.chatgpt.com/docs/extend/mcp?surface=cli):

```toml
[mcp_servers.collect-direct-desktop]
command = "/Volumes/PRO-G40/Development/Node/bin/node"
args = ["/Volumes/T7/01 Projects/COLLECT/tools/collect-admin-mcp/src/direct-desktop/server.mjs"]
startup_timeout_sec = 10
tool_timeout_sec = 45
```

On 2026-10-19 the project entry was added and the matching dry-run command was
registered with `codex mcp add`. `codex mcp get collect-direct-desktop --json`
verified the effective enabled global STDIO entry. The project entry alone was
not visible in that CLI's effective configuration; no trust setting was changed.
A direct host launch returned twelve tools and `ready_dry_run`, with a durable
journal, no lease and zero attempts. Discovery in the
running chat and a Dot connection require independent evidence. Do not substitute
the older removed `collect-notification-mcp` path, or the API-backed `server.mjs`,
for this entrypoint.

## Tools And States

The fixed local catalogue is `operator_health`, `observe_admin_queue`,
`prepare_notification`, `dispatch_prepared_notification`, `reconcile_attempt`,
`write_admin_outcome`, `prepare_call`, `start_prepared_call`, `inspect_call_state`,
`end_current_call`, `get_pending_exceptions`, and `stop_all`.

`prepare_notification` accepts the strict `PREPARE_SCHEMA` exported by
`contract.mjs`. It checks a confirmed visible source, previous-attempt/authority
checks, one visible recipient, explicit E.164 destination and country context,
approved purpose and exact source labels. It does not infer a country or prove
the supplied UI assertions. Actual visible-source verification is a native
adapter acceptance obligation. A minimal supported receipt uses
`payment_receipt_v1` and copies these fields without calculating a balance:

```text
Payment confirmed. Reference: <transaction_reference>. Amount: <amount_label>. Balance: <balance_label>.
```

Other templates and campaigns are outside this initial implemented contract.
The operation identity hashes namespace, tenant, reference and notification kind
as structured data. Changing a destination, message or template cannot create a
fresh attempted operation. A changed unsent source can supersede an older ticket;
the older immutable ticket then becomes ineligible for dispatch.

The disk journal separates tickets, jobs, attempts, observations, policy revisions,
UI sync attempts, control state and ordered audit events. SQLite transactions use
`BEGIN IMMEDIATE`, full synchronous writes and schema/integrity checks. Only a
durable journal can arm even a synthetic adapter dispatch.

Each native-effect workflow must hold the shared journal's exclusive lease and
monotonic fence. No executor automatically steals an expired lease. An abandoned
lease closes the execution gate and appears in the exceptions queue. Recovery
requires persistent Stop, an exact expired lease token/fence, an owner review
reference and an independently verified quiescent old executor. The optional
`reconcile_attempt.recovery` request cannot supply that proof itself. A trusted
quiescence verifier must be supplied by the native integration; the current
runtime has none and refuses recovery. Successful synthetic recovery advances
the fence, permits read-only reconciliation and keeps Stop set. This version
supplies no automatic lease steal or stop-reset tool. All future native actors
must share this journal.

The attempt is committed as `DISPATCH_ARMED` before an adapter may cross the
action boundary. The adapter must request its single-use permit with fresh
source/app/account/recipient/content evidence immediately before the UI action.
The core freezes execution snapshots, expires action callbacks when their
invocation ends, and rechecks policy, expiry, Stop and lease. Stop latches in the
running process before its durable write, so temporary journal failure cannot
reopen an already pending action. These checks do not make a
native UI click atomic with the journal. Restarted arming is exposed as
`OUTCOME_UNKNOWN`; any existing attempt consumes the operation permanently in
this version, including a positive pre-action `FAILED_NO_SEND` result.

`OUTGOING_OBSERVED` always retains `delivery_state: unverified`. An outgoing
bubble is not universal delivery or carrier confirmation. Reconciliation cannot
turn the absence of a bubble into proof that nothing was sent.

Admin writeback accepts an attempt ID, not an invented result. It has its own
durable arm, visible source/account checks, readback and uncertain state. A lost
reply can be resolved by matching UI observation; it does not trigger another
message or blind UI write. Outcome revisions keep later reconciliation from
being hidden by an older synchronized result.

`stop_all` bypasses the normal STDIO work queue and persists the local inhibit
gate. It reports its scope truthfully. It does not claim to cancel Dot tasks,
schedules, unrelated calls or system-wide audio. Calling and customer audio
are unconfigured; no tool ends an unowned call.

## Native Acceptance Still Required

The supplied start prompt authorizes no real send/call. The next native pilot
requires a signed-in visible Admin source, a reviewed supported native adapter,
owner-designated consenting recipient, an explicit bounded test gate and observed
UI evidence. The gate must identify channel/account, permitted purpose, exact
recipient set, expiry and exclusions. Enabling JSON fields alone is insufficient.

Native dialing, assisted two-way voice and unattended lifecycle remain separate
capabilities. The audio inventory does not demonstrate a working two-way route.
An owner-started isolated native customer context, two-way signal test, no owner
speech leakage, echo/interruption checks and owned-call teardown are required.
No ChatGPT automation, security-prompt helper or external model/voice API may
replace missing native support.

Current host evidence and implementation acceptance are recorded in
`docs/release/direct-desktop-operations-2026-10-03/` at the repository root.
