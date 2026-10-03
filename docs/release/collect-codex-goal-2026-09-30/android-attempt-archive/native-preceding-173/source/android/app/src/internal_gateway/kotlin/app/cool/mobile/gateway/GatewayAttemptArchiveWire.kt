package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject

/** Version3 proves durable observations. It never carries an invocation permit. */
internal fun validateGatewayArchivePayload(action: String, payload: JSONObject, request: String) {
    if (action == "archive_lookup") {
        requireKeys(payload, setOf("target_request_id"))
        if (requireUuid(payload, "target_request_id") == request) invalidArchive()
        return
    }
    if (action != "archive_attempt") invalidArchive()
    requireKeys(payload, setOf("attempt_id", "fence_version", "body_sha256", "destination_sha256", "callback_requests"))
    requireUuid(payload, "attempt_id")
    if (strictInteger(payload, "fence_version") !in 1..1_000_000_000L ||
        !listOf("body_sha256", "destination_sha256").all { strictString(payload, it).matches(Regex("[0-9a-f]{64}")) }) invalidArchive()
    validateArchiveReferences(payload.getJSONArray("callback_requests"), request)
}

private fun validateArchiveReferences(rows: JSONArray, request: String? = null) {
    if (rows.length() !in 2..20 || rows.length() % 2 != 0) invalidArchive()
    val callbacks = HashSet<String>(); val requests = HashSet<String>()
    for (i in 0 until rows.length()) {
        val row = rows.getJSONObject(i)
        requireKeys(row, setOf("callback_id", "request_id", "request_sha256"))
        if (!callbacks.add(requireUuid(row, "callback_id")) || !requests.add(requireUuid(row, "request_id")) ||
            row.getString("request_id") == request || !strictString(row, "request_sha256").matches(Regex("[0-9a-f]{64}"))) invalidArchive()
    }
}

internal fun validateGatewayArchiveResult(action: String, request: String, device: String, payload: JSONObject, result: JSONObject) {
    if (action == "archive_lookup") {
        requireKeys(result, setOf("target_request_id", "outcome", "recorded_result"))
        if (requireUuid(result, "target_request_id") != requireUuid(payload, "target_request_id")) invalidArchive()
        when (strictString(result, "outcome")) {
            "unknown" -> if (!result.isNull("recorded_result")) invalidArchive()
            "recorded" -> validateGatewayArchiveAck(result.getJSONObject("recorded_result"), result.getString("target_request_id"), device)
            else -> invalidArchive()
        }
        return
    }
    validateGatewayArchiveAck(result, request, device, payload)
}

internal fun validateGatewayArchiveAck(result: JSONObject, request: String, device: String, payload: JSONObject? = null) {
    requireKeys(result, setOf("request_id", "device_id", "attempt_id", "fence_version", "ok", "code", "archive_ack_id", "receipt_id",
        "body_sha256", "destination_sha256", "segment_count", "callback_requests", "recorded_at", "replay", "evidence_kind", "carrier_proof", "delivery_proven", "send_authority"))
    if (requireUuid(result, "request_id") != request || requireUuid(result, "device_id") != device ||
        strictInteger(result, "fence_version") !in 1..1_000_000_000L || strictInteger(result, "segment_count") !in 1..10 ||
        listOf("carrier_proof", "delivery_proven", "send_authority").any { strictBoolean(result, it) } ||
        !listOf("body_sha256", "destination_sha256").all { strictString(result, it).matches(Regex("[0-9a-f]{64}")) }) invalidArchive()
    requireUuid(result, "attempt_id"); strictTimestamp(result, "recorded_at"); strictBoolean(result, "replay")
    if (payload != null && (requireUuid(result, "attempt_id") != requireUuid(payload, "attempt_id") ||
            result.getLong("fence_version") != strictInteger(payload, "fence_version") ||
            result.getString("body_sha256") != strictString(payload, "body_sha256") ||
            result.getString("destination_sha256") != strictString(payload, "destination_sha256"))) invalidArchive()
    if (strictBoolean(result, "ok")) {
        if (!result.isNull("code") || strictString(result, "evidence_kind") != "complete_framework_callback_observations") invalidArchive()
        requireUuid(result, "archive_ack_id"); requireUuid(result, "receipt_id")
        val rows = result.getJSONArray("callback_requests");validateArchiveReferences(rows, request)
        if (rows.length().toLong() != result.getLong("segment_count") * 2 || payload != null && !archiveJsonEqual(rows, payload.getJSONArray("callback_requests"))) invalidArchive()
    } else if (strictString(result, "code") !in setOf("CALLBACK_EVIDENCE_INCOMPLETE", "CALLBACK_EVIDENCE_UNCERTAIN", "ATTEMPT_ALREADY_ACKNOWLEDGED") ||
        listOf("archive_ack_id", "receipt_id", "callback_requests", "evidence_kind").any { !result.isNull(it) }) invalidArchive()
}

internal fun parseGatewayArchiveReply(action: String, request: String, device: String, payload: JSONObject, bytes: ByteArray): JSONObject {
    if (bytes.size > 32 * 1024) invalidArchive()
    val text = String(bytes, Charsets.UTF_8)
    if (!bytes.contentEquals(text.toByteArray(Charsets.UTF_8))) invalidArchive()
    val reply = JSONObject(text)
    requireKeys(reply, setOf("contract_version", "action", "device_id", "request_id", "result"))
    if (strictInteger(reply, "contract_version") != 3L || strictString(reply, "action") != action ||
        requireUuid(reply, "device_id") != device || requireUuid(reply, "request_id") != request) invalidArchive()
    validateGatewayArchivePayload(action, payload, request)
    validateGatewayArchiveResult(action, request, device, payload, reply.getJSONObject("result"))
    return reply
}
