# Android MoMo receipt capture

The ordinary Android member app offers opt-in capture of eligible newly arriving
MoMo SMS. This feature is separate from the optional dedicated receiver and
outbound gateway installations. Captured messages are candidate evidence; capture,
parsing or a device-observed message does not independently prove settlement.

## Installation boundaries

The source manifests describe the following capabilities. Review the merged
manifest of the exact build before distribution.

| Flavor | Source permission and role |
| --- | --- |
| `production` | Consented member receipt capture through `RECEIVE_SMS`; its manifest removes `READ_SMS`. It is not the outbound gateway. |
| `dev` | The main manifest supplies the member receiver and `RECEIVE_SMS`; check the actual merged build and test configuration. |
| `internal_receiver` | A separate receiving installation declares `RECEIVE_SMS` and `READ_SMS` for its scoped receiving and inbox-recovery workflow. |
| `internal_gateway` | A separate sending installation declares `SEND_SMS` and removes the member incoming receiver. Its governed outbound workflow is distinct from member receipt capture. |

The shared receiver is exported for Android's protected `SMS_RECEIVED` broadcast
and declares `android.permission.BROADCAST_SMS`. Source manifest declarations do
not establish Play permission approval, the contents of a particular signed build,
or actual Android/OEM behavior.

## Member consent and custody

The member flow requests Android permission and binds capture to the consenting
owner. `record_sms_access_consent` records the corresponding server-side consent.
The receiver keeps eligible messages in a bounded, owner-bound encrypted queue;
OTP/PIN and promotional messages are not intended for capture. The production
member path does not request inbox-history or message-sending access. Device and
provider coverage still need physical testing.

Disabling capture stops new capture and preserves unacknowledged queued sources.
A different account must not take over another owner's queue. Android background
jobs require a current protected member session and network; expired sessions or
transient failures leave the source pending for recovery. Permanent rejected
sources can be parked for review rather than silently deleted.

The authenticated `ingest-client-sms` handler stores protected receipt evidence
and returns an acknowledgement containing the owner, client envelope and body
hash. Native custody removes a queued source only after the acknowledgement
matches its owner and retained body. Incomplete or ambiguous transport and
receipt evidence must remain visible for review instead of being treated as a
confirmed payment.

## Dedicated receiver and outbound gateway

The internal receiver's enrollment, account binding, capture permissions and
retained-inbox recovery are separate from ordinary member consent. Pairing or a
server credential does not grant operating-system permission. Original owner and
binding information must not be rewritten when an installation is re-paired.
The internal sending gateway has a separate credential, permission and dispatch
workflow; enabling one installation does not authorize the other.

## Verification and release

Review the current native receiver, `MemberSmsJobs.kt`, `SmsQueueStore.kt`,
`supabase/functions/_shared/domain/receipts.js` and the relevant migration chain
for the candidate under test. Verify consent, revocation, account changes,
protected custody, exact acknowledgements, multipart completeness, retry and
recovery on controlled fixtures and on appropriate physical devices. Provider
formats, background execution, finality controls, retention, signed artifacts
and store permissions require their own evidence. A local build or synthetic test
is not a deployment or production-acceptance record.
