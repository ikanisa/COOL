# Notification protocol 2: local code validation

The adjacent `code-validation.json` records exact commands, exit codes, runtime SHA-256, and 21 source hashes before/after testing. All hashed sources were unchanged during these runs. The directory name follows the 2026-09-29 work packet; the JSON timestamp is the execution time.

## Verified locally

- **40 tests passed** using exact `.cache/roster-deno-2.5.6-20260929/deno` (2.5.6). This includes provider serialization, recipient validation, generic previews, Retry-After interpretation/floors, dispatch fencing/accepted-send uncertainty, bounded request body/enqueue/wake-up operations, cancellation, redirect policy and preserved durable enqueue.
- Both Edge entrypoints and FCM/APNs modules **typechecked** with the same pinned Deno.
- The existing actual-handler harness passed **45 Edge tests plus 10 roster tests** under Bun 1.4.0. Its output explicitly reports that `tsc` was unavailable; that runner is execution evidence. The separate pinned Deno check supplies typecheck evidence for the notification entrypoints.
- Updated concurrent SQL harness passed Ruby syntax validation only in this packet.

The handlers use synthetic dependency adapters and provider responses; no notification was sent. Test fixtures contain synthetic UUIDs, tokens and messages only.

## Implemented contract

Both transports serialize `collect_push_version: "2"`, the claimed recipient as `recipient_id`, and `collect_event_id`. Push preview text is always `Collect` / `Open Collect to view your updates`; full event content remains in the authorized database store. The required database claim protocol is 2, with no default arguments; its response adds the owner-validated `user_id` and generic preview text. Old workers cannot acquire a new claim. Migration 139 rotates existing active claim fences, preserves their expiry/attempt evidence and defers reclaim until the old lease wait is respected.

Provider Retry-After seconds/HTTP-date floors reach the fenced completion RPC. SQL adds nonnegative jitter after the larger of exponential delay and provider floor. Excessive instructions terminalize for operator review rather than retrying too early. Successful HTTP acceptance and failed completion acknowledgement retain their existing uncertainty semantics.

The recurring minute job is declared in migration 139 but starts **inactive**. `deploy/notifications/README.md` and the project-checking activation SQL describe the coordinated worker rollout and owner-only Vault configuration/activation. No credentials were invented, provisioned or read back.

## Limits and remaining acceptance

This packet does not assert SQL execution, hosted deployment, scheduler activation, provider configuration, installed-device delivery or account-switch acceptance. Root owns the isolated 138→139 live-claim upgrade, rollback-only SQL suite and concurrent-session execution; their outputs must be retained separately. Source scripts are runnable evidence inputs until those executions pass.

Previously accepted/in-flight private legacy messages cannot be recalled. Database and service administrators retain trusted mutation capabilities. At-least-once delivery can still duplicate after a lost provider/completion acknowledgement; no exactly-once guarantee is made. A timed-out enqueue is not automatically replayed; callers must preserve business-event idempotency when resolving uncertain acknowledgement. OTP/Integrity/parser outage policy, representative load, live alerts and dead-letter operating acceptance remain separate gates.

Policy sources: [Firebase retries](https://firebase.google.com/docs/cloud-messaging/scale-fcm), [Firebase error codes](https://firebase.google.com/docs/cloud-messaging/error-codes), [Apple APNs responses](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns), [Supabase cron/Vault scheduling](https://supabase.com/docs/guides/functions/schedule-functions).

## SQL fixture correction after code validation

Root’s first guarded138 upgrade seed attempt rejected unsupported event type `notice` and rolled back. The seed now uses supported `group_update`; migration139 remains unchanged. The JSON retains the original test-time source hashes and records the later seed correction plus current source fingerprints separately. Root must rerun that SQL seed/upgrade verification; earlier code-test results are not SQL execution evidence.
