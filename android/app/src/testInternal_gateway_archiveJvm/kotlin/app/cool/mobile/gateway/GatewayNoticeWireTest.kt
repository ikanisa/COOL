package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.Instant
import java.util.UUID

/** Exact retained signed Edge + real SQL observations. No live sender or key. */
class GatewayNoticeWireTest {
    private fun entries(): List<JSONObject> {
        val fixture = JSONObject(File(System.getProperty("collect.notice.fixtures"), "observed-signed-edge.json").readText())
        assertTrue(fixture.getBoolean("actual_sql_sdk_observations"))
        assertFalse(fixture.getBoolean("physical_sender"))
        val rows = fixture.getJSONArray("entries")
        return (0 until rows.length()).map { rows.getJSONObject(it) }
    }
    private fun grant(): JSONObject = entries().first {
        it.getString("action") == "dispatch_grant" && it.getJSONObject("response").getJSONObject("result").optString("code") == "NOTICE_GRANTED"
    }
    private fun arm(): JSONObject = entries().first { it.getString("action") == "arm_dispatch" && it.getJSONObject("response").getJSONObject("result").optString("code") == "NOTICE_ARMED" }
    private fun callback(): JSONObject = entries().first { it.getString("action") == "callback" }
    private fun id() = UUID.randomUUID().toString()
    private fun failure(block: () -> Unit) {
        try { block(); fail("Strict notice decoder must refuse") } catch (_: GatewayStateException) { }
    }
    private fun inspect(entry: JSONObject, changed: JSONObject = entry.getJSONObject("response"), now: Instant? = null) {
        val action = entry.getString("action"); val result = entry.getJSONObject("response").getJSONObject("result")
        val clock = now ?: when (action) {
            "dispatch_grant" -> if (result.has("issued_at")) Instant.parse(result.getString("issued_at")) else Instant.EPOCH
            "arm_dispatch" -> if (result.has("armed_at")) Instant.parse(result.getString("armed_at")) else Instant.EPOCH
            else -> Instant.EPOCH
        }
        val expiry = if (action == "arm_dispatch") clock.plusSeconds(30) else null
        parseNoticeReply(action, entry.getString("request_id"), entry.getJSONObject("response").getString("device_id"),
            entry.getJSONObject("payload"), changed.toString().toByteArray(), clock, expiry)
    }
    @Test fun everyActualSuccessEdgeSqlObservationPassesStrictNativeDecoder() {
        val rows = entries(); assertEquals(32, rows.size)
        val successful = rows.filter { it.getInt("status") == 200 }; assertEquals(31, successful.size)
        successful.forEach { inspect(it) }
        assertEquals(setOf("dispatch_grant", "arm_dispatch", "callback", "reconcile", "attempt_status", "archive_attempt"), successful.map { it.getString("action") }.toSet())
    }
    @Test fun bothGrantFamiliesDeriveImmutableBodyDestinationAndThreeRevisions() {
        val values = entries().filter { it.getString("action") == "dispatch_grant" && it.getJSONObject("response").getJSONObject("result").optString("code") == "NOTICE_GRANTED" }
        val families = values.map {
            val result = it.getJSONObject("response").getJSONObject("result")
            val lease = parseNoticeGrant(it.getString("request_id"), result.getString("device_id"), result, Instant.parse(result.getString("issued_at")))!!
            assertEquals(lease.grant.bodySha256, sha256(lease.grant.body)); assertEquals(lease.grant.destinationSha256, sha256(lease.grant.destinationE164))
            assertTrue(lease.operationsPolicyRevision > 0); assertTrue(lease.noticePolicyRevision > 0); assertTrue(lease.configurationRevision > 0)
            assertFalse(result.getBoolean("send_authority")); (lease.grant.dispatchRoute as GatewayDispatchRoute.ReceiptNoticeV1).noticeFamily
        }.toSet()
        assertEquals(setOf("duplicate_copy", "reversal_notice"), families)
    }
    @Test fun freshFirstArmAloneCarriesFifteenSecondInvocationDeadline() {
        val entry = arm(); val result = entry.getJSONObject("response").getJSONObject("result"); val now = Instant.parse(result.getString("armed_at"))
        val ack = parseNoticeArm(entry.getString("request_id"), result.getString("device_id"), entry.getJSONObject("payload"), result, now.plusSeconds(30), now)!!
        assertTrue(ack.expiresAt <= now.plusSeconds(15)); assertEquals(noticeRouteFromJson(result.getJSONObject("route")), ack.dispatchRoute)
        entries().filter { it.getString("action") in setOf("dispatch_grant", "arm_dispatch") && it.getJSONObject("response").optJSONObject("result")?.optString("code") == "ORIGINAL_REQUEST_RECORDED" }.forEach {
            assertFalse(it.getJSONObject("response").getJSONObject("result").getBoolean("send_authority")); inspect(it)
        }
    }
    @Test fun lostArmReconciliationCannotReturnFreshAuthorityOrSensitiveBody() {
        val entry = entries().first { it.getString("action") == "reconcile" }; inspect(entry)
        val bad = JSONObject(entry.getJSONObject("response").toString()); bad.getJSONObject("result").getJSONObject("recorded_result").put("send_authority", true)
        failure { inspect(entry, bad) }
        bad.getJSONObject("result").getJSONObject("recorded_result").put("send_authority", false).put("body", "injected")
        failure { inspect(entry, bad) }
    }
    @Test fun committedLateCallbacksAndStatusKeepStickyUncertainty() {
        val rows = entries().filter { it.getString("action") in setOf("callback", "attempt_status") && it.getJSONObject("response").getJSONObject("result").getJSONObject("route").getString("notice_family") == "reversal_notice" }
        assertTrue(rows.size > 2)
        rows.forEach { inspect(it); assertEquals("uncertain", it.getJSONObject("response").getJSONObject("result").getString("state")) }
        val denial = entries().single { it.getInt("status") == 409 }; assertEquals("archive_attempt", denial.getString("action"))
        assertFalse(denial.getJSONObject("response").getBoolean("send_authority"))
    }
    @Test fun nativeRefusesSwappedRouteFamilyRootJobAndApproval() {
        val entry = arm()
        for (key in listOf("primary_receipt_id", "notice_job_id", "notice_approval_id", "notice_family")) {
            val bad = JSONObject(entry.getJSONObject("response").toString()); val route = bad.getJSONObject("result").getJSONObject("route")
            route.put(key, if (key == "notice_family") "reversal_notice" else id()); failure { inspect(entry, bad) }
        }
        for (family in listOf("retry_uninvoked", "approved_resend", "correction")) {
            val route = JSONObject(grant().getJSONObject("response").getJSONObject("result").getJSONObject("route").toString()).put("notice_family", family)
            failure { noticeRouteFromJson(route) }
        }
    }
    @Test fun rejectsOldEnvelopeAndExtraNestedKeys() {
        val entry = grant()
        for (key in listOf("protocol_family", "audience", "contract_version")) {
            val bad = JSONObject(entry.getJSONObject("response").toString()).put(key, when (key) { "protocol_family" -> SUCCESSOR_FAMILY; "audience" -> SUCCESSOR_AUDIENCE; else -> 2 })
            failure { inspect(entry, bad) }
        }
        val extra = JSONObject(entry.getJSONObject("response").toString()); extra.getJSONObject("result").put("receipt_id", id()); failure { inspect(entry, extra) }
        extra.getJSONObject("result").remove("receipt_id"); extra.getJSONObject("result").getJSONObject("route").put("dispatch_job_id", id()); failure { inspect(entry, extra) }
    }
    @Test fun expiredGrantAndArmAndInvalidCurrentHashesNeverAuthorize() {
        val entry = grant(); val result = entry.getJSONObject("response").getJSONObject("result")
        failure { inspect(entry, now = Instant.parse(result.getString("expires_at"))) }
        for (key in listOf("body_sha256", "destination_sha256", "sim_revision_sha256", "operations_policy_revision", "notice_policy_revision", "configuration_revision", "segment_count", "body")) {
            val bad = JSONObject(entry.getJSONObject("response").toString()); bad.getJSONObject("result").put(key, when {
                key == "body" -> "unsafe\ntext"; key.endsWith("sha256") -> "e".repeat(63); else -> 0
            }); failure { inspect(entry, bad) }
        }
        val arm = arm(); failure { inspect(arm, now = Instant.parse(arm.getJSONObject("response").getJSONObject("result").getString("invoke_before"))) }
    }
    @Test fun payloadRejectsCallerContentAndCollidingCallbackPlan() {
        failure { validateNoticePayload("dispatch_grant", id(), JSONObject().put("destination_e164", "+250788000000")) }
        val entry = arm(); val source = JSONObject(entry.getJSONObject("payload").toString())
        failure { validateNoticePayload("arm_dispatch", entry.getString("request_id"), JSONObject(source.toString()).put("body", "caller")) }
        val plan = source.getJSONArray("callbacks"); val first = plan.getJSONObject(0)
        for (key in listOf("primary_receipt_id", "notice_job_id", "notice_approval_id")) {
            val value = JSONObject(source.toString()); value.getJSONArray("callbacks").getJSONObject(0).put("sent_callback_id", value.getJSONObject("route").getString(key))
            failure { validateNoticePayload("arm_dispatch", entry.getString("request_id"), value) }
        }
        first.put("delivery_callback_id", first.getString("sent_callback_id")); failure { validateNoticePayload("arm_dispatch", entry.getString("request_id"), source) }
    }
    @Test fun callbacksRemainEvidenceAndCannotForgeObservedSentOrDeliveryProof() {
        val entry = callback()
        for (key in listOf("send_authority", "carrier_proof", "delivery_proven")) {
            val bad = JSONObject(entry.getJSONObject("response").toString()); bad.getJSONObject("result").put(key, true); failure { inspect(entry, bad) }
        }
        val uncertain = entries().first { it.getString("action") == "callback" && it.getJSONObject("response").getJSONObject("result").getString("state") == "uncertain" }
        val bad = JSONObject(uncertain.getJSONObject("response").toString()); bad.getJSONObject("result").put("state", "observed_sent"); failure { inspect(uncertain, bad) }
    }
    @Test fun exactTerminalCustodyAckCannotMoveToAnotherOriginalRequest() {
        val entry = entries().first { it.getString("action") == "archive_attempt" && it.getInt("status") == 200 }; inspect(entry)
        for (key in listOf("request_id", "attempt_id", "acknowledgement_id", "terminal_archive_ack", "send_authority")) {
            val bad = JSONObject(entry.getJSONObject("response").toString()); bad.getJSONObject("result").put(key, when (key) {
                "terminal_archive_ack" -> false; "send_authority" -> true; "acknowledgement_id" -> "not-uuid"; else -> id()
            }); failure { inspect(entry, bad) }
        }
    }
    @Test fun parserRejectsDuplicateKeysUtf8BomAndOversizedReplies() {
        val entry = grant(); val reply = entry.getJSONObject("response"); val device = reply.getString("device_id")
        val now = Instant.parse(reply.getJSONObject("result").getString("issued_at")); val original = reply.toString()
        for (bytes in listOf(("{\"contract_version\":1," + original.substring(1)).toByteArray(), byteArrayOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte()) + original.toByteArray(), byteArrayOf(0xc3.toByte(), 0x28), ByteArray(8193))) {
            failure { parseNoticeReply("dispatch_grant", entry.getString("request_id"), device, entry.getJSONObject("payload"), bytes, now) }
        }
    }
    @Test fun originalEnvelopeRetainsExactEightKeysWithoutCallerAuthority() {
        val callback = callback(); val envelope = JSONObject().put("contract_version", 1).put("protocol_family", NOTICE_FAMILY).put("audience", NOTICE_AUDIENCE)
            .put("action", callback.getString("action")).put("device_id", callback.getJSONObject("response").getString("device_id"))
            .put("request_id", callback.getString("request_id")).put("issued_at", "2026-10-03T08:13:00.000Z").put("payload", callback.getJSONObject("payload"))
        validateNoticeEnvelope(envelope.toString(), envelope)
        failure { val extra = JSONObject(envelope.toString()).put("send_authority", true); validateNoticeEnvelope(extra.toString(), extra) }
    }
}
