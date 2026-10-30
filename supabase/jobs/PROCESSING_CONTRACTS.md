# Bounded periodic receipt and Android push contracts

This document describes the repository implementation. It does not authorize
hosted installation, scheduler activation, extraction-provider calls or Firebase
sends. Historical `QUALIFICATION.json` records its original source and remains
historical evidence. Requalify the exact adopted source and current deployment.

## Modes

The default is `maintenance_only`, with `MOMO_PROCESSING_PAUSED=true`. Setting
the pause flag to false does not admit receipt work. Setting a push enable flag
does not admit push work. The authenticated request must carry an exact contract
that matches the current deployment and its reviewed approval.

| `COLLECT_JOBS_MODE` | Receipt contract | Notification contract | Receipt pause |
| --- | --- | --- | --- |
| `maintenance_only` | Absent | Absent | `true` |
| `receipt_processing_v1` | Required | Absent | `false` |
| `notification_delivery_v1` | Absent | Required | `true` |
| `receipt_and_push_v1` | Required | Required | `false` |

Every active contract includes `source_sha256`, which must equal the exact
adopted `BUILD_SOURCE_ID`. Both the SQL scheduler and the Edge handler validate
the source. Changing source, approval, token version, mode or provider identity
requires a new review and qualified probe; an old successful probe cannot admit
the changed contract.

## Receipt processing

The `processing_admission` object has exactly these fields:

```json
{
  "contract": "collect.receipt-processing.v1",
  "source_sha256": "<64 lowercase hex characters>",
  "approval_sha256": "<64 lowercase hex characters>",
  "model_id": "<reviewed configured model>",
  "batch_limit": 1
}
```

The deployment must additionally provide
`COLLECT_JOBS_PROCESSING_APPROVAL_SHA256`, `MOMO_AI_MODEL`,
`MOMO_AI_ENABLED=true`, and its existing private `OPENAI_API_KEY` binding.
Admission requires a configured production extractor adapter. No new AI provider
or model is selected by this implementation.

The worker drains one due receipt job. The existing source/lease/parser fences,
four-attempt budget, backoff and financial boundaries remain authoritative.
Pending jobs, due retries and expired leases can recover without another ingest
request. Parsing creates receipt facts; it does not authorize a contribution,
posting, settlement confirmation or provider payout.

Use `readiness.processing.example.json` as the closed readiness-file shape.
Its placeholders are deliberately invalid and cannot activate a scheduler.

## Android push

The `notification_admission` object has exactly these fields:

```json
{
  "contract": "collect.android-push.v1",
  "source_sha256": "<64 lowercase hex characters>",
  "approval_sha256": "<64 lowercase hex characters>",
  "project_id": "<reviewed Firebase project>",
  "android_package": "app.cool.mobile",
  "admitted_from": 1793232000,
  "batch_limit": 1
}
```

The timestamp above illustrates the integer type only; it is not an approved
replay boundary. The current operator must select and review the event lower
bound. Older events are not silently backfilled. The Android package is one of
the existing `app.cool.mobile` or `app.cool.mobile.dev` identities.

The deployment must match these explicit bindings:

| Binding | Meaning |
| --- | --- |
| `COLLECT_PUSH_ENABLED=true` | One prerequisite for the explicitly admitted lane |
| `COLLECT_JOBS_PUSH_APPROVAL_SHA256` | Exact approval digest in the request |
| `COLLECT_PUSH_ADMITTED_FROM` | Decimal string equal to the admitted integer timestamp |
| `FCM_PROJECT_ID` | Exact approved Firebase project |
| `FCM_ANDROID_PACKAGE` | Exact approved Android package |
| `FCM_SERVICE_ACCOUNT_JSON` | Private service-account JSON for that project |

Keep the credential in the existing private deployment secret channel. It must
never enter readiness JSON, operator output, the scheduler journal, application
logs or repository files. The adapter only uses the fixed Google OAuth token
endpoint and FCM HTTP v1 project endpoint. It signs a bounded RS256 JWT for the
Firebase messaging scope and refuses alternate token endpoints, projects,
packages, arbitrary payload fields and delegated-user impersonation.

The migration `20261029130000_collect_notification_delivery.sql` adds private
`app.notification_deliveries` and installs no credentials or work. Its
`schema-src/notification-delivery.sql` source is byte-identical. SQL15 diagnostics
and the exact current predecessor schema must also be accounted for by the
deployment/adoption process; this document is not a migration application order
or a substitute for the stopped-source admission requirements.

### Durable obligations and current authority

Contribution posting already commits its in-app notification event in the
financial transaction. The periodic worker derives a unique obligation for each
eligible event/device pair using a bounded `INSERT SELECT` transaction. A worker
interruption cannot lose an event-to-queue transition or recreate a terminal
obligation. Each obligation binds the recipient, existing device, owner session,
encrypted-token digest, event digest, Firebase project and Android package.

