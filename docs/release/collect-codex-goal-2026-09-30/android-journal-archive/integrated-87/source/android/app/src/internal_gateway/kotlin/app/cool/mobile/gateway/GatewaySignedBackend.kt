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

    override fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant? {
        val result = mutation("dispatch_grant", JSONObject())
        requireKeys(result, setOf("ok", "code", "device_id", "request_id", "replay"))
        if (strictBoolean(result, "ok") || strictString(result, "code") != "GATEWAY_DISPATCH_AUTHORITY_PENDING" ||
            strictString(result, "device_id") != deviceId()) throw GatewayStateException("gateway_response_invalid")
        requireUuid(result, "request_id")
        strictBoolean(result, "replay")
        // No arbitrary future object can become a live dispatch grant. A new
        // reviewed business-authority contract is required to enable issuance.
        return null
    }

    override fun reconcile(journal: GatewayJournalState) {
        val requests = store.readRequests().getJSONArray("requests")
        // One bounded manual read per unresolved request, at most four per
        // user action; no mutation replay or automatic resend.
        var checked = 0
        for (index in 0 until requests.length()) {
            val row = requests.getJSONObject(index)
            if (strictString(row, "state") != "outcome_unknown") continue
            if (checked++ >= 4) break
            val target = requireUuid(row, "request_id")
            val readId = UUID.randomUUID().toString()
            val receipt = requestReply("reconcile", JSONObject().put("target_request_id", target), readId)
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
                    validateGatewayResult(strictString(row, "action"), target, deviceId(), original.getJSONObject("payload"), result.getJSONObject("recorded_result"))
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
        for (attempt in journal.attempts) for ((index, segment) in attempt.segments.withIndex()) {
            for (kind in CallbackKind.entries) {
                val callbackId = if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId
                val code = if (kind == CallbackKind.SENT) segment.sentCode else segment.deliveryCode
                val occurred = if (kind == CallbackKind.SENT) segment.sentObservedAt else segment.deliveryObservedAt
                if (code == null || occurred == null || hasCallbackRequest(callbackId)) continue
                if (checked++ >= 4) return
                if (code !in -1..200) throw GatewayStateException("gateway_callback_result_unsupported")
                val payload = JSONObject().put("callback_id", callbackId).put("attempt_id", attempt.attemptId)
                    .put("fence_version", attempt.fence).put("segment_index", index).put("segment_count", attempt.segments.size)
                    .put("body_sha256", attempt.bodySha256).put("destination_sha256", attempt.destinationSha256)
                    .put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery")
                    .put("result_code", code).put("tp_status", JSONObject.NULL).put("occurred_at", gatewayWireTime(Instant.parse(occurred)))
                val result = mutation("callback", payload, callbackId)
                requireKeys(result, setOf("callback_id", "recorded_at", "replay", "carrier_proof"))
                if (requireUuid(result, "callback_id") != callbackId || strictBoolean(result, "carrier_proof")) throw GatewayStateException("gateway_response_invalid")
                strictBoolean(result, "replay")
                strictTimestamp(result, "recorded_at")
            }
        }
    }

    private fun hasCallbackRequest(id: String): Boolean {
        val rows = store.readRequests().getJSONArray("requests")
        return (0 until rows.length()).any { rows.getJSONObject(it).optString("callback_id") == id }
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

    private fun envelope(action: String, payload: JSONObject, id: String): ByteArray = JSONObject()
        .put("contract_version", 1).put("action", action).put("device_id", deviceId()).put("request_id", id)
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
