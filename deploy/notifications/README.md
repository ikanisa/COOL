# Notification protocol 2 and recurring dispatcher

This source package installs bounded enqueue/wake-up requests, recipient-bound generic push previews, fenced completion with provider retry floors, and a minute-based dispatcher schedule. Full notification content stays in the authorized in-app event store.

## Coordinated rollout

1. Freeze the exact source/migration hashes and record the candidate environment. Stop/disable the existing push scheduler and quiesce old Edge workers before migration. Accepted provider messages cannot be recalled; retain the account-switch privacy gate for previously accepted/in-flight messages.
2. Rehearse migration 139 on a guarded synthetic 138 fixture with a live version-1 claim: `scripts/tests/notification_protocol_upgrade_seed.sql`, apply the migration through the existing migration runner, then `scripts/tests/notification_protocol_upgrade_verify.sql`. Run the 139 rollback and concurrent-session suites. These scripts require isolated-clone settings; never aim them at production.
3. Apply migration `20260929160000_notification_retry_schedule.sql` through the existing approved deployment procedure. It changes the required claim contract to **2**, rejects version 1, and fences existing processing claims while preserving their wait/attempt evidence. Both claim arguments remain mandatory. A worker rolled back to version 1 stops before new provider work. Prefer a reviewed forward correction over restoring an unfenced/private-preview worker.
4. Deploy the matching `send-notification` and `dispatch-notifications` sources and client version-2 recipient checks. Verify deployed source/config hashes, internal request authentication, and absence of legacy worker traffic before enabling scheduling. The migration installs `collect-dispatch-notifications` **inactive**.
5. Using the existing approved secret channel, provision these Vault names from the same verified project configuration. Do not paste secrets into SQL history, logs, task output or cron commands:

   | Vault name | Existing value |
   |---|---|
   | `collect_notification_project_url` | Canonical `SUPABASE_URL`, exactly `https://<20-character-project-ref>.supabase.co` |
   | `collect_notification_api_key` | This project's publishable/anon API key |
   | `collect_notification_internal_secret` | The same `INTERNAL_FUNCTION_SECRET` used by the Edge worker; at least 32 characters |

   No secret values are included in this repository. Rotate through the same secret channel and read back matching configuration without exposing values. The worker is deployed with its existing no-JWT-verify setting and authenticates `x-collect-signature`; an API key alone is insufficient.
6. As database owner, run `activate_dispatch_scheduler.sql` with the verified non-secret `expected_project_url`. It refuses project mismatch/missing configuration, then activates exactly one minute-based job. Stop with `select public.configure_notification_dispatch_schedule(false);`. Secret access and activation are revoked from public, anon, authenticated and service_role.
7. Prove a failed/stale job drains with **no fresh notification enqueue**, then demonstrate worker overlap, paused/resumed scheduling, a provider outage, expired tokens, dead-letter intervention and capacity. Retain cron/HTTP status, redacted queue age/depth and alert evidence. A pg_net request ID proves only queuing, never delivery; inspect the worker response and provider/device evidence independently. Do not log provider tokens or full notification content.

## Retry and bounded execution policy

- Body/enqueue/wake-up stages have independent eight-second bounds. A committed enqueue remains successful if its best-effort wake-up fails. An uncertain enqueue is not automatically replayed; callers still need their own business-event idempotency discipline.
- Dispatcher budget remains 60 seconds, with 43 seconds reserved before the next claim. RPCs use eight-second bounds; FCM sends retain at least ten seconds.
- FCM quota retry floor is 60 seconds. APNs 5xx floor is 900 seconds; APNs provider-token update throttling waits at least 1200 seconds. Valid Retry-After seconds/HTTP-date instructions can increase these floors.
- SQL persists exponential backoff plus nonnegative random jitter (up to 25%, capped at 3600 seconds). Jitter never schedules before the provider floor. A provider instruction beyond 3600 seconds terminalizes with `retry_after_exceeds_budget` for operator review rather than clipping into an early retry. At most five automatic attempts remain permitted; Admin retry preserves cumulative history.
- Successful provider HTTP acceptance remains successful even when its optional response body is malformed/unavailable. Lost completion acknowledgement remains uncertain, without rewriting acceptance as a provider failure. At-least-once delivery uncertainty remains across crashes and cannot be replaced by an exactly-once claim.

Policy references checked 2026-09-29: [Firebase scaling/retries](https://firebase.google.com/docs/cloud-messaging/scale-fcm), [Firebase error codes](https://firebase.google.com/docs/cloud-messaging/error-codes), [Apple APNs responses](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns), [Supabase scheduled Edge functions](https://supabase.com/docs/guides/functions/schedule-functions).
