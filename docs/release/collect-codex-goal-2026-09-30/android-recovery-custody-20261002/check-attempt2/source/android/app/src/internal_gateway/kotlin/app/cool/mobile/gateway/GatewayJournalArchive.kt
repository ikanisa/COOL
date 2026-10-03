package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.Base64

/** A bounded, append-only local copy of durable server receipts. Implementations
 * must encrypt and fsync the archive atomically before active records are pruned.
 * No API caller, flag, local callback or HTTP status alone is an acknowledgement. */
internal interface GatewayArchiveStorage : GatewayJournalStorage {
    fun readRequests(): JSONObject
    fun saveRequests(value: JSONObject)
    fun readArchive(): JSONObject
    fun commitArchive(value: JSONObject)
}

internal interface GatewayContinuousArchiveStorage : GatewayArchiveStorage {
    fun readRetainedRequest(requestId: String): GatewayStoredRequest?
    fun readRequestReceipt(requestId: String): JSONObject?
    fun commitRequestReceipt(value: JSONObject)
    fun requestAcknowledged(request: GatewayStoredRequest): Boolean
    fun retainedCallbackReceipt(callbackId: String): JSONObject?
    fun readObservedAttempt(attemptId: String): JSONObject?
    fun commitObservedAttempt(value: JSONObject)
}

internal data class GatewayStoredRequest(
    val requestId: String, val deviceId: String, val action: String,
    val digest: String, val callbackId: String?, val envelope: JSONObject, val row: JSONObject,
) {
    companion object {
        fun parse(row: JSONObject): GatewayStoredRequest {
            requireKeys(row, setOf("request_id", "action", "state", "callback_id", "request_sha256", "request_bytes_base64"))
            val id = requireUuid(row, "request_id")
            val action = strictString(row, "action")
            if (action !in setOf("heartbeat", "callback", "dispatch_grant", "arm_dispatch", "archive_attempt") ||
                strictString(row, "state") !in setOf("outcome_unknown", "recorded")) invalidArchive()
            val callback = if (row.isNull("callback_id")) null else requireUuid(row, "callback_id")
            if ((action == "callback") != (callback != null)) invalidArchive()
            val digest = strictString(row, "request_sha256")
            if (!digest.matches(Regex("[0-9a-f]{64}"))) invalidArchive()
            val encoded = strictString(row, "request_bytes_base64")
            if (encoded.length > 44 * 1024) invalidArchive()
            val bytes = try { Base64.getDecoder().decode(encoded) } catch (_: Exception) { invalidArchive() }
            val text = String(bytes, Charsets.UTF_8)
            if (bytes.size > 32 * 1024 || !bytes.contentEquals(text.toByteArray(Charsets.UTF_8)) || sha256(text) != digest) invalidArchive()
            val envelope = try { JSONObject(text) } catch (_: org.json.JSONException) { invalidArchive() }
            if (isSuccessorEnvelope(envelope)) {
                validateSuccessorEnvelope(text, envelope)
                if (requireUuid(envelope, "request_id") != id || strictString(envelope, "action") != action ||
                    action !in setOf("dispatch_grant", "arm_dispatch", "callback", "archive_attempt")) invalidArchive()
                if (callback != null && requireUuid(envelope.getJSONObject("payload"), "callback_id") != callback) invalidArchive()
                return GatewayStoredRequest(id, requireUuid(envelope, "device_id"), action, digest, callback, envelope, JSONObject(row.toString()))
            }
            requireKeys(envelope, setOf("contract_version", "action", "device_id", "request_id", "issued_at", "payload"))
            val version = strictInteger(envelope, "contract_version")
            if ((version == 1L && action !in setOf("heartbeat", "callback", "dispatch_grant")) ||
                (version == 2L && action !in setOf("callback", "dispatch_grant", "arm_dispatch")) ||
                (version == 3L && action != "archive_attempt") || version !in 1L..3L ||
                requireUuid(envelope, "request_id") != id ||
                strictString(envelope, "action") != action || envelope.get("payload") !is JSONObject) invalidArchive()
            val device = requireUuid(envelope, "device_id")
            strictTimestamp(envelope, "issued_at")
            if (version == 3L) validateGatewayArchivePayload(action, envelope.getJSONObject("payload"), id)
            if (callback != null && requireUuid(envelope.getJSONObject("payload"), "callback_id") != callback) invalidArchive()
            return GatewayStoredRequest(id, device, action, digest, callback, envelope, JSONObject(row.toString()))
        }
    }
}

