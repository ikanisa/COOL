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

The installed 36-assertion SQL packet and the 39-test health UI packet cover the
current threshold/missing/stale presentation parts. A complete concurrent
operator-response rehearsal is still pending; this runbook is an implemented
procedure, not a claim that every rehearsal step has run.
