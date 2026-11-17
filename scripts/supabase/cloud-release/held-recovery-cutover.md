# Held SMS recovery: future cutover requirements

This is an isolated, disabled candidate. Do not apply the migration or enable
either recovery route until the financial, authorization, concurrency and
Android checks for the exact candidate have passed.

## Preserve existing v47 clients

The installed v47 receiver can reuse an in-memory reconciliation proof for
less than five minutes using `SystemClock.elapsedRealtime()`. A server response
that changes legacy `hasPending` to `true` cannot immediately invalidate an
already cached proof.

1. Complete the coordinated Cloud schema/runtime cutover with
   `heldRecoveryEnabled` **false**. Verify that all older runtime instances are
   drained, the legacy status route has its unchanged v47 JSON shape and returns
   `hasPending: true`, and all three new routes return 404.
2. Start the five-minute interval only after verifying that no old runtime can
   still issue a successful legacy status response. The interval is at least
   300,000 milliseconds; allow for observation and deployment uncertainty.
3. After that interval, exercise a reconciliation cycle on every installed v47
   receiver and verify a fresh Cloud status read reaches `sync_unconfirmed`.
   An offline, idle, unreachable or otherwise unverified receiver does not
   count as invalidated merely because wall-clock time elapsed. An independently
   proven cache invalidation may replace the waiting interval, but it must still
   be followed by a fresh post-cutover Cloud status read and observed
   `sync_unconfirmed` on that receiver.
4. Verify the new Android client requires `scope: "verified_collection"`, never
   describes that scope as equality of unscoped receipts, and keeps the
   recovery path disabled until the above boundary and all other qualifications
   are met. Staff builds must retain their existing SMS restriction.

The v47 cache boundary requires Android regression evidence immediately before
and at 300,000 milliseconds, plus a device-level fresh-read check. Rollout is
not qualified solely by a passed server JSON test or a simulated clock.

## Other outstanding qualifications

- This checkout is based on commit `3c29f0d6010340c966811a6884cc804b3c38d30f`,
  the source tree associated with Cloud source SHA
  `16080f9483eb0bc8f272c64ca2dfd72459af530cf89f90767328d9a37d6278d8`.
  Verify and integrate any newer live changes before packaging. The existing
  opt-in masked-number rule is a separate owner decision.
- Execute the latest synthetic gateway, queue and separated-status fixtures in
  an authorized isolated Cloud test, and obtain independent review of their
  results and of production-role grants.
- Review and qualify the two-connection shared-schema race harness, including
  exact schema cleanup and readback. A passed synthetic test does not establish
  all production financial paths.
- Reconcile scheduler and retention manifests to the final migration and Edge
  checksums, and test a fenced, coordinated migration/runtime rollout.
- Before installing the recovery migration, qualify and apply the separate
  `20261117205959_burimunsi_sms_source_index.sql` predecessor while the
  application fence is closed and existing writers have drained. Its ordinary
  index build takes a table write lock; `lock_timeout=5s` and
  `statement_timeout=60s` bound the attempt. If it times out or its exact
  catalog/readback checks fail, leave the runtime disabled and investigate;
  do not silently switch to an untracked concurrent build. Read back the exact
  valid, ready btree index before the recovery runtime can be enabled. A
  synthetic planner check is not a measurement of live latency.
- Confirm the new client handles `unconfirmed`, timeout and every error from
  the read-only `/sms/observations/recover-held-ack` as no authority to resend
  `/recover-held`. Polling that same acknowledgement request is permitted.
  Verify recovery remains non-financial and a later same-group association
  invalidates the verified-group result. General unscoped receipts remain
  outside that verified-group result until their association is established.
- The client journals `ATTEMPTING` before sending. If it stops before sending,
  the current acknowledgement remains `unconfirmed`. The separate candidate
  `20261117220000_burimunsi_held_resume_guard.sql` permits a retry of the exact
  immutable request and enforces at most one durable Storage PUT attempt per
  held object, across all routes. No retry derives authority from an ACK absence.
  Do not enable this candidate until its exact migration, role grants, concurrent
  starts and Android integration pass independent review and Cloud qualification.
  An attempt marked active or unknown before the network call may remain pending
  and require a separately reviewed manual resolution; do not clear it by timeout
  or infer that a Storage 404 makes a second PUT safe.
- A changed consent generation currently prevents acknowledgement even if
  consent is subsequently re-enabled. Preserve the pending request until a
  reviewed same-account/current-consent recovery rule or a manual resolution
  is available; do not infer that the source was absent.
- The candidate's production switch is off while both
  `BURIMUNSI_HELD_RECOVERY_SOURCE_SHA256` and
  `BURIMUNSI_HELD_RECOVERY_COLLECTION_ID` are absent or empty. Any partial,
  invalid or stale source binding fails closed. Only after all qualifications
  and the v47 cache boundary are complete may a controlled release set both:
  the first must equal the fenced `BUILD_SOURCE_ID` and the second must be the
  single verified collection ID. The existing observation feature must also be
  enabled. Confirm a different collection still receives 404 and a revoked
  admin/grant or disabled consent is denied. Never set these values merely to
  compensate for an incomplete migration or missing test.