/** Local adapter for the existing signature-authenticated gateway HTTPS protocol.
 * The transport owner must supply the exact successfully validated response to
 * the exact request, or a fresh authenticated reconciliation response. This
 * class does not perform HTTP, infer hosted acknowledgement or issue authority. */
internal class GatewayArchiveAcknowledgement private constructor(
    val request: GatewayStoredRequest, val result: JSONObject, val evidence: JSONObject,
) {
    companion object {
        fun direct(request: GatewayStoredRequest, authenticatedReply: JSONObject): GatewayArchiveAcknowledgement {
            requireAcknowledgableEnvelope(request)
            validateReply(authenticatedReply, request.action, request.deviceId, request.requestId, strictInteger(request.envelope, "contract_version"), isSuccessorEnvelope(request.envelope))
            val result = authenticatedReply.getJSONObject("result")
            validateArchivedGatewayResult(request, request.action, request.requestId, request.envelope.getJSONObject("payload"), result)
            return GatewayArchiveAcknowledgement(request, JSONObject(result.toString()), JSONObject(authenticatedReply.toString()))
        }

        fun reconciled(request: GatewayStoredRequest, reconcileRequestId: String, authenticatedReply: JSONObject): GatewayArchiveAcknowledgement {
            requireAcknowledgableEnvelope(request)
            if (!validUuid(reconcileRequestId) || reconcileRequestId == request.requestId) invalidArchive()
            validateReply(authenticatedReply, "reconcile", request.deviceId, reconcileRequestId, strictInteger(request.envelope, "contract_version"), isSuccessorEnvelope(request.envelope))
            val result = authenticatedReply.getJSONObject("result")
            validateArchivedGatewayResult(request, "reconcile", reconcileRequestId,
                JSONObject().put("target_request_id", request.requestId), result)
            if (strictString(result, "outcome") != "recorded" || strictString(result, "recorded_action") != request.action) {
                throw GatewayStateException("gateway_archive_acknowledgement_pending")
            }
            val recorded = result.getJSONObject("recorded_result")
            validateArchivedGatewayResult(request, request.action, request.requestId, request.envelope.getJSONObject("payload"), recorded)
            return GatewayArchiveAcknowledgement(request, JSONObject(recorded.toString()), JSONObject(authenticatedReply.toString()))
        }

        private fun validateArchivedGatewayResult(request: GatewayStoredRequest, action: String, id: String, payload: JSONObject, result: JSONObject) {
            if (isSuccessorEnvelope(request.envelope)) {
                if (action in setOf("dispatch_grant", "arm_dispatch") && (!result.has("ok") || strictBoolean(result, "ok"))) invalidArchive()
                validateSuccessorResult(action, id, request.deviceId, payload, result, Instant.now())
                if (action == "reconcile" && strictString(result, "outcome") == "recorded") {
                    if (strictString(result, "recorded_action") != request.action) invalidArchive()
                    if (request.action != "dispatch_grant" && !result.isNull("recorded_route") &&
                        successorRouteFromJson(result.getJSONObject("recorded_route")) != successorRouteFromJson(request.envelope.getJSONObject("payload").getJSONObject("route"))) invalidArchive()
                }
            } else if (strictInteger(request.envelope, "contract_version") == 1L) {
                validateGatewayResult(action, id, request.deviceId, payload, result)
            } else {
                // Successful grants/arms contain short-lived authority and are
                // never archive ACKs. Only redacted original-request facts may
                // compact their request record. Callback history stays active.
                if (action in setOf("dispatch_grant", "arm_dispatch") && (!result.has("ok") || strictBoolean(result, "ok"))) invalidArchive()
                validateGatewayDispatchResultV2(action, id, request.deviceId, payload, result, Instant.now())
            }
        }

        private fun validateReply(reply: JSONObject, action: String, deviceId: String, requestId: String, version: Long, successor: Boolean) {
            if (successor) {
                requireKeys(reply, setOf("contract_version", "protocol_family", "audience", "action", "device_id", "request_id", "result"))
                if (strictString(reply, "protocol_family") != SUCCESSOR_FAMILY || strictString(reply, "audience") != SUCCESSOR_AUDIENCE) invalidArchive()
            } else requireKeys(reply, setOf("contract_version", "action", "device_id", "request_id", "result"))
            if (strictInteger(reply, "contract_version") != version || strictString(reply, "action") != action ||
                requireUuid(reply, "device_id") != deviceId || requireUuid(reply, "request_id") != requestId ||
                reply.get("result") !is JSONObject) invalidArchive()
        }

        private fun requireAcknowledgableEnvelope(request: GatewayStoredRequest) {
            // Existing active journals admit 32 KiB; the authenticated server
            // admits only 8 KiB. Larger legacy evidence stays active, unresolved.
            if (Base64.getDecoder().decode(request.row.getString("request_bytes_base64")).size > 8 * 1024) invalidArchive()
        }
    }
}

