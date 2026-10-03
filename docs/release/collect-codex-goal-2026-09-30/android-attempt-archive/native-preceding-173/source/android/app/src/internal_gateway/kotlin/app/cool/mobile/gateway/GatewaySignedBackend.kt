package app.cool.mobile.gateway

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.UUID

/** Exact-host, redirect-free, bounded device-key transport. No user JWT,
 * service key, arbitrary RPC, caller-provided grant, body or recipient. */
internal class GatewaySignedBackend(
    private val context: Context,
    private val store: GatewayEncryptedStore,
    private val identity: GatewayDeviceIdentity,
    // Offline dependency seams; production uses the enrolled Keystore identity
    // and the fixed-host transport. No runtime endpoint/key/response setting.
    private val fingerprint: () -> String = identity::keyId,
    private val transport: GatewayHttpsTransport = GatewayHttpsTransport(identity::keyId, identity::signExact),
) : GatewayBackend {
    companion object {
        const val HOST = GatewayHttpsTransport.HOST
    }

    private fun deviceId(): String {
        val record = store.readEnrollment() ?: throw GatewayStateException("gateway_not_enrolled")
        val id = strictString(record, "device_id")
        if (!validUuid(id) || strictString(record, "key_sha256") != fingerprint()) throw GatewayStateException("gateway_enrollment_invalid")
        return id
    }

    fun configured(): Boolean {
        val resource = context.resources.getIdentifier("collect_gateway_backend_host", "string", context.packageName)
        return resource != 0 && context.getString(resource) == HOST && store.readEnrollment() != null
    }

    override fun heartbeat(observations: GatewayObservations): GatewayAuthority {
        val now = Instant.now()
        val payload = JSONObject().put("sms_permission", observations.sendSmsPermission)
            .put("network", when { observations.networkValidated -> "validated"; observations.networkConnected -> "unvalidated"; else -> "offline" })
            .put("telephony", when { !observations.readPhoneStatePermission -> "unknown"; observations.simReady && observations.telephonyInService -> "ready"; else -> "unavailable" })
            .put("sim_selected", observations.subscriptionUnambiguous)
            .put("sim_revision_sha256", if (observations.subscriptionUnambiguous && observations.subscriptionId != null)
                sha256("android-subscription-selection:${observations.subscriptionId}") else JSONObject.NULL)
            .put("local_pause", GatewayJournal(store).read().emergencyPaused).put("reported_at", gatewayWireTime(now))
        val result = mutation("heartbeat", payload)
        requireKeys(result, setOf("observation_id", "ingested_at", "replay", "carrier_proof"))
        requireUuid(result, "observation_id")
        strictBoolean(result, "replay")
        if (strictBoolean(result, "carrier_proof")) throw GatewayStateException("gateway_response_invalid")
        val checked = strictTimestamp(result, "ingested_at")
        // Recorded health does not establish owner activation or dispatch
        // permission. The initial backend intentionally issues no authority.
        return GatewayAuthority(deviceId(), GatewayEnrollmentState.UNKNOWN, false, checked)
    }

    override fun supportsPolicyDispatch(): Boolean = true

    private val leases = LinkedHashMap<String, GatewayDispatchLease>()
    private var reconciliationOffset = 0
    // Scheduling metadata only. This position never grants authority, deletes
    // unknown evidence or changes any original request identity.
    fun restoreReconciliationOffset(value: Int) { reconciliationOffset = value.coerceIn(0, GatewayEncryptedStore.MAX_REQUESTS - 1) }
    fun reconciliationOffset(): Int = reconciliationOffset

    override fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant? {
        val receipt = mutationV2("dispatch_grant", JSONObject())
        val lease = parseGatewayDispatchGrantV2(requireUuid(receipt, "request_id"), deviceId(), receipt.getJSONObject("result"), Instant.now()) ?: return null
        if (!observations.ready() || observations.subscriptionId == null ||
            lease.simRevisionSha256 != sha256("android-subscription-selection:${observations.subscriptionId}")) {
            throw GatewayStateException("gateway_grant_sim_mismatch")
        }
        synchronized(GatewayJournal.PROCESS_LOCK) {
            if (leases.size >= GatewayEncryptedStore.MAX_REQUESTS) throw GatewayStateException("gateway_grant_memory_limit")
            leases[lease.grant.attemptId] = lease
        }
        return lease.grant
    }

    override fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck? {
        val lease = synchronized(GatewayJournal.PROCESS_LOCK) { leases.remove(grant.attemptId) }
            ?: throw GatewayStateException("gateway_grant_unavailable")
        if (lease.grant != grant || reservation.deviceId != grant.deviceId || reservation.attemptId != grant.attemptId ||
            reservation.jobId != grant.jobId || reservation.fence != grant.fence ||
            reservation.bodySha256 != grant.bodySha256 || reservation.destinationSha256 != grant.destinationSha256 ||
            reservation.segments.size != grant.segmentCount || store.read().attempts.none { it == reservation }) {
            throw GatewayStateException("gateway_reservation_binding_invalid")
        }
        val plan = JSONArray(reservation.segments.mapIndexed { index, part -> JSONObject()
            .put("segment_index", index).put("sent_callback_id", part.sentCallbackId).put("delivery_callback_id", part.deliveryCallbackId) })
        val payload = JSONObject().put("attempt_id", grant.attemptId).put("fence_version", grant.fence)
            .put("body_sha256", grant.bodySha256).put("destination_sha256", grant.destinationSha256)
            .put("reservation_sha256", gatewayReservationDigest(reservation)).put("callbacks", plan)
        val reply = mutationV2("arm_dispatch", payload, grantExpiry = grant.expiresAt)
        return parseGatewayDispatchArmV2(requireUuid(reply, "request_id"), deviceId(), payload,
            reply.getJSONObject("result"), grant.expiresAt, Instant.now())
    }

    private fun mutationV2(action: String, payload: JSONObject, callbackId: String? = null, grantExpiry: Instant? = null): JSONObject {
        if (!configured()) throw GatewayStateException("gateway_not_configured")
        val id = UUID.randomUUID().toString()
        val bytes = envelope(action, payload, id, 2)
        synchronized(GatewayJournal.PROCESS_LOCK) {
            val rows = store.readRequests().getJSONArray("requests")
            if (rows.length() >= GatewayEncryptedStore.MAX_REQUESTS) throw GatewayStateException("gateway_request_journal_limit")
            rows.put(JSONObject().put("request_id", id).put("action", action).put("state", "outcome_unknown")
                .put("callback_id", callbackId ?: JSONObject.NULL).put("request_sha256", sha256(String(bytes, Charsets.UTF_8)))
                .put("request_bytes_base64", Base64.encodeToString(bytes, Base64.NO_WRAP)))
            store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        }
        val reply = transmitReplyV2(action, id, bytes, grantExpiry)
        // A valid response does not clear the original request. Redacted manual
        // reconciliation can archive grant/arm receipts later, without replay.
        synchronized(GatewayJournal.PROCESS_LOCK) {
            val rows = store.readRequests().getJSONArray("requests")
            for (index in 0 until rows.length()) if (rows.getJSONObject(index).getString("request_id") == id) rows.getJSONObject(index).put("state", "recorded")
            store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        }
        return reply
    }

    private fun transmitReplyV2(action: String, id: String, bytes: ByteArray, expiry: Instant? = null): JSONObject {
        if (!configured() || bytes.size > 8 * 1024) throw GatewayStateException("gateway_not_configured")
        val body = transport.postExact(bytes)
        try { return parseGatewayDispatchReplyV2(action, id, deviceId(), JSONObject(String(bytes, Charsets.UTF_8)).getJSONObject("payload"), body, Instant.now(), expiry) }
        catch (_: Exception) { throw GatewayStateException("gateway_http_outcome_unknown") }
    }

    private fun attemptUsesV2(id: String): Boolean {
        val active = store.readRequests().getJSONArray("requests")
        val archive = store.readArchive().getJSONArray("requests")
        val rows = (0 until active.length()).map { active.getJSONObject(it) } +
            (0 until archive.length()).map { archive.getJSONObject(it).getJSONObject("request") }
        return rows.any { row -> val request = GatewayStoredRequest.parse(row)
            request.action == "arm_dispatch" && strictInteger(request.envelope, "contract_version") == 2L &&
                requireUuid(request.envelope.getJSONObject("payload"), "attempt_id") == id }
    }

    override fun reconcile(journal: GatewayJournalState) {
        val requests = store.readRequests().getJSONArray("requests")
        // Reserve half of this four-call batch for new callback evidence so
        // permanently unknown requests cannot starve multipart uploads.
        // Original requests are read only, never replayed.
        var checked = 0
        val length = requests.length()
        val start = reconciliationOffset % maxOf(1, length)
        var visited = 0
        while (visited < length && checked < 2) {
            val index = (start + visited++) % length
            val row = requests.getJSONObject(index)
            val stored = GatewayStoredRequest.parse(row)
            val v2 = strictInteger(stored.envelope, "contract_version") == 2L
            val archive = strictInteger(stored.envelope, "contract_version") == 3L
            if (strictString(row, "state") != "outcome_unknown" && !(v2 && stored.action != "callback")) continue
            checked++
            reconciliationOffset = (index + 1) % length
            val target = requireUuid(row, "request_id")
            val readId = UUID.randomUUID().toString()
            val readPayload = JSONObject().put("target_request_id", target)
            if (archive) {
                val receipt = transmitArchive("archive_lookup", readId, readPayload)
                val result = receipt.getJSONObject("result")
                if (strictString(result, "outcome") == "recorded") {
                    val ack = result.getJSONObject("recorded_result")
                    validateGatewayArchiveAck(ack, target, deviceId(), stored.envelope.getJSONObject("payload"))
                    if (strictBoolean(ack, "ok")) GatewayAttemptArchive(store).acknowledge(stored, ack)
                    else markArchiveRefused(target)
                }
                continue // unknown/refused never replays a mutation or authorizes compaction
            }
            val receipt = if (v2) transmitReplyV2("reconcile", readId, envelope("reconcile", readPayload, readId, 2))
                else requestReply("reconcile", readPayload, readId)
            val result = receipt.getJSONObject("result")
            requireKeys(result, setOf("target_request_id", "outcome", "recorded_action", "recorded_result"))
            if (strictString(result, "target_request_id") != target) throw GatewayStateException("gateway_response_invalid")
            when (strictString(result, "outcome")) {
                "unknown" -> if (!result.isNull("recorded_action") || !result.isNull("recorded_result")) throw GatewayStateException("gateway_response_invalid")
                "recorded" -> {
                    if (strictString(result, "recorded_action") != strictString(row, "action") || result.opt("recorded_result") !is JSONObject) {
                        throw GatewayStateException("gateway_response_invalid")
                    }
                    val bytes = Base64.decode(strictString(row, "request_bytes_base64"), Base64.NO_WRAP)
                    if (bytes.size > 32 * 1024 || sha256(String(bytes, Charsets.UTF_8)) != strictString(row, "request_sha256")) {
                        throw GatewayStateException("gateway_request_journal_invalid")
                    }
                    val original = JSONObject(String(bytes, Charsets.UTF_8))
                    if (requireUuid(original, "request_id") != target || requireUuid(original, "device_id") != deviceId() ||
                        strictString(original, "action") != strictString(row, "action")) throw GatewayStateException("gateway_request_journal_invalid")
                    if (v2) validateGatewayDispatchResultV2(strictString(row, "action"), target, deviceId(), original.getJSONObject("payload"), result.getJSONObject("recorded_result"), Instant.now())
                    else validateGatewayResult(strictString(row, "action"), target, deviceId(), original.getJSONObject("payload"), result.getJSONObject("recorded_result"))
                    if (strictString(row, "action") != "callback") {
                        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.reconciled(GatewayStoredRequest.parse(row), readId, receipt))
                    } else {
                        // Re-read after every archive commit; a stale batch must
                        // not reintroduce a heartbeat UUID already compacted.
                        val latest = store.readRequests().getJSONArray("requests")
                        for (position in 0 until latest.length()) {
                            if (latest.getJSONObject(position).getString("request_id") == target) latest.getJSONObject(position).put("state", "recorded")
                        }
                        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", latest))
                    }
                }
                else -> throw GatewayStateException("gateway_response_invalid")
            }
        }
        // Upload each observed callback only once. Uncertain HTTP writes stay
        // in the request journal and are reconciled by their original UUID.
        var uploaded = 0
        for (attempt in journal.attempts) for ((index, segment) in attempt.segments.withIndex()) {
            for (kind in CallbackKind.entries) {
                val callbackId = if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId
                val code = if (kind == CallbackKind.SENT) segment.sentCode else segment.deliveryCode
                val occurred = if (kind == CallbackKind.SENT) segment.sentObservedAt else segment.deliveryObservedAt
                if (code == null || occurred == null) continue
                if (code !in -1..200) throw GatewayStateException("gateway_callback_result_unsupported")
                val payload = JSONObject().put("callback_id", callbackId).put("attempt_id", attempt.attemptId)
                    .put("fence_version", attempt.fence).put("segment_index", index).put("segment_count", attempt.segments.size)
                    .put("body_sha256", attempt.bodySha256).put("destination_sha256", attempt.destinationSha256)
                    .put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery")
                    .put("result_code", code).put("tp_status", JSONObject.NULL).put("occurred_at", gatewayWireTime(Instant.parse(occurred)))
                val v2 = attemptUsesV2(attempt.attemptId)
                if (hasCallbackRequest(callbackId, payload, v2)) continue
                if (uploaded++ >= 2) return
                val result = if (v2) mutationV2("callback", payload, callbackId).getJSONObject("result") else mutation("callback", payload, callbackId)
                if (!v2) requireKeys(result, setOf("callback_id", "recorded_at", "replay", "carrier_proof"))
                if (requireUuid(result, "callback_id") != callbackId || strictBoolean(result, "carrier_proof")) throw GatewayStateException("gateway_response_invalid")
                strictBoolean(result, "replay")
                strictTimestamp(result, "recorded_at")
            }
        }
        // Cold conflicts keep the local gate closed. Reconciliation uploads raw
        // evidence once and then uses its original request UUID on uncertainty.
        for ((attempt, callback) in store.coldPendingCallbacks()) {
            val p = JSONObject().put("callback_id", callback.callbackId).put("attempt_id", attempt.attemptId)
                .put("fence_version", attempt.fence).put("segment_index", callback.segmentIndex).put("segment_count", attempt.segments.size)
                .put("body_sha256", attempt.bodySha256).put("destination_sha256", attempt.destinationSha256)
                .put("callback_kind", if (callback.kind == CallbackKind.SENT) "sent" else "delivery")
                .put("result_code", callback.resultCode).put("tp_status", JSONObject.NULL).put("occurred_at", gatewayWireTime(Instant.parse(callback.occurredAt)))
            if (hasCallbackRequest(callback.callbackId, p, true)) continue
            if (uploaded++ >= 2) return
            mutationV2("callback", p, callback.callbackId)
        }
        archiveOneKnownAttempt()
    }

    private fun transmitArchive(action: String, id: String, payload: JSONObject, bytes: ByteArray = envelope(action, payload, id, 3)): JSONObject {
        if (!configured() || bytes.size > 8 * 1024) throw GatewayStateException("gateway_not_configured")
        val body = transport.postExact(bytes)
        try { return parseGatewayArchiveReply(action, id, deviceId(), payload, body) }
        catch (_: Exception) { throw GatewayStateException("gateway_http_outcome_unknown") }
    }

    private fun archiveOneKnownAttempt() {
        val candidates = store.read().attempts.filter { it.outcome() == AttemptOutcome.DELIVERY_CALLBACK_OBSERVED && attemptUsesV2(it.attemptId) }
        for (attempt in candidates) {
            val rows = store.readRequests().getJSONArray("requests")
            if ((0 until rows.length()).any { val r = GatewayStoredRequest.parse(rows.getJSONObject(it));r.action == "archive_attempt" && requireUuid(r.envelope.getJSONObject("payload"), "attempt_id") == attempt.attemptId }) continue
            val payload = try { GatewayAttemptArchive(store).payload(attempt) } catch (e: GatewayStateException) {
                if (e.reasonCode == "gateway_archive_acknowledgement_pending") continue else throw e
            }
            val id = UUID.randomUUID().toString();val bytes = envelope("archive_attempt", payload, id, 3)
            synchronized(GatewayJournal.PROCESS_LOCK) {
                val latest = store.readRequests().getJSONArray("requests")
                if (latest.length() >= GatewayEncryptedStore.MAX_REQUESTS) throw GatewayStateException("gateway_request_journal_limit")
                latest.put(JSONObject().put("request_id", id).put("action", "archive_attempt").put("state", "outcome_unknown").put("callback_id", JSONObject.NULL)
                    .put("request_sha256", sha256(String(bytes, Charsets.UTF_8))).put("request_bytes_base64", Base64.encodeToString(bytes, Base64.NO_WRAP)))
                store.saveRequests(JSONObject().put("contract_version", 1).put("requests", latest))
            }
            val reply = transmitArchive("archive_attempt", id, payload, bytes)
            if (strictBoolean(reply.getJSONObject("result"), "ok")) {
                synchronized(GatewayJournal.PROCESS_LOCK) {
                    val latest = store.readRequests().getJSONArray("requests")
                    val original = (0 until latest.length()).map { GatewayStoredRequest.parse(latest.getJSONObject(it)) }.single { it.requestId == id }
                    GatewayAttemptArchive(store).acknowledge(original, reply.getJSONObject("result"))
                }
            } else markArchiveRefused(id)
            return // at most one new maintenance mutation in a cycle
        }
    }

    private fun markArchiveRefused(id: String) = synchronized(GatewayJournal.PROCESS_LOCK) {
        val rows = store.readRequests().getJSONArray("requests")
        for (i in 0 until rows.length()) if (rows.getJSONObject(i).getString("request_id") == id) rows.getJSONObject(i).put("state", "recorded")
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
    }

    private fun hasCallbackRequest(id: String, payload: JSONObject, v2: Boolean): Boolean {
        val rows = store.readRequests().getJSONArray("requests")
        return (0 until rows.length()).any {
            val row = rows.getJSONObject(it)
            row.optString("callback_id") == id && (!v2 || archiveJsonEqual(GatewayStoredRequest.parse(row).envelope.getJSONObject("payload"), payload))
        }
    }

    private fun mutation(action: String, payload: JSONObject, callbackId: String? = null): JSONObject {
        if (!configured()) throw GatewayStateException("gateway_not_configured")
        val id = UUID.randomUUID().toString()
        val bytes = envelope(action, payload, id)
        synchronized(GatewayJournal.PROCESS_LOCK) {
            val rows = store.readRequests().getJSONArray("requests")
            if (rows.length() >= GatewayEncryptedStore.MAX_REQUESTS) throw GatewayStateException("gateway_request_journal_limit")
            rows.put(JSONObject().put("request_id", id).put("action", action).put("state", "outcome_unknown")
                .put("callback_id", callbackId ?: JSONObject.NULL).put("request_sha256", sha256(String(bytes, Charsets.UTF_8)))
                .put("request_bytes_base64", Base64.encodeToString(bytes, Base64.NO_WRAP)))
            // Durable request identity is recorded before any network write.
            store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        }
        val receipt = transmitReply(action, id, bytes)
        val result = receipt.getJSONObject("result")
        if (action != "callback") {
            synchronized(GatewayJournal.PROCESS_LOCK) {
                val rows = store.readRequests().getJSONArray("requests")
                val source = (0 until rows.length()).map { rows.getJSONObject(it) }.firstOrNull { it.getString("request_id") == id }
                    ?: throw GatewayStateException("gateway_archive_request_missing")
                // Preserve the original unknown reservation until an exact
                // authenticated receipt is durably archived. Archive failure
                // remains recoverable by the original UUID; no network retry.
                GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(source), receipt))
            }
            return result
        }
        // HTTP success alone cannot authorize a send. This records a transport
        // receipt; each action still strictly validates its result contract.
        synchronized(GatewayJournal.PROCESS_LOCK) {
            val rows = store.readRequests().getJSONArray("requests")
            for (index in 0 until rows.length()) {
                val row = rows.getJSONObject(index)
                if (row.getString("request_id") == id) row.put("state", "recorded")
            }
            store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        }
        return result
    }

    private fun requestReply(action: String, payload: JSONObject, id: String): JSONObject = transmitReply(action, id, envelope(action, payload, id))

    private fun envelope(action: String, payload: JSONObject, id: String, version: Int = 1): ByteArray = JSONObject()
        .put("contract_version", version).put("action", action).put("device_id", deviceId()).put("request_id", id)
        .put("issued_at", gatewayWireTime(Instant.now())).put("payload", payload).toString().toByteArray(Charsets.UTF_8)

    private fun transmitReply(action: String, id: String, bytes: ByteArray): JSONObject {
        if (!configured() || bytes.size > 32 * 1024) throw GatewayStateException("gateway_not_configured")
        val body = transport.postExact(bytes)
        try {
            val text = String(body, Charsets.UTF_8)
            if (!body.contentEquals(text.toByteArray(Charsets.UTF_8))) throw GatewayStateException("gateway_response_invalid")
            val reply = JSONObject(text)
            requireKeys(reply, setOf("contract_version", "action", "device_id", "request_id", "result"))
            if (reply.get("contract_version") != 1 || strictString(reply, "action") != action ||
                strictString(reply, "device_id") != deviceId() || strictString(reply, "request_id") != id ||
                reply.get("result") !is JSONObject) throw GatewayStateException("gateway_response_invalid")
            validateGatewayResult(action, id, deviceId(), JSONObject(String(bytes, Charsets.UTF_8)).getJSONObject("payload"), reply.getJSONObject("result"))
            return reply
        } catch (_: Exception) {
            // A malformed successful mutation is still uncertain. Its durable
            // original request UUID remains available for read reconciliation.
            throw GatewayStateException("gateway_http_outcome_unknown")
        }
    }

}
