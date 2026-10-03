package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** One bounded encrypted cold object per identity, with bounded shard metadata.
 * No eviction/retention setter. Lossless ciphertext export never grants pruning. */
internal interface GatewayColdArchiveStorage : GatewayArchiveStorage {
    fun readColdAttempt(attemptId: String): JSONObject?
    fun commitColdAttempt(attemptId: String, value: JSONObject)
    fun coldStop(): Boolean
    fun appendColdConflict(attempt: GatewayAttempt, callback: GatewayCallback)
    fun coldPendingCallbacks(): List<Pair<GatewayAttempt, GatewayCallback>>
    fun exportColdAttempt(attemptId: String): GatewayColdArchiveExport
    fun retainUncompactableAck(original: GatewayStoredRequest, ack: JSONObject)
}

internal class GatewayColdArchiveExport(val attemptId: String, val encryptedParts: Map<String, ByteArray>) {
    val sha256: Map<String, String> = encryptedParts.mapValues { (_, bytes) -> java.security.MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) } }
}

internal class GatewayAttemptArchive(private val store: GatewayColdArchiveStorage) {
    fun payload(attempt: GatewayAttempt): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateAttempt(attempt)
        if (attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) throw GatewayStateException("gateway_archive_attempt_unresolved")
        if (store.read().attempts.singleOrNull { it.attemptId == attempt.attemptId } != attempt) throw GatewayStateException("gateway_archive_source_conflict")
        val requests = store.readRequests().getJSONArray("requests")
        val refs = JSONArray()
        for ((index, segment) in attempt.segments.withIndex()) for (kind in CallbackKind.entries) {
            val callbackId = if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId
            val matches = (0 until requests.length()).map { GatewayStoredRequest.parse(requests.getJSONObject(it)) }
                .filter { it.callbackId == callbackId && strictInteger(it.envelope, "contract_version") == 2L }
            val matching = matches.singleOrNull { callbackMatches(attempt, index, kind, it) }
                ?: throw GatewayStateException("gateway_archive_acknowledgement_pending")
            refs.put(JSONObject().put("callback_id", callbackId).put("request_id", matching.requestId).put("request_sha256", matching.digest))
        }
        JSONObject().put("attempt_id", attempt.attemptId).put("fence_version", attempt.fence).put("body_sha256", attempt.bodySha256)
            .put("destination_sha256", attempt.destinationSha256).put("callback_requests", refs)
    }

    fun acknowledge(original: GatewayStoredRequest, ack: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (original.action != "archive_attempt" || strictInteger(original.envelope, "contract_version") != 3L) invalidArchive()
        val payload = original.envelope.getJSONObject("payload")
        validateGatewayArchiveAck(ack, original.requestId, original.deviceId, payload)
        if (!strictBoolean(ack, "ok") || strictBoolean(ack, "replay")) throw GatewayStateException("gateway_archive_acknowledgement_pending")
        val id = requireUuid(payload, "attempt_id")
        val cold = store.readColdAttempt(id)
        if (cold != null) {
            requireSameRequest(original, GatewayStoredRequest.parse(cold.getJSONObject("archive_request")))
            if (!archiveJsonEqual(cold.getJSONObject("acknowledgement"), ack)) invalidArchive()
            // A crash may leave the fsynced object before its shard/catalog.
            // Repair that exact identity under the same capacity checks before
            // any active original is compacted.
            store.commitColdAttempt(id, cold)
            compact(id, cold);return@synchronized
        }
        val attempt = store.read().attempts.firstOrNull { it.attemptId == id } ?: throw GatewayStateException("gateway_attempt_missing")
        if (requireUuid(ack, "receipt_id") != attempt.jobId || original.deviceId != attempt.deviceId) invalidArchive()
        if (strictInteger(payload, "fence_version") != attempt.fence || strictString(payload, "body_sha256") != attempt.bodySha256 ||
            strictString(payload, "destination_sha256") != attempt.destinationSha256) invalidArchive()
        // A callback can contradict the local snapshot while the authenticated
        // ACK is in flight. Retain both facts without pruning or starving that
        // new callback behind repeated ACK lookups.
        if (attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED || !archiveJsonEqual(payload(attempt), payload)) {
            store.retainUncompactableAck(original, ack);return@synchronized
        }
        val refs = payload.getJSONArray("callback_requests");val requests = store.readRequests().getJSONArray("requests")
        val copy = JSONArray()
        for (i in 0 until refs.length()) {
            val source = (0 until requests.length()).map { requests.getJSONObject(it) }.singleOrNull { it.getString("request_id") == refs.getJSONObject(i).getString("request_id") }
                ?: throw GatewayStateException("gateway_archive_source_conflict")
            copy.put(JSONObject(source.toString()))
        }
        val tombstone = JSONObject().put("contract_version", 3).put("attempt", archiveAttemptJson(attempt))
            .put("archive_request", original.row).put("acknowledgement", JSONObject(ack.toString())).put("callback_requests", copy)
            .put("archived_at", gatewayWireTime(Instant.now()))
        validateColdAttempt(tombstone)
        store.commitColdAttempt(id, tombstone) // encrypted fsync + exact cold readback
        compact(id, tombstone) // only after the complete immutable object exists
    }

    private fun compact(id: String, cold: JSONObject) {
        validateColdAttempt(cold)
        val state = store.read()
        val attempt = archiveAttemptFromJson(cold.getJSONObject("attempt"))
        val active = state.attempts.firstOrNull { it.attemptId == id }
        if (active != null && active != attempt) throw GatewayStateException("gateway_archive_source_conflict")
        store.commit(state.copy(emergencyPaused = state.emergencyPaused || store.coldStop(), attempts = state.attempts.filterNot { it.attemptId == id }))
        val known = cold.getJSONArray("callback_requests")
        val ids = (0 until known.length()).associate { val row = known.getJSONObject(it);row.getString("request_id") to row } +
            (cold.getJSONObject("archive_request").getString("request_id") to cold.getJSONObject("archive_request"))
        val requests = store.readRequests();val keep = JSONArray()
        for (i in 0 until requests.getJSONArray("requests").length()) {
            val row = requests.getJSONArray("requests").getJSONObject(i)
            val previous = ids[row.getString("request_id")]
            if (previous == null) keep.put(row) else requireSameRequest(GatewayStoredRequest.parse(row), GatewayStoredRequest.parse(previous))
        }
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", keep))
    }
}

