package app.cool.mobile.gateway

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant

internal const val NOTICE_FAMILY = "receipt_notice"
internal const val NOTICE_AUDIENCE = "collect-receipt-notice-gateway"
internal fun isNoticeEnvelope(value: JSONObject): Boolean = value.opt("protocol_family") == NOTICE_FAMILY
private fun badNotice(): Nothing = throw GatewayStateException("gateway_notice_response_invalid")
private fun noticeHash(row: JSONObject, key: String): String = strictString(row, key).also {
    if (!it.matches(Regex("[0-9a-f]{64}"))) badNotice()
}
private fun noticeInt(row: JSONObject, key: String, min: Long, max: Long): Long = strictInteger(row, key).also {
    if (it !in min..max) badNotice()
}
private fun noticeTime(row: JSONObject, key: String): Instant = strictTimestamp(row, key).also {
    if (it.toString().take(19) != strictString(row, key).take(19)) badNotice()
}
internal fun validateNoticeRoute(route: GatewayDispatchRoute.ReceiptNoticeV1, job: String) {
    if (!listOf(route.primaryReceiptId, route.noticeJobId, route.approvalId, job).all(::validUuid) ||
        route.noticeJobId != job || route.primaryReceiptId.equals(job, ignoreCase = true) ||
        route.noticeFamily !in setOf("duplicate_copy", "reversal_notice")) badNotice()
}
internal fun noticeRouteJson(route: GatewayDispatchRoute): JSONObject {
    val notice = route as? GatewayDispatchRoute.ReceiptNoticeV1 ?: badNotice()
    validateNoticeRoute(notice, notice.noticeJobId)
    return JSONObject().put("route_version", 1).put("route_kind", NOTICE_FAMILY)
        .put("primary_receipt_id", notice.primaryReceiptId).put("notice_job_id", notice.noticeJobId)
        .put("notice_approval_id", notice.approvalId).put("notice_family", notice.noticeFamily)
}
internal fun noticeRouteFromJson(row: JSONObject): GatewayDispatchRoute.ReceiptNoticeV1 {
    requireKeys(row, setOf("route_version", "route_kind", "primary_receipt_id", "notice_job_id", "notice_approval_id", "notice_family"))
    if (strictInteger(row, "route_version") != 1L || strictString(row, "route_kind") != NOTICE_FAMILY) badNotice()
    return GatewayDispatchRoute.ReceiptNoticeV1(requireUuid(row, "primary_receipt_id"), requireUuid(row, "notice_job_id"),
        requireUuid(row, "notice_approval_id"), strictString(row, "notice_family")).also { validateNoticeRoute(it, it.noticeJobId) }
}
internal fun noticeReservationDigest(record: GatewayAttempt, original: String): String {
    val route = record.dispatchRoute as? GatewayDispatchRoute.ReceiptNoticeV1 ?: badNotice()
    validateNoticeRoute(route, record.jobId)
    return sha256(listOf("collect-receipt-notice-reservation:v1", "1", NOTICE_FAMILY, route.primaryReceiptId,
        route.noticeJobId, route.approvalId, route.noticeFamily, original).joinToString("|"))
}
private fun noticeBase(row: JSONObject) {
    if (strictInteger(row, "contract_version") != 1L || strictString(row, "protocol_family") != NOTICE_FAMILY ||
        strictBoolean(row, "carrier_proof") || strictBoolean(row, "delivery_proven")) badNotice()
}
private val noticeRefusals = setOf("NOTICE_DISPATCH_DISABLED", "NO_ELIGIBLE_NOTICE", "OPERATIONS_PAUSED", "NO_CURRENT_RUN",
    "NOTICE_ALREADY_MATERIALIZED", "DEVICE_NOT_READY", "QUOTA_EXHAUSTED", "ORIGINAL_REQUEST_RECORDED")
