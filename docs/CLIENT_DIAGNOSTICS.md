# Fixed-code client diagnostics

The member app and shipping cookie-authenticated Admin entrypoint can deliver the existing safe `CollectDiagnostics` events to the existing Supabase business backend. No third-party crash SDK or telemetry account is required. This is client-reported application health, not financial evidence or an independently measured crash rate.

## Collection boundary

`CollectDiagnostics.record` still accepts only a fixed enum plus a bounded attempt number. The console contract is unchanged, so the existing QA diagnostic observer remains compatible. The remote sink never receives an exception, stack trace, request, URL, receipt, SMS, phone number, email, credential, device identifier, or arbitrary caller metadata.

| Code | Source boundary | Severity |
| --- | --- | --- |
| `startupStarted` | `CollectStartupController` starts initialization | info |
| `startupWaiting` | Startup exceeds the waiting threshold | info |
| `startupTimedOut` | Startup deadline expires | warning |
| `startupFailed` | Initialization rejects | error |
| `startupReady` | Initialization completes | info |
| `frameworkFailure` | `CollectGlobalErrorHandlers` framework callback | error |
| `platformFailure` | `CollectGlobalErrorHandlers` platform callback | error |
| `diagnosticsSuppressed` | Existing diagnostic burst budget is exhausted | warning |

The fingerprint is SHA-256 of `collect.diagnostic.v1|surface|environment|build_version|source_revision|code`. It groups a fixed code within a source/release. It is **not** a stack fingerprint, symbolicated crash, or source-line diagnosis. Source locations are mapped locally by the table above and the release source tree; stack data is never uploaded.

Builds supply `COLLECT_BUILD_VERSION` and `COLLECT_BUILD_SOURCE_ID`. The source identifier accepts only a 40- or 64-character lowercase hexadecimal source identity; malformed/missing values become `unknown`. Build versions use the existing bounded numeric version grammar or `unknown`. An unknown label is displayed honestly and does not prove release attribution.

The maintained Android and Admin release wrappers now generate both values through `scripts/qa/client_diagnostic_identity.py`. The version must equal `pubspec.yaml`. The source ID is a deterministic SHA-256 over the actual `lib` and vendored Dart inputs, `pubspec.yaml`, `pubspec.lock`, surface and validated public define profile. It is generated before compilation and rechecked afterward; changed inputs or a conflicting preexisting label fail the build. Android also requires the version and source ID to occur in both compiled APK/AAB app binaries, and the existing Play runtime gate recomputes the identity against its artifact/profile hashes. The Admin wrapper carries the identity in build metadata. This client source/profile identity is separate from complete native-toolchain, signed-artifact and deployed-resource provenance.

The generated source manifests are `.cache/client-diagnostics/android.json` and `build/admin-diagnostics-source.json`; they contain input hashes, not define values or credentials. The public Admin `version.json` includes the diagnostics version/source ID. Qualification and preview profiles normalize to `staging`; the current platform profile normalizes to `production`. Direct ad-hoc Flutter builds still need explicit validated defines, otherwise their diagnostic label remains `unknown`.

## Client delivery and local custody

The queue delivers only while an existing authenticated member or Admin session is current. Anonymous and pre-authentication bootstrap failures remain available through the existing console/QA boundary; this implementation creates no anonymous ingestion endpoint.

The queue holds at most 64 reports, persists at most 64 KiB, sends at most eight reports per batch, and expires reports after 24 hours. Equal unsent fingerprints coalesce up to 64 occurrences. Once dispatched, a report's random ID and payload stay immutable, including after an unknown acknowledgement or restart. Server replay handling therefore cannot double-count a repeated batch.

Delivery uses one logical attempt at a time with exponential retry delay from five seconds to five minutes. A timeout, unavailable schema, denied session, quota pressure, or offline connection cannot block startup, recovery, or a financial operation. Queue/storage/transport failures are caught and are never sent back into the reporter. Malformed/permanently rejected contracts are dropped. The existing business request retry rules are unchanged.

The existing `shared_preferences` dependency stores only validated safe reports, their local queue age, and a one-way local session custody fence under `collect.diagnostics.v1.member` or `collect.diagnostics.v1.admin`. Raw identity and credential values never enter that storage. Logout/account/session changes clear pending reports. A restored queue is admitted only for its matching session fence. Expired local bytes are removed when the app next processes the queue; an app that is not running cannot physically clear its storage.