internal fun callbackMatches(a: GatewayAttempt, index: Int, kind: CallbackKind, request: GatewayStoredRequest): Boolean {
    val p = request.envelope.getJSONObject("payload");val s = a.segments[index]
    return request.action == "callback" && request.deviceId == a.deviceId && requireUuid(p, "attempt_id") == a.attemptId &&
        strictInteger(p, "fence_version") == a.fence && strictInteger(p, "segment_index") == index.toLong() &&
        strictInteger(p, "segment_count") == a.segments.size.toLong() && strictString(p, "body_sha256") == a.bodySha256 &&
        strictString(p, "destination_sha256") == a.destinationSha256 && strictString(p, "callback_kind") == (if (kind == CallbackKind.SENT) "sent" else "delivery") &&
        strictInteger(p, "result_code") == -1L && strictTimestamp(p, "occurred_at") == Instant.parse(if (kind == CallbackKind.SENT) s.sentObservedAt else s.deliveryObservedAt)
}

internal fun validateColdAttempt(value: JSONObject): JSONObject {
    requireKeys(value, setOf("contract_version", "attempt", "archive_request", "acknowledgement", "callback_requests", "archived_at"))
    if (strictInteger(value, "contract_version") != 3L) invalidArchive()
    strictTimestamp(value, "archived_at")
    val a = archiveAttemptFromJson(value.getJSONObject("attempt"))
    if (a.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) invalidArchive()
    val request = GatewayStoredRequest.parse(value.getJSONObject("archive_request"));val p = request.envelope.getJSONObject("payload")
    if (request.action != "archive_attempt" || strictInteger(request.envelope, "contract_version") != 3L) invalidArchive()
    validateGatewayArchivePayload(request.action, p, request.requestId)
    validateGatewayArchiveAck(value.getJSONObject("acknowledgement"), request.requestId, a.deviceId, p)
    if (!strictBoolean(value.getJSONObject("acknowledgement"), "ok") || strictBoolean(value.getJSONObject("acknowledgement"), "replay") ||
        requireUuid(value.getJSONObject("acknowledgement"), "receipt_id") != a.jobId || requireUuid(p, "attempt_id") != a.attemptId ||
        strictInteger(p, "fence_version") != a.fence || strictString(p, "body_sha256") != a.bodySha256 || strictString(p, "destination_sha256") != a.destinationSha256) invalidArchive()
    val rows = value.getJSONArray("callback_requests");val refs = p.getJSONArray("callback_requests")
    if (rows.length() != a.segments.size * 2 || rows.length() != refs.length()) invalidArchive()
    for (i in 0 until rows.length()) {
        val callback = GatewayStoredRequest.parse(rows.getJSONObject(i));val ref = refs.getJSONObject(i)
        if (strictInteger(callback.envelope, "contract_version") != 2L || callback.requestId != requireUuid(ref, "request_id") || callback.callbackId != requireUuid(ref, "callback_id") || callback.digest != strictString(ref, "request_sha256") ||
            !callbackMatches(a, i / 2, if (i % 2 == 0) CallbackKind.SENT else CallbackKind.DELIVERY, callback)) invalidArchive()
    }
    return value
}
