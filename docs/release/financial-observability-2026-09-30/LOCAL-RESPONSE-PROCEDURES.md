# Local operational-health response procedures

Use the Admin health page with an authorized, current operator session. Its
24-hour counts are diagnostic measurements; balances and payment finality come
from the authoritative transaction workflow. Refresh an expired sample before
using its measurements. Retain only the sample time, alert code and redacted
counts in an incident record.

## Missing or invalid samples

An invalid contract, lost permission or missing measurement calls for an
explicit fresh read. Do not infer zero from missing telemetry. If the read
fails, preserve the stable error and verify session/permission and local
database availability. A timer updates expiry presentation only. Repeated
reads must not create financial, notification or roster mutations.

## Alert responses

| Alert code | Local investigation and response |
| --- | --- |
| `receipt_parse_backlog` | Inspect the authorized receipt queue and parser state; compare queued count with parsed/failed counts. Diagnose the consumer before any explicit governed retry. |
| `receipt_parse_age` | Check the oldest pending receipt time and lease state. Preserve the durable receipt; a delayed parse is not a missing payment confirmation. |
| `receipt_parse_failure` | Inspect authorized parse-failure metadata and the stable failure category. Correct the parser/configuration defect before a governed retry. Keep raw SMS out of logs. |
| `receipt_parser_lease_expired` | Inspect expired parser claims and consumer health. Verify fencing and bounded recovery; an expired claim must not authorize duplicate finality work. |
| `payment_unmatched` | Inspect unmatched events in the reconciliation queue. Require the existing identity/evidence workflow before allocation; never guess a member or group from text. |
| `payment_review_age` | Inspect the payment-review queue, ownership and audit history. Resolve using governed evidence and reasons; queue age does not authorize posting. |
| `reconciliation_exception` | Inspect the authorized exception queue and immutable source references. Use the existing resolution workflow and verify its exact audited acknowledgement. |
| `push_queue_age` | Check notification due times, attempts and scheduler state. Confirm the retry is eligible under current fencing; do not fabricate user-delivery status. |
| `push_expired_lease` | Inspect due/processing deliveries and expired claims. Use lease recovery with a new fence; reject completion from an old worker. |
| `push_missing_lease` | Inspect processing-state consistency and consumer failures. Preserve the event and attempts; recover through the governed delivery workflow. |
| `push_attempt_failure` | Inspect redacted attempt outcomes and retry eligibility. Provider acceptance and user delivery are separate facts. Avoid automatic resends after uncertain acceptance. |
| `receipt_telemetry_stale` | Compare durable receipt activity with telemetry age and telemetry-writer outcome. Missing metrics do not invalidate an already durable receipt; diagnose the bounded telemetry path. |
| `push_scheduler_stale` | Inspect successful scheduler samples and due work. A schedule's activation does not prove provider configuration. Diagnose the local scheduler without enabling an external sender. |

For a queue with no relevant work, age checks show **No queued work**. For
queued work without a measured age, they show **Not measured**. Any attention
alert keeps the overall sample at **Attention required**, even if another
measurement is missing.

## Receipt exception worker and transport responses

Use the Automations worker card and the Exceptions inbox with current approved
platform-owner access. Refresh the worker sample before following its links.
Retain the original job ID, configuration/source/workflow revisions, sample
time, finite outcome code and redacted counts. Never put raw SMS, response
content, headers, credentials or provider error strings in an incident export.

| Worker alert | Governed response |
| --- | --- |
| `WORKER_STALE` | Refresh worker evidence and inspect the original scheduled job. Check its recorded deadline and the worker's configuration revision. An older completed result cannot resolve a newer unknown job. |
| `ORIGINAL_OUTCOME_UNKNOWN` | Look up the exact original request. Preserve its ID and payload binding through response loss; use the recorded receipt or explicit original-expiry proof to reconcile it. |
| `ORIGINAL_EXPIRED_UNHANDLED` | Inspect the original expiry proof and current source exception. Require a fresh source-bound review before requesting new work; expiry does not acknowledge handling or release a reservation. |
| `DEFERRAL_BACKLOG` | Open receipt exceptions, inspect the exact event/backlog source, then assign, acknowledge or escalate through the authorized workflow with its current revisions and reason. Verify the exact durable ACK and refresh source evidence. |
| `SOURCE_REFUSALS` | Inspect each redacted refusal category and current recipient/source access. Preserve refused originals; permissions and eligibility must be current before a separately reviewed action. |
| `TRANSPORT_UNCONFIGURED` | Check the controlled transport configuration through its operator procedure. Retain only configuration revision and the finite refusal code. A reservation or configured flag does not prove endpoint availability. |
| `WORKER_QUOTA_EXHAUSTED` | Inspect UTC-day batch reservations and limits. Reservations count admitted batches, not completed scans or delivered escalations. Any configuration change requires current authority, a reason, revision checking and its exact audited result. |

