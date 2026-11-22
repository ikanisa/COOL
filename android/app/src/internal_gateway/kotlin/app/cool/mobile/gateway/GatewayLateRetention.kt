package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigInteger
import java.time.Instant

internal data class GatewayLateCallbackEvidence(val cursorKey: String, val evidenceKey: String, val attempt: GatewayAttempt, val callback: GatewayCallback) {
    init { if (!cursorKey.matches(Regex("[0-9a-f]{32}")) || !evidenceKey.matches(Regex("[0-9a-f]{32}"))) invalidArchive() }
}
internal data class GatewayColdCallbackPage(val entries: List<GatewayLateCallbackEvidence>, val nextCursor: String?, val migrationPending: Boolean = false) {
    init {
        if (entries.size > GatewayLateRetention.PAGE_LIMIT || entries.map { it.cursorKey }.toSet().size != entries.size ||
            (nextCursor != null && !nextCursor.matches(Regex("[0-9a-f]{32}"))) || (migrationPending && (entries.isNotEmpty() || nextCursor != null))) invalidArchive()
    }
}

/** Immutable exact observations and a separate monotonic work order. The work
 * cursor advances before transport and wraps at its captured ceiling. A lost
 * response keeps its original transport UUID; cursor movement never closes it.
 * Legacy ciphertext remains unchanged and each migration call copies <=4 rows. */
