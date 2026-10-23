package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.util.Locale

/** Parsed only after fixed-host authenticated transport. Parsing is not a
 * radio invocation, durable-reservation attestation or delivery conclusion. */
internal data class GatewayDispatchLease(
    val grant: GatewayDispatchGrant,
    val requestId: String,
    val runId: String,
    val policyRevision: Long,
    val simRevisionSha256: String,
    val issuedAt: Instant,
)

internal data class GatewayDispatchArmAck(
    val attemptId: String,
    val fence: Long,
    val reservationSha256: String,
    val armedAt: Instant,
    val expiresAt: Instant,
    val dispatchRoute: GatewayDispatchRoute? = null,
)

private val dispatchActions = setOf("dispatch_grant", "arm_dispatch", "callback", "reconcile", "attempt_status")
private val dispatchRefusals = setOf("OPERATIONS_PAUSED", "NO_CURRENT_RUN", "DEVICE_NOT_READY",
    "NO_ELIGIBLE_RECEIPT", "QUOTA_EXHAUSTED", "ORIGINAL_REQUEST_RECORDED")
private val dispatchHash = Regex("[0-9a-f]{64}")

private fun invalidDispatch(): Nothing = throw GatewayStateException("gateway_response_invalid")

private inline fun <T> dispatchValidation(block: () -> T): T = try {
    block()
} catch (error: GatewayStateException) {
    throw error
} catch (_: Exception) {
    invalidDispatch()
}

private fun dispatchUuid(value: String): String = value.lowercase(Locale.ROOT).also {
    if (!validUuid(it)) invalidDispatch()
}
private fun dispatchUuid(row: JSONObject, name: String): String = dispatchUuid(strictString(row, name))
private fun dispatchHash(row: JSONObject, name: String): String = strictString(row, name).also {
    if (!dispatchHash.matches(it)) invalidDispatch()
}
private fun dispatchInteger(row: JSONObject, name: String, min: Long, max: Long): Long = strictInteger(row, name).also {
    if (it !in min..max) invalidDispatch()
}
private fun dispatchTime(row: JSONObject, name: String): Instant = strictTimestamp(row, name).also {
    // ISO_INSTANT accepts 24:00 and leap-second normalization; the Edge wire
    // requires the supplied calendar and clock fields themselves to be valid.
    if (it.toString().take(19) != strictString(row, name).take(19)) invalidDispatch()
}
private fun dispatchDeadline(start: Instant, expiry: Instant, now: Instant, grantExpiry: Instant? = null) {
    if (expiry <= start || expiry > start.plusSeconds(30) || expiry <= now ||
        (grantExpiry != null && expiry > grantExpiry)) invalidDispatch()
}

private fun exactDispatchRefusal(id: String, deviceId: String, result: JSONObject): Boolean {
    if (strictBoolean(result, "ok")) return false
    requireKeys(result, setOf("ok", "code", "device_id", "request_id", "replay"))
    if (strictString(result, "code") !in dispatchRefusals || dispatchUuid(result, "device_id") != dispatchUuid(deviceId) ||
        dispatchUuid(result, "request_id") != dispatchUuid(id)) invalidDispatch()
    strictBoolean(result, "replay")
    return true
}

internal fun parseGatewayDispatchGrantV2(id: String, deviceId: String, result: JSONObject, now: Instant): GatewayDispatchLease? = dispatchValidation {
    if (exactDispatchRefusal(id, deviceId, result)) return@dispatchValidation null
    requireKeys(result, setOf("ok", "code", "device_id", "request_id", "attempt_id", "receipt_id", "run_id",
        "fence_version", "policy_revision", "issued_at", "expires_at", "segment_count", "body", "destination_e164",
        "body_sha256", "destination_sha256", "sim_revision_sha256", "replay"))
    if (strictString(result, "code") != "DISPATCH_GRANTED" || strictBoolean(result, "replay") ||
        dispatchUuid(result, "device_id") != dispatchUuid(deviceId) || dispatchUuid(result, "request_id") != dispatchUuid(id)) invalidDispatch()
    val issued = dispatchTime(result, "issued_at")
    val expiry = dispatchTime(result, "expires_at")
    dispatchDeadline(issued, expiry, now)
    val body = strictString(result, "body")
    val destination = strictString(result, "destination_e164")
    val bodyHash = dispatchHash(result, "body_sha256")
    val destinationHash = dispatchHash(result, "destination_sha256")
    if (sha256(body) != bodyHash || sha256(destination) != destinationHash) invalidDispatch()
    val grant = GatewayDispatchGrant(dispatchUuid(result, "device_id"), dispatchUuid(result, "receipt_id"),
        dispatchUuid(result, "attempt_id"), dispatchInteger(result, "fence_version", 1, 1_000_000_000L), destination,
        destinationHash, body, bodyHash, expiry, dispatchInteger(result, "segment_count", 1, 10).toInt())
    // Retain the existing native body/radio safety contract as an additional
    // boundary; the selected service template already satisfies those bounds.
    grant.validate(now, GatewayAuthority(dispatchUuid(deviceId), GatewayEnrollmentState.ACTIVE, true, now))
    GatewayDispatchLease(grant, dispatchUuid(id), dispatchUuid(result, "run_id"),
        dispatchInteger(result, "policy_revision", 1, 1_000_000_000L), dispatchHash(result, "sim_revision_sha256"), issued)
}