Transport evidence is read through `admin_get_receipt_worker_transport_v1` for
the exact original job. `HTTP_ACCEPTED`/`HTTP_PENDING` describe HTTP transport;
the independent immutable worker receipt establishes recorded worker handling.
Receipt business handling, financial posting and SMS delivery each retain their
own evidence.

| Transport observation | Response |
| --- | --- |
| `QUEUED_UNOBSERVED`, `RESPONSE_UNOBSERVED` | Refresh redacted transport evidence and check the original job. Missing ephemeral response rows do not establish rejection or authorize replay. |
| `AUTH_REFUSED`, `WORKER_CONFIG_REFUSED`, `ENDPOINT_UNAVAILABLE` | Investigate the finite authentication/configuration/deployment category. Reconcile the original worker job separately before considering a new request. |
| `REQUEST_REFUSED`, `ORIGINAL_CONFLICT` | Compare the original request ID, configuration revision and expiry. Preserve the original payload and investigate the mismatch through its retained audit record. |
| `RATE_LIMITED`, `HTTP_SERVER_FAILURE`, `NETWORK_TIMEOUT`, `NETWORK_FAILURE` | Check the worker lookup and controlled retry policy. A transport failure alone cannot establish an unrecorded original or permit an arbitrary resend. |
| `RESPONSE_INVALID`, `RESPONSE_CONFLICT`, `HTTP_UNEXPECTED`, `HTTP_REFUSED` | Keep the finite outcome and exact original ID; inspect the bounded collector and original receipt. Raw response bodies and network errors stay out of operator evidence. |
| `COLLECTOR_UNOBSERVED`, `COLLECTOR_STALE`, `COLLECTOR_QUOTA_EXHAUSTED`, `SOURCE_SCHEMA_UNAVAILABLE` | Check collector sampling, quota and the platform-owned response-table schema/index/read prerequisites. Refresh after the controlled correction; missing collection evidence is not a zero count or a worker failure. |

Read refreshes and incident investigation must retain the source's current
permission and session fences. The local rehearsals use synthetic job/response
fixtures, disabled cron launch and zero network dispatch. Hosted transport and
physical carrier evidence are separate release checks.

## Controlled local rehearsal

1. Use the exact isolated fixture, with cron launch disabled, pg_net batch size
   zero and no device tokens. Capture owner/registry identity, a decodable
   backup and complete table/catalog/cron fingerprints.
2. Seed synthetic pending, failed, reviewed and expired-lease states only in a
   transaction. Read health as an approved operator and assert the affected
   threshold, missing value and evidence limitations.
3. Check the unauthorized/revoked session paths and the two concurrent orders
   before calling any action. Bind acknowledgements to the same actor/session.
4. Roll back. Require exact table/catalog/cron equivalence and no worker
   sessions remaining; retain failure packets before correcting a fixture.

The installed150 alert matrix passes180 assertions. Its metric writer passes
five cases with four observed blocking races; health authority passes six
observed blocking races. Each packet restores all149 table/catalog/cron
fingerprints and leaves no worker sessions.

The current interface supplies local guidance for all13 alerts. The immutable
`ui150-responses-attempt3-consistent-age` export passes55 tests, including one
320x568/2x-text response/expiry case per alert. Guidance is hidden when the
sample expires, healthy/empty queues offer no incident instruction, missing
measurements require explicit refresh, and supplied server instructions are
rejected. The only action in the panel is the existing Refresh health control.
Its fixture equals a newly captured actual150 API receipt; synthetic receipt
content is absent from that receipt and the capture rolls back exactly.

`performance150-rollback-attempt1` passes32 assertions at1,000,10,000 and50,000
generated queued records, with60 actual health reads and2,000 metric writes.
Health reads preserve all17 checked business/receipt/notification/roster row
families; the final rollback restores all149 tables and controls. The observed
P95 read times are4.830ms,10.017ms and53.397ms. These are local measurements,
not an externally contracted service objective.

The first UI export retained five fixture failures because an empty queue
correctly made missing receipt telemetry inapplicable. The second retained an
inconsistent age-alert fixture after its pending count changed. The corrected
fixture records one real synthetic receipt in a rollback-only transaction and
keeps independent age applicability consistent with its queue count. No
runtime health-validation rule was weakened.

A complete operator action-response rehearsal and final integrated current
source verification remain pending. Guidance/presentation tests do not attest
that each operational action was executed or that an external sender works.
