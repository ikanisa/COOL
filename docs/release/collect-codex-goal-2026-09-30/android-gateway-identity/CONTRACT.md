# Gateway identity foundation v1

The Edge endpoint is `collect-android-gateway`. It verifies ECDSA P-256/SHA256
over the exact UTF8 HTTP request body using DER signatures, with header
`X-Collect-Gateway-Key-Id` equal to SHA256 of the enrolled SPKI DER public key.
The SQL layer trusts only this narrow service boundary; it neither verifies a
signature nor independently attests an Android application or carrier.

Envelope: `contract_version:1`, action `heartbeat|reconcile|callback|dispatch_grant`,
device_id/request_id UUIDs, issued_at UTC ISO, payload object. Edge builds the
response envelope with the same version/action/device/request and SQL `result`.
The handset has no Collect Auth identity or service credential.

All service RPCs except lookup accept named arguments `p_device_id uuid`,
`p_request_id uuid`, `p_request_sha256 text` (Edge-computed exact request body
SHA256), `p_payload jsonb`. Only `service_role` may execute them; direct private
table/schema access is denied. Owner RPCs require the currently approved
platform owner, live session and both notifications.manage/system_health.read,
using the existing locked authority helper.

| RPC | Exact result fields |
| --- | --- |
| gateway_device_key_v1(p_device_id uuid) | device_id, state pending/active/revoked, public_key_spki_base64, key_sha256, installation_id, signing_certificate_sha256 |
| gateway_heartbeat_v1 | observation_id UUID, ingested_at UTC timestamp, replay bool, carrier_proof false |
| gateway_reconcile_v1 | target_request_id UUID, outcome recorded/unknown, recorded_action heartbeat/callback/dispatch_grant or null, recorded_result object or null |
| gateway_callback_v1 | callback_id UUID, recorded_at UTC timestamp, replay bool, carrier_proof false |
| gateway_dispatch_grant_v1 | ok false, code GATEWAY_DISPATCH_AUTHORITY_PENDING, device_id UUID, request_id UUID, replay bool; no grant/body/destination fields |

Heartbeat payload has exactly sms_permission(bool), network(validated/unvalidated/
offline/unknown), telephony(ready/unavailable/unknown), sim_selected(bool),
sim_revision_sha256(null if no SIM selected, otherwise lowercase 64hex),
local_pause(bool), reported_at(UTC ISO). Client reported time must be within
120 seconds behind or 30 seconds ahead of server ingestion. Pending devices
may supply key-possession health before activation; revoked devices cannot
submit new heartbeats. Health is an immutable device observation and does not
establish carrier readiness or actual permission independently.

Callback payload has exactly callback_id/attempt_id UUID, fence_version positive
integer<=1e9, segment_index zero-based integer, segment_count 1..10, body_sha256/
destination_sha256 lowercase 64hex, callback_kind sent/delivery, result_code
integer -1..200, tp_status null or integer 0..255, occurred_at UTC ISO. The
reported segment count is accepted only when equal to the prior server arm.
All identity/fence/hash/count values must match a retained private arm for
that device and existing attempt. No public function creates an arm. A missing
arm is refused; callbacks for prior arms remain recordable after revocation or
pause. Callbacks store raw OS/result/TP observations only, without changing
SMS outbox/attempt/payment/ledger states or claiming delivery.

Reconcile payload is exactly target_request_id UUID. It reads only the same
device's immutable prior accepted/refused result, returning unknown otherwise.
It does not retry, create or consume a dispatch grant. Reconcile is read-only
and can observe a target request that committed after an earlier unknown read.

Dispatch payload is exactly `{}`. Requests from a retained non-revoked device
record the stable authority-pending refusal; they cannot expose a body,
destination, grant, sender capability or financial data.

Owner enrollment signature:
`admin_enroll_gateway_device_v1(p_request_id uuid,p_installation_id uuid,
p_public_key_spki_base64 text,p_key_sha256 text,p_signing_certificate_sha256 text)`.
Activation/revocation signatures:
`admin_activate_gateway_device_v1(p_device_id uuid,p_request_id uuid,
p_expected_key_sha256 text,p_expected_signing_certificate_sha256 text)` and
the equivalent `admin_revoke_gateway_device_v1` arguments. Owner results contain
device_id, request_id, state_at_action pending/active/revoked, recorded_at and
replay. Exact request replay is actor/action/input bound and requires fresh
current owner authority. Installation IDs and keys cannot be reset/rebound.
Activation requires a recent signed-service health observation for the pinned
key; health readiness flags remain observations independent from active identity.

Mutation request UUIDs are durable and input/digest bound. A request collision
never changes an old result; an unknown outcome is reconciled by its original
UUID. Callback UUIDs are distinct from HTTP request UUIDs and each segment/kind
has one immutable accepted callback. No live device enrollment, real key, Auth
provisioning, scheduler or send occurs through this foundation.