The worker rechecks an active member, current managed Auth session, device
ownership, membership, active collection, push/payment preferences, unread event
and absence of a privacy retention barrier. It repeats that check after OAuth,
in the transaction that records send-start. Revocation before that boundary
suppresses the send. An already admitted provider call cannot be recalled by a
later account change.

At most one FCM message attempt runs per admitted invocation. Claims use a
90-second lease. OAuth and FCM HTTP each have a 10-second timeout. Each delivery
has at most four attempts. The bounded scan materializes up to 100 obligations
and recovers up to 100 expired leases per invocation; these are row limits, not a
large-dataset latency qualification.

The payload is the existing Android v2 contract:
`collect_push_version=2`, `collect_event_id`, `recipient_id`,
`deep_link=/activity`, and `type=contribution`. The provider notification is
always **Collect — Open Collect to view your updates.** It uses the private
`collect_contributions` Android channel, a five-minute TTL and an event-specific
replacement tag. No financial amount, balance, group name, payer name, receipt
text or MoMo reference is sent. A shared JSON fixture is tested by both the
backend serializer and the current Android consumer.

### Outcomes and retries

| Durable state | Meaning and next action |
| --- | --- |
| `pending` | Eligible obligation has not been claimed |
| `claimed` | Worker owns the current lease; no durable send-start yet |
| `sending` | Current authority was checked and send-start committed |
| `accepted` | FCM returned a valid acceptance name; this is not device delivery |
| `retry` | Known safe retry condition, after bounded backoff and provider delay |
| `rejected` | Confirmed refusal, invalid configuration/payload or exhausted attempts |
| `suppressed` | Recipient/source authority changed before send-start |
| `unknown` | A send may have happened; this obligation never retries automatically |

Explicit throttling/unavailability respects `Retry-After` and exponential
backoff with bounded jitter. Out-of-contract provider delays stop that
obligation instead of shortening the delay. Only confirmed `UNREGISTERED`
disables a registration, and only if its exact original token/session still
owns that device. `INVALID_ARGUMENT` does not delete or disable a device token.

A lost send-start commit acknowledgement sends nothing in that invocation. If
the durable row is later found expired in `sending`, it becomes `unknown`.
Expired `claimed` rows without send-start may retry. Timeouts, malformed success
responses and unclassified provider outcomes become terminal `unknown`. A lost
final database acknowledgement can be reconciled only by the same original
attempt's durable result; it never authorizes another send.

The scheduler may acknowledge a successfully recorded terminal `unknown` result.
That acknowledges the worker's durable uncertainty record, not delivery or a
retry permission. An unconfirmed local journal/commit returns 503 and retains the
existing scheduler unknown-outcome gate. Semantic provider uncertainty is also
reported to the application source-fence observation.

Delivery identities and attempt history are retained, private and not an
approved erase class. Missing/deleted event/device sources suppress future work;
their approved deletion never cascades away delivery uncertainty. Pending,
claimed, sending, retry and unknown obligations remain visible to the existing
retention inspection. No legal disposition policy is invented by this change.

Use `readiness.notifications.example.json` or
`readiness.combined.example.json` for the corresponding exact readiness shape.
They require current provider/device evidence and independent remaining budgets
of 10,000 delivery attempts and 20,000 provider HTTP requests, alongside the
existing invocation budget. The local scheduler cap covers this scheduler's
requests only; it is not organization-wide provider quota enforcement.

## Installation and release evidence

The renderer retains inactive installation. Its explicit `--upgrade-output`
path upgrades only the exact reviewed maintenance predecessor while it is
inactive and has no awaiting or unconfirmed work. It preserves dispatch history,
the original Cron identity and unknown-outcome records. The operator refuses
drift, active predecessors and unresolved work. Do not replace the installed
objects manually or clear uncertainty to make a probe pass.

Native regression tests use an owned PostgreSQL 17 database with real
transactions, runtime RLS, source fencing and production SQL. The scheduler's
Cron/net/Vault interfaces and all provider HTTP responses are explicit synthetic
fixtures. These tests do not prove native managed-extension versions, deployed
credentials, current provider permissions, Android device receipt, delivery
latency, quota headroom, hosted database capacity or launch approval.

The implemented notification channel is Android FCM for the existing in-app
contribution event. Contribution email is a separate unimplemented channel: the
current preference/destination model has no contribution-email contract. Existing
auth/Admin SMTP code is not contribution-email delivery. Assisted receipt SMS
retains its separate consent, operator and native-device lifecycle and is not
activated by either scheduler mode. iOS/APNs is outside this implementation.

## Protocol sources

- [FCM HTTP v1 authorization](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
- [FCM response and retry codes](https://firebase.google.com/docs/cloud-messaging/error-codes)
- [Google service-account OAuth JWT flow](https://developers.google.com/identity/protocols/oauth2/service-account)
- [FCM send endpoint](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send)
- [FCM message and Android schema](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages)
