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
import java.security.Signature
import java.security.cert.Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.HttpsURLConnection

/** Actual Engine/Store/signed transport callers. Recorded SQL/Edge templates
 * remain untouched; in-memory UUID/time/SIM adaptation is synthetic runtime
 * evidence, never another SQL producer or device/carrier/hosted acceptance. */
class GatewayNoticeCustodyIntegrationTest {
    private fun id() = UUID.randomUUID().toString()
    private fun observations() = GatewayObservations(true, true, true, true, true, true, true, 1, true)
    private fun entries(): List<JSONObject> {
        val source = JSONObject(File(System.getProperty("collect.notice.fixtures"), "observed-signed-edge.json").readText())
        assertTrue(source.getBoolean("actual_sql_sdk_observations")); assertFalse(source.getBoolean("physical_sender"))
        return source.getJSONArray("entries").let { rows -> (0 until rows.length()).map { rows.getJSONObject(it) } }
    }
    private fun template(action: String, code: String): JSONObject = JSONObject(entries().first {
        it.getString("action") == action && it.getInt("status") == 200 && it.getJSONObject("response").getJSONObject("result").optString("code") == code
    }.getJSONObject("response").getJSONObject("result").toString())
    private fun refusal(action: () -> Unit) { try { action(); fail("Expected strict refusal") } catch (_: GatewayStateException) { } }
    private class LocalContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    private inner class Fixture(val businessFamily: String = "duplicate_copy") : AutoCloseable {
        val root = Files.createTempDirectory("collect-notice-custody-").toFile()
        val context = LocalContext(root)
        val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val fingerprint = java.security.MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) }
        val device = id(); val attempt = id(); val installation = id()
        val route = GatewayDispatchRoute.ReceiptNoticeV1(id(), id(), id(), businessFamily)
        val originalGrant = template("dispatch_grant", "NOTICE_GRANTED")
        val body = originalGrant.getString("body"); val destination = originalGrant.getString("destination_e164")
        val parts = if (body.length <= 160) listOf(body) else body.chunked(153)
        val store = GatewayEncryptedStore(context) { name -> crypto(name) }
        val requests = mutableListOf<JSONObject>(); val signed = mutableListOf<ByteArray>(); val raw = mutableListOf<ByteArray>(); val endpoints = mutableListOf<String>()
        val results = mutableMapOf<String, JSONObject>()
        var expiry = Instant.now().plusSeconds(25)
        var admitted = true; var loseArm = false; var unknownLookup = false; var pauseAtArm = false
        var expiredGrant = false; var expiredArm = false; var swapArm = false; var failEntered = false
        var invokes = 0; var noticesAvailable = true
        lateinit var transport: GatewayHttpsTransport
        val backend: GatewaySignedBackend
        fun crypto(name: String) = GatewayCrypto(SecretKeySpec(ByteArray(32) { 43 }, "AES"), "CollectGateway/$name/v1")
        fun backend(): GatewaySignedBackend = GatewaySignedBackend(context, store, GatewayDeviceIdentity(), { fingerprint }, transport, { admitted })
        init {
            store.saveEnrollment(JSONObject().put("contract_version", 1).put("device_id", device).put("installation_id", installation)
                .put("key_sha256", fingerprint).put("signing_certificate_sha256", "a".repeat(64)))
            transport = GatewayHttpsTransport({ fingerprint }, { bytes ->
                signed.add(bytes.clone()); Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run { initSign(key.private); update(bytes); sign() })
            }, { url ->
                assertEquals(GatewayHttpsTransport.HOST, url.host); endpoints.add(url.path)
                object : HttpsURLConnection(url) {
                    val output = ByteArrayOutputStream(); var response: ByteArray? = null
                    override fun connect() = Unit; override fun disconnect() = Unit; override fun usingProxy() = false
                    override fun getCipherSuite() = "synthetic"
                    override fun getLocalCertificates(): Array<Certificate>? = null
                    override fun getServerCertificates(): Array<Certificate> = emptyArray()
                    override fun getOutputStream() = output
                    override fun getResponseCode(): Int {
                        val bytes = output.toByteArray(); assertNull(getRequestProperty("Authorization"))
                        assertEquals(fingerprint, getRequestProperty("X-Collect-Gateway-Key-Id"))
                        assertTrue(Signature.getInstance("SHA256withECDSA").run { initVerify(key.public); update(bytes); verify(Base64.getDecoder().decode(getRequestProperty("X-Collect-Gateway-Signature"))) })
                        raw.add(bytes); val request = JSONObject(String(bytes, Charsets.UTF_8)); requests.add(request)
                        if (isNoticeEnvelope(request)) validateNoticeEnvelope(String(bytes, Charsets.UTF_8), request)
                        response = wrapper(request, respond(request)).toString().toByteArray(); return 200
                    }
                    override fun getInputStream() = ByteArrayInputStream(response!!)
                }
            })
            backend = backend()
        }
        private fun wrapper(e: JSONObject, value: JSONObject) = JSONObject().put("contract_version", e.getInt("contract_version"))
            .put("action", e.getString("action")).put("device_id", device).put("request_id", e.getString("request_id")).put("result", value)
            .also { if (isNoticeEnvelope(e)) it.put("protocol_family", NOTICE_FAMILY).put("audience", NOTICE_AUDIENCE)
                else if (isSuccessorEnvelope(e)) it.put("protocol_family", SUCCESSOR_FAMILY).put("audience", SUCCESSOR_AUDIENCE) }
        private fun denied(e: JSONObject, code: String): JSONObject = JSONObject().put("ok", false).put("code", code).put("device_id", device)
            .put("request_id", e.getString("request_id")).put("replay", code == "ORIGINAL_REQUEST_RECORDED").also {
                if (isNoticeEnvelope(e) || isSuccessorEnvelope(e)) it.put("contract_version", 1).put("protocol_family", if (isNoticeEnvelope(e)) NOTICE_FAMILY else SUCCESSOR_FAMILY)
                    .put("send_authority", false).put("carrier_proof", false).put("delivery_proven", false)
            }
        private fun respond(e: JSONObject): JSONObject {
            val action = e.getString("action"); val payload = e.getJSONObject("payload")
            if (!isNoticeEnvelope(e)) return when (action) {
                "heartbeat" -> JSONObject().put("observation_id", id()).put("ingested_at", gatewayWireTime(Instant.now())).put("replay", false).put("carrier_proof", false)
                "dispatch_grant" -> denied(e, if (isSuccessorEnvelope(e)) "NO_SUCCESSOR_INTENT" else "NO_ELIGIBLE_RECEIPT")
                "reconcile" -> {
                    val target = payload.getString("target_request_id"); val original = requests.first { it.getString("request_id") == target }
                    JSONObject().put("target_request_id", target).put("outcome", "recorded").put("recorded_action", original.getString("action")).put("recorded_result", denied(original, if (isSuccessorEnvelope(original)) "NO_SUCCESSOR_INTENT" else "ORIGINAL_REQUEST_RECORDED"))
                        .also { if (isSuccessorEnvelope(e)) it.put("contract_version", 1).put("protocol_family", SUCCESSOR_FAMILY).put("recorded_route", JSONObject.NULL)
                            .put("send_authority", false).put("carrier_proof", false).put("delivery_proven", false) }
                }
                else -> error("Unsupported predecessor action")
            }
            val result = when (action) {
                "dispatch_grant" -> if (!noticesAvailable) denied(e, "NO_ELIGIBLE_NOTICE") else JSONObject(originalGrant.toString())
                    .put("route", noticeRouteJson(route)).put("request_id", e.getString("request_id")).put("device_id", device).put("attempt_id", attempt)
                    .put("issued_at", gatewayWireTime(Instant.now())).put("expires_at", gatewayWireTime(if (expiredGrant) Instant.now().minusSeconds(1) else expiry))
                    .put("sim_revision_sha256", sha256("android-subscription-selection:1"))
                "arm_dispatch" -> template(action, "NOTICE_ARMED").put("route", noticeRouteJson(if (swapArm) route.copy(approvalId = id()) else route))
                    .put("request_id", e.getString("request_id")).put("device_id", device).put("attempt_id", attempt).put("body_sha256", sha256(body)).put("destination_sha256", sha256(destination))
                    .put("segment_count", parts.size).put("reservation_sha256", payload.getString("reservation_sha256"))
                    .put("armed_at", gatewayWireTime(Instant.now().minusSeconds(if (expiredArm) 2 else 0)))
                    .put("invoke_before", gatewayWireTime(if (expiredArm) Instant.now().minusSeconds(1) else Instant.now().plusSeconds(12)))
                "callback" -> template(action, "NOTICE_CALLBACK_RECORDED").put("route", noticeRouteJson(route)).put("device_id", device)
                    .put("request_id", e.getString("request_id")).put("callback_id", payload.getString("callback_id")).put("attempt_id", attempt)
                    .put("state", if (payload.getInt("result_code") == -1) "observed_sent" else "uncertain").put("segment_count", parts.size)
                    .put("sent_observations", parts.size).put("delivery_observations", parts.size).put("failed_sent", payload.getInt("result_code") != -1)
                    .put("conflicting_observations", payload.getInt("result_code") != -1).put("recorded_at", gatewayWireTime(Instant.now()))
                "archive_attempt" -> template(action, "NOTICE_ARCHIVED").put("route", noticeRouteJson(route)).put("device_id", device)
                    .put("request_id", e.getString("request_id")).put("attempt_id", attempt).put("recorded_at", gatewayWireTime(Instant.now()))
                "reconcile" -> {
                    val target = payload.getString("target_request_id"); val original = requests.first { it.getString("request_id") == target }
                    val recorded = if (original.getString("action") in setOf("dispatch_grant", "arm_dispatch")) denied(original, "ORIGINAL_REQUEST_RECORDED") else results[target] ?: error("Missing original")
                    JSONObject().put("contract_version", 1).put("protocol_family", NOTICE_FAMILY).put("target_request_id", target)
                        .put("outcome", if (unknownLookup) "unknown" else "recorded").put("recorded_action", if (unknownLookup) JSONObject.NULL else original.getString("action"))
                        .put("recorded_result", if (unknownLookup) JSONObject.NULL else recorded).put("send_authority", false)
                }
                else -> error("Unsupported notice synthetic action")
            }
            if (action != "reconcile") results[e.getString("request_id")] = JSONObject(result.toString())
            if (action == "arm_dispatch") {
                if (pauseAtArm) GatewayJournal(store).pause()
                if (failEntered) AtomicFileFaults.failFileOnce = "retention-invoke-terminal-${retentionUuidKey(attempt)}.bin"
                if (loseArm) throw java.io.IOException("Synthetic committed arm reply lost")
            }
            return result
        }
        fun journalVersion(): Int = JSONObject(String(crypto("journal").decrypt(File(root, "collect_gateway_v1/journal.bin").readBytes()), Charsets.UTF_8)).getInt("contract_version")
        fun dispatch(source: GatewaySignedBackend = backend): GatewayAttempt? {
            GatewayJournal(store).resume()
            return GatewayDispatchEngine(GatewayJournal(store), source, object : GatewaySmsInvoker {
                override fun divide(body: String, subscriptionId: Int) = parts
                override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
                    GatewayInvocationCustody(store).requireEntered(record); assertEquals(route, record.dispatchRoute)
                    assertEquals(record, store.read().attempts.single()); invokes++
                }
            }, ::observations).dispatchOne()
        }
        fun observe(record: GatewayAttempt) {
            for ((index, segment) in record.segments.withIndex()) for (kind in CallbackKind.entries)
                assertTrue(GatewayJournal(store).record(GatewayCallback(if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId,
                    device, attempt, record.fence, index, record.callbackNonce, kind, -1, gatewayWireTime(Instant.now()))))
        }
        fun archive(): GatewayAttempt {
            val record = dispatch()!!; observe(record); val observed = store.read().attempts.single()
            repeat(8) { backend.reconcile(store.read()) }; assertTrue(store.read().attempts.isEmpty()); return observed
        }
        override fun close() { AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failFinishOnce = false; root.deleteRecursively() }
    }
    private fun fixture(family: String = "duplicate_copy", action: (Fixture) -> Unit) { Fixture(family).use(action) }

    @Test fun actualSignedEngineJoinsDistinctNoticeRootJobApprovalFamilyAndEnteredBeforeInvoke() { fixture { f ->
        val record = f.dispatch()!!; assertEquals(1, f.invokes); assertEquals(f.route, f.store.retainedNoticeRoute(record.attemptId)); assertFalse(f.store.retainedAttemptUsesV2(record.attemptId))
        val binding = f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE, record.attemptId)!!.getJSONObject("binding")
        assertEquals("receipt_notice_v1", binding.getString("source_family")); assertEquals(f.route.primaryReceiptId, binding.getString("root_receipt_id")); assertEquals(f.route.noticeJobId, binding.getString("job_id"))
        assertTrue(archiveJsonEqual(noticeRouteJson(f.route), binding.getJSONObject("dispatch_route"))); assertEquals(gatewayReservationDigest(record), binding.getString("reservation_sha256"))
        assertEquals(f.installation, binding.getJSONObject("realm").getString("installation_id")); assertEquals("invoke_entered", f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, record.attemptId)!!.getString("phase"))
        assertEquals(record, f.store.read().attempts.single()); assertEquals(2, f.journalVersion())
        for (i in f.raw.indices) assertArrayEquals(f.raw[i], f.signed[i])
        f.requests.forEachIndexed { i, request -> if (isNoticeEnvelope(request)) assertEquals("/functions/v1/collect-receipt-notice-gateway", f.endpoints[i]) }
    } }
    @Test fun defaultDisabledNoticeAdmissionCannotReachItsEndpointOrInvoke() { fixture { f ->
        assertNull(f.dispatch(GatewaySignedBackend(f.context, f.store, GatewayDeviceIdentity(), { f.fingerprint }, f.transport))); assertEquals(0, f.invokes); assertFalse(f.requests.any(::isNoticeEnvelope))
    } }
    @Test fun firstNoticeHotVersionAndColdSevenArchivePreserveClosedSourceAndExactOriginals() { fixture { f ->
        val observed = f.archive(); assertEquals(1, f.invokes); val cold = f.store.readColdAttempt(observed.attemptId)!!
        assertEquals(7L, strictInteger(cold, "contract_version")); assertEquals(observed, archiveAttemptFromJson(cold.getJSONObject("attempt")))
        assertEquals("receipt_notice_v1", cold.getJSONObject("attempt").getString("record_kind")); assertEquals(f.route, f.store.retainedNoticeRoute(observed.attemptId))
        val original = GatewayStoredRequest.parse(cold.getJSONObject("archive_request")); requireSameRequest(original, f.store.readRetainedRequest(original.requestId)!!)
        assertFalse(cold.getJSONObject("acknowledgement").getBoolean("send_authority")); assertFalse(cold.getJSONObject("acknowledgement").getBoolean("delivery_proven"))
        GatewayInvocationCustody(f.store).validateRecord(observed.attemptId)
    } }
    @Test fun reversalNoticeUsesItsDistinctBusinessFamilyWithoutResendOrPrimaryConversion() { fixture("reversal_notice") { f ->
        val record = f.dispatch()!!; assertEquals("reversal_notice", (record.dispatchRoute as GatewayDispatchRoute.ReceiptNoticeV1).noticeFamily)
        assertFalse(f.store.retainedAttemptUsesV2(record.attemptId)); assertNull(f.store.retainedSuccessorRoute(record.attemptId)); assertEquals(1, f.invokes)
    } }
    @Test fun expiredNoticeGrantAndArmNeverReachInvocation() { fixture { f ->
        f.expiredGrant = true; refusal { f.dispatch() }; assertEquals(0, f.invokes); assertTrue(f.store.read().attempts.isEmpty())
    }; fixture { f -> f.expiredArm = true; refusal { f.dispatch() }; assertEquals(0, f.invokes); assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, f.attempt)) } }
    @Test fun swappedNoticeApprovalIsRejectedBeforeEnteredBarrier() { fixture { f ->
        f.swapArm = true; refusal { f.dispatch() }; assertEquals(0, f.invokes); assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, f.attempt))
    } }
    @Test fun failedEnteredPublicationAfterArmNeverInvokesAndPreservesOriginalArm() { fixture { f ->
        f.failEntered = true; refusal { f.dispatch() }; assertEquals(0, f.invokes)
        val arm = f.requests.single { isNoticeEnvelope(it) && it.getString("action") == "arm_dispatch" }
        assertEquals(arm.getString("request_id"), f.store.readRetainedRequest(arm.getString("request_id"))!!.requestId)
        assertNotNull(f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE, f.attempt)); assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, f.attempt))
    } }
    @Test fun pauseDuringNoticeArmHoldsUnknownUntilExplicitProspectiveAbort() { fixture { f ->
        f.pauseAtArm = true; refusal { f.dispatch() }; assertEquals(0, f.invokes)
        assertTrue(f.store.read().emergencyPaused); assertTrue(f.store.read().attempts.single().invocationException)
        assertNotNull(f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE, f.attempt))
        assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, f.attempt))
        GatewayJournal(f.store).abortUninvoked(f.attempt, "operator_stop")
        assertEquals("aborted_uninvoked", f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL, f.attempt)!!.getString("phase"))
        refusal { GatewayJournal(f.store).resume() }; assertEquals(0, f.invokes)
    } }
    @Test fun uncertainArmRestartLooksUpOriginalUuidWithoutReplayOrRecoveredSendAuthority() { fixture { f ->
        f.loseArm = true; refusal { f.dispatch() }; assertEquals(0, f.invokes)
        val arm = f.requests.single { isNoticeEnvelope(it) && it.getString("action") == "arm_dispatch" }; val original = f.store.readRetainedRequest(arm.getString("request_id"))!!
        f.unknownLookup = true; val recovered = f.backend(); repeat(6) { recovered.reconcile(f.store.read()) }
        requireSameRequest(original, f.store.readRetainedRequest(original.requestId)!!); assertNull(f.store.readRequestReceipt(original.requestId))
        assertEquals(1, f.requests.count { isNoticeEnvelope(it) && it.getString("action") == "arm_dispatch" }); assertEquals(0, f.invokes)
        assertTrue(f.requests.any { isNoticeEnvelope(it) && it.getString("action") == "reconcile" && it.getJSONObject("payload").getString("target_request_id") == original.requestId })
    } }
    @Test fun lateNoticeConflictKeepsOriginalFamilyPayloadAndDurableEvidenceAfterColdClosure() { fixture { f ->
        val observed = f.archive(); val callback = GatewayCallback(observed.segments[0].sentCallbackId, observed.deviceId, observed.attemptId, observed.fence, 0, observed.callbackNonce,
            CallbackKind.SENT, 1, gatewayWireTime(Instant.now()))
        assertTrue(GatewayJournal(f.store).record(callback)); assertTrue(f.store.coldStop())
        repeat(8) { f.backend.reconcile(f.store.read()) }
        val originals = f.requests.filter { isNoticeEnvelope(it) && it.getString("action") == "callback" && it.getJSONObject("payload").getInt("result_code") == 1 }
        assertEquals(1, originals.size); val payload = originals.single().getJSONObject("payload")
        assertTrue(archiveJsonEqual(noticeRouteJson(f.route), payload.getJSONObject("route"))); assertTrue(f.store.retainedLateCallbackPayload(payload))
        val request = f.store.readRetainedRequest(originals.single().getString("request_id"))!!; assertNotNull(f.store.readRequestReceipt(request.requestId))
        assertTrue(f.store.retainedCallbackRequest(callback.callbackId, payload, true)); assertEquals(f.route, f.store.retainedNoticeRoute(observed.attemptId)); assertEquals(1, f.invokes)
    } }
    @Test fun noticeOriginalUuidCannotBecomePrimaryOrSuccessorAndColdRecoveryStaysInactive() { fixture { f ->
        val observed = f.archive(); val cold = f.store.readColdAttempt(observed.attemptId)!!; val original = GatewayStoredRequest.parse(cold.getJSONObject("archive_request"))
        val altered = JSONObject(original.envelope.toString()).put("protocol_family", SUCCESSOR_FAMILY).put("audience", SUCCESSOR_AUDIENCE)
        val bytes = altered.toString().toByteArray(); val row = JSONObject(original.row.toString()).put("request_bytes_base64", Base64.getEncoder().encodeToString(bytes)).put("request_sha256", sha256(String(bytes)))
        refusal { f.store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray().put(row))) }; requireSameRequest(original, f.store.readRetainedRequest(original.requestId)!!)
        val before = File(f.root, "collect_gateway_v1").listFiles()!!.associate { it.name to it.readBytes() }
        val archive = f.store.exportRecovery(File(f.root, "archive")); val recovered = f.store.restoreRecovery(archive.directory, archive.manifestSha256, File(f.root, "restore"))
        assertTrue(recovered.keyValidated); assertTrue(recovered.requiresReEnrollment)
        for ((name, bytes0) in before) assertArrayEquals(name, bytes0, File(recovered.directory, "original/$name").readBytes())
        assertTrue(File(recovered.directory, "view/${GatewayRecovery.INACTIVE}").isFile); assertEquals(1, f.invokes)
    } }
    @Test fun ordinaryNoticeRequestsStayAt64AndCannotTakeLegacyOnlyMaintenanceSlot() { fixture { f ->
        fun row(action: String, payload: JSONObject): JSONObject {
            val request = id(); val envelope = JSONObject().put("contract_version", 1).put("protocol_family", NOTICE_FAMILY).put("audience", NOTICE_AUDIENCE)
                .put("device_id", f.device).put("request_id", request).put("action", action).put("issued_at", gatewayWireTime(Instant.now())).put("payload", payload)
            validateNoticeEnvelope(envelope.toString(), envelope); val bytes = envelope.toString().toByteArray()
            return JSONObject().put("request_id", request).put("action", action).put("state", "outcome_unknown").put("callback_id", JSONObject.NULL)
                .put("request_sha256", sha256(String(bytes))).put("request_bytes_base64", Base64.getEncoder().encodeToString(bytes))
        }
        val rows = JSONArray(); repeat(64) { rows.put(row("dispatch_grant", JSONObject())) }
        f.store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows)); assertEquals(64, f.store.readRequests().getJSONArray("requests").length())
        refusal { f.store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(rows.toString()).put(row("dispatch_grant", JSONObject())))) }
        val refs = JSONArray(); repeat(2) { refs.put(JSONObject().put("callback_id", id()).put("request_id", id()).put("request_sha256", "e".repeat(64))) }
        val archive = JSONObject().put("route", noticeRouteJson(f.route)).put("attempt_id", f.attempt).put("fence_version", 1)
            .put("body_sha256", sha256(f.body)).put("destination_sha256", sha256(f.destination)).put("callback_requests", refs)
        refusal { f.store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(rows.toString()).put(row("archive_attempt", archive)))) }
        assertEquals(64, f.store.readRequests().getJSONArray("requests").length()); assertEquals(0, f.invokes)
    } }
}