Persistence retains one actual plugin write until it settles, with only the newest pending snapshot coalesced behind it. A completion timeout does not cancel a plugin write or release that slot, so a late old-session write cannot complete after a newer snapshot has been dispatched. Delivery shares one observation of at most three seconds per storage drain; later flushes reuse that result instead of retaining additional timeout listeners on a stalled write. Disposal waits at most two seconds before returning; neither operation waits indefinitely for an unavailable store. The original write and final queued snapshot can still finish afterward. A logout clear is ordered behind an unresolved write, and physical clearing remains unconfirmed until the store actually completes it. Authentication/session fencing continues to deny upload of stale-session reports throughout that interval.

The member transport reuses its configured, already-owned authenticated client. The Admin transport uses its existing cookie/CSRF boundary and deliberately does not clear authentication or retry business requests when telemetry receives an error. The Admin diagnostics host remains above the fatal recovery host.

## API and server admission

- `POST /v1/diagnostics`: an active authenticated member session.
- `POST /api/admin/diagnostics`: the current Admin BFF account and CSRF boundary.
- `GET /api/admin/diagnostics`: the existing `system_health.read` permission, checked again against the current BFF account and actor after the aggregate read. Query parameters are refused.

The POST envelope is exactly `{contract_version: 1, reports: [...]}`. Each report contains the eight existing safe console fields plus `report_id`, `source_revision`, `fingerprint`, and `occurrences`. The server limits the request to 12 KiB, refuses unknown fields and invalid enum/type/bounds, recomputes the fingerprint, and binds the surface to the authenticated actor. A successful commit returns HTTP 202 with exactly `{contract_version: 1, accepted: true}`.

Atomic admission uses the existing live-session mutation guard and existing Admin account guard. Existing `admin_rate_limits` rows provide a 16-batch-per-principal-per-hour budget and a global 256-batch-per-hour budget. A diagnostic report stores no principal/session/device identifier. Quota accounting uses a one-way principal hash in a distinct `client_diag:v1:` namespace; these are derived subject identifiers, not anonymous data, and remain covered by the retention inventory. Quota rows expire within two hours.

`app.client_diagnostic_reports` stores only fixed safe fields, a random report ID, a payload digest, and server-controlled coarse receipt hour/expiry. Anonymous/authenticated/service-role clients receive no direct table access. Runtime access is limited to SELECT/INSERT/DELETE, with RLS and the existing application fence trigger. A changed payload under an existing report ID is refused. A lost commit reply is retried with the same immutable payload.

The aggregate read contains at most 64 groups with fixed surface/environment/release/code/fingerprint, severity, occurrence/report counts, and the latest receipt hour. It contains no report IDs or quota identities. `truncated` reports omitted groups honestly. The authorized `collect_admin_diagnostics` MCP tool reads this same contract without a generic SQL or arbitrary endpoint capability.

## Schema, retention, and maintenance

The additive source is `supabase/schema-src/client-diagnostics.sql`; its exact generated migration is `20261029120000_collect_client_diagnostics.sql`. Historical migrations and baseline bytes remain unchanged. `generate_baseline.py --check` checks additive source/migration equality as well as the original baseline. The migration adds one table, one expiry index, one RLS policy and one existing-function fence trigger; it creates no new function or user grant.

The read window and report eligibility are 24 hours. Ingestion removes up to 1,000 expired rows per request. The existing authenticated maintenance path also calls bounded diagnostic cleanup. Physical deletion follows the next successful cleanup pass and may lag if maintenance is unavailable. Diagnostic cleanup has its own truthful status and cannot make successful financial processing ambiguous. The global write budget bounds the report population; no unbounded user-provided grouping metadata exists.

The additive retention schema profile preserves previous profile and approval identities. Existing approvals are not silently extended to the new schema. Identity-free aggregates have no subject selector; derived quota rows remain explicitly inventoried. This does not authorize a new personal-data erasure policy.

## Verification and remaining acceptance

Local tests cover safe schema rejection, fingerprint stability, queue/storage limits, coalescing, immutable retries, unknown commit acknowledgements, restored-session isolation, account switching, quota limits, final session revocation, expiry cleanup, transport origin/CSRF and absence of credentials/phone/subject IDs in report bodies. Native PostgreSQL component tests separately cover schema, grants/RLS and application-fence integration. These tests use synthetic local identities and data and make no provider request.

Release acceptance still requires deploying the exact migration and runtime/client candidates, confirming their source identities, observing a controlled authenticated device/browser event through the authorized readout, and checking retention maintenance. Native process crashes, ANRs, stack symbolication, external alert delivery, on-call response, and hosted capacity/SLO qualification remain outside this fixed-code feature. No release or production acceptance is implied by the local tests.
