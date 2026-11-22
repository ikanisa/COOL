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
    fun coldCallbackPage(afterExclusive: String?, limit: Int): GatewayColdCallbackPage
    fun nextColdCallbackPage(limit: Int): GatewayColdCallbackPage
    fun exportColdCallbackPage(afterExclusive: String?, limit: Int): GatewayLateCallbackExportPage
    fun exportColdAttempt(attemptId: String): GatewayColdArchiveExport
    fun retainUncompactableAck(original: GatewayStoredRequest, ack: JSONObject)
}

internal class GatewayColdArchiveExport(val attemptId: String, val encryptedParts: Map<String, ByteArray>, val lateEvidenceRequiresPaging: Boolean = false) {
    val sha256: Map<String, String> = encryptedParts.mapValues { (_, bytes) -> java.security.MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) } }
}

/** Ciphertext pages are installation evidence, not portable key recovery or
 * restore authority. Base export omits new late objects only with an explicit
 * paging-required flag; each page contains at most sixteen bounded objects. */
internal class GatewayLateCallbackExportPage(val nextCursor: String?, val encryptedParts: Map<String, ByteArray>, val migrationPending: Boolean) {
    init { if (encryptedParts.size > GatewayLateRetention.PAGE_LIMIT * 2 || (migrationPending && encryptedParts.isNotEmpty())) invalidArchive() }
}

internal class GatewayAttemptArchive(private val store: GatewayColdArchiveStorage) {
    fun payload(attempt: GatewayAttempt, legacy: Boolean = false): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateAttempt(attempt)
        if (legacy && attempt.dispatchRoute !is GatewayDispatchRoute.PrimaryV2) invalidArchive()
        if (attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) throw GatewayStateException("gateway_archive_attempt_unresolved")
        if (store.read().attempts.singleOrNull { it.attemptId == attempt.attemptId } != attempt) throw GatewayStateException("gateway_archive_source_conflict")
        val requests = store.readRequests().getJSONArray("requests")
        val refs = JSONArray()
        for ((index, segment) in attempt.segments.withIndex()) for (kind in CallbackKind.entries) {
            val callbackId = if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId
            val matches = (0 until requests.length()).map { GatewayStoredRequest.parse(requests.getJSONObject(it)) }
                .filter { it.callbackId == callbackId && requestMatchesRoute(it, attempt.dispatchRoute) && (if (legacy) !isSuccessorEnvelope(it.envelope) && strictInteger(it.envelope, "contract_version") == 1L else isNoticeEnvelope(it.envelope) || isSuccessorEnvelope(it.envelope) || strictInteger(it.envelope, "contract_version") == 2L) }
            val matching = matches.singleOrNull { callbackMatches(attempt, index, kind, it) }
                ?: throw GatewayStateException("gateway_archive_acknowledgement_pending")
            refs.put(JSONObject().put("callback_id", callbackId).put("request_id", matching.requestId).put("request_sha256", matching.digest))
        }
        JSONObject().put("attempt_id", attempt.attemptId).put("fence_version", attempt.fence).put("body_sha256", attempt.bodySha256)
            .put("destination_sha256", attempt.destinationSha256).put("callback_requests", refs)
            .also { if (attempt.dispatchRoute is GatewayDispatchRoute.ReceiptNoticeV1) it.put("route", noticeRouteJson(attempt.dispatchRoute)) else if (attempt.dispatchRoute is GatewayDispatchRoute.ReceiptSuccessorV1) it.put("route", successorRouteJson(attempt.dispatchRoute)) }
    }

    fun acknowledge(original: GatewayStoredRequest, ack: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        val legacy=original.action=="archive_legacy_attempt" && !isSuccessorEnvelope(original.envelope) && strictInteger(original.envelope,"contract_version")==4L
        if (!legacy && (original.action != "archive_attempt" || (!isNoticeEnvelope(original.envelope) && !isSuccessorEnvelope(original.envelope) && strictInteger(original.envelope, "contract_version") != 3L))) invalidArchive()
        val payload = original.envelope.getJSONObject("payload")
        validateTerminalArchiveAck(original, ack)
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
        if (!requestMatchesRoute(original, attempt.dispatchRoute) || original.deviceId != attempt.deviceId ||
            (attempt.dispatchRoute is GatewayDispatchRoute.PrimaryV2 && requireUuid(ack, "receipt_id") != attempt.jobId)) invalidArchive()
        if (strictInteger(payload, "fence_version") != attempt.fence || strictString(payload, "body_sha256") != attempt.bodySha256 ||
            strictString(payload, "destination_sha256") != attempt.destinationSha256) invalidArchive()
        // A callback can contradict the local snapshot while the authenticated
        // ACK is in flight. Retain both facts without pruning or starving that
        // new callback behind repeated ACK lookups.
        if (attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED || !archiveJsonEqual(payload(attempt,legacy), payload)) {
            store.retainUncompactableAck(original, ack);return@synchronized
        }
        val refs = payload.getJSONArray("callback_requests");val requests = store.readRequests().getJSONArray("requests")
        val copy = JSONArray()
        for (i in 0 until refs.length()) {
            val source = (0 until requests.length()).map { requests.getJSONObject(it) }.singleOrNull { it.getString("request_id") == refs.getJSONObject(i).getString("request_id") }
                ?: throw GatewayStateException("gateway_archive_source_conflict")
            copy.put(JSONObject(source.toString()))
        }
        val tombstone = JSONObject().put("contract_version", if (legacy) 6 else if (attempt.dispatchRoute is GatewayDispatchRoute.ReceiptNoticeV1) 7 else if (attempt.dispatchRoute is GatewayDispatchRoute.ReceiptSuccessorV1) 5 else 3).put("attempt", archiveAttemptJson(attempt))
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
    return requestMatchesRoute(request, a.dispatchRoute) && request.action == "callback" && request.deviceId == a.deviceId && requireUuid(p, "attempt_id") == a.attemptId &&
        strictInteger(p, "fence_version") == a.fence && strictInteger(p, "segment_index") == index.toLong() &&
        strictInteger(p, "segment_count") == a.segments.size.toLong() && strictString(p, "body_sha256") == a.bodySha256 &&
        strictString(p, "destination_sha256") == a.destinationSha256 && strictString(p, "callback_kind") == (if (kind == CallbackKind.SENT) "sent" else "delivery") &&
        strictInteger(p, "result_code") == -1L && strictTimestamp(p, "occurred_at") == Instant.parse(if (kind == CallbackKind.SENT) s.sentObservedAt else s.deliveryObservedAt)
}

