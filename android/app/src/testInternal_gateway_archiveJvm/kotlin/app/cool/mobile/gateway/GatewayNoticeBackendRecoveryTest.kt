package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.cert.Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.HttpsURLConnection

/** Actual Engine/Store/HTTPS/signing serializers, declared synthetic server
 * adaptation of immutable SQL/Edge DTOs. No physical/network/SMS authority. */
class GatewayNoticeBackendRecoveryTest {
    private fun id() = UUID.randomUUID().toString()
    private fun observations() = GatewayObservations(true, true, true, true, true, true, true, 1, true)
    private fun failure(block: () -> Unit) {
        try { block(); fail("Expected durable refusal") } catch (_: GatewayStateException) { }
    }
    private fun template(action: String, code: String? = null, family: String? = null): JSONObject {
        val root = JSONObject(File(System.getProperty("collect.notice.fixtures"), "observed-signed-edge.json").readText())
        val entries = root.getJSONArray("entries")
        return (0 until entries.length()).map { entries.getJSONObject(it) }.first {
            it.getString("action") == action && it.getInt("status") == 200 &&
                (code == null || it.getJSONObject("response").getJSONObject("result").optString("code") == code) &&
                (family == null || it.getJSONObject("response").getJSONObject("result").getJSONObject("route").getString("notice_family") == family)
        }.getJSONObject("response").getJSONObject("result").let { JSONObject(it.toString()) }
    }
    private class TestContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    private inner class Fixture(val family: String = "duplicate_copy") {
        val root = Files.createTempDirectory("collect-notice-native-").toFile()
        val context = TestContext(root)
        val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) }
        val device = id(); val attempt = id()
        val route = GatewayDispatchRoute.ReceiptNoticeV1(id(), id(), id(), family)
        val sourceGrant = template("dispatch_grant", "NOTICE_GRANTED", family)
        val count = sourceGrant.getInt("segment_count")
        var admitted = true; var blockedPrimary = false; var blockedSuccessor = false
        var loseGrant = false; var loseArm = false; var loseArchive = false; var unknownLookup = false
        var swapArm = false; var failReservation = false; var conflictAtAck = false; var serverUncertain = false
        var stopAfterGrant = false; var staleArm = false; var extraGrant = false
        val requests = mutableListOf<JSONObject>(); val raw = mutableListOf<ByteArray>(); val endpoints = mutableListOf<String>()
        val results = linkedMapOf<String, JSONObject>()
        val sent = mutableSetOf<String>(); val delivery = mutableSetOf<String>()
        var expiry = Instant.now().plusSeconds(25)
        val store = GatewayEncryptedStore(context) { name -> crypto(name) }
        fun crypto(name: String) = GatewayCrypto(SecretKeySpec(ByteArray(32) { 19 }, "AES"), "CollectGateway/$name/v1")
        val backend: GatewaySignedBackend
        var forgedArm: GatewayDispatchArmAck? = null
        init {
            store.saveEnrollment(JSONObject().put("contract_version", 1).put("device_id", device).put("installation_id", id())
                .put("key_sha256", fingerprint).put("signing_certificate_sha256", "b".repeat(64)))
            val transport = GatewayHttpsTransport({ fingerprint }, { bytes -> Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run {
                initSign(key.private); update(bytes); sign()
            }) }, { url ->
                assertEquals(GatewayHttpsTransport.HOST, url.host); endpoints.add(url.path)
                object : HttpsURLConnection(url) {
                    val output = ByteArrayOutputStream(); var response: ByteArray? = null; var code = 200
                    override fun connect() = Unit
                    override fun disconnect() = Unit
                    override fun usingProxy() = false
                    override fun getCipherSuite() = "synthetic"
                    override fun getLocalCertificates(): Array<Certificate>? = null
                    override fun getServerCertificates(): Array<Certificate> = emptyArray()
                    override fun getOutputStream() = output
                    override fun getResponseCode(): Int {
                        val bytes = output.toByteArray()
                        assertTrue(Signature.getInstance("SHA256withECDSA").run {
                            initVerify(key.public); update(bytes); verify(Base64.getDecoder().decode(getRequestProperty("X-Collect-Gateway-Signature")))
                        })
                        assertEquals(fingerprint, getRequestProperty("X-Collect-Gateway-Key-Id")); assertNull(getRequestProperty("Authorization"))
                        assertFalse(instanceFollowRedirects); assertFalse(useCaches)
                        val envelope = JSONObject(String(bytes, Charsets.UTF_8)); requests.add(envelope); raw.add(bytes)
                        if (isNoticeEnvelope(envelope)) {
                            assertEquals("/functions/v1/collect-receipt-notice-gateway", url.path)
                            validateNoticeEnvelope(String(bytes, Charsets.UTF_8), envelope)
                            if (envelope.getString("action") in setOf("dispatch_grant", "arm_dispatch", "callback", "archive_attempt")) {
                                val original = store.readRetainedRequest(envelope.getString("request_id"))!!
                                assertEquals(sha256(String(bytes, Charsets.UTF_8)), original.digest)
                                assertArrayEquals(bytes, Base64.getDecoder().decode(original.row.getString("request_bytes_base64")))
                            }
                        }
                        if (isNoticeEnvelope(envelope) && envelope.getString("action") == "archive_attempt" && serverUncertain) {
                            code = 409; response = "{\"send_authority\":false}".toByteArray(); return code
                        }
                        val result = respond(envelope)
                        response = wrapper(envelope, result).toString().toByteArray()
                        return code
                    }
                    override fun getInputStream() = ByteArrayInputStream(response!!)
                }
            })
            backend = GatewaySignedBackend(context, store, GatewayDeviceIdentity(), { fingerprint }, transport, { admitted })
        }
        private fun wrapper(envelope: JSONObject, result: JSONObject): JSONObject = JSONObject().put("contract_version", envelope.getInt("contract_version"))
            .put("action", envelope.getString("action")).put("device_id", device).put("request_id", envelope.getString("request_id")).put("result", result).also {
                if (isNoticeEnvelope(envelope)) it.put("protocol_family", NOTICE_FAMILY).put("audience", NOTICE_AUDIENCE)
                else if (isSuccessorEnvelope(envelope)) it.put("protocol_family", SUCCESSOR_FAMILY).put("audience", SUCCESSOR_AUDIENCE)
            }
        private fun refusal(envelope: JSONObject, code: String): JSONObject = JSONObject().put("ok", false).put("code", code)
            .put("device_id", device).put("request_id", envelope.getString("request_id")).put("replay", code == "ORIGINAL_REQUEST_RECORDED").also {
                if (isNoticeEnvelope(envelope) || isSuccessorEnvelope(envelope)) it.put("contract_version", 1)
                    .put("protocol_family", if (isNoticeEnvelope(envelope)) NOTICE_FAMILY else SUCCESSOR_FAMILY)
                    .put("send_authority", false).put("carrier_proof", false).put("delivery_proven", false)
            }
        private fun respond(envelope: JSONObject): JSONObject {
            val action = envelope.getString("action"); val payload = envelope.getJSONObject("payload"); val requestId = envelope.getString("request_id")
            if (!isNoticeEnvelope(envelope)) return if (isSuccessorEnvelope(envelope)) {
                if (action == "dispatch_grant") refusal(envelope, if (blockedSuccessor) "OPERATIONS_PAUSED" else "NO_SUCCESSOR_INTENT")
                else {
                    val target = payload.getString("target_request_id"); val original = requests.first { it.getString("request_id") == target }
                    JSONObject().put("contract_version", 1).put("protocol_family", SUCCESSOR_FAMILY).put("target_request_id", target).put("outcome", "recorded")
                        .put("recorded_action", original.getString("action")).put("recorded_route", JSONObject.NULL)
                        .put("recorded_result", refusal(original, "NO_SUCCESSOR_INTENT")).put("send_authority", false).put("carrier_proof", false).put("delivery_proven", false)
                }
            } else when (action) {
                "heartbeat" -> JSONObject().put("observation_id", id()).put("ingested_at", gatewayWireTime(Instant.now())).put("replay", false).put("carrier_proof", false)
                "dispatch_grant" -> refusal(envelope, if (blockedPrimary) "OPERATIONS_PAUSED" else "NO_ELIGIBLE_RECEIPT")
                "reconcile" -> {
                    val target = payload.getString("target_request_id"); val original = requests.first { it.getString("request_id") == target }
                    JSONObject().put("target_request_id", target).put("outcome", "recorded").put("recorded_action", original.getString("action"))
                        .put("recorded_result", refusal(original, "ORIGINAL_REQUEST_RECORDED"))
                }
                else -> error("Unexpected original protocol action")
            }
            val result = when (action) {
                // Current SQL will never grant this already materialized,
                // armed uncertain job again. Eligibility polling for other
                // work remains legitimate and receives this closed refusal.
                "dispatch_grant" -> if (serverUncertain) refusal(envelope, "NO_ELIGIBLE_NOTICE") else JSONObject(sourceGrant.toString()).put("device_id", device).put("request_id", requestId).put("route", noticeRouteJson(route))
                    .put("attempt_id", attempt).put("issued_at", gatewayWireTime(Instant.now())).put("expires_at", gatewayWireTime(expiry))
                    .put("sim_revision_sha256", sha256("android-subscription-selection:1")).also { if (extraGrant) it.put("body_override", "caller") }
                "arm_dispatch" -> template("arm_dispatch", "NOTICE_ARMED").put("device_id", device).put("request_id", requestId)
                    .put("route", noticeRouteJson(if (swapArm) route.copy(approvalId = id()) else route)).put("attempt_id", attempt)
                    .put("fence_version", payload.getLong("fence_version")).put("body_sha256", payload.getString("body_sha256"))
                    .put("destination_sha256", payload.getString("destination_sha256")).put("segment_count", payload.getJSONArray("callbacks").length())
                    .put("reservation_sha256", payload.getString("reservation_sha256")).put("armed_at", gatewayWireTime(Instant.now()))
                    .put("invoke_before", gatewayWireTime(if (staleArm) Instant.now().minusMillis(1) else minOf(Instant.now().plusSeconds(14), expiry)))
                "callback" -> {
                    if (payload.getInt("result_code") != -1) serverUncertain = true
                    if (payload.getString("callback_kind") == "sent") sent.add(payload.getString("callback_id")) else delivery.add(payload.getString("callback_id"))
                    template("callback").put("device_id", device).put("request_id", requestId).put("route", noticeRouteJson(route)).put("attempt_id", attempt)
                        .put("callback_id", payload.getString("callback_id")).put("segment_count", count).put("sent_observations", sent.size).put("delivery_observations", delivery.size)
                        .put("failed_sent", serverUncertain).put("failed_delivery", false).put("conflicting_observations", serverUncertain)
                        .put("state", if (serverUncertain) "uncertain" else if (sent.size == count) "observed_sent" else "send_started")
                        .put("terminal_archive_ack", false).put("delivery_callback_gap", false).put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false)
                }
                "archive_attempt" -> template("archive_attempt", "NOTICE_ARCHIVED").put("device_id", device).put("request_id", requestId)
                    .put("route", noticeRouteJson(route)).put("attempt_id", attempt).put("acknowledgement_id", id()).put("recorded_at", gatewayWireTime(Instant.now()))
                "reconcile" -> {
                    val target = payload.getString("target_request_id"); val original = requests.first { it.getString("request_id") == target }
                    val found = results[target]; val unknown = unknownLookup || found == null
                    val recorded = if (original.getString("action") in setOf("dispatch_grant", "arm_dispatch")) refusal(original, "ORIGINAL_REQUEST_RECORDED") else found
                    JSONObject().put("contract_version", 1).put("protocol_family", NOTICE_FAMILY).put("target_request_id", target)
                        .put("outcome", if (unknown) "unknown" else "recorded").put("recorded_action", if (unknown) JSONObject.NULL else original.getString("action"))
                        .put("recorded_result", if (unknown) JSONObject.NULL else recorded).put("send_authority", false)
                }
                else -> error("Unexpected notice action")
            }
            if (action != "reconcile") results[requestId] = JSONObject(result.toString())
            if (action == "dispatch_grant" && failReservation) AtomicFileFaults.failFileOnce = "journal.bin"
            if (action == "dispatch_grant" && stopAfterGrant) admitted = false
            if (action == "archive_attempt" && conflictAtAck) {
                conflictAtAck = false; val current = store.read().attempts.single()
                GatewayJournal(store).record(GatewayCallback(current.segments[0].sentCallbackId, device, attempt, current.fence, 0,
                    current.callbackNonce, CallbackKind.SENT, 1, gatewayWireTime(Instant.now())))
            }
            if (action == "dispatch_grant" && loseGrant || action == "arm_dispatch" && loseArm || action == "archive_attempt" && loseArchive) throw java.io.IOException("Synthetic response lost after server recording")
            return result
        }
        fun dispatch(forgeArmRoute: Boolean = false, counter: () -> Unit): GatewayAttempt? {
            GatewayJournal(store).resume()
            // The real signed producer first validates and durably retains its
            // correct arm; a hostile interface adapter changes only the route.
            // Every other ACK/grant/record field remains valid. This isolates
            // the generic Engine invariant from the trusted producer check.
            val source = if (!forgeArmRoute) backend else object : GatewayBackend {
                override fun heartbeat(observations: GatewayObservations) = backend.heartbeat(observations)
                override fun dispatchGrant(observations: GatewayObservations) = backend.dispatchGrant(observations)
                override fun supportsPolicyDispatch() = backend.supportsPolicyDispatch()
                override fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck? =
                    backend.armDispatch(grant, reservation)?.copy(dispatchRoute = route.copy(approvalId = id())).also { forgedArm = it }
                override fun reconcile(journal: GatewayJournalState) = backend.reconcile(journal)
            }
            return GatewayDispatchEngine(GatewayJournal(store), source, object : GatewaySmsInvoker {
                override fun divide(body: String, subscriptionId: Int) = if (body.length <= 160) listOf(body) else body.chunked(153)
                override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
                    assertEquals(route, record.dispatchRoute); assertEquals(record, store.read().attempts.single())
                    assertEquals(grant.body, parts.joinToString("")); assertEquals(count, parts.size); counter()
                }
            }, ::observations).dispatchOne()
        }
        fun observe(attempt: GatewayAttempt) {
            for ((index, segment) in attempt.segments.withIndex()) for (kind in CallbackKind.entries) {
                assertTrue(GatewayJournal(store).record(GatewayCallback(if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId,
                    attempt.deviceId, attempt.attemptId, attempt.fence, index, attempt.callbackNonce, kind, -1, gatewayWireTime(Instant.now()))))
            }
        }
        fun flush() { repeat(16) { if (store.read().attempts.isNotEmpty()) backend.reconcile(store.read()) } }
        fun archive(counter: () -> Unit): GatewayAttempt {
            val attempt = dispatch(counter = counter)!!; observe(attempt); val observed = store.read().attempts.single(); flush(); return observed
        }
        fun close() { AtomicFileFaults.failFinishOnce = false; AtomicFileFaults.failFileOnce = null; root.deleteRecursively() }
    }
    private fun test(family: String = "duplicate_copy", block: (Fixture) -> Unit) { val fixture = Fixture(family); try { block(fixture) } finally { fixture.close() } }
    @Test fun originalOrSuccessorPolicyRefusalDoesNotPollNotices() {
        test { f -> f.blockedPrimary = true; assertNull(f.dispatch { fail("No invocation") }); assertFalse(f.requests.any(::isNoticeEnvelope)) }
        test { f -> f.blockedSuccessor = true; assertNull(f.dispatch { fail("No invocation") }); assertFalse(f.requests.any(::isNoticeEnvelope)) }
    }
    @Test fun lostGrantUsesOriginalUuidAndNeverRepeatsMutation() = test { f ->
        f.loseGrant = true; failure { f.dispatch { fail("No invocation") } }; val original = f.requests.last().getString("request_id")
        f.unknownLookup = true; repeat(3) { failure { f.dispatch { fail("No invocation") } }; f.backend.reconcile(f.store.read()) }
        assertEquals(1, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "dispatch_grant" })
        assertTrue(f.requests.any { isNoticeEnvelope(it) && it.getString("action") == "reconcile" && it.getJSONObject("payload").getString("target_request_id") == original })
        assertNotNull(f.store.readRetainedRequest(original)); assertTrue(f.store.read().attempts.isEmpty())
    }
    @Test fun lostArchiveReadsSameOriginalUuidAndNeverRepeatsArchivalWrite() = test { f ->
        var invoked = 0; val attempt = f.dispatch { invoked++ }!!; f.observe(attempt); f.loseArchive = true
        failure { f.flush() }; val original = f.requests.single { isNoticeEnvelope(it) && it.getString("action") == "archive_attempt" }.getString("request_id")
        f.backend.reconcile(f.store.read()); f.flush(); assertEquals(1, invoked); assertNotNull(f.store.readColdAttempt(attempt.attemptId))
        assertEquals(1, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "archive_attempt" })
        assertTrue(f.requests.any { isNoticeEnvelope(it) && it.getString("action") == "reconcile" && it.getJSONObject("payload").getString("target_request_id") == original })
    }
    @Test fun serverUnknownCannotBeArchivedOrBlindlyRetriedAfterCompleteLocalCallbacks() = test { f ->
        var invokes = 0
        val attempt = f.dispatch { invokes++ }!!; f.observe(attempt); f.serverUncertain = true; failure { f.flush() }
        repeat(4) { f.backend.reconcile(f.store.read()) }
        assertNull(f.dispatch { fail("Unknown server outcome must not invoke again") })
        assertEquals(1, invokes)
        assertNull(f.store.readColdAttempt(attempt.attemptId)); assertEquals(1, f.store.read().attempts.size)
        assertEquals(1, f.results.values.count { it.optString("code") == "NOTICE_GRANTED" })
        assertEquals(2, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "dispatch_grant" })
        assertEquals(1, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "arm_dispatch" })
        assertEquals(1, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "archive_attempt" })
        assertNotNull(f.store.readRetainedRequest(f.requests.single { isNoticeEnvelope(it) && it.getString("action") == "archive_attempt" }.getString("request_id")))
    }
    @Test fun ackRaceAndLateContradictionRetainImmutableEvidenceAndStop() {
        test { f -> val attempt = f.dispatch {}!!; f.observe(attempt); f.conflictAtAck = true; f.flush(); assertNull(f.store.readColdAttempt(attempt.attemptId)); assertNotNull(f.store.readUncompactableAck(attempt.attemptId)); assertTrue(f.store.coldStop()) }
        test { f -> val attempt = f.archive {}; val old = f.store.readColdAttempt(attempt.attemptId)!!.toString()
            assertTrue(GatewayJournal(f.store).record(GatewayCallback(attempt.segments[0].sentCallbackId, attempt.deviceId, attempt.attemptId, attempt.fence, 0, attempt.callbackNonce, CallbackKind.SENT, 1, gatewayWireTime(Instant.now()))))
            f.backend.reconcile(f.store.read()); assertTrue(f.store.coldStop()); assertEquals(old, f.store.readColdAttempt(attempt.attemptId)!!.toString())
            assertTrue(f.requests.filter { it.getString("action") == "callback" }.all { isNoticeEnvelope(it) && noticeRouteFromJson(it.getJSONObject("payload").getJSONObject("route")) == f.route })
        }
    }
    @Test fun genericEngineRejectsNoticeArmRouteChangedAfterTrustedProducerValidation() = test { f ->
        var invokes = 0
        failure { f.dispatch(forgeArmRoute = true) { invokes++ } }
        val forged = f.forgedArm!!
        val record = f.store.read().attempts.single()
        assertEquals(0, invokes)
        assertEquals(record.attemptId, forged.attemptId); assertEquals(record.fence, forged.fence)
        assertEquals(gatewayReservationDigest(record), forged.reservationSha256)
        assertEquals(f.route, record.dispatchRoute); assertNotEquals(f.route, forged.dispatchRoute)
        assertNotNull(f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE, record.attemptId))
        assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, record.attemptId))
        val original = f.requests.single { isNoticeEnvelope(it) && it.getString("action") == "arm_dispatch" }
        val retained = f.store.readRetainedRequest(original.getString("request_id"))!!
        assertArrayEquals(f.raw[f.requests.indexOf(original)], Base64.getDecoder().decode(retained.row.getString("request_bytes_base64")))
        assertEquals(f.route, noticeRouteFromJson(original.getJSONObject("payload").getJSONObject("route")))
        assertEquals(1, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "arm_dispatch" })
    }
}
