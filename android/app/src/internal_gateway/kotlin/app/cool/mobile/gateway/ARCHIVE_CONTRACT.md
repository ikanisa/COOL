# Native request and attempt archive

This is an encrypted local evidence store, not dispatch or delivery authority.
The existing `collect-android-gateway` signed HTTPS endpoint is the only response
source accepted by the production adapter. No JWT, service credential, receipt
body, destination or key is supplied through this archive API.

`GatewayArchiveAcknowledgement.direct(request, reply)` requires the exact v1
response wrapper (`contract_version`, `action`, `device_id`, `request_id`,
`result`) to the exact retained signed request. `reconciled(request,
reconcileRequestId, reply)` requires a separately authenticated v1 reconciliation
response with the original `target_request_id`, `outcome=recorded`, matching
`recorded_action` and the existing strict action result. Unknown, malformed,
wrong-device/request/action and invented carrier proof responses cannot archive
anything. The source request SHA-256 and original bytes must still match.
This local adapter validates bindings; it does not authenticate arbitrary JSON.
Only the existing validated fixed-host transport may call it in production.

The request archive retains the original request row, strict backend result,
actual direct/reconciliation wrapper and local `acknowledged_at`. The local time
records archiving, not server settlement, delivery or freshness. First receipts
are immutable. A replay result may differ only in its existing `replay` flag;
the first receipt stays retained. Legacy `state=recorded` is insufficient because
it retains no backend receipt.

Heartbeat recording and the current dispatch-authority refusal can free active
request capacity after the archive is durably written. Callback requests remain
active so the existing stable-callback duplicate check remains authoritative.
No unknown request is removed without a later bound durable acknowledgement.

Attempt archival requires a fully known local sent/delivery callback set and a
durable matching server receipt for every callback. Device/job/attempt/fence,
segment position/count, body/destination hashes, callback IDs, raw result codes
and occurrence times must match. Unknown, partial and invocation-exception
attempts stay untouched. The complete original attempt, nonce and identities are
retained encrypted. A late contradictory callback remains in the active attempt
and does not rewrite its earlier archived observation.

Attempt **compaction is unavailable** (`gateway_attempt_archive_authority_pending`).
Current v1 has no terminal-attempt acknowledgement or closed callback window.
Callback recording proves recording only. A future server contract must authorize
local removal for the exact device/job/attempt/fence and original evidence digest,
specify how late callbacks remain durable/reconcilable and preserve the lifetime
invocation tombstone. No such server endpoint or hosted acceptance is claimed here.

The active limits remain 64 requests / 100 attempts. The archive holds at most
256 request receipts / 100 attempt copies and at most 512 KiB of plaintext before
encryption. It never evicts evidence to create capacity. Exhaustion stops
compaction, preserving existing evidence; an approved export/retention protocol
is a separate requirement for indefinite operation.

Storage uses the existing no-backup directory and non-exportable Android Keystore
AES-GCM key with a distinct per-file AAD. An established archive marker is written
first; encrypted archive AtomicFile + descriptor and directory fsync precede
active-file pruning. A crash after archive commit can recover by matching the
exact retained source digest and ignoring only acknowledged non-callback rows.
Missing established data, conflicting digest, corrupted ciphertext or append-only
violation fails closed. Archived request/attempt IDs cannot become fresh intents.

The offline runner executes actual Kotlin storage/archive code with synthetic
AES and narrow Android filesystem API shims, and separately compiles against the
cached real Android API. It does not certify Android Keystore, handset power loss,
authenticated hosted acknowledgement, carrier behavior, deployment or throughput.