internal fun validateColdAttempt(value: JSONObject): JSONObject {
    requireKeys(value, setOf("contract_version", "attempt", "archive_request", "acknowledgement", "callback_requests", "archived_at"))
    val version = strictInteger(value, "contract_version")
    if (version !in setOf(3L, 5L, 6L, 7L)) invalidArchive()
    strictTimestamp(value, "archived_at")
    val a = archiveAttemptFromJson(value.getJSONObject("attempt"))
    if ((version == 5L) != (a.dispatchRoute is GatewayDispatchRoute.ReceiptSuccessorV1)) invalidArchive()
    if ((version == 7L) != (a.dispatchRoute is GatewayDispatchRoute.ReceiptNoticeV1)) invalidArchive()
    if (a.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) invalidArchive()
    val request = GatewayStoredRequest.parse(value.getJSONObject("archive_request"));val p = request.envelope.getJSONObject("payload")
    val legacy=version==6L
    if (request.action != (if(legacy) "archive_legacy_attempt" else "archive_attempt") || !requestMatchesRoute(request, a.dispatchRoute) || request.deviceId != a.deviceId ||
        (!isNoticeEnvelope(request.envelope) && !isSuccessorEnvelope(request.envelope) && strictInteger(request.envelope, "contract_version") != (if(legacy) 4L else 3L))) invalidArchive()
    if (isNoticeEnvelope(request.envelope)) validateNoticePayload(request.action, request.requestId, p) else if (isSuccessorEnvelope(request.envelope)) validateSuccessorPayload(request.action, request.requestId, p) else if(legacy) validateGatewayLegacyArchivePayload(request.action,p,request.requestId) else validateGatewayArchivePayload(request.action, p, request.requestId)
    validateTerminalArchiveAck(request, value.getJSONObject("acknowledgement"))
    if (!strictBoolean(value.getJSONObject("acknowledgement"), "ok") || strictBoolean(value.getJSONObject("acknowledgement"), "replay") ||
        (a.dispatchRoute is GatewayDispatchRoute.PrimaryV2 && requireUuid(value.getJSONObject("acknowledgement"), "receipt_id") != a.jobId) || requireUuid(p, "attempt_id") != a.attemptId ||
        strictInteger(p, "fence_version") != a.fence || strictString(p, "body_sha256") != a.bodySha256 || strictString(p, "destination_sha256") != a.destinationSha256) invalidArchive()
    val rows = value.getJSONArray("callback_requests");val refs = p.getJSONArray("callback_requests")
    if (rows.length() != a.segments.size * 2 || rows.length() != refs.length()) invalidArchive()
    for (i in 0 until rows.length()) {
        val callback = GatewayStoredRequest.parse(rows.getJSONObject(i));val ref = refs.getJSONObject(i)
        if (!requestMatchesRoute(callback, a.dispatchRoute) || (!isNoticeEnvelope(callback.envelope) && !isSuccessorEnvelope(callback.envelope) && strictInteger(callback.envelope, "contract_version") != (if(legacy) 1L else 2L)) || callback.requestId != requireUuid(ref, "request_id") || callback.callbackId != requireUuid(ref, "callback_id") || callback.digest != strictString(ref, "request_sha256") ||
            !callbackMatches(a, i / 2, if (i % 2 == 0) CallbackKind.SENT else CallbackKind.DELIVERY, callback)) invalidArchive()
    }
    return value
}