/** Archive capacity is finite. Exhaustion stops compaction; it never evicts an
 * acknowledgement, changes an identity, drops unknown work or enables a send. */
internal class GatewayJournalArchive(private val storage: GatewayArchiveStorage, private val clock: () -> Instant = Instant::now) {
    companion object {
        const val MAX_REQUESTS = 256
        const val MAX_ATTEMPTS = 100
        fun empty(): JSONObject = JSONObject().put("contract_version", 1).put("requests", JSONArray()).put("attempts", JSONArray())
    }

    fun acknowledge(ack: GatewayArchiveAcknowledgement) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (storage is GatewayContinuousArchiveStorage) {
            val existing = storage.readRequestReceipt(ack.request.requestId)
            if (existing != null) {
                requireSameRequest(ack.request, GatewayStoredRequest.parse(existing.getJSONObject("request")))
                if (!archiveJsonEqual(normalizedResult(existing.getJSONObject("result")), normalizedResult(ack.result))) invalidArchive()
            } else {
                val active = storage.readRequests().getJSONArray("requests")
                val source = (0 until active.length()).map { active.getJSONObject(it) }.singleOrNull { it.getString("request_id") == ack.request.requestId }
                    ?: throw GatewayStateException("gateway_archive_request_missing")
                requireSameRequest(ack.request, GatewayStoredRequest.parse(source))
                storage.commitRequestReceipt(JSONObject().put("request", JSONObject(source.toString())).put("result", JSONObject(ack.result.toString()))
                    .put("evidence", JSONObject(ack.evidence.toString())).put("acknowledged_at", gatewayWireTime(clock())))
            }
            compactRequests(validatedArchive(storage.readArchive()), ack.request.action != "callback")
            return@synchronized
        }
        val archive = validatedArchive(storage.readArchive())
        val entries = archive.getJSONArray("requests")
        val existing = (0 until entries.length()).map { entries.getJSONObject(it) }.firstOrNull {
            it.getJSONObject("request").getString("request_id") == ack.request.requestId
        }
        if (existing != null) {
            requireSameRequest(ack.request, GatewayStoredRequest.parse(existing.getJSONObject("request")))
            if (!archiveJsonEqual(normalizedResult(existing.getJSONObject("result")), normalizedResult(ack.result))) invalidArchive()
            // Retry only the local pruning step after an interrupted archive-first
            // commit; never replay a network mutation or replace receipt evidence.
            compactRequests(archive, ack.request.action != "callback")
            return@synchronized
        }
        val active = storage.readRequests().getJSONArray("requests")
        val source = (0 until active.length()).map { active.getJSONObject(it) }.firstOrNull {
            it.getString("request_id") == ack.request.requestId
        } ?: throw GatewayStateException("gateway_archive_request_missing")
        requireSameRequest(ack.request, GatewayStoredRequest.parse(source))
        if (entries.length() >= MAX_REQUESTS) throw GatewayStateException("gateway_archive_limit")
        entries.put(JSONObject().put("request", JSONObject(source.toString())).put("result", JSONObject(ack.result.toString()))
            .put("evidence", JSONObject(ack.evidence.toString())).put("acknowledged_at", gatewayWireTime(clock())))
        validatedArchive(archive)
        storage.commitArchive(archive) // durable commit point precedes pruning
        compactRequests(archive, ack.request.action != "callback")
    }

    fun compactAcknowledgedRequests() = synchronized(GatewayJournal.PROCESS_LOCK) {
        val archive = validatedArchive(storage.readArchive())
        val requests = archive.getJSONArray("requests")
        compactRequests(archive, (0 until requests.length()).any { requests.getJSONObject(it).getJSONObject("request").getString("action") != "callback" })
    }

    /** A complete known callback set can be archived only when each observation
     * has a bound durable server receipt. The original attempt stays active:
     * current v1 has no terminal-attempt acknowledgement/callback closure API.
     * Unknown/partial/exception attempts are never archived or compacted. */
    fun archiveAcknowledgedAttempt(attemptId: String) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (!validUuid(attemptId)) invalidArchive()
        val archive = validatedArchive(storage.readArchive())
        val state = storage.read()
        val attempt = state.attempts.firstOrNull { it.attemptId == attemptId }
            ?: throw GatewayStateException("gateway_attempt_missing")
        validateAttempt(attempt)
        if (attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) throw GatewayStateException("gateway_archive_attempt_unresolved")
        if (storage is GatewayContinuousArchiveStorage) {
            val receipts = JSONArray()
            for (segment in attempt.segments) for (callbackId in listOf(segment.sentCallbackId, segment.deliveryCallbackId)) {
                val receipt = storage.retainedCallbackReceipt(callbackId)
                    ?: (0 until archive.getJSONArray("requests").length()).map { archive.getJSONArray("requests").getJSONObject(it) }
                        .firstOrNull { it.getJSONObject("request").optString("callback_id") == callbackId }
                    ?: throw GatewayStateException("gateway_archive_acknowledgement_pending")
                receipts.put(receipt)
            }
            requireAttemptReceipts(attempt, receipts)
            val previous = storage.readObservedAttempt(attemptId)
            if (previous != null) {
                if (!archiveJsonEqual(previous.getJSONObject("attempt"), archiveAttemptJson(attempt)) || !archiveJsonEqual(previous.getJSONArray("callback_receipts"), receipts)) throw GatewayStateException("gateway_archive_source_conflict")
            } else storage.commitObservedAttempt(JSONObject().put("contract_version", 4).put("attempt", archiveAttemptJson(attempt))
                .put("callback_receipts", receipts).put("archived_at", gatewayWireTime(clock())))
            return@synchronized
        }
        requireAttemptReceipts(attempt, archive.getJSONArray("requests"))
        val rows = archive.getJSONArray("attempts")
        val encoded = archiveAttemptJson(attempt)
        val prior = (0 until rows.length()).map { rows.getJSONObject(it) }.firstOrNull {
            it.getJSONObject("attempt").getString("attempt_id") == attemptId
        }
        if (prior != null) {
            if (!archiveJsonEqual(prior.getJSONObject("attempt"), encoded)) throw GatewayStateException("gateway_archive_source_conflict")
            return@synchronized
        }
        if (rows.length() >= MAX_ATTEMPTS) throw GatewayStateException("gateway_archive_limit")
        rows.put(JSONObject().put("attempt", encoded).put("archived_at", gatewayWireTime(clock())))
        validatedArchive(archive)
        storage.commitArchive(archive)
    }

    fun compactAttempt(attemptId: String): Nothing {
        if (!validUuid(attemptId)) invalidArchive()
        throw GatewayStateException("gateway_attempt_archive_authority_pending")
    }

    private fun compactRequests(archive: JSONObject, forcePrune: Boolean = false) {
        val active = storage.readRequests()
        val keep = JSONArray()
        val receipts = archive.getJSONArray("requests")
        for (index in 0 until active.getJSONArray("requests").length()) {
            val row = active.getJSONArray("requests").getJSONObject(index)
            val request = GatewayStoredRequest.parse(row)
            val recorded = archivedRequest(receipts, request.requestId)
            if (recorded != null) requireSameRequest(request, GatewayStoredRequest.parse(recorded.getJSONObject("request")))
            // Retain callback requests in the active journal so existing upload
            // duplicate checks and all late callback reconciliation remain intact.
            val retained = (storage as? GatewayContinuousArchiveStorage)?.requestAcknowledged(request) == true
            if ((recorded == null && !retained) || request.action == "callback") keep.put(row)
        }
        if (forcePrune || keep.length() != active.getJSONArray("requests").length()) {
            storage.saveRequests(JSONObject().put("contract_version", 1).put("requests", keep))
        }
    }
}

