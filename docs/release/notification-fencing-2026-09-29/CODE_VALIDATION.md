# Notification code validation

This supplement records local code evidence for O05/S10. It does not establish
production acceptance. The coordinating run records database upgrade, rollback
UAT and concurrent worker evidence separately in this directory.

## Verified run

[code-validation.json](code-validation.json) binds the commands and outcomes to
14 source/configuration files and the runtime executable using SHA-256. Those
source hashes matched before and after execution. The checkout is a modified
candidate; the report also records its Git HEAD.

- Runtime: the repository-pinned Deno **2.5.6**, using
  `.cache/roster-deno-2.5.6-20260929/deno`; executable hash and reported version
  are in the JSON report.
- Type check: dispatch endpoint and FCM sender passed, including their imported
  modules. See [type-check log](logs/notification-typecheck.stderr).
- Unit tests: **22 passed, zero failed**. See
  [test output](logs/notification-unit-tests.stdout) and
  [test diagnostics](logs/notification-unit-tests.stderr).
- Tests received no network or environment permissions. Provider dependencies
  returned synthetic responses; no provider sends or hosted database operations
  were performed by this run.

## Coverage

The ten dispatcher tests exercise immediate single-item claims, a lost database
completion response after provider acceptance, attempt exhaustion, transient and
terminal provider failures, the invocation budget, an empty queue, a failed
claim RPC, a lost lease preflight, and a legacy claim without a fence. A failed
completion response does not overwrite the accepted provider result with a
retryable transport failure.

The twelve FCM tests exercise private channel routing and invalid-token
classification; accepted responses with an unreadable stream, oversized body,
invalid UTF-8, malformed JSON, a null payload or malformed fields; a valid
provider message name; and status-based rejection handling with malformed error
details. An accepted response with unavailable diagnostic data remains accepted,
with `accepted_response_unavailable` recorded as its diagnostic code.

The FCM send timeout is ten seconds, matching the minimum send timeout in
[Firebase's retry guidance](https://firebase.google.com/docs/cloud-messaging/scale-fcm#timeouts).
The dispatch loop reserves the database, OAuth and provider time budgets before
claiming additional work.

## Practical limits

- Provider acceptance does not prove delivery or display on a device. Real
  APNs/FCM credentials, installed-device behavior, scheduler cadence and outage
  capacity remain release checks.
- Network failure before response headers can leave provider acceptance
  uncertain. Retried pushes remain capable of duplicate delivery; these tests
  do not establish exactly-once provider effects or recall of an in-flight send.
- Database ownership protection covers ordinary API callers and the reviewed
  registration/unregistration RPCs. Trusted database owners and service-role
  administrators retain their existing direct mutation capabilities.
- SQL migration 137 removes the unfenced completion and one-argument claim
  contracts. Migration and worker deployment must be coordinated; an old worker
  is expected to stop rather than send through the removed claim contract.
- Provider-directed `Retry-After` scheduling and retry jitter are not implemented
  by the fixed database backoff in this candidate. Provider outage and throughput
  acceptance remains open under S10/O05.
- These code tests do not replace the SQL evidence, true concurrent-session
  tests, hosted schema verification, operator acceptance or production signoff.