private fun validateArmPayload(id: String, payload: JSONObject) {
    requireKeys(payload, setOf("attempt_id", "fence_version", "body_sha256", "destination_sha256", "callbacks", "reservation_sha256"))
    val attempt = dispatchUuid(payload, "attempt_id")
    dispatchInteger(payload, "fence_version", 1, 1_000_000_000L)
    dispatchHash(payload, "body_sha256")
    dispatchHash(payload, "destination_sha256")
    dispatchHash(payload, "reservation_sha256")
    val callbacks = payload.get("callbacks") as? JSONArray ?: invalidDispatch()
    if (callbacks.length() !in 1..10) invalidDispatch()
    val seen = mutableSetOf<String>()
    for (index in 0 until callbacks.length()) {
        val row = callbacks.get(index) as? JSONObject ?: invalidDispatch()
        requireKeys(row, setOf("segment_index", "sent_callback_id", "delivery_callback_id"))
        if (dispatchInteger(row, "segment_index", 0, 9) != index.toLong()) invalidDispatch()
        for (name in listOf("sent_callback_id", "delivery_callback_id")) {
            val callback = dispatchUuid(row, name)
            if (!seen.add(callback) || callback == dispatchUuid(id) || callback == attempt) invalidDispatch()
        }
    }
}

internal fun parseGatewayDispatchArmV2(id: String, deviceId: String, payload: JSONObject, result: JSONObject,
    grantExpiresAt: Instant, now: Instant): GatewayDispatchArmAck? = dispatchValidation {
    validateArmPayload(id, payload)
    if (exactDispatchRefusal(id, deviceId, result)) return@dispatchValidation null
    requireKeys(result, setOf("ok", "code", "device_id", "request_id", "attempt_id", "fence_version",
        "reservation_sha256", "armed_at", "expires_at", "replay", "carrier_proof"))
    if (strictString(result, "code") != "DISPATCH_ARMED" || strictBoolean(result, "replay") || strictBoolean(result, "carrier_proof") ||
        dispatchUuid(result, "device_id") != dispatchUuid(deviceId) || dispatchUuid(result, "request_id") != dispatchUuid(id) ||
        dispatchUuid(result, "attempt_id") != dispatchUuid(payload, "attempt_id") ||
        dispatchInteger(result, "fence_version", 1, 1_000_000_000L) != dispatchInteger(payload, "fence_version", 1, 1_000_000_000L) ||
        dispatchHash(result, "reservation_sha256") != dispatchHash(payload, "reservation_sha256")) invalidDispatch()
    val armed = dispatchTime(result, "armed_at")
    val expiry = dispatchTime(result, "expires_at")
    dispatchDeadline(armed, expiry, now, grantExpiresAt)
    GatewayDispatchArmAck(dispatchUuid(result, "attempt_id"), strictInteger(result, "fence_version"),
        dispatchHash(result, "reservation_sha256"), armed, expiry)
}

private fun validateObservationCounts(result: JSONObject, segmentCount: Long? = null) {
    val count = segmentCount ?: 10L
    val sent = dispatchInteger(result, "sent_observations", 0, count)
    dispatchInteger(result, "delivery_observations", 0, count)
    val conflicting = strictBoolean(result, "conflicting_observations")
    if (strictBoolean(result, "carrier_proof") || (strictString(result, "state") == "observed_sent" &&
        (conflicting || sent == 0L || (segmentCount != null && sent != count)))) invalidDispatch()
}