internal fun exactNoticeRefusal(row: JSONObject, id: String, device: String): Boolean {
    if (!row.has("ok") || strictBoolean(row, "ok")) return false
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "replay",
        "send_authority", "carrier_proof", "delivery_proven"))
    noticeBase(row)
    if (strictString(row, "code") !in noticeRefusals || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id ||
        strictBoolean(row, "send_authority") || strictString(row, "code") == "ORIGINAL_REQUEST_RECORDED" && !strictBoolean(row, "replay")) badNotice()
    strictBoolean(row, "replay")
    return true
}
internal fun validateNoticePayload(action: String, id: String, row: JSONObject) {
    if (!validUuid(id)) badNotice()
    if (action == "dispatch_grant") { requireKeys(row, emptySet()); return }
    if (action == "reconcile") {
        requireKeys(row, setOf("target_request_id"))
        if (requireUuid(row, "target_request_id").equals(id, ignoreCase = true)) badNotice()
        return
    }
    val keys = when (action) {
        "arm_dispatch" -> setOf("route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "reservation_sha256", "callbacks")
        "callback" -> setOf("route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "callback_id", "segment_index",
            "segment_count", "callback_kind", "result_code", "tp_status", "occurred_at")
        "attempt_status" -> setOf("route", "attempt_id", "fence_version")
        "archive_attempt" -> setOf("route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "callback_requests")
        else -> badNotice()
    }
    requireKeys(row, keys)
    val route = noticeRouteFromJson(row.getJSONObject("route")); val attempt = requireUuid(row, "attempt_id")
    noticeInt(row, "fence_version", 1, 1_000_000_000)
    if (action == "attempt_status") return
    noticeHash(row, "body_sha256"); noticeHash(row, "destination_sha256")
    if (action == "callback") {
        if (requireUuid(row, "callback_id").equals(id, ignoreCase = true) || strictString(row, "callback_kind") !in setOf("sent", "delivery")) badNotice()
        val count = noticeInt(row, "segment_count", 1, 10); noticeInt(row, "segment_index", 0, count - 1)
        noticeInt(row, "result_code", -1, 200)
        if (!row.isNull("tp_status")) noticeInt(row, "tp_status", 0, 255)
        noticeTime(row, "occurred_at")
        return
    }
    val excluded = setOf(id, attempt, route.primaryReceiptId, route.noticeJobId, route.approvalId).map { it.lowercase() }
    val callbacks = excluded.toMutableSet(); val requests = excluded.toMutableSet()
    if (action == "arm_dispatch") {
        noticeHash(row, "reservation_sha256"); val rows = row.getJSONArray("callbacks")
        if (rows.length() !in 1..10) badNotice()
        for (i in 0 until rows.length()) {
            val value = rows.getJSONObject(i); requireKeys(value, setOf("segment_index", "sent_callback_id", "delivery_callback_id"))
            if (noticeInt(value, "segment_index", 0, 9) != i.toLong()) badNotice()
            for (key in listOf("sent_callback_id", "delivery_callback_id")) if (!callbacks.add(requireUuid(value, key).lowercase())) badNotice()
        }
    } else {
        val rows = row.getJSONArray("callback_requests")
        if (rows.length() !in 2..20 || rows.length() % 2 != 0) badNotice()
        for (i in 0 until rows.length()) {
            val value = rows.getJSONObject(i); requireKeys(value, setOf("callback_id", "request_id", "request_sha256"))
            if (!callbacks.add(requireUuid(value, "callback_id").lowercase()) || !requests.add(requireUuid(value, "request_id").lowercase())) badNotice()
            noticeHash(value, "request_sha256")
        }
    }
}
internal data class GatewayNoticeLease(
    val grant: GatewayDispatchGrant, val requestId: String, val runId: String,
    val operationsPolicyRevision: Long, val noticePolicyRevision: Long, val configurationRevision: Long,
    val simRevisionSha256: String, val issuedAt: Instant,
)
internal fun parseNoticeGrant(id: String, device: String, row: JSONObject, now: Instant): GatewayNoticeLease? {
    if (exactNoticeRefusal(row, id, device)) return null
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "run_id",
        "fence_version", "operations_policy_revision", "notice_policy_revision", "configuration_revision", "issued_at", "expires_at",
        "segment_count", "body", "destination_e164", "body_sha256", "destination_sha256", "sim_revision_sha256", "replay", "send_authority",
        "carrier_proof", "delivery_proven"))
    noticeBase(row)
    val route = noticeRouteFromJson(row.getJSONObject("route")); val issued = noticeTime(row, "issued_at"); val expiry = noticeTime(row, "expires_at")
    val body = strictString(row, "body"); val count = if (body.length <= 160) 1 else (body.length + 152) / 153
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "NOTICE_GRANTED" || strictBoolean(row, "send_authority") ||
        strictBoolean(row, "replay") || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id ||
        issued > now.plusSeconds(5) || expiry <= issued || expiry > issued.plusSeconds(30) || expiry <= now ||
        !body.matches(Regex("[A-Za-z0-9 .,/:_-]+")) || body.length > 1000 || noticeInt(row, "segment_count", 1, 10) != count.toLong()) badNotice()
    val grant = GatewayDispatchGrant(device, route.noticeJobId, requireUuid(row, "attempt_id"), noticeInt(row, "fence_version", 1, 1_000_000_000),
        strictString(row, "destination_e164"), noticeHash(row, "destination_sha256"), body, noticeHash(row, "body_sha256"), expiry, count, route)
    grant.validate(now, GatewayAuthority(device, GatewayEnrollmentState.ACTIVE, true, now))
    return GatewayNoticeLease(grant, id, requireUuid(row, "run_id"), noticeInt(row, "operations_policy_revision", 1, 1_000_000_000),
        noticeInt(row, "notice_policy_revision", 1, 1_000_000_000), noticeInt(row, "configuration_revision", 1, 1_000_000_000),
        noticeHash(row, "sim_revision_sha256"), issued)
}
internal fun parseNoticeArm(id: String, device: String, payload: JSONObject, row: JSONObject, expiry: Instant, now: Instant): GatewayDispatchArmAck? {
    validateNoticePayload("arm_dispatch", id, payload)
    if (exactNoticeRefusal(row, id, device)) return null
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "fence_version",
        "body_sha256", "destination_sha256", "segment_count", "armed_at", "invoke_before", "reservation_sha256", "replay", "send_authority",
        "carrier_proof", "delivery_proven"))
    noticeBase(row)
    val route = noticeRouteFromJson(row.getJSONObject("route")); val armed = noticeTime(row, "armed_at"); val before = noticeTime(row, "invoke_before")
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "NOTICE_ARMED" || strictBoolean(row, "replay") || !strictBoolean(row, "send_authority") ||
        requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id || route != noticeRouteFromJson(payload.getJSONObject("route")) ||
        requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id") || strictInteger(row, "fence_version") != strictInteger(payload, "fence_version") ||
        noticeHash(row, "body_sha256") != noticeHash(payload, "body_sha256") || noticeHash(row, "destination_sha256") != noticeHash(payload, "destination_sha256") ||
        noticeHash(row, "reservation_sha256") != noticeHash(payload, "reservation_sha256") || noticeInt(row, "segment_count", 1, 10) != payload.getJSONArray("callbacks").length().toLong() ||
        armed > now.plusSeconds(5) || before <= armed || before > armed.plusSeconds(15) || before > expiry || before <= now) badNotice()
    return GatewayDispatchArmAck(requireUuid(row, "attempt_id"), strictInteger(row, "fence_version"), noticeHash(row, "reservation_sha256"), armed, before, route)
}
private val noticeFacts = setOf("sent_observations", "delivery_observations", "failed_sent", "failed_delivery", "conflicting_observations", "state",
    "attempt_id", "segment_count", "terminal_archive_ack", "delivery_callback_gap", "carrier_proof", "delivery_proven", "send_authority")