internal fun requireSameRequest(left: GatewayStoredRequest, right: GatewayStoredRequest) {
    if (left.requestId != right.requestId || left.deviceId != right.deviceId || left.action != right.action ||
        left.digest != right.digest || left.callbackId != right.callbackId ||
        left.row.getString("request_bytes_base64") != right.row.getString("request_bytes_base64")) {
        throw GatewayStateException("gateway_archive_source_conflict")
    }
}

internal fun normalizedResult(result: JSONObject): JSONObject = JSONObject(result.toString()).put("replay", false)
internal fun archivedRequest(rows: JSONArray, id: String): JSONObject? = (0 until rows.length()).map { rows.getJSONObject(it) }
    .firstOrNull { it.getJSONObject("request").getString("request_id") == id }
internal fun invalidArchive(): Nothing = throw GatewayStateException("gateway_archive_invalid")

// Android's org.json has no JSONObject.similar. Compare exact keys and ordered
// arrays without relying on serialization key order or numeric coercion.
internal fun archiveJsonEqual(left: Any?, right: Any?): Boolean = when {
    left is JSONObject && right is JSONObject -> {
        val keys = left.keys().asSequence().toSet()
        keys == right.keys().asSequence().toSet() && keys.all { archiveJsonEqual(left.get(it), right.get(it)) }
    }
    left is JSONArray && right is JSONArray -> left.length() == right.length() &&
        (0 until left.length()).all { archiveJsonEqual(left.get(it), right.get(it)) }
    (left is Int || left is Long) && (right is Int || right is Long) -> (left as Number).toLong() == (right as Number).toLong()
    else -> left == right
}

