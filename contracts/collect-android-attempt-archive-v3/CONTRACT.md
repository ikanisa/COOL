# Android attempt archive v3 — local implementation

This extends the existing exact-host, enrolled P-256 device-signature gateway.
The UTF-8 envelope is bounded to8KiB and uses contract_version3, action
archive_attempt or archive_lookup, device_id/request_id UUID, issued_at UTC
within120s, and payload. Existing v1/v2 wire meaning remains unchanged.
No handset Auth/service credential, send authority or delivery conclusion exists.

The narrow service-only RPCs are gateway_archive_attempt_v3 and
 gateway_archive_lookup_v3(p_device_id uuid,p_request_id uuid,
 p_request_sha256 text,p_payload jsonb). The Edge derives the request digest
from the exact signature-verified bytes; a caller cannot supply it in payload.
Private collect_gateway_archive tables have RLS, no direct API grants, immutable
requests/ACKs, a lifetime unique acknowledged automatic attempt, and the same
cross-version original-request UUID fence as existing device evidence.

archive_attempt payload has exactly attempt_id,fence_version (1..1e9),
body_sha256,destination_sha256 (lowercase64hex),callback_requests.
callback_requests has exactly2×segment_count entries (2..20), ordered by zero-
based segment then SENT,DELIVERY. Each entry has callback_id,request_id UUID
and request_sha25664hex for the original immutable signed callback request.
Callback/request IDs must be unique. The archive request is a new stable UUID;
it cannot equal a callback request or reuse any v1/v2 mutation request UUID.

The backend accepts only a prior automatic arm for the same device/fence and
immutable receipt hashes. All planned callbacks must be durably recorded,
all raw result codes must equal−1, and no contradictory evidence may exist.
Unknown, incomplete and uncertain attempts are ineligible. Pause, stop and
revocation permit prior evidence archival/reconciliation but grant no send.
Receipt→attempt locks serialize archive admission with real callbacks.
The ACK changes no payment, journal, snapshot, receipt state or attempt state.

The exact result keys are request_id,device_id,attempt_id,fence_version,ok,code,
archive_ack_id,receipt_id,body_sha256,destination_sha256,segment_count,
callback_requests,recorded_at,replay,evidence_kind,carrier_proof,delivery_proven,
send_authority. UUIDs/UTC timestamps/integers are strict. The last three fields
are always false. Success has ok=true,code=null,non-null ACK/receipt UUIDs,
exact bound callback_requests,evidence_kind=complete_framework_callback_observations.
Refusal has ok=false and one of CALLBACK_EVIDENCE_INCOMPLETE,
CALLBACK_EVIDENCE_UNCERTAIN,ATTEMPT_ALREADY_ACKNOWLEDGED; ACK/receipt/references/
evidence_kind are null. Original mutation replay returns the immutable result
with replay=true; the handset never performs that replay.

archive_lookup payload has only target_request_id, the original stable mutation
UUID, distinct from the read UUID. Result has exactly target_request_id,outcome
(unknown|recorded),recorded_result (null for unknown, original immutable result
with replay=false for recorded). A different device sees unknown, never another
device’s evidence. Lookup authorizes no invocation or second mutation.

Native compaction additionally requires its original local invocation to be
fully known and exception-free, exact original request/digest/nonce/callback
binding, and archive-first encrypted/fsynced write plus cold readback before
active pruning. The point-in-time server ACK proves recorded framework callback
observations, not carrier acceptance/delivery or future callback closure.
Every acknowledged identity and full evidence remain reserved in encrypted cold
storage. Late conflicts are durably retained and block new local sends; original
invocation bytes are never replayed. Unknown evidence is never evicted.

If local source evidence becomes contradictory while the authenticated ACK is
in flight, compaction stays ineligible. The handset persists the exact original
request and ACK in a separate encrypted, immutable uncompactable record, keeps
every hot attempt and callback original, and durably closes local dispatch.
Only the transport request becomes recorded after ACK readback. This allows
the contradictory raw callback to reconcile once without starving behind
repeated ACK lookups. It grants no terminal compaction, source resolution,
delivery conclusion or replacement invocation. Such retained attempts remain
within the existing hot-journal bounds and require manual evidence review.

Cold storage/export uses bounded segments and immutable original identities.
Export is lossless encrypted bytes plus hashes/readback, not deletion authority.
There is no approved retention horizon or portable Keystore recovery policy.
Finite storage exhaustion must preserve existing evidence and fail closed.
Hosted deployment, device activation/OS/carrier tests remain unexecuted.

The native store uses one immutable encrypted object per acknowledged attempt,
indexed by the first byte of SHA256(attempt_id). Each of256 possible shards
admits at most128 identities; a full shard refuses the next archive without
pruning its hot originals, even when other shards have capacity. Each object
admits at most512KiB plaintext before AES-GCM framing. Permanent indexed
tombstones prevent a second invocation with an archived attempt UUID. The
established shard catalog detects missing indexes; indexed missing objects or
corrupt ciphertext fail closed. An object-before-index crash retains the exact
hot originals until the original-UUID ACK read repairs index/catalog metadata
under the same capacity checks. A fully indexed cold copy can logically remove
only byte-equivalent, fully known hot evidence after a prune interruption.

Late contradictory observations use separate append-only encrypted files,
bounded to64 distinct observations per attempt and256 affected attempts.
Their durable global stop is written first, cannot be cleared by local resume,
and preserves the original cold object/ACK. Capacity or corruption cannot evict
unknown evidence or reopen dispatch. A matching known late callback is only a
duplicate of a recorded raw outcome; it does not establish carrier proof.

Each maintenance cycle admits at most two original-request reads, two new
callback uploads and one new archive mutation. An uncertain archive mutation
is read by its exact original request UUID; unknown or refusal cannot prune,
create another archive request, or replay the invocation. After a lookup ACK,
the callback phase re-reads active storage so archived originals cannot be
uploaded again under replacement UUIDs. ACK byte parsing rejects duplicate
keys, BOM, malformed UTF8, non-JSON tokens and trailing content before parsing.

Lossless export returns exact authenticated ciphertext parts and SHA256 values
for one attempt and its late observations. It preserves all local files and
identities. It is an internal same-installation adapter, not a user export UI,
portable key backup, disaster-recovery approval or deletion mechanism. The
separate legacy request-ACK archive remains bounded to256 request records and
100 legacy attempt records; it fails closed at capacity. Version3 terminal
automatic attempts use the segmented store above rather than that100-attempt
array. Further legacy archive maintenance and an approved retention policy
remain outside this bounded slice.

Existing version2 attempt_status.terminal_archive_ack=false remains a constant
of that version2 projection: it does not expose version3 ACK evidence. It must
not be interpreted as a cross-version assertion that no version3 ACK exists.

Current hot source, ordered original callback references and the durable
archive request are prepared under the same process lock used by callback
recording. A stale terminal snapshot cannot prepare a new request. Deleting
both control files while any cold evidence remains is detected as missing
established control and cannot clear the dispatch stop or reset the catalog.