private fun noticeCounts(row: JSONObject) {
    noticeBase(row); requireUuid(row, "attempt_id"); val count = noticeInt(row, "segment_count", 1, 10)
    val sent = noticeInt(row, "sent_observations", 0, count); noticeInt(row, "delivery_observations", 0, count)
    val failed = strictBoolean(row, "failed_sent"); val conflict = strictBoolean(row, "conflicting_observations")
    strictBoolean(row, "failed_delivery"); strictBoolean(row, "terminal_archive_ack"); strictBoolean(row, "delivery_callback_gap")
    val state = strictString(row, "state")
    if (state !in setOf("granted", "send_started", "observed_sent", "uncertain") || strictBoolean(row, "send_authority") ||
        state == "observed_sent" && (sent != count || failed || conflict)) badNotice()
}
private fun validateNoticeCallbackFact(row: JSONObject, id: String, device: String) {
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "route", "device_id", "request_id", "callback_id", "recorded_at", "replay") + noticeFacts)
    noticeCounts(row)
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "NOTICE_CALLBACK_RECORDED" || strictString(row, "state") == "granted" ||
        requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id) badNotice()
    noticeRouteFromJson(row.getJSONObject("route")); requireUuid(row, "callback_id"); noticeTime(row, "recorded_at"); strictBoolean(row, "replay")
}
internal fun validateNoticeArchiveAck(row: JSONObject, id: String, device: String, payload: JSONObject) {
    if (exactNoticeRefusal(row, id, device)) return
    requireKeys(row, setOf("contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "acknowledgement_id",
        "recorded_at", "terminal_archive_ack", "send_authority", "carrier_proof", "delivery_proven", "replay"))
    noticeBase(row)
    if (!strictBoolean(row, "ok") || strictString(row, "code") != "NOTICE_ARCHIVED" || !strictBoolean(row, "terminal_archive_ack") ||
        strictBoolean(row, "send_authority") || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id ||
        noticeRouteFromJson(row.getJSONObject("route")) != noticeRouteFromJson(payload.getJSONObject("route")) ||
        requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id")) badNotice()
    requireUuid(row, "acknowledgement_id"); noticeTime(row, "recorded_at"); strictBoolean(row, "replay")
}
internal fun validateNoticeResult(action: String, id: String, device: String, payload: JSONObject, row: JSONObject, now: Instant, expiry: Instant? = null) {
    validateNoticePayload(action, id, payload)
    if (action != "reconcile" && exactNoticeRefusal(row, id, device)) return
    when (action) {
        "dispatch_grant" -> parseNoticeGrant(id, device, row, now)
        "arm_dispatch" -> parseNoticeArm(id, device, payload, row, expiry ?: badNotice(), now)
        "callback" -> {
            validateNoticeCallbackFact(row, id, device)
            if (noticeRouteFromJson(row.getJSONObject("route")) != noticeRouteFromJson(payload.getJSONObject("route")) ||
                requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id") || requireUuid(row, "callback_id") != requireUuid(payload, "callback_id") ||
                strictInteger(row, "segment_count") != strictInteger(payload, "segment_count")) badNotice()
        }
        "archive_attempt" -> validateNoticeArchiveAck(row, id, device, payload)
        "attempt_status" -> {
            requireKeys(row, setOf("contract_version", "protocol_family", "route", "grant_expired", "revoked") + noticeFacts); noticeCounts(row)
            if (noticeRouteFromJson(row.getJSONObject("route")) != noticeRouteFromJson(payload.getJSONObject("route")) ||
                requireUuid(row, "attempt_id") != requireUuid(payload, "attempt_id")) badNotice()
            strictBoolean(row, "grant_expired"); strictBoolean(row, "revoked")
        }
        "reconcile" -> {
            requireKeys(row, setOf("contract_version", "protocol_family", "target_request_id", "outcome", "recorded_action", "recorded_result", "send_authority"))
            val target = requireUuid(payload, "target_request_id")
            if (strictInteger(row, "contract_version") != 1L || strictString(row, "protocol_family") != NOTICE_FAMILY ||
                requireUuid(row, "target_request_id") != target || strictBoolean(row, "send_authority")) badNotice()
            when (strictString(row, "outcome")) {
                "unknown" -> if (!row.isNull("recorded_action") || !row.isNull("recorded_result")) badNotice()
                "recorded" -> {
                    val originalAction = strictString(row, "recorded_action"); val recorded = row.getJSONObject("recorded_result")
                    when (originalAction) {
                        "dispatch_grant", "arm_dispatch" -> if (!exactNoticeRefusal(recorded, target, device) || strictString(recorded, "code") != "ORIGINAL_REQUEST_RECORDED") badNotice()
                        "callback" -> validateNoticeCallbackFact(recorded, target, device)
                        "archive_attempt" -> {
                            // Exact original request provides all hash/ref bindings
                            // before this observation can authorize compaction.
                            val source = JSONObject().put("route", recorded.getJSONObject("route")).put("attempt_id", recorded.getString("attempt_id"))
                            validateNoticeArchiveAck(recorded, target, device, source)
                        }
                        else -> badNotice()
                    }
                }
                else -> badNotice()
            }
        }
        else -> badNotice()
    }
}
internal fun validateNoticeEnvelope(text: String, row: JSONObject) {
    validateGatewayStrictJson(text)
    requireKeys(row, setOf("contract_version", "protocol_family", "audience", "action", "device_id", "request_id", "issued_at", "payload"))
    if (strictInteger(row, "contract_version") != 1L || strictString(row, "protocol_family") != NOTICE_FAMILY || strictString(row, "audience") != NOTICE_AUDIENCE) badNotice()
    requireUuid(row, "device_id"); noticeTime(row, "issued_at")
    validateNoticePayload(strictString(row, "action"), requireUuid(row, "request_id"), row.getJSONObject("payload"))
}
internal fun parseNoticeReply(action: String, id: String, device: String, payload: JSONObject, bytes: ByteArray, now: Instant, expiry: Instant? = null): JSONObject {
    try {
        if (bytes.isEmpty() || bytes.size > 8192 || bytes.take(3) == listOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte())) badNotice()
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        validateGatewayStrictJson(text); val row = JSONObject(text)
        requireKeys(row, setOf("contract_version", "protocol_family", "audience", "action", "device_id", "request_id", "result"))
        if (strictInteger(row, "contract_version") != 1L || strictString(row, "protocol_family") != NOTICE_FAMILY || strictString(row, "audience") != NOTICE_AUDIENCE ||
            strictString(row, "action") != action || requireUuid(row, "device_id") != device || requireUuid(row, "request_id") != id) badNotice()
        validateNoticeResult(action, id, device, payload, row.getJSONObject("result"), now, expiry)
        return row
    } catch (error: GatewayStateException) { throw error } catch (_: Exception) { badNotice() }
}
