package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant

internal const val SUCCESSOR_FAMILY = "receipt_successor"
internal const val SUCCESSOR_AUDIENCE = "collect-receipt-successor-gateway"
internal fun isSuccessorEnvelope(value: JSONObject): Boolean = value.opt("protocol_family") == SUCCESSOR_FAMILY
private fun badSuccessor(): Nothing = throw GatewayStateException("gateway_response_invalid")
private fun successorHash(row: JSONObject, name: String): String = strictString(row, name).also { if (!it.matches(Regex("[0-9a-f]{64}"))) badSuccessor() }
private fun successorInt(row: JSONObject, name: String, min: Long, max: Long): Long = strictInteger(row, name).also { if (it !in min..max) badSuccessor() }
private fun successorTime(row: JSONObject, name: String): Instant = strictTimestamp(row, name).also { if (it.toString().take(19) != strictString(row, name).take(19)) badSuccessor() }
private fun successorBase(row: JSONObject) {
    if (strictInteger(row, "contract_version") != 1L || strictString(row, "protocol_family") != SUCCESSOR_FAMILY ||
        strictBoolean(row, "carrier_proof") || strictBoolean(row, "delivery_proven")) badSuccessor()
}
private val successorRefusals = setOf("SUCCESSORS_DISABLED", "OPERATIONS_PAUSED", "NO_CURRENT_RUN", "SUCCESSOR_EXECUTION_PRESENT", "APPROVAL_REVIEW_REQUIRED", "NO_SUCCESSOR_INTENT", "DEVICE_NOT_READY", "QUOTA_EXHAUSTED", "ORIGINAL_REQUEST_RECORDED", "CALLBACK_EVIDENCE_INCOMPLETE")
private fun exactSuccessorRefusal(row: JSONObject, id: String, device: String): Boolean {
    if (!row.has("ok") || strictBoolean(row, "ok")) return false
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "replay", "send_authority", "carrier_proof", "delivery_proven"))
    successorBase(row)
    val code = strictString(row, "code")
    if (code !in successorRefusals || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id ||
        strictBoolean(row, "send_authority") || (code == "ORIGINAL_REQUEST_RECORDED" && !strictBoolean(row, "replay"))) badSuccessor()
    strictBoolean(row, "replay")
    return true
}
internal fun validateSuccessorPayload(action: String, id: String, payload: JSONObject) {
    if (!validUuid(id)) badSuccessor()
    if (action == "dispatch_grant") { requireKeys(payload, emptySet()); return }
    if (action == "reconcile") { requireKeys(payload, setOf("target_request_id")); if (requireUuid(payload, "target_request_id") == id) badSuccessor(); return }
    val fields = when (action) {
        "arm_dispatch" -> setOf("route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "reservation_sha256", "callbacks")
        "callback" -> setOf("route", "callback_id", "attempt_id", "fence_version", "segment_index", "segment_count", "body_sha256", "destination_sha256", "callback_kind", "result_code", "tp_status", "occurred_at")
        "attempt_status" -> setOf("route", "attempt_id", "fence_version")
        "archive_attempt" -> setOf("route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "callback_requests")
        else -> badSuccessor()
    }
    requireKeys(payload, fields)
    val route = successorRouteFromJson(payload.getJSONObject("route")); val attempt = requireUuid(payload, "attempt_id")
    successorInt(payload, "fence_version", 1, 1_000_000_000)
    if (action == "attempt_status") return
    successorHash(payload, "body_sha256"); successorHash(payload, "destination_sha256")
    if (action == "callback") {
        if (requireUuid(payload, "callback_id") == id || strictString(payload, "callback_kind") !in setOf("sent", "delivery")) badSuccessor()
        val count = successorInt(payload, "segment_count", 1, 10); successorInt(payload, "segment_index", 0, count - 1)
        successorInt(payload, "result_code", -1, 200); if (!payload.isNull("tp_status")) successorInt(payload, "tp_status", 0, 255)
        successorTime(payload, "occurred_at"); return
    }
    val seen = hashSetOf(id, attempt, route.dispatchJobId)
    if (action == "arm_dispatch") {
        successorHash(payload, "reservation_sha256"); val rows = payload.getJSONArray("callbacks")
        if (rows.length() !in 1..10) badSuccessor()
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index); requireKeys(row, setOf("segment_index", "sent_callback_id", "delivery_callback_id"))
            if (successorInt(row, "segment_index", 0, 9) != index.toLong()) badSuccessor()
            for (name in listOf("sent_callback_id", "delivery_callback_id")) if (!seen.add(requireUuid(row, name))) badSuccessor()
        }
    } else {
        val rows = payload.getJSONArray("callback_requests"); val requests = hashSetOf<String>()
        if (rows.length() !in 2..20 || rows.length() % 2 != 0) badSuccessor()
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index); requireKeys(row, setOf("callback_id", "request_id", "request_sha256"))
            if (!seen.add(requireUuid(row, "callback_id")) || !requests.add(requireUuid(row, "request_id"))) badSuccessor()
            successorHash(row, "request_sha256")
        }
    }
}
internal fun parseSuccessorGrant(id: String, device: String, row: JSONObject, now: Instant): GatewayDispatchLease? {
    if (exactSuccessorRefusal(row, id, device)) return null
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "run_id", "fence_version", "policy_revision", "issued_at", "expires_at", "segment_count", "body", "destination_e164", "body_sha256", "destination_sha256", "sim_revision_sha256", "replay", "send_authority", "carrier_proof", "delivery_proven"))
    successorBase(row); val route = successorRouteFromJson(row.getJSONObject("route")); val issued = successorTime(row, "issued_at"); val expiry = successorTime(row, "expires_at")
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "SUCCESSOR_GRANTED" || strictBoolean(row, "replay") || strictBoolean(row, "send_authority") || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id || issued > now.plusSeconds(5) || expiry <= issued || expiry > issued.plusSeconds(30) || expiry <= now) badSuccessor()
    val grant = GatewayDispatchGrant(device, route.dispatchJobId, requireUuid(row, "attempt_id"), successorInt(row, "fence_version", 1, 1_000_000_000), strictString(row, "destination_e164"), successorHash(row, "destination_sha256"), strictString(row, "body"), successorHash(row, "body_sha256"), expiry, successorInt(row, "segment_count", 1, 10).toInt(), route)
    grant.validate(now, GatewayAuthority(device, GatewayEnrollmentState.ACTIVE, true, now))
    return GatewayDispatchLease(grant, id, requireUuid(row, "run_id"), successorInt(row, "policy_revision", 1, 1_000_000_000), successorHash(row, "sim_revision_sha256"), issued)
}
internal fun parseSuccessorArm(id: String, device: String, payload: JSONObject, row: JSONObject, grantExpiry: Instant, now: Instant): GatewayDispatchArmAck? {
    validateSuccessorPayload("arm_dispatch", id, payload); if (exactSuccessorRefusal(row, id, device)) return null
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "fence_version", "reservation_sha256", "armed_at", "expires_at", "replay", "send_authority", "carrier_proof", "delivery_proven")); successorBase(row)
    val route = successorRouteFromJson(row.getJSONObject("route")); val armed = successorTime(row, "armed_at"); val expiry = successorTime(row, "expires_at")
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "SUCCESSOR_ARMED" || strictBoolean(row, "replay") || !strictBoolean(row, "send_authority") || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id || route != successorRouteFromJson(payload.getJSONObject("route")) || requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id") || strictInteger(row, "fence_version") != strictInteger(payload, "fence_version") || successorHash(row, "reservation_sha256") != successorHash(payload, "reservation_sha256") || armed > now.plusSeconds(5) || expiry <= armed || expiry > armed.plusSeconds(30) || expiry > grantExpiry || expiry <= now) badSuccessor()
    return GatewayDispatchArmAck(requireUuid(row, "attempt_id"), strictInteger(row, "fence_version"), successorHash(row, "reservation_sha256"), armed, expiry, route)
}
internal fun validateSuccessorArchiveAck(row: JSONObject, id: String, device: String, payload: JSONObject) {
    if (exactSuccessorRefusal(row, id, device)) return
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "archive_ack_id", "evidence_sha256", "callback_requests", "recorded_at", "replay", "journal_ack", "send_authority", "carrier_proof", "delivery_proven")); successorBase(row)
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "SUCCESSOR_JOURNAL_ARCHIVE_ACKNOWLEDGED" || !strictBoolean(row, "journal_ack") || strictBoolean(row, "send_authority") || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id || successorRouteFromJson(row.getJSONObject("route")) != successorRouteFromJson(payload.getJSONObject("route")) || requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id") || strictInteger(row, "fence_version") != strictInteger(payload, "fence_version") || successorHash(row, "body_sha256") != successorHash(payload, "body_sha256") || successorHash(row, "destination_sha256") != successorHash(payload, "destination_sha256") || !archiveJsonEqual(row.getJSONArray("callback_requests"), payload.getJSONArray("callback_requests"))) badSuccessor()
    requireUuid(row, "archive_ack_id"); successorHash(row, "evidence_sha256"); successorTime(row, "recorded_at"); strictBoolean(row, "replay")
}
internal fun validateSuccessorResult(action: String, id: String, device: String, payload: JSONObject, row: JSONObject, now: Instant, grantExpiry: Instant? = null) {
    validateSuccessorPayload(action, id, payload)
    when (action) {
        "dispatch_grant" -> parseSuccessorGrant(id, device, row, now)
        "arm_dispatch" -> if (!exactSuccessorRefusal(row, id, device)) parseSuccessorArm(id, device, payload, row, grantExpiry ?: badSuccessor(), now)
        "archive_attempt" -> validateSuccessorArchiveAck(row, id, device, payload)
        "callback" -> {
            requireKeys(row, setOf("contract_version", "protocol_family", "route", "callback_id", "attempt_id", "recorded_at", "replay", "state", "sent_observations", "delivery_observations", "conflicting_observations", "failed_observations", "send_authority", "carrier_proof", "delivery_proven")); successorBase(row)
            if (successorRouteFromJson(row.getJSONObject("route")) != successorRouteFromJson(payload.getJSONObject("route")) || requireUuid(row, "callback_id") != requireUuid(payload, "callback_id") || requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id") || strictString(row, "state") !in setOf("armed_unknown", "observed_sent", "uncertain") || strictBoolean(row, "send_authority")) badSuccessor()
            successorTime(row, "recorded_at"); strictBoolean(row, "replay"); validateSuccessorCounts(row, successorInt(payload, "segment_count", 1, 10))
        }
        "attempt_status" -> {
            requireKeys(row, setOf("contract_version", "protocol_family", "route", "attempt_id", "fence_version", "state", "segment_count", "armed_at", "sent_observations", "delivery_observations", "conflicting_observations", "failed_observations", "terminal_archive_ack", "send_authority", "carrier_proof", "delivery_proven")); successorBase(row)
            if (successorRouteFromJson(row.getJSONObject("route")) != successorRouteFromJson(payload.getJSONObject("route")) || requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id") || strictInteger(row, "fence_version") != strictInteger(payload, "fence_version") || strictString(row, "state") !in setOf("unarmed_granted", "unarmed_revoked", "unarmed_expired", "armed_unknown", "observed_sent", "uncertain") || strictBoolean(row, "send_authority")) badSuccessor()
            if (!row.isNull("armed_at")) successorTime(row, "armed_at"); strictBoolean(row, "terminal_archive_ack"); validateSuccessorCounts(row, successorInt(row, "segment_count", 1, 10))
        }
        "reconcile" -> {
            requireKeys(row, setOf("contract_version", "protocol_family", "target_request_id", "outcome", "recorded_action", "recorded_route", "recorded_result", "send_authority", "carrier_proof", "delivery_proven")); successorBase(row)
            if (requireUuid(row, "target_request_id") != requireUuid(payload, "target_request_id") || strictBoolean(row, "send_authority")) badSuccessor()
            when (strictString(row, "outcome")) {
                "unknown" -> if (!row.isNull("recorded_action") || !row.isNull("recorded_route") || !row.isNull("recorded_result")) badSuccessor()
                "recorded" -> {
                    val recorded = row.getJSONObject("recorded_result"); val action = strictString(row, "recorded_action")
                    if (action !in setOf("dispatch_grant", "arm_dispatch", "callback", "archive_attempt")) badSuccessor()
                    if (action in setOf("dispatch_grant", "arm_dispatch")) {
                        if (!exactSuccessorRefusal(recorded, requireUuid(row, "target_request_id"), device)) badSuccessor()
                        if (strictString(recorded, "code") == "ORIGINAL_REQUEST_RECORDED") successorRouteFromJson(row.getJSONObject("recorded_route")) else if (!row.isNull("recorded_route")) badSuccessor()
                    } else if (row.isNull("recorded_route")) badSuccessor() else successorRouteFromJson(row.getJSONObject("recorded_route"))
                    if (action == "callback") {
                        requireKeys(recorded, setOf("contract_version", "protocol_family", "route", "callback_id", "attempt_id", "recorded_at", "replay", "state", "sent_observations", "delivery_observations", "conflicting_observations", "failed_observations", "send_authority", "carrier_proof", "delivery_proven"))
                        successorBase(recorded); requireUuid(recorded, "callback_id"); requireUuid(recorded, "attempt_id"); successorTime(recorded, "recorded_at"); strictBoolean(recorded, "replay")
                        if (successorRouteFromJson(recorded.getJSONObject("route")) != successorRouteFromJson(row.getJSONObject("recorded_route")) || strictString(recorded, "state") !in setOf("armed_unknown", "observed_sent", "uncertain") || strictBoolean(recorded, "send_authority")) badSuccessor()
                        successorInt(recorded, "sent_observations", 0, 10); successorInt(recorded, "delivery_observations", 0, 10); strictBoolean(recorded, "failed_observations"); strictBoolean(recorded, "conflicting_observations")
                    } else if (action == "archive_attempt" && !exactSuccessorRefusal(recorded, requireUuid(row, "target_request_id"), device)) {
                        val source = JSONObject().put("route", recorded.getJSONObject("route")).put("attempt_id", recorded.getString("attempt_id")).put("fence_version", recorded.get("fence_version"))
                            .put("body_sha256", recorded.getString("body_sha256")).put("destination_sha256", recorded.getString("destination_sha256")).put("callback_requests", recorded.getJSONArray("callback_requests"))
                        validateSuccessorPayload("archive_attempt", requireUuid(row, "target_request_id"), source)
                        validateSuccessorArchiveAck(recorded, requireUuid(row, "target_request_id"), device, source)
                        if (successorRouteFromJson(recorded.getJSONObject("route")) != successorRouteFromJson(row.getJSONObject("recorded_route"))) badSuccessor()
                    }
                    // The exact durable original supplies the source binding before compaction.
                    if (recorded.has("send_authority") && strictBoolean(recorded, "send_authority")) badSuccessor()
                }
                else -> badSuccessor()
            }
        }
    }
}
private fun validateSuccessorCounts(row: JSONObject, count: Long) {
    val sent = successorInt(row, "sent_observations", 0, count); successorInt(row, "delivery_observations", 0, count)
    val conflict = strictBoolean(row, "conflicting_observations"); val failed = strictBoolean(row, "failed_observations")
    if (strictString(row, "state") == "observed_sent" && (sent != count || conflict || failed)) badSuccessor()
}
internal fun parseSuccessorReply(action: String, id: String, device: String, payload: JSONObject, bytes: ByteArray, now: Instant, grantExpiry: Instant? = null): JSONObject {
    try {
        if (bytes.isEmpty() || bytes.size > 8192 || bytes.take(3) == listOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte())) badSuccessor()
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        validateGatewayStrictJson(text); val reply = JSONObject(text)
        requireKeys(reply, setOf("contract_version", "protocol_family", "audience", "action", "device_id", "request_id", "result"))
        if (strictInteger(reply, "contract_version") != 1L || strictString(reply, "protocol_family") != SUCCESSOR_FAMILY || strictString(reply, "audience") != SUCCESSOR_AUDIENCE || strictString(reply, "action") != action || requireUuid(reply, "device_id") != device || requireUuid(reply, "request_id") != id) badSuccessor()
        validateSuccessorResult(action, id, device, payload, reply.getJSONObject("result"), now, grantExpiry); return reply
    } catch (error: GatewayStateException) { throw error } catch (_: Exception) { badSuccessor() }
}

internal fun validateSuccessorEnvelope(text: String, row: JSONObject) {
    validateGatewayStrictJson(text)
    requireKeys(row, setOf("contract_version", "protocol_family", "audience", "action", "device_id", "request_id", "issued_at", "payload"))
    if (strictInteger(row, "contract_version") != 1L || strictString(row, "protocol_family") != SUCCESSOR_FAMILY || strictString(row, "audience") != SUCCESSOR_AUDIENCE) badSuccessor()
    requireUuid(row, "device_id"); strictTimestamp(row, "issued_at")
    validateSuccessorPayload(strictString(row, "action"), requireUuid(row, "request_id"), row.getJSONObject("payload"))
}
internal fun requestMatchesRoute(request: GatewayStoredRequest, route: GatewayDispatchRoute): Boolean = when (route) {
    is GatewayDispatchRoute.ReceiptNoticeV1 -> isNoticeEnvelope(request.envelope) && request.envelope.getJSONObject("payload").has("route") && noticeRouteFromJson(request.envelope.getJSONObject("payload").getJSONObject("route")) == route
    is GatewayDispatchRoute.PrimaryV2 -> !isSuccessorEnvelope(request.envelope) && !isNoticeEnvelope(request.envelope)
    is GatewayDispatchRoute.ReceiptSuccessorV1 -> isSuccessorEnvelope(request.envelope) && request.envelope.getJSONObject("payload").has("route") && successorRouteFromJson(request.envelope.getJSONObject("payload").getJSONObject("route")) == route
}
internal fun validateRouteArchiveAck(request: GatewayStoredRequest, ack: JSONObject) {
    if (isNoticeEnvelope(request.envelope)) validateNoticeArchiveAck(ack, request.requestId, request.deviceId, request.envelope.getJSONObject("payload"))
    else if (isSuccessorEnvelope(request.envelope)) validateSuccessorArchiveAck(ack, request.requestId, request.deviceId, request.envelope.getJSONObject("payload"))
    else validateGatewayArchiveAck(ack, request.requestId, request.deviceId, request.envelope.getJSONObject("payload"))
}