private fun validateCallbackPayload(payload: JSONObject): Long {
    requireKeys(payload, setOf("callback_id", "attempt_id", "fence_version", "segment_index", "segment_count", "body_sha256",
        "destination_sha256", "callback_kind", "result_code", "tp_status", "occurred_at"))
    dispatchUuid(payload, "callback_id")
    dispatchUuid(payload, "attempt_id")
    dispatchInteger(payload, "fence_version", 1, 1_000_000_000L)
    val count = dispatchInteger(payload, "segment_count", 1, 10)
    dispatchInteger(payload, "segment_index", 0, count - 1)
    dispatchHash(payload, "body_sha256")
    dispatchHash(payload, "destination_sha256")
    if (strictString(payload, "callback_kind") !in setOf("sent", "delivery")) invalidDispatch()
    dispatchInteger(payload, "result_code", -1, 200)
    if (!payload.isNull("tp_status")) dispatchInteger(payload, "tp_status", 0, 255)
    dispatchTime(payload, "occurred_at")
    return count
}

private fun validateCallbackResult(payload: JSONObject?, result: JSONObject) {
    requireKeys(result, setOf("callback_id", "recorded_at", "replay", "carrier_proof", "state", "sent_observations",
        "delivery_observations", "conflicting_observations"))
    if (payload != null && dispatchUuid(result, "callback_id") != dispatchUuid(payload, "callback_id")) invalidDispatch()
    dispatchUuid(result, "callback_id")
    dispatchTime(result, "recorded_at")
    strictBoolean(result, "replay")
    if (strictString(result, "state") !in setOf("send_started", "observed_sent", "uncertain")) invalidDispatch()
    validateObservationCounts(result, payload?.let(::validateCallbackPayload))
}

private fun validateAttemptStatusResult(payload: JSONObject?, result: JSONObject) {
    requireKeys(result, setOf("attempt_id", "fence_version", "state", "armed_at", "sent_observations", "delivery_observations",
        "conflicting_observations", "terminal_archive_ack", "carrier_proof", "segment_count"))
    dispatchUuid(result, "attempt_id")
    dispatchInteger(result, "fence_version", 1, 1_000_000_000L)
    if (payload != null) {
        requireKeys(payload, setOf("attempt_id", "fence_version"))
        if (dispatchUuid(result, "attempt_id") != dispatchUuid(payload, "attempt_id") ||
            strictInteger(result, "fence_version") != dispatchInteger(payload, "fence_version", 1, 1_000_000_000L)) invalidDispatch()
    }
    if (strictString(result, "state") !in setOf("granted", "send_started", "observed_sent", "uncertain") ||
        strictBoolean(result, "terminal_archive_ack")) invalidDispatch()
    if (!result.isNull("armed_at")) dispatchTime(result, "armed_at")
    validateObservationCounts(result, dispatchInteger(result, "segment_count", 1, 10))
}

internal fun validateGatewayDispatchResultV2(action: String, id: String, deviceId: String, payload: JSONObject,
    result: JSONObject, now: Instant, grantExpiresAt: Instant? = null): Unit = dispatchValidation {
    if (action !in dispatchActions) invalidDispatch()
    dispatchUuid(id)
    dispatchUuid(deviceId)
    when (action) {
        "dispatch_grant" -> {
            requireKeys(payload, emptySet())
            parseGatewayDispatchGrantV2(id, deviceId, result, now)
        }
        "arm_dispatch" -> {
            validateArmPayload(id, payload)
            if (!exactDispatchRefusal(id, deviceId, result)) {
                parseGatewayDispatchArmV2(id, deviceId, payload, result, grantExpiresAt ?: invalidDispatch(), now)
            }
        }
        "callback" -> {
            validateCallbackPayload(payload)
            if (dispatchUuid(payload, "callback_id") == dispatchUuid(id)) invalidDispatch()
            validateCallbackResult(payload, result)
        }
        "attempt_status" -> validateAttemptStatusResult(payload, result)
        "reconcile" -> {
            requireKeys(payload, setOf("target_request_id"))
            val target = dispatchUuid(payload, "target_request_id")
            requireKeys(result, setOf("target_request_id", "outcome", "recorded_action", "recorded_result"))
            if (dispatchUuid(result, "target_request_id") != target) invalidDispatch()
            when (strictString(result, "outcome")) {
                "unknown" -> if (!result.isNull("recorded_action") || !result.isNull("recorded_result")) invalidDispatch()
                "recorded" -> {
                    val recorded = result.get("recorded_result") as? JSONObject ?: invalidDispatch()
                    when (strictString(result, "recorded_action")) {
                        "dispatch_grant", "arm_dispatch" -> {
                            // Reconciliation never reconstructs reusable content or a
                            // permit, including an unexpired original arm response.
                            if (!exactDispatchRefusal(target, deviceId, recorded) || strictString(recorded, "code") != "ORIGINAL_REQUEST_RECORDED" ||
                                !strictBoolean(recorded, "replay")) invalidDispatch()
                        }
                        "callback" -> validateCallbackResult(null, recorded)
                        "attempt_status" -> validateAttemptStatusResult(null, recorded)
                        else -> invalidDispatch()
                    }
                }
                else -> invalidDispatch()
            }
        }
    }
    Unit
}

