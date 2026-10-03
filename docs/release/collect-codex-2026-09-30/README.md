# Collect × Codex implementation readback — 30 September 2026

The read-only MCP stage and Admin operations view are implemented locally. The configured Codex host enables five read tools. Current live verification is blocked by operator reauthentication. This task has not deployed the Admin build, navigation migration or new health contract, enabled an unattended supervisor, or sent an OTP/SMS.

This is implementation evidence for the owner's selected scope, **MCP connection plus Admin operations UI**. It follows the attached guide's read-only-first delivery stage. It does not certify the proposed end-to-end production sender or every proposed Admin capability.

## MCP connection

The existing `tools/collect-notification-mcp` bridge is extended rather than duplicated. It uses the configured current-user session and dedicated local Keychain helper. Application services authenticate and authorize each read; client-side checks do not grant permissions. No client service-role key or independent financial calculation was added.

| Enabled host tool | Service and purpose |
| --- | --- |
| `collect_notification_health` | Existing authenticated operator queue/gate health |
| `collect_list_pending_receipts` | Existing bounded pending work read |
| `get_collect_health` | Public `admin_system_health`, fixed `p_id: system` |
| `get_notification_status` | Public `admin_get_hybrid_sms_receipt`, exact UUID |
| `list_notification_failures` | Public `admin_list_hybrid_sms_receipts`, definite no-send or uncertain states, maximum 25 rows |

The new operational reads remove names, telephone numbers, message bodies, amounts, balances, references, hashes and arbitrary diagnostics. Requests refuse redirects, enforce a 15-second network/body deadline and a 256 KiB response limit, validate fixed schemas and return safe error codes. Expired or excessively future-dated health samples clear metrics and report unknown. These measures cover the new operational reads; existing queue reads retain their existing contract.

Existing supervised control tools remain registered in the bridge for its separate operator workflow, but this host excludes them. Tool annotations are descriptive; the host allowlist and backend authorization remain separate controls. There is no scheduled job created by this task.

The configured local profile is `collect-notifications`; its `/Volumes/PRO-G40/COOL` path resolves to this checkout. Configuration registration and an SDK initialize response do not establish successful authenticated backend calls. Current logs show:

- `mcp-session-preflight.log`: `BLOCKED_OPERATOR_SESSION_REAUTHENTICATION_REQUIRED`.
- `mcp-preflight.log`: `BLOCKED_STDIO_MCP` at `collect_notification_health`.
- Both report zero queue mutations, zero provider sends and no printed credentials.

`get_collect_health` requires the version-1 redacted operational-health contract from `20260930160000_redacted_operational_health.sql`. Its availability on the hosted backend remains unverified. Current reads require the backend's approved platform Admin identity; a separate tenant-scoped unattended supervisor principal was not implemented.

## Admin operations

The canonical `/admin/automations` route requires `system_health.read`. SMS data separately requires `notifications.read`. The page and persistent shell banner consume the actual authenticated operator-health service; scheduler health uses the existing authenticated operational-health RPC. Strict response validation, session fencing, independent section errors and 60-second display freshness prevent malformed, expired or previous-session measurements being shown as current.

The page shows the SMS receipt gate, queue states, oldest queued receipt, checked time in Africa/Kigali, operator heartbeats and the separate app-notification scheduler. It explicitly identifies unavailable Codex run telemetry, gateway measurements and schedule controls. A heartbeat is not presented as a successful supervisor run or delivery result. Unknown send outcomes link to receipt investigation; there is no newly introduced retry/send control.

Shared Admin changes make status text visible with icons, compact references, show Kigali timestamps, and reflow records at narrow widths without hiding actions. Live events announce **New activity available** and require **Refresh records**; loaded rows remain stable until explicit refresh. Account/session changes reset the queue view, and events arriving during an in-flight load remain pending.

The manual status refresh is exercised against both independent services and performs no writes. Capture validation also verifies that the real Collect logo has decoded before imaging; light and dark renders use current typography. The selected sidebar icon contrast issue found in the light capture is corrected with the existing rail foreground token. Both inherited icon colors are checked by the final capture tests.

Server-configured navigation remains authoritative. The local route is not injected into a configured menu that omits it. `20260930200000_admin_automation_navigation.sql` provisions the server menu entry while preserving an existing disabled/customized key or occupied route. It serializes its absence check to avoid governance-trigger side effects on skipped insertions. Hosted menu visibility requires the normal migration deployment and may remain disabled by server policy.

## Design evidence

The sole design authority is the owner-selected [revolut-design skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>). The page adapts shared Collect tokens/components and preserves product terminology and access controls. The supplied operations specification is product workflow input, not a competing visual authority.

The inspected static Business/operator reference captures informed this surface. An exact authenticated desktop comparator and full route/state interaction comparison remain unavailable. No 100% fidelity or mobile acceptance claim is made. The light and dark PNGs in this folder are synthetic widget renders of the implemented shell at 1440 × 1000 with the actual Inter font; they contain no production records and are regression evidence, not new design specifications. The native mobile app and public website were outside this change's scope.