internal fun validatedArchive(value: JSONObject): JSONObject {
    requireKeys(value, setOf("contract_version", "requests", "attempts"))
    if (value.get("contract_version") != 1 || value.get("requests") !is JSONArray || value.get("attempts") !is JSONArray) invalidArchive()
    if (value.toString().toByteArray(Charsets.UTF_8).size > GatewayCrypto.MAX_BYTES || value.getJSONArray("requests").length() > GatewayJournalArchive.MAX_REQUESTS ||
        value.getJSONArray("attempts").length() > GatewayJournalArchive.MAX_ATTEMPTS) throw GatewayStateException("gateway_archive_limit")
    val ids = HashSet<String>()
    val callbacks = HashSet<String>()
    val requests = value.getJSONArray("requests")
    for (index in 0 until requests.length()) {
        val row = requests.getJSONObject(index)
        requireKeys(row, setOf("request", "result", "evidence", "acknowledged_at"))
        val request = GatewayStoredRequest.parse(row.getJSONObject("request"))
        if (!ids.add(request.requestId) || request.callbackId?.let { !callbacks.add(it) } == true) invalidArchive()
        strictTimestamp(row, "acknowledged_at")
        val evidence = row.getJSONObject("evidence")
        val ack = if (strictString(evidence, "action") == "reconcile")
            GatewayArchiveAcknowledgement.reconciled(request, requireUuid(evidence, "request_id"), evidence)
            else GatewayArchiveAcknowledgement.direct(request, evidence)
        if (!archiveJsonEqual(normalizedResult(ack.result), normalizedResult(row.getJSONObject("result")))) invalidArchive()
    }
    val attempts = value.getJSONArray("attempts")
    val attemptIds = HashSet<String>()
    for (index in 0 until attempts.length()) {
        val row = attempts.getJSONObject(index)
        requireKeys(row, setOf("attempt", "archived_at"))
        strictTimestamp(row, "archived_at")
        val attempt = archiveAttemptFromJson(row.getJSONObject("attempt"))
        if (!attemptIds.add(attempt.attemptId) || attempt.outcome() != AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) invalidArchive()
        requireAttemptReceipts(attempt, requests)
    }
    return value
}