internal class GatewayLateRetention(
    private val index: GatewayRetentionIndex,
    private val load: (String) -> JSONObject?,
    private val save: (String, JSONObject) -> Unit,
    private val originalAttempt: (String) -> GatewayAttempt,
    private val stop: () -> Unit,
    private val legacyIds: () -> JSONArray,
    private val legacyRows: (String) -> JSONArray,
) {
    companion object { const val PAGE_LIMIT = 8; private val ZERO = "0".repeat(32) }
    private fun key(value: String): String { if (!value.matches(Regex("[0-9a-f]{32}"))) invalidArchive();return value }
    private fun increment(value: String): String {
        val next = BigInteger(key(value), 16).add(BigInteger.ONE).toString(16)
        if (next.length > 32) throw GatewayStateException("gateway_storage_limit")
        return next.padStart(32, '0')
    }
    private fun pending(): JSONObject {
        val value = load("late-retention-pending") ?: throw GatewayStateException("gateway_retention_missing")
        requireKeys(value, setOf("contract_version", "pending"))
        if (strictInteger(value, "contract_version") != 5L || (!value.isNull("pending") && value.get("pending") !is JSONObject)) invalidArchive()
        return value
    }
    private fun control(): JSONObject {
        val value = load("late-retention-control")
        if (value == null) {
            if (index.hasKind("late-evidence") || index.hasKind("late-work") || index.hasKind("late-body") || index.hasKind("late-receipt")) throw GatewayStateException("gateway_retention_missing")
            val intent = load("late-retention-pending")
            if (intent != null) { requireKeys(intent, setOf("contract_version", "pending"));if (strictInteger(intent, "contract_version") != 5L || !intent.isNull("pending")) invalidArchive() }
            if (intent == null) save("late-retention-pending", JSONObject().put("contract_version", 5).put("pending", JSONObject.NULL))
            val initial = JSONObject().put("contract_version", 5).put("next_sequence", ZERO)
            save("late-retention-control", initial)
            if (!archiveJsonEqual(load("late-retention-control"), initial)) invalidArchive()
            return initial
        }
        requireKeys(value, setOf("contract_version", "next_sequence"))
        if (strictInteger(value, "contract_version") != 5L) invalidArchive()
        key(strictString(value, "next_sequence"));pending()
        return value
    }
    private fun evidenceKey(value: JSONObject): String = sha256(retentionCanonical(value)).take(32)
    private fun parseEvidence(value: JSONObject): Pair<GatewayAttempt, GatewayCallback> {
        requireKeys(value, setOf("contract_version", "attempt_id", "callback"))
        if (strictInteger(value, "contract_version") != 5L) invalidArchive()
        val attempt = originalAttempt(requireUuid(value, "attempt_id"))
        val callback = gatewayLateCallbackFromJson(value.getJSONObject("callback"))
        validateGatewayLateCallback(attempt, callback)
        return attempt to callback
    }
    internal fun readEvidence(id: String): Pair<GatewayAttempt, GatewayCallback>? {
        val value = index.read("late-evidence", key(id)) ?: return null
        if (evidenceKey(value) != id) invalidArchive()
        return parseEvidence(value)
    }
    private fun publishPending(intent: JSONObject) {
        requireKeys(intent, setOf("sequence", "evidence"))
        val sequence = key(strictString(intent, "sequence"));val value = intent.getJSONObject("evidence")
        val (attempt, callback) = parseEvidence(value);val id = evidenceKey(value)
        val state = control();val next = strictString(state, "next_sequence")
        if (next != sequence && next != increment(sequence)) throw GatewayStateException("gateway_archive_source_conflict")
        index.publish("late-evidence", id, value)
        val payload = gatewayLatePayload(attempt, callback);val bodyKey = sha256(retentionCanonical(payload)).take(32)
        val body = index.read("late-body", bodyKey)
        if (body != null) {
            requireKeys(body, setOf("contract_version", "payload", "evidence_key"))
            if (strictInteger(body, "contract_version") != 5L || !archiveJsonEqual(body.getJSONObject("payload"), payload)) throw GatewayStateException("gateway_archive_source_conflict")
            readEvidence(key(strictString(body, "evidence_key"))) ?: throw GatewayStateException("gateway_retention_missing")
        }
        index.publish("late-body", bodyKey, body ?: JSONObject().put("contract_version", 5).put("payload", payload).put("evidence_key", id))
        index.publish("late-work", sequence, JSONObject().put("contract_version", 5).put("sequence", sequence).put("evidence_key", id).put("evidence_sha256", sha256(retentionCanonical(value))))
        if (!index.indexed("late-evidence", id) || !index.indexed("late-body", bodyKey) || !index.indexed("late-work", sequence)) invalidArchive()
        if (next == sequence) {
            state.put("next_sequence", increment(sequence));save("late-retention-control", state)
            if (!archiveJsonEqual(load("late-retention-control"), state)) invalidArchive()
        }
        save("late-retention-pending", JSONObject().put("contract_version", 5).put("pending", JSONObject.NULL))
        if (!pending().isNull("pending")) invalidArchive()
    }
    private fun repair() {
        control();val value = pending()
        if (!value.isNull("pending")) { stop();publishPending(value.getJSONObject("pending")) }
    }
    fun append(attempt: GatewayAttempt, callback: GatewayCallback) {
        if (originalAttempt(attempt.attemptId) != attempt) throw GatewayStateException("gateway_archive_source_conflict")
        validateGatewayLateCallback(attempt, callback)
        stop() // durable latch precedes pending intent, index or evidence writes
        repair()
        val value = JSONObject().put("contract_version", 5).put("attempt_id", attempt.attemptId).put("callback", gatewayLateCallbackJson(callback))
        val id = evidenceKey(value);val known = index.read("late-evidence", id)
        if (known != null) {
            if (!archiveJsonEqual(known, value)) throw GatewayStateException("gateway_archive_source_conflict")
            if (!index.indexed("late-evidence", id)) throw GatewayStateException("gateway_retention_missing")
            return
        }
        val sequence = strictString(control(), "next_sequence")
        val intent = JSONObject().put("sequence", sequence).put("evidence", value)
        save("late-retention-pending", JSONObject().put("contract_version", 5).put("pending", intent))
        if (!archiveJsonEqual(pending().getJSONObject("pending"), intent)) invalidArchive()
        publishPending(intent)
    }
    internal fun migrateLegacy(): Boolean {
        repair()
        val ids = legacyIds();val hash = sha256(retentionCanonical(ids))
        val state = load("late-retention-migration") ?: JSONObject().put("contract_version", 5).put("legacy_ids_sha256", hash)
            .put("attempt_position", 0).put("callback_position", 0).put("rows_sha256", JSONObject.NULL).put("complete", false)
        requireKeys(state, setOf("contract_version", "legacy_ids_sha256", "attempt_position", "callback_position", "rows_sha256", "complete"))
        if (strictInteger(state, "contract_version") != 5L || strictString(state, "legacy_ids_sha256") != hash) invalidArchive()
        var position = strictInteger(state, "attempt_position").toInt();var row = strictInteger(state, "callback_position").toInt()
        if (position !in 0..ids.length() || row !in 0..GatewayEncryptedStore.MAX_LATE_CALLBACKS) invalidArchive()
        if (strictBoolean(state, "complete")) { if (position != ids.length() || row != 0 || !state.isNull("rows_sha256")) invalidArchive();return true }
        var budget = 4
        while (position < ids.length() && budget > 0) {
            val attemptId = ids.getString(position);val callbacks = legacyRows(attemptId);val sourceHash = sha256(retentionCanonical(callbacks))
            if (row > callbacks.length() || (!state.isNull("rows_sha256") && strictString(state, "rows_sha256") != sourceHash)) invalidArchive()
            state.put("rows_sha256", sourceHash)
            if (row == callbacks.length()) { position++;row = 0;state.put("rows_sha256", JSONObject.NULL);continue }
            val callback = gatewayLateCallbackFromJson(callbacks.getJSONObject(row));append(originalAttempt(attemptId), callback)
            row++;budget--
            if (row == callbacks.length()) { position++;row = 0;state.put("rows_sha256", JSONObject.NULL) }
        }
        state.put("attempt_position", position).put("callback_position", row).put("complete", position == ids.length())
        save("late-retention-migration", state)
        if (!archiveJsonEqual(load("late-retention-migration"), state)) invalidArchive()
        return position == ids.length()
    }
    private fun latest(): String? {
        val next = strictString(control(), "next_sequence")
        if (next == ZERO) return null
        val last = BigInteger(next, 16).subtract(BigInteger.ONE).toString(16).padStart(32, '0')
        readWork(last);return last
    }
    private fun readWork(sequence: String): GatewayLateCallbackEvidence {
        val value = index.read("late-work", key(sequence)) ?: throw GatewayStateException("gateway_retention_missing")
        requireKeys(value, setOf("contract_version", "sequence", "evidence_key", "evidence_sha256"))
        if (strictInteger(value, "contract_version") != 5L || strictString(value, "sequence") != sequence) invalidArchive()
        val id = key(strictString(value, "evidence_key"));val evidence = index.read("late-evidence", id) ?: throw GatewayStateException("gateway_retention_missing")
        if (evidenceKey(evidence) != id || strictString(value, "evidence_sha256") != sha256(retentionCanonical(evidence))) throw GatewayStateException("gateway_archive_source_conflict")
        val (attempt, callback) = parseEvidence(evidence)
        return GatewayLateCallbackEvidence(sequence, id, attempt, callback)
    }
    fun page(afterExclusive: String?, limit: Int, ceiling: String? = null): GatewayColdCallbackPage {
        if (limit !in 1..PAGE_LIMIT) invalidArchive()
        afterExclusive?.let(::key);ceiling?.let(::key)
        if (!migrateLegacy()) return GatewayColdCallbackPage(emptyList(), null, true)
        val upper = ceiling ?: latest() ?: return GatewayColdCallbackPage(emptyList(), null)
        if (afterExclusive != null && afterExclusive > upper) invalidArchive()
        val rows = index.page("late-work", afterExclusive, limit, upper).map(::readWork)
        if (rows.isEmpty() && (afterExclusive == null || afterExclusive < upper)) throw GatewayStateException("gateway_retention_missing")
        return GatewayColdCallbackPage(rows, rows.lastOrNull()?.cursorKey?.takeUnless { it == upper })
    }
    fun nextPage(limit: Int): GatewayColdCallbackPage {
        if (limit !in 1..PAGE_LIMIT) invalidArchive()
        if (!migrateLegacy()) return GatewayColdCallbackPage(emptyList(), null, true)
        val last = latest() ?: return GatewayColdCallbackPage(emptyList(), null)
        val state = load("late-retention-reader") ?: JSONObject().put("contract_version", 5).put("after", JSONObject.NULL).put("ceiling", JSONObject.NULL)
        requireKeys(state, setOf("contract_version", "after", "ceiling"))
        if (strictInteger(state, "contract_version") != 5L) invalidArchive()
        val after = if (state.isNull("after")) null else key(strictString(state, "after"))
        val upper = if (state.isNull("ceiling")) last else key(strictString(state, "ceiling"))
        if (upper > last || (after != null && after >= upper) || (after == null && !state.isNull("ceiling")) || (after != null && state.isNull("ceiling"))) invalidArchive()
        val result = page(after, limit, upper)
        val updated = JSONObject().put("contract_version", 5).put("after", result.nextCursor ?: JSONObject.NULL)
            .put("ceiling", if (result.nextCursor == null) JSONObject.NULL else upper)
        save("late-retention-reader", updated) // a crash delays this page until wrap; never grants completion
        if (!archiveJsonEqual(load("late-retention-reader"), updated)) invalidArchive()
        return result
    }
    internal fun evidenceForPayload(payload: JSONObject): String? {
        val id = sha256(retentionCanonical(payload)).take(32);val alias = index.read("late-body", id) ?: return null
        requireKeys(alias, setOf("contract_version", "payload", "evidence_key"))
        if (strictInteger(alias, "contract_version") != 5L || !archiveJsonEqual(alias.getJSONObject("payload"), payload)) throw GatewayStateException("gateway_archive_source_conflict")
        val evidenceKey = key(strictString(alias, "evidence_key"));val (attempt, callback) = readEvidence(evidenceKey) ?: throw GatewayStateException("gateway_retention_missing")
        if (!archiveJsonEqual(gatewayLatePayload(attempt, callback), payload)) invalidArchive()
        return evidenceKey
    }
    internal fun validateRecoveryReader() {
        val upper=latest()
        val state=load("late-retention-reader") ?: return
        requireKeys(state,setOf("contract_version","after","ceiling"))
        if(strictInteger(state,"contract_version")!=5L) invalidArchive()
        val after=if(state.isNull("after"))null else key(strictString(state,"after"))
        val ceiling=if(state.isNull("ceiling"))null else key(strictString(state,"ceiling"))
        if((after==null)!=(ceiling==null) || (after!=null && (upper==null || after>=ceiling!! || ceiling>upper))) invalidArchive()
        if(after!=null) { readWork(after);readWork(ceiling!!) }
    }
    internal fun validateRecoveryRecord(kind: String, id: String) {
        when(kind) {
            "late-evidence" -> readEvidence(id) ?: throw GatewayStateException("gateway_retention_missing")
            "late-work" -> {
                readWork(id)
                // The sequence is advanced only after durable work indexing.
                // A future orphan without its original pending intent cannot
                // be adopted as healthy historical scheduling evidence.
                if(id>=strictString(control(),"next_sequence")) invalidArchive()
            }
            "late-body" -> {
                val value=index.read(kind,key(id)) ?: invalidArchive()
                requireKeys(value,setOf("contract_version","payload","evidence_key"))
                val payload=value.getJSONObject("payload")
                if(sha256(retentionCanonical(payload)).take(32)!=id || evidenceForPayload(payload)!=strictString(value,"evidence_key")) invalidArchive()
            }
            else -> invalidArchive()
        }
    }
    fun bindReceipt(request: GatewayStoredRequest) {
        if (request.action != "callback" || (!isNoticeEnvelope(request.envelope) && !isSuccessorEnvelope(request.envelope) && strictInteger(request.envelope, "contract_version") != 2L)) return
        if (isNoticeEnvelope(request.envelope)) validateNoticeEnvelope(String(java.util.Base64.getDecoder().decode(strictString(request.row, "request_bytes_base64")), Charsets.UTF_8), request.envelope)
        val id = evidenceForPayload(request.envelope.getJSONObject("payload")) ?: return
        index.publish("late-receipt", retentionUuidKey(request.requestId), JSONObject().put("contract_version", 5).put("request_id", request.requestId)
            .put("request_sha256", request.digest).put("evidence_key", id))
    }
    fun receiptBound(request: GatewayStoredRequest): Boolean {
        if (isNoticeEnvelope(request.envelope)) validateNoticeEnvelope(String(java.util.Base64.getDecoder().decode(strictString(request.row, "request_bytes_base64")), Charsets.UTF_8), request.envelope)
        val value = index.read("late-receipt", retentionUuidKey(request.requestId)) ?: return false
        requireKeys(value, setOf("contract_version", "request_id", "request_sha256", "evidence_key"))
        if (strictInteger(value, "contract_version") != 5L || requireUuid(value, "request_id") != request.requestId || strictString(value, "request_sha256") != request.digest ||
            request.action != "callback" || (!isNoticeEnvelope(request.envelope) && !isSuccessorEnvelope(request.envelope) && strictInteger(request.envelope, "contract_version") != 2L) || evidenceForPayload(request.envelope.getJSONObject("payload")) != strictString(value, "evidence_key")) invalidArchive()
        return index.indexed("late-receipt", retentionUuidKey(request.requestId))
    }
}

