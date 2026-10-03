# Collect × Codex: manual shadow monitoring

> Owner scope amended 1 October 2026: use revolut-design directly as the sole design skill. The separate mandatory mobile checklist and its gates were removed. Changed package bytes are outside previous integrity attestations; dated product observations retain their original scope.

This is the next local implementation stage after the [read-only MCP and Admin operations work](../collect-codex-2026-09-30/README.md). The user selected MCP connection plus Admin operations UI and asked to continue. This stage adds an explicit one-shot monitoring command and persisted Admin history. It does not enable a scheduled supervisor or notification dispatch.

The current host profile retains its five read tools. The final live read-only reconciliation probe returned `SHADOW_SESSION_REQUIRED` and exited 2, so local reauthentication is required. Deployment of the new migration and authenticated live end-to-end validation remain outstanding. No production shadow lifecycle was run in this task, and no OTP or provider message was sent.

## Implemented behavior

`20260930210000_shadow_supervisor_runs.sql` adds a global `collect_platform` shadow lease, immutable samples and durable run records in the private `collect_security` schema. A run has one request UUID, a monotonically increasing fence and a fixed 120-second lease. At most 60 new runs can start in a rolling hour. The server derives system-health and assisted-SMS aggregates from existing services; clients cannot supply outcomes, counters or health facts. Sampling requires current source health, and completion requires that persisted sample to remain fresh.

The three lifecycle RPCs write only shadow telemetry and lease metadata. Current authenticated platform-owner authority, both `system_health.read` and `notifications.read`, confirmed registration approval and the original actor/session protect every lifecycle step. Reauthentication permits read-only reconciliation by the original actor; it cannot resume the old session's lease. Direct table access is revoked from API roles, including `service_role`.

The MCP server registers `begin_supervisor_run`, `sample_supervisor_run`, `complete_supervisor_run` and read-only `get_supervisor_run`. The first three carry write annotations because monitoring metadata is persisted. The desktop host profile still enables only `collect_notification_health`, `collect_list_pending_receipts`, `get_collect_health`, `get_notification_status` and `list_notification_failures`. No lifecycle tool was added to that host allowlist.

The manual CLI initializes the real MCP stdio protocol, calls the fixed begin/sample/complete sequence once, and closes. Network requests are bounded at 15 seconds, with a 60-second overall transport deadline and bounded response bodies. It prints only safe status codes, opaque request/run identifiers and aggregate evidence. It has no retry loop. Unknown outcomes retain the request UUID for an independent read.

Admin `/admin/automations` displays read-only platform history, the current lease, Kigali timestamps, sampled observations and bounded keyset pagination. Both read permissions are checked before loading history; the backend remains authoritative. Loading, unavailable, denied, failed, empty and stale reads are explicit. A replaced session suppresses an old response. Completed observations remain dated history and do not establish current service health or message delivery.

## Local operator workflow

Use the existing configured Collect profile and dedicated Keychain helper from this checkout. No credential belongs in command arguments or this report. After the candidate migration is reviewed and deployed, an approved operator can authenticate with the existing local flow:

```sh
python3 scripts/collect_operator_login.py request
python3 scripts/collect_operator_login.py verify
python3 scripts/collect_operator_login.py check
```

`request` explicitly sends an OTP. These commands are provided for the operator; this task did not run `request` or `verify`.

Retain a fresh request identifier before a manual run:

```sh
collect_shadow_request_id="$(uuidgen)"
python3 scripts/collect_operator_login.py shadow --request-id "$collect_shadow_request_id"
```

If the response is uncertain or the connection is interrupted, reconcile the same identifier through a read:

```sh
python3 scripts/collect_operator_login.py shadow-status --request-id "$collect_shadow_request_id"
```

A found running record is not completion. An absent record does not authorize an automatic replay. An expired record cannot be resumed. Keep the request identifier with the operator's local evidence and decide the next action after reading the durable state.

## Verification record

The final machine-readable record is `validation.json`; its file hashes identify the source and evidence checked in this shared worktree. Backend UAT is limited to a disposable local database restored from schema and API privilege definitions, with synthetic identities and empty scheduling fixtures. It does not validate hosted deployment, real provider behavior or a production identity. The unchanged business-table fingerprints start from empty fixtures; they do not establish behavior across production records.

| Check | Final result | Evidence |
| --- | --- | --- |
| MCP transport, contracts and lifecycle CLI | 77/77 passed | `mcp-tests.log` |
| TypeScript | Passed | `mcp-typecheck.log` |
| Isolated backend authority, leases and adversarial UAT | 89/89 passed | `backend-uat/result.json` |
| History, real SDK repository and existing Automations tests | 37/37 passed | `admin-final-tests.log` |
| Local operator wrapper, without network/Keychain/subprocess actions | 6/6 passed | `operator-wrapper-tests.log` |
| Six-file Flutter analysis | No issues | `admin-analysis.log` |
| Sole design-authority hygiene | Passed | `design-authority.log` |
| Live read-only reconciliation | Blocked: `SHADOW_SESSION_REQUIRED` | `live-read-only-reconciliation.log` |

These are 209 passing tests/UAT cases across the primary suites. Supplemental backend schema validation passed 11 fixtures, and migration structural checks passed 3 tests with 10 assertions. Historical attempts and focused rechecks remain in files with `attempt` or `targeted` names; use the final listed logs for current results. These checks do not constitute whole-system acceptance.

The real Admin service-client tests cover the fixed authenticated read, paired cursor arguments, invalid request rejection, malformed history, same-user session replacement and serialization refusal without fallback. They also validate actual receipts generated by the isolated backend UAT through the pinned SDK and strict history parser. The installed prerequisite migration statements and relevant authority/health function bodies were compared with the current source; byte and normalized parity are recorded in `backend-uat/prerequisite-source-parity.json`. Wrapper tests use a synthetic profile and stubbed subprocess, covering fixed routes, request retention, argument rejection and sanitized setup failures. MCP tests cover the real local stdio sequence against fixtures and uncertainty boundaries.

The earlier release web build belongs to the previous stage and excludes this stage's new history view. This stage's Flutter tests compile the current widgets. Neither result is whole-system or production acceptance.

## Design and remaining work

The owner-selected [revolut-design skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>) remains the sole design authority. The history view uses existing shared Collect components and tokens. Synthetic captures are regression evidence; an authenticated Business/operator comparator is still unavailable. The authority hygiene gate does not certify visual fidelity, and no surface is claimed to match 100 percent.

The final opaque 1440×1000 [light capture](shadow-history-light-synthetic.png) and [dark capture](shadow-history-dark-synthetic.png) were inspected for readable status, historical counts and second-level Kigali timestamps. They show the history component with a synthetic backend contract. The tests also exercise 320-pixel width with doubled text and fatal hit-test misses; they do not provide an authenticated route comparison.

Live authentication, migration deployment, host MCP reload and authenticated end-to-end evidence remain open. Dedicated unattended identity, event acknowledgements, scheduling, recovery automation, an unattended Android SMS gateway and delivery callbacks are later work. The manual shadow run changes no payment, ledger, receipt, notification outbox, sender heartbeat or provider state.