internal fun requireAttemptReceipts(attempt: GatewayAttempt, requests: JSONArray) {
    for ((index, segment) in attempt.segments.withIndex()) for (kind in CallbackKind.entries) {
        val callbackId = if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId
        val entries = (0 until requests.length()).map { requests.getJSONObject(it) }
        val row = entries.firstOrNull { it.getJSONObject("request").optString("callback_id") == callbackId }
            ?: throw GatewayStateException("gateway_archive_acknowledgement_pending")
        val request = GatewayStoredRequest.parse(row.getJSONObject("request"))
        val payload = request.envelope.getJSONObject("payload")
        if (!requestMatchesRoute(request, attempt.dispatchRoute) || request.action != "callback" || request.deviceId != attempt.deviceId || requireUuid(payload, "attempt_id") != attempt.attemptId ||
            strictInteger(payload, "fence_version") != attempt.fence || strictInteger(payload, "segment_index") != index.toLong() ||
            strictInteger(payload, "segment_count") != attempt.segments.size.toLong() || strictString(payload, "body_sha256") != attempt.bodySha256 ||
            strictString(payload, "destination_sha256") != attempt.destinationSha256 || strictString(payload, "callback_kind") != (if (kind == CallbackKind.SENT) "sent" else "delivery") ||
            strictInteger(payload, "result_code") != (if (kind == CallbackKind.SENT) segment.sentCode else segment.deliveryCode)?.toLong() ||
            strictTimestamp(payload, "occurred_at") != Instant.parse(if (kind == CallbackKind.SENT) segment.sentObservedAt else segment.deliveryObservedAt)) {
            throw GatewayStateException("gateway_archive_source_conflict")
        }
    }
}

private fun primaryArchiveAttemptJson(attempt: GatewayAttempt): JSONObject = JSONObject()
    .put("device_id", attempt.deviceId).put("job_id", attempt.jobId).put("attempt_id", attempt.attemptId).put("fence", attempt.fence)
    .put("body_sha256", attempt.bodySha256).put("destination_sha256", attempt.destinationSha256).put("grant_expires_at", attempt.grantExpiresAt)
    .put("invocation_started_at", attempt.invocationStartedAt).put("callback_nonce", attempt.callbackNonce).put("invocation_exception", attempt.invocationException)
    .put("segments", JSONArray(attempt.segments.map { segment -> JSONObject()
        .put("sent_callback_id", segment.sentCallbackId).put("delivery_callback_id", segment.deliveryCallbackId)
        .put("sent", segment.sent.name).put("delivery", segment.delivery.name)
        .put("sent_code", segment.sentCode ?: JSONObject.NULL).put("delivery_code", segment.deliveryCode ?: JSONObject.NULL)
        .put("sent_observed_at", segment.sentObservedAt ?: JSONObject.NULL).put("delivery_observed_at", segment.deliveryObservedAt ?: JSONObject.NULL) }))