## Validation

| Check | Result and scope |
| --- | --- |
| MCP TypeScript check | Passed: `node_modules/.bin/tsc --noEmit` |
| MCP tests | 55/55 passed in the adapter's final execution, covering SDK transport, bounds, malformed data, redaction and stale metrics. No raw log was retained; this is the recorded execution result. |
| Flutter Admin broad run | 258 passed; one retry test tapped below the viewport and failed. The test now scrolls and renders before tapping; its targeted rerun passed (1/1, `route-retry-test.log`). Original evidence is retained in `flutter-tests.log` and `route-retry-attempt1.log`. The whole broad run was not repeated after this harness correction. |
| Final Automations tests | 12/12 passed with actual logo decode, manual refresh, expiry, partial error, permissions and 320px doubled-text checks; see `automations-final-tests.log`. |
| Final sidebar capture checks | 2/2 passed after the icon contrast correction, including actual inherited foreground; see `sidebar-capture-tests.log`. |
| Admin web compilation | JavaScript release build passed (exit 0); see `admin-build.log`. Output: `output/collect-codex-admin`. This build has no supplied live credentials and is not a deployment. |
| Repository static analysis | `flutter analyze --no-pub --no-fatal-infos` passed with **No issues found**; archived partial evidence and the separately configured syntax auditor are excluded by current repository configuration. |
| Sole-design-authority hygiene | Passed: `make revolut-design-authority`; see `authority.log`. This does not certify visual fidelity. |
| Navigation migration | Structural validator passed. Scoped synthetic PostgreSQL replay verified initial insert, repeat-run governance stability, customized/disabled existing-key preservation and occupied-route preservation. Supporting dependencies were stubs; this was not full-schema/RLS/hosted acceptance. Database was removed; no raw log/fixture retained. |
| Local login wrapper | Python compilation passed. Uses the configured profile and existing hidden-input/Keychain login flow. |
| Current authenticated MCP check | Blocked; no live backend acceptance claim. |

The initial checkout contained substantial existing work, and another task committed the shared checkout during implementation. `df1150ea` was HEAD at final validation start. This task initiated no commit or push. Validation is scoped to these changes and does not establish whole-system, device, carrier or production acceptance.

The final build command was:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --target lib/main_admin.dart --output output/collect-codex-admin
```

The earlier build's optional WebAssembly compatibility pass was cancelled to reduce host load; its partial log is retained. WebAssembly acceptance was not tested. `validation.json` records the scoped source and artifact hashes, successful checks and live-authentication boundary. Logs and the build output are local artifacts excluded by repository ignore rules.

## Complete the live read check locally

Run these commands from the repository in a local interactive terminal. The first requests the existing approved operator's normal sign-in OTP; the second accepts it through hidden terminal input and stores credentials only through the dedicated Keychain flow. Keep OTPs/tokens out of chat and reports.

```sh
python3 scripts/collect_operator_login.py request
python3 scripts/collect_operator_login.py verify
python3 scripts/collect_operator_login.py check
```

Reload the configured MCP connection or start a chat with its updated inventory. Keep the five-tool read allowlist. The `check` command performs SDK initialization, existing queue reads, operational health and a bounded failure read; it calls exact receipt status only when a real failure row exists. An empty failure page leaves that status call unverified. Successful reads still do not prove a supervisor run, permission to send, provider availability or delivery.

If the new health contract is absent, apply it through the project's normal reviewed deployment process before repeating the read check. Deploy the navigation migration and Admin build through that same process for hosted UI access. No production deployment credentials or approval were inferred from local test results.

## Remaining proposed capabilities

The inspected backend already has atomic financial posting, balance snapshots and an assisted receipt outbox. An incoming SMS observation does not independently settle a payment. The existing human-assisted send lifecycle remains intact; `uncertain` must be investigated rather than automatically retried.

The proposed unattended architecture still needs dedicated scoped identity, supervisor leases/fencing/run history, durable commit-safe event acknowledgement, server-enforced action caps, operational exception services and approved constrained write tools. A programmatic Android sender also needs durable local attempt journaling, per-part callbacks and physical restart/recovery evidence, or an approved provider integration. The current services do not report telephony/SIM/permission state or carrier delivery. These missing capabilities are explicitly unmeasured in the UI; no placeholder success or inactive control is substituted for them.

Primary-receipt lifetime identity must be reviewed before expanding template versions or resend operations. Current template checks and uniqueness suppress current duplicates, but future template releases must not create another primary receipt for an old posting. Native schedule editing and a working Run now control also require an actual runner integration.

These are subsequent stages of the attached guide, requiring concrete backend/device capabilities and observed pilot evidence. This read-only implementation does not authorize them.
