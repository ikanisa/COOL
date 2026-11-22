package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class GatewayDispatchWireTest {
    private val device = "aa750000-0000-4000-8000-000000000001"
    private val request = "aa750000-0000-4000-8000-000000000002"
    private val attempt = "aa750000-0000-4000-8000-000000000003"
    private val receipt = "aa750000-0000-4000-8000-000000000004"
    private val run = "aa750000-0000-4000-8000-000000000005"
    private val callback = "aa750000-0000-4000-8000-000000000006"
    private val delivery = "aa750000-0000-4000-8000-000000000007"
    private val target = "aa750000-0000-4000-8000-000000000008"
    private val now = Instant.parse("2026-10-01T12:00:00Z")
    private val expires = now.plusSeconds(30)
    private val body = "BuriMunsi: Ubwizigame bwa 100 RWF bwanditswe."
    private val destination = "+250788000001"
    private val reservation = "d".repeat(64)

    private fun grant() = JSONObject().put("ok", true).put("code", "DISPATCH_GRANTED")
        .put("device_id", device).put("request_id", request).put("attempt_id", attempt).put("receipt_id", receipt)
        .put("run_id", run).put("fence_version", 7).put("policy_revision", 8).put("issued_at", now.toString())
        .put("expires_at", expires.toString()).put("segment_count", 1).put("body", body).put("destination_e164", destination)
        .put("body_sha256", sha256(body)).put("destination_sha256", sha256(destination)).put("sim_revision_sha256", "e".repeat(64))
        .put("replay", false)
    private fun plan(index: Int = 0, sent: String = callback, delivered: String = delivery) = JSONObject()
        .put("segment_index", index).put("sent_callback_id", sent).put("delivery_callback_id", delivered)
    private fun armPayload() = JSONObject().put("attempt_id", attempt).put("fence_version", 7)
        .put("body_sha256", sha256(body)).put("destination_sha256", sha256(destination))
        .put("callbacks", JSONArray().put(plan())).put("reservation_sha256", reservation)
    private fun armed() = JSONObject().put("ok", true).put("code", "DISPATCH_ARMED").put("device_id", device)
        .put("request_id", request).put("attempt_id", attempt).put("fence_version", 7).put("reservation_sha256", reservation)
        .put("armed_at", now.toString()).put("expires_at", expires.toString()).put("replay", false).put("carrier_proof", false)
    private fun refusal(code: String = "ORIGINAL_REQUEST_RECORDED", id: String = request) = JSONObject()
        .put("ok", false).put("code", code).put("device_id", device).put("request_id", id).put("replay", true)
    private fun callbackPayload(count: Int = 1) = JSONObject().put("callback_id", callback).put("attempt_id", attempt)
        .put("fence_version", 7).put("segment_index", 0).put("segment_count", count).put("body_sha256", sha256(body))
        .put("destination_sha256", sha256(destination)).put("callback_kind", "sent").put("result_code", -1)
        .put("tp_status", JSONObject.NULL).put("occurred_at", now.toString())
    private fun callbackResult() = JSONObject().put("callback_id", callback).put("recorded_at", now.toString())
        .put("replay", false).put("carrier_proof", false).put("state", "observed_sent").put("sent_observations", 1)
        .put("delivery_observations", 0).put("conflicting_observations", false)
    private fun statusPayload() = JSONObject().put("attempt_id", attempt).put("fence_version", 7)
    private fun statusResult() = JSONObject().put("attempt_id", attempt).put("fence_version", 7).put("state", "observed_sent")
        .put("armed_at", now.toString()).put("segment_count", 1).put("sent_observations", 1).put("delivery_observations", 0)
        .put("conflicting_observations", false).put("terminal_archive_ack", false).put("carrier_proof", false)
    private fun reply(action: String, result: JSONObject) = JSONObject().put("contract_version", 2).put("action", action)
        .put("device_id", device).put("request_id", request).put("result", result)
    private fun reject(block: () -> Unit) {
        try { block(); fail("Expected bounded dispatch refusal") } catch (_: GatewayStateException) { }
    }
    private fun validate(action: String, payload: JSONObject, result: JSONObject) =
        validateGatewayDispatchResultV2(action, request, device, payload, result, now, expires)

    @Test fun initialGrantMapsExistingNativeGrantAndRetainsRunPolicySimLease() {
        val lease = parseGatewayDispatchGrantV2(request, device, grant(), now)!!
        assertEquals(device, lease.grant.deviceId)
        assertEquals(receipt, lease.grant.jobId)
        assertEquals(attempt, lease.grant.attemptId)
        assertEquals(7L, lease.grant.fence)
        assertEquals(body, lease.grant.body)
        assertEquals(destination, lease.grant.destinationE164)
        assertEquals(expires, lease.grant.expiresAt)
        assertEquals(run, lease.runId)
        assertEquals(8L, lease.policyRevision)
        assertEquals("e".repeat(64), lease.simRevisionSha256)
        assertEquals(request, lease.requestId)
        assertEquals(now, lease.issuedAt)
    }

    @Test fun exactRefusalsNeverCreateGrantOrArmAuthority() {
        for (code in listOf("OPERATIONS_PAUSED", "NO_CURRENT_RUN", "DEVICE_NOT_READY", "NO_ELIGIBLE_RECEIPT", "QUOTA_EXHAUSTED", "ORIGINAL_REQUEST_RECORDED")) {
            assertNull(parseGatewayDispatchGrantV2(request, device, refusal(code), now))
            assertNull(parseGatewayDispatchArmV2(request, device, armPayload(), refusal(code), expires, now))
        }
        reject { parseGatewayDispatchGrantV2(request, device, refusal("NEW_UNREVIEWED_CODE"), now) }
        reject { parseGatewayDispatchGrantV2(request, device, refusal().put("body", body), now) }
    }

    @Test fun grantRejectsChangedContentDestinationIdentityAndInventedFields() {
        for ((name, value) in listOf("body_sha256" to "0".repeat(64), "destination_sha256" to "0".repeat(64),
            "body" to "Changed savings", "destination_e164" to "+256788000001", "device_id" to target,
            "request_id" to target, "body" to "x".repeat(1001), "replay" to true, "private_key" to "private")) {
            reject { parseGatewayDispatchGrantV2(request, device, grant().put(name, value), now) }
        }
        reject { parseGatewayDispatchGrantV2(request, device, grant().put("body", "bad\u0000body").put("body_sha256", sha256("bad\u0000body")), now) }
    }

    @Test fun grantRejectsExpiredAndExtendedThirtySecondAuthority() {
        reject { parseGatewayDispatchGrantV2(request, device, grant().put("expires_at", expires.plusNanos(1000).toString()), now) }
        reject { parseGatewayDispatchGrantV2(request, device, grant(), expires) }
        reject { parseGatewayDispatchGrantV2(request, device, grant().put("issued_at", expires.toString()), now) }
        reject { parseGatewayDispatchGrantV2(request, device, grant().put("issued_at", "2026-10-01T24:00:00Z"), now) }
    }

    @Test fun numericStringsFractionsBooleansAndOverflowAreNeverCoerced() {
        for (field in listOf("fence_version", "policy_revision", "segment_count")) {
            for (value in listOf<Any>("1", 1.0, true, 0, 1_000_000_001L)) {
                reject { parseGatewayDispatchGrantV2(request, device, grant().put(field, value), now) }
            }
        }
    }

    @Test fun armBindsAttemptFenceReservationAndOriginalGrantExpiry() {
        val ack = parseGatewayDispatchArmV2(request, device, armPayload(), armed(), expires, now)!!
        assertEquals(attempt, ack.attemptId)
        assertEquals(7L, ack.fence)
        assertEquals(reservation, ack.reservationSha256)
        assertEquals(now, ack.armedAt)
        assertEquals(expires, ack.expiresAt)
        reject { parseGatewayDispatchArmV2(request, device, armPayload(), armed(), expires.minusNanos(1000), now) }
        for ((name, value) in listOf("attempt_id" to target, "fence_version" to 8, "reservation_sha256" to "0".repeat(64),
            "request_id" to target, "device_id" to target, "replay" to true, "carrier_proof" to true, "body" to body)) {
            reject { parseGatewayDispatchArmV2(request, device, armPayload(), armed().put(name, value), expires, now) }
        }
        reject { validateGatewayDispatchResultV2("arm_dispatch", request, device, armPayload(), armed(), now) }
    }

    @Test fun multipartPlanRequiresContiguousGloballyDistinctCallbackIds() {
        for (badPlan in listOf(JSONArray(), JSONArray().put(plan(index = 1)), JSONArray().put(plan(sent = delivery)),
            JSONArray().put(plan(sent = request.uppercase())), JSONArray().put(plan(delivered = attempt.uppercase())),
            JSONArray().put(plan()).put(plan(1, sent = target, delivered = callback.uppercase())),
            JSONArray().put(plan().put("body", body)))) {
            reject { parseGatewayDispatchArmV2(request, device, armPayload().put("callbacks", badPlan), armed(), expires, now) }
        }
        val valid = armPayload().put("callbacks", JSONArray().put(plan()).put(plan(1, target, run)))
        assertNotNull(parseGatewayDispatchArmV2(request, device, valid, armed(), expires, now))
    }

    @Test fun normalizedUuidIdentityIsBoundWithoutChangingHashes() {
        val result = grant().put("device_id", device.uppercase()).put("attempt_id", attempt.uppercase())
        assertEquals(attempt, parseGatewayDispatchGrantV2(request.uppercase(), device.uppercase(), result, now)!!.grant.attemptId)
        val payload = armPayload().put("attempt_id", attempt.uppercase())
        assertNotNull(parseGatewayDispatchArmV2(request.uppercase(), device.uppercase(), payload, armed(), expires, now))
    }

    @Test fun sentSuccessRequiresAllSegmentsAndNoConflictWithNoDeliveryConclusion() {
        validate("callback", callbackPayload(), callbackResult())
        reject { validate("callback", callbackPayload(2), callbackResult()) }
        validate("callback", callbackPayload(2), callbackResult().put("sent_observations", 2))
        reject { validate("callback", callbackPayload(), callbackResult().put("conflicting_observations", true)) }
        validate("callback", callbackPayload(2), callbackResult().put("state", "uncertain").put("conflicting_observations", true))
        reject { validate("callback", callbackPayload(), callbackResult().put("carrier_proof", true)) }
        reject { validate("callback", callbackPayload(), callbackResult().put("delivery_observations", 2)) }
        reject { validate("callback", callbackPayload(), callbackResult().put("callback_id", target)) }
        reject { validate("callback", callbackPayload().put("callback_id", request), callbackResult().put("callback_id", request)) }
    }

    @Test fun statusRequiresExactAttemptFenceCountsAndNoArchiveAcknowledgement() {
        validate("attempt_status", statusPayload(), statusResult())
        validate("attempt_status", statusPayload(), statusResult().put("state", "granted").put("armed_at", JSONObject.NULL).put("sent_observations", 0))
        for ((name, value) in listOf("attempt_id" to target, "fence_version" to 8, "segment_count" to 2,
            "terminal_archive_ack" to true, "carrier_proof" to true, "conflicting_observations" to true,
            "body" to body, "sent_observations" to "1")) {
            reject { validate("attempt_status", statusPayload(), statusResult().put(name, value)) }
        }
    }

    @Test fun recordedLookupCannotRecoverGrantBodyOrArmPermit() {
        val payload = JSONObject().put("target_request_id", target)
        for (action in listOf("dispatch_grant", "arm_dispatch")) {
            val result = JSONObject().put("target_request_id", target).put("outcome", "recorded")
                .put("recorded_action", action).put("recorded_result", refusal(id = target))
            validate("reconcile", payload, result)
            val authority = if (action == "dispatch_grant") grant() else armed()
            reject { validate("reconcile", payload, result.put("recorded_result", authority.put("request_id", target))) }
            reject { validate("reconcile", payload, result.put("recorded_result", refusal(id = target).put("replay", false))) }
        }
    }

    @Test fun lookupValidatesNestedCallbacksStatusAndNullUnknownEvidence() {
        val payload = JSONObject().put("target_request_id", target)
        val result = JSONObject().put("target_request_id", target).put("outcome", "unknown")
            .put("recorded_action", JSONObject.NULL).put("recorded_result", JSONObject.NULL)
        validate("reconcile", payload, result)
        reject { validate("reconcile", payload, result.put("recorded_result", callbackResult())) }
        for ((action, nested) in listOf("callback" to callbackResult(), "attempt_status" to statusResult())) {
            result.put("outcome", "recorded").put("recorded_action", action).put("recorded_result", nested)
            validate("reconcile", payload, result)
            reject { validate("reconcile", payload, result.put("recorded_result", nested.put("body", body))) }
        }
    }

    @Test fun exactV2ResponseEnvelopeAndUtf8BoundRemainRequired() {
        val envelope = reply("dispatch_grant", grant())
        val bytes = envelope.toString().toByteArray(Charsets.UTF_8)
        assertEquals(2, parseGatewayDispatchReplyV2("dispatch_grant", request, device, JSONObject(), bytes, now).getInt("contract_version"))
        for ((name, value) in listOf("contract_version" to 1, "request_id" to target, "device_id" to target, "action" to "callback", "private" to body)) {
            reject { parseGatewayDispatchReplyV2("dispatch_grant", request, device, JSONObject(), reply("dispatch_grant", grant()).put(name, value).toString().toByteArray(), now) }
        }
        reject { parseGatewayDispatchReplyV2("dispatch_grant", request, device, JSONObject(), byteArrayOf(0xff.toByte()), now) }
        reject { parseGatewayDispatchReplyV2("dispatch_grant", request, device, JSONObject(), " ".repeat(8193).toByteArray(), now) }
        reject { parseGatewayDispatchReplyV2("dispatch_grant", request, device, JSONObject(), byteArrayOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte()) + bytes, now) }
        reject { parseGatewayDispatchReplyV2("heartbeat", request, device, JSONObject(), reply("heartbeat", grant()).toString().toByteArray(), now) }
    }

    @Test fun duplicateEscapedKeysAndPermissiveJsonExtensionsAreRejectedBeforeJsonObject() {
        val raw = reply("dispatch_grant", grant()).toString()
        for (bad in listOf(raw.replace("\"contract_version\":2", "\"contract_version\":2,\"contract_version\":2"),
            raw.replace("\"replay\":false", "\"replay\":false,\"re\\u0070lay\":false"),
            raw.replace("\"replay\":false", "'replay':false"), raw + "garbage", raw.replace("{", "{/*comment*/", true))) {
            reject { parseGatewayDispatchReplyV2("dispatch_grant", request, device, JSONObject(), bad.toByteArray(), now) }
        }
    }

    @Test fun lostArmReplyAndUnknownLookupNeverReturnAReusablePermit() {
        val payload = JSONObject().put("target_request_id", target)
        val unknown = JSONObject().put("target_request_id", target).put("outcome", "unknown")
            .put("recorded_action", JSONObject.NULL).put("recorded_result", JSONObject.NULL)
        validate("reconcile", payload, unknown)
        reject { parseGatewayDispatchArmV2(request, device, armPayload(), armed().put("replay", true), expires, now) }
        assertNull(parseGatewayDispatchArmV2(request, device, armPayload(), refusal(), expires, now))
    }
}