private fun primaryArchiveAttemptFromJson(row: JSONObject): GatewayAttempt {
    requireKeys(row, setOf("device_id", "job_id", "attempt_id", "fence", "body_sha256", "destination_sha256", "grant_expires_at", "invocation_started_at", "callback_nonce", "segments", "invocation_exception"))
    val segments = row.getJSONArray("segments")
    if (segments.length() !in 1..GatewayJournal.MAX_SEGMENTS) invalidArchive()
    val attempt = GatewayAttempt(requireUuid(row, "device_id"), requireUuid(row, "job_id"), requireUuid(row, "attempt_id"), strictInteger(row, "fence"),
        strictString(row, "body_sha256"), strictString(row, "destination_sha256"), strictString(row, "grant_expires_at"), strictString(row, "invocation_started_at"),
        strictString(row, "callback_nonce"), (0 until segments.length()).map {
            val segment = segments.getJSONObject(it)
            requireKeys(segment, setOf("sent_callback_id", "delivery_callback_id", "sent", "delivery", "sent_code", "delivery_code", "sent_observed_at", "delivery_observed_at"))
            SegmentEvidence(requireUuid(segment, "sent_callback_id"), requireUuid(segment, "delivery_callback_id"),
                SegmentOutcome.valueOf(strictString(segment, "sent")), SegmentOutcome.valueOf(strictString(segment, "delivery")),
                archiveCallbackCode(segment, "sent_code"), archiveCallbackCode(segment, "delivery_code"),
                if (segment.isNull("sent_observed_at")) null else strictString(segment, "sent_observed_at"),
                if (segment.isNull("delivery_observed_at")) null else strictString(segment, "delivery_observed_at"))
        }, strictBoolean(row, "invocation_exception"))
    validateAttempt(attempt)
    return attempt
}

private fun archiveCallbackCode(value: JSONObject, name: String): Int? {
    if (value.isNull(name)) return null
    val number = strictInteger(value, name)
    if (number !in -1..200) invalidArchive()
    return number.toInt()
}

private val originalAttemptKeys = setOf("device_id", "job_id", "attempt_id", "fence", "body_sha256", "destination_sha256", "grant_expires_at", "invocation_started_at", "callback_nonce", "segments", "invocation_exception")
internal fun archiveAttemptJson(attempt: GatewayAttempt): JSONObject {
    validateAttempt(attempt)
    val row = primaryArchiveAttemptJson(attempt)
    return if (attempt.dispatchRoute is GatewayDispatchRoute.ReceiptSuccessorV1) row.put("record_kind", "receipt_successor_v1").put("route", successorRouteJson(attempt.dispatchRoute)) else row
}
internal fun archiveAttemptFromJson(row: JSONObject): GatewayAttempt {
    if (!row.has("record_kind")) return primaryArchiveAttemptFromJson(row)
    requireKeys(row, originalAttemptKeys + setOf("record_kind", "route"))
    if (strictString(row, "record_kind") != "receipt_successor_v1") invalidArchive()
    val route = successorRouteFromJson(row.getJSONObject("route"))
    val original = JSONObject(row.toString()).also { it.remove("record_kind"); it.remove("route") }
    return primaryArchiveAttemptFromJson(original).copy(dispatchRoute = route).also(::validateAttempt)
}
internal fun journalAttemptJsonV2(attempt: GatewayAttempt): JSONObject = archiveAttemptJson(attempt).also {
    if (attempt.dispatchRoute is GatewayDispatchRoute.PrimaryV2) it.put("record_kind", "primary_v2")
}
internal fun journalAttemptFromJsonV2(row: JSONObject): GatewayAttempt = when (strictString(row, "record_kind")) {
    "primary_v2" -> { requireKeys(row, originalAttemptKeys + "record_kind"); archiveAttemptFromJson(JSONObject(row.toString()).also { it.remove("record_kind") }) }
    "receipt_successor_v1" -> archiveAttemptFromJson(row)
    else -> invalidArchive()
}
