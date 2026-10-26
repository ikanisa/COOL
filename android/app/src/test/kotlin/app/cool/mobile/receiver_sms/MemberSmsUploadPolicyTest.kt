package app.cool.mobile.receiver_sms

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MemberSmsUploadPolicyTest {
    private val owner = "11111111-1111-4111-8111-111111111111"
    private val other = "22222222-2222-4222-8222-222222222222"
    private val envelope = "33333333-3333-4333-8333-333333333333"
    private val rawId = "44444444-4444-4444-8444-444444444444"
    private fun session(sub: String = owner, exp: Long = 2000): String {
        val claims = JSONObject().put("sub", sub).put("session_id", "test-session")
            .put("iss", "collect-platform-api").put("aud", "collect").put("role", "authenticated").put("exp", exp)
        val encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(claims.toString().toByteArray())
        return JSONObject().put("access_token", "header.$encoded.signature").put("user", JSONObject().put("id", sub)).toString()
    }
    private fun token(value: String?, expected: String = owner): String? = MemberSmsUploadPolicy.token(value, expected, 1000) {
        String(java.util.Base64.getUrlDecoder().decode(it))
    }
    private fun row() = JSONObject().put("id", envelope).put("raw_body", " exact body é \n")
    private fun response() = JSONObject().put("ok", true).put("receipt", JSONObject()
        .put("contract_version", 2).put("stored", true).put("raw_sms_id", rawId)
        .put("owner_user_id", owner).put("client_envelope_id", envelope)
        .put("body_sha256", ReceiptAckPolicy.sha256(row().getString("raw_body"))))

    @Test fun ordinaryAppCaptureDoesNotRequireOperatorFlavor() {
        assertTrue(MomoGatewayPolicy.memberCaptureSupported("production"))
        assertTrue(MomoGatewayPolicy.memberCaptureSupported("dev"))
        assertFalse(MomoGatewayPolicy.memberCaptureSupported("internal_gateway"))
    }
    @Test fun storesIncomingOutgoingFailedAndReversalMessagesWithoutAReceiptTemplate() {
        for (body in listOf("You received 1500 RWF.", "Sent 3000 RWF. Txn 1234", "Transaction failed: 100 RWF", "Reversal 321: 200 UGX", "Wakiriye 600 RWF"))
            assertTrue(body, MomoGatewayPolicy.memberSource("M-Money", body))
    }
    @Test fun captureExcludesUnrelatedMessagesPromotionsAndOneTimeCodes() {
        assertFalse(MomoGatewayPolicy.memberSource("Courier", "Received 100 RWF ref 123"))
        assertFalse(MomoGatewayPolicy.memberSource("M-Money", "OTP verification code 123456 for transaction 100 RWF"))
        assertFalse(MomoGatewayPolicy.memberSource("MTN MoMo", "Promotion: buy a bundle for 1000 RWF"))
        assertFalse(MomoGatewayPolicy.memberSource("M-Money", "Your PIN is 1234 for 1000 RWF"))
        assertFalse(MomoGatewayPolicy.memberSource("M-Money", "Hello"))
    }
    @Test fun backgroundDrainUsesOnlyCurrentOwnerUnexpiredSession() {
        assertNotNull(token(session()))
        assertNull(token(session(), other))
        assertNull(token(session(exp = 1000)))
        assertNull(token(session(exp = 1030)))
        assertNull(token(null))
        assertNull(token("malformed"))
    }
    @Test fun supabaseIdentityMapsToStableCaptureOwnerOnlyForTheConfiguredIssuer() {
        val issuer = "https://rrlduytparvsjfmegalh.supabase.co/auth/v1"
        val claims = JSONObject().put("sub", other).put("session_id", "test-session")
            .put("iss", issuer).put("aud", "authenticated").put("role", "authenticated").put("exp", 2000)
        val encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(claims.toString().toByteArray())
        val value = JSONObject().put("access_token", "header.$encoded.signature")
            .put("user", JSONObject().put("id", owner).put("auth_user_id", other)).toString()
        fun checked(expectedIssuer: String, mapped: Boolean) = MemberSmsUploadPolicy.token(value, owner, 1000,
            expectedIssuer = expectedIssuer, expectedAudience = "authenticated", allowMappedAuthUser = mapped) {
            String(java.util.Base64.getUrlDecoder().decode(it))
        }
        assertNotNull(checked(issuer, true))
        assertNull(checked("https://foreign.invalid/auth/v1", true))
        assertNull(checked(issuer, false))
        assertNull(token(value))
    }
    @Test fun acknowledgementRequiresExactOwnerEnvelopeBodyAndDurableContract() {
        assertEquals(mapOf(envelope to ReceiptAckPolicy.sha256(row().getString("raw_body"))), MemberSmsUploadPolicy.acknowledgement(response(), owner, row()))
        for ((field, value) in listOf("owner_user_id" to other, "client_envelope_id" to other, "body_sha256" to "0".repeat(64), "raw_sms_id" to "missing", "contract_version" to 1, "stored" to false)) {
            val changed = response();changed.getJSONObject("receipt").put(field, value)
            assertNull(field, MemberSmsUploadPolicy.acknowledgement(changed, owner, row()))
        }
    }
    @Test fun flutterProjectionRetainsCompletenessAndReviewWithoutInferringSuccess() {
        val source = row().put("owner_user_id", owner).put("raw_sender", " M-Money ")
            .put("received_at_device", "2026-10-19T08:00:00Z").put("completeness", "incomplete").put("needs_review", true)
        val value = MemberSmsUploadPolicy.flutterEnvelope(source)
        assertEquals("incomplete", value["completeness"])
        assertEquals("true", value["needs_review"])
        assertEquals(" M-Money ", value["raw_sender"])
        assertEquals(source.getString("raw_body"), value["raw_body"])
        assertEquals("incomplete", MemberSmsUploadPolicy.flutterEnvelope(row())["completeness"])
    }
    @Test fun parkedOriginalsDoNotBlockLaterSourcesOrTriggerEndlessDrain() {
        val parked = row().put("needs_review", true)
        assertFalse(MemberSmsUploadPolicy.hasUploadable(listOf(parked)))
        assertTrue(MemberSmsUploadPolicy.hasUploadable(listOf(parked, row())))
        for (status in listOf(400, 409, 413, 422)) assertTrue(MemberSmsUploadPolicy.permanentSourceError(status))
        for (status in listOf(401, 403, 404, 408, 429, 503)) assertFalse(MemberSmsUploadPolicy.permanentSourceError(status))
    }
    @Test fun reviewAndRetryNeverChangeTheOriginalEvidenceFields() {
        val source = row().put("owner_user_id", owner).put("raw_sender", " M-Money ")
            .put("received_at_device", "2026-10-19T08:00:00Z").put("completeness", "incomplete")
        val originals = source.keys().asSequence().associateWith { source.get(it) }
        MemberSmsUploadPolicy.park(source, 413)
        assertTrue(source.getBoolean("needs_review"))
        for ((key, value) in originals) assertEquals(key, value, source.get(key))
        MemberSmsUploadPolicy.retry(source)
        assertFalse(source.has("needs_review"))
        assertFalse(source.has("upload_error_status"))
        for ((key, value) in originals) assertEquals(key, value, source.get(key))
    }
    @Test fun captureIdentityPreservesOriginalSenderWhitespace() {
        val receiver = CollectSmsReceiver()
        assertNotEquals(receiver.envelopeIdFor(owner, "M-Money", "received100RWF", 1000),
            receiver.envelopeIdFor(owner, " M-Money ", "received100RWF", 1000))
    }
    @Test fun exactTombstoneMakesConcurrentForegroundAndBackgroundAcknowledgementIdempotent() {
        val hashes = mapOf(envelope to ReceiptAckPolicy.sha256("exact source"))
        assertTrue(ReceiptAckPolicy.canAcknowledge(owner, owner, hashes, emptyList(), hashes))
        assertTrue(ReceiptAckPolicy.canAcknowledge(owner, owner, hashes,
            listOf(ReceiptAckPolicy.Envelope(envelope, owner, "exact source")), hashes))
    }
    @Test fun tombstoneCannotAcknowledgeAnotherOwnerUnknownIdOrChangedBody() {
        val hashes = mapOf(envelope to ReceiptAckPolicy.sha256("exact source"))
        assertFalse(ReceiptAckPolicy.canAcknowledge(owner, other, hashes, emptyList(), hashes))
        assertFalse(ReceiptAckPolicy.canAcknowledge(owner, owner, hashes, emptyList(), emptyMap()))
        assertFalse(ReceiptAckPolicy.canAcknowledge(owner, owner, hashes, emptyList(), mapOf(envelope to "0".repeat(64))))
        assertFalse(ReceiptAckPolicy.canAcknowledge(owner, owner, hashes,
            listOf(ReceiptAckPolicy.Envelope(envelope, owner, "changed source")), hashes))
    }
    @Test fun bodyWhitespaceRemainsPartOfAcknowledgementIdentity() {
        assertNull(MemberSmsUploadPolicy.acknowledgement(response(), owner, row().put("raw_body", "exact body é")))
    }
}