internal fun gatewayLateCallbackJson(c: GatewayCallback): JSONObject = JSONObject().put("callback_id", c.callbackId).put("device_id", c.deviceId)
    .put("attempt_id", c.attemptId).put("fence", c.fence).put("segment_index", c.segmentIndex).put("nonce", c.nonce).put("kind", c.kind.name)
    .put("result_code", c.resultCode).put("occurred_at", c.occurredAt)
internal fun gatewayLateCallbackFromJson(value: JSONObject): GatewayCallback {
    requireKeys(value, setOf("callback_id", "device_id", "attempt_id", "fence", "segment_index", "nonce", "kind", "result_code", "occurred_at"))
    val kind = try { CallbackKind.valueOf(strictString(value, "kind")) } catch (_: Exception) { invalidArchive() }
    val c = GatewayCallback(requireUuid(value, "callback_id"), requireUuid(value, "device_id"), requireUuid(value, "attempt_id"), strictInteger(value, "fence"),
        strictInteger(value, "segment_index").toInt(), strictString(value, "nonce"), kind, strictInteger(value, "result_code").toInt(), strictString(value, "occurred_at"))
    if (c.fence !in 1..1_000_000_000L || strictInteger(value, "segment_index") !in 0..9 || strictInteger(value, "result_code") !in -1..200 || !c.nonce.matches(Regex("[0-9a-f]{64}"))) invalidArchive()
    strictTimestamp(value, "occurred_at");return c
}
internal fun validateGatewayLateCallback(a: GatewayAttempt, c: GatewayCallback) {
    gatewayLateCallbackFromJson(gatewayLateCallbackJson(c))
    if (c.deviceId != a.deviceId || c.attemptId != a.attemptId || c.fence != a.fence || c.segmentIndex !in a.segments.indices || !sameNonce(c.nonce, a.callbackNonce) ||
        c.callbackId != (if (c.kind == CallbackKind.SENT) a.segments[c.segmentIndex].sentCallbackId else a.segments[c.segmentIndex].deliveryCallbackId) || c.resultCode == -1 ||
        Instant.parse(c.occurredAt) < Instant.parse(a.invocationStartedAt)) invalidArchive()
}
internal fun gatewayLatePayload(a: GatewayAttempt, c: GatewayCallback): JSONObject = JSONObject().put("callback_id", c.callbackId).put("attempt_id", a.attemptId)
    .put("fence_version", a.fence).put("segment_index", c.segmentIndex).put("segment_count", a.segments.size).put("body_sha256", a.bodySha256)
    .put("destination_sha256", a.destinationSha256).put("callback_kind", if (c.kind == CallbackKind.SENT) "sent" else "delivery")
    .put("result_code", c.resultCode).put("tp_status", JSONObject.NULL).put("occurred_at", gatewayWireTime(Instant.parse(c.occurredAt)))
    .also {
        when (val route = a.dispatchRoute) {
            is GatewayDispatchRoute.PrimaryV2 -> Unit
            is GatewayDispatchRoute.ReceiptSuccessorV1 -> it.put("route", successorRouteJson(route))
            is GatewayDispatchRoute.ReceiptNoticeV1 -> it.put("route", noticeRouteJson(route))
        }
    }