/** Exact bounded response parser. It is used only by the authenticated
 * fixed-host backend; an untrusted Dart/operator JSON object grants nothing. */
internal fun parseGatewayDispatchReplyV2(action: String, id: String, deviceId: String, payload: JSONObject,
    bytes: ByteArray, now: Instant, grantExpiresAt: Instant? = null): JSONObject = dispatchValidation {
    if (bytes.isEmpty() || bytes.size > 8192 || (bytes.size >= 3 && bytes[0] == 0xef.toByte() &&
        bytes[1] == 0xbb.toByte() && bytes[2] == 0xbf.toByte())) invalidDispatch()
    val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
    DispatchJsonScanner(text).validate()
    val reply = JSONObject(text)
    requireKeys(reply, setOf("contract_version", "action", "device_id", "request_id", "result"))
    if (strictInteger(reply, "contract_version") != 2L || strictString(reply, "action") != action ||
        dispatchUuid(reply, "device_id") != dispatchUuid(deviceId) || dispatchUuid(reply, "request_id") != dispatchUuid(id)) invalidDispatch()
    val result = reply.get("result") as? JSONObject ?: invalidDispatch()
    validateGatewayDispatchResultV2(action, id, deviceId, payload, result, now, grantExpiresAt)
    reply
}

/** Android's JSONObject may overwrite duplicate keys. Reject them before
 * parsing and reject permissive JSON extensions before they lose evidence. */
internal fun validateGatewayStrictJson(text: String) = DispatchJsonScanner(text).validate()

private class DispatchJsonScanner(private val text: String) {
    private var at = 0
    private fun whitespace() { while (at < text.length && text[at] in "\t\n\r ") at++ }
    fun validate() {
        value(0)
        whitespace()
        if (at != text.length) invalidDispatch()
    }
    private fun string(): String {
        if (at >= text.length || text[at] != '"') invalidDispatch()
        val start = at++
        while (at < text.length) {
            val character = text[at++]
            if (character == '"') return JSONTokener(text.substring(start, at)).nextValue() as? String ?: invalidDispatch()
            if (character.code < 32) invalidDispatch()
            if (character == '\\') {
                if (at >= text.length) invalidDispatch()
                when (text[at++]) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' -> Unit
                    'u' -> {
                        if (at + 4 > text.length || !text.substring(at, at + 4).matches(Regex("[0-9a-fA-F]{4}"))) invalidDispatch()
                        at += 4
                    }
                    else -> invalidDispatch()
                }
            }
        }
        invalidDispatch()
    }
    private fun value(depth: Int) {
        if (depth > 8) invalidDispatch()
        whitespace()
        if (at >= text.length) invalidDispatch()
        when (text[at]) {
            '{' -> {
                at++
                whitespace()
                val seen = mutableSetOf<String>()
                if (take('}')) return
                while (true) {
                    whitespace()
                    if (!seen.add(string())) invalidDispatch()
                    whitespace()
                    if (!take(':')) invalidDispatch()
                    value(depth + 1)
                    whitespace()
                    if (take('}')) return
                    if (!take(',')) invalidDispatch()
                }
            }
            '[' -> {
                at++
                whitespace()
                if (take(']')) return
                while (true) {
                    value(depth + 1)
                    whitespace()
                    if (take(']')) return
                    if (!take(',')) invalidDispatch()
                }
            }
            '"' -> string()
            else -> {
                val token = Regex("(?:true|false|null|-?(?:0|[1-9]\\d*)(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)").find(text, at)
                    ?.takeIf { it.range.first == at } ?: invalidDispatch()
                at += token.value.length
            }
        }
    }
    private fun take(character: Char): Boolean {
        if (at >= text.length || text[at] != character) return false
        at++
        return true
    }
}
