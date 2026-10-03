# Dedicated shadow supervisor caller journal

`tools/collect-notification-mcp/src/supervisor_journal.ts` supplies the durable
caller boundary around the existing signed supervisor client. It permits only
explicit `prove_key` or `shadow_health` calls and manual reconciliation of the
original request. It creates no key, enrollment, profile, schedule or business
authority and is not registered in the MCP host's five-read allowlist.

`SupervisorJournal.once(identity, {action, requestId}, signer, fetcher)` reserves
the caller-supplied UUID in an append-only checkpoint, then fsyncs and reads back
the exact signed envelope hash and issued time before allowing one HTTP call.
`readOriginal(requestId)` reads local evidence. `reconcile(identity,
originalRequestId, distinctLookupRequestId, signer, fetcher)` performs one
explicit lookup; it never generates or reissues the original UUID/action.
Use an owner-private 0700 directory (and a 0700 parent when creating the leaf).
Files are 0600, bounded and checked for symlinks, ownership, hardlinks,
canonical bytes and stable readback. Storage failure prevents the initial
HTTP call or retains unknown if an invocation already occurred.

Restart, overlapping callers, timeout, malformed responses and uncertain
persistence retain the original evidence and forbid mutation replay. Recorded
means an original shadow observation was recorded, not a business action or
provider delivery. Busy, in-progress and unavailable lookups remain unknown.
A negative lookup cannot establish absence before 120 seconds from the retained
original signed time. Missing, inconsistent or future time evidence remains
unknown. Even an accepted negative lookup preserves the checkpoint and never
enables original mutation replay. The 120-second bound depends on the v1 server
rechecking its 30-second issued window after acquiring the original request
lock and holding that lock through commit; protocol changes require review.

The journal stores opaque request/principal IDs, fixed scope/action, key digest,
envelope digest, timestamps and reason-coded outcomes. It stores no signature,
raw envelope, token, destination, message body, phone number or amount.

Final scoped journal checks passed 26/26 cases. Final current combined bridge
checks passed 139/139 cases in 18 files, with clean TypeScript 7.0.2 analysis
under pinned Node v24.19.0. All 58 bound bridge/handler/fixture/identity inputs
matched before and after the combined run. Exact commands and actual logs are
in `combined-current-*.result.json`. This is separate from source05's 80-case
snapshot run; counts are not added across snapshots or attempts.

Earlier attempts are retained. The first development fixture omitted JSON
Content-Type; the strict client correctly returned unknown. A type check
exposed optional `getuid`, which the journal now guards. The first combined
run's actual output passed 139 cases but the helper failed to parse Node's
summary and did not retain its binding receipt. The next bound run passed
138/139: an existing CLI process test's seven-second watchdog killed its last
child before JSON output under parallel load. The final run explicitly uses
TAP and two concurrent test files; no runtime deadline or safety bound changed.

Root's narrow source review reported no new concrete defect in UUID reservation,
signed-byte binding, lookup ownership, retained observations or conservative
absence handling. This is a scoped review, not production approval. No actual
endpoint, Keychain, profile, OTP or provider call occurred in these checks.
The core C20 manifest and dependency pins remain unchanged. Production caller
integration, approved enrollment/activation and deployed protocol verification
remain separate gates; no live scheduling or sender authority is established.
