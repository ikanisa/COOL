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
import java.net.URL
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

class GatewayAttemptArchiveBackendTest {
    private val device = "00000000-0000-0000-0000-000000000001"
    private fun observations() = GatewayObservations(true, true, true, true, true, true, true, 1, true)
    private data class Response(val status: Int, val bytes: ByteArray)
    private val attempt = "00000000-0000-0000-0000-000000000003"
    private val receipt = "00000000-0000-0000-0000-000000000002"
    private val body = "Synthetic recorded savings only."
    private val destination = "+250788000101"
    private var expiry = Instant.now().plusSeconds(25)
    private fun wrapper(request: JSONObject, result: JSONObject) = JSONObject().put("contract_version", request.getInt("contract_version"))
        .put("action", request.getString("action")).put("device_id", device).put("request_id", request.getString("request_id")).put("result", result)
    private fun recorded(request: JSONObject) = JSONObject().put("ok", false).put("code", "ORIGINAL_REQUEST_RECORDED")
        .put("device_id", device).put("request_id", request.getString("request_id")).put("replay", true)
    private fun respond(request: JSONObject): Response {
        val payload=request.getJSONObject("payload")
        val result=when(request.getString("action")) {
            "heartbeat" -> JSONObject().put("observation_id", UUID.randomUUID().toString()).put("ingested_at", gatewayWireTime(Instant.now())).put("replay", false).put("carrier_proof", false)
            "dispatch_grant" -> {
                expiry=Instant.now().plusSeconds(25)
                JSONObject().put("ok", true).put("code", "DISPATCH_GRANTED").put("device_id", device).put("request_id", request.getString("request_id"))
                    .put("attempt_id",attempt).put("receipt_id",receipt).put("run_id",UUID.randomUUID().toString()).put("fence_version",1).put("policy_revision",2)
                    .put("issued_at",gatewayWireTime(Instant.now())).put("expires_at",gatewayWireTime(expiry)).put("segment_count",1)
                    .put("body",body).put("destination_e164",destination).put("body_sha256",sha256(body)).put("destination_sha256",sha256(destination))
                    .put("sim_revision_sha256",sha256("android-subscription-selection:1")).put("replay",false)
            }
            "arm_dispatch" -> JSONObject().put("ok",true).put("code","DISPATCH_ARMED").put("device_id",device).put("request_id",request.getString("request_id"))
                .put("attempt_id",attempt).put("fence_version",1).put("reservation_sha256",payload.getString("reservation_sha256"))
                .put("armed_at",gatewayWireTime(Instant.now())).put("expires_at",gatewayWireTime(expiry)).put("replay",false).put("carrier_proof",false)
            else -> throw IllegalArgumentException("Synthetic unsupported operation")
        }
        return Response(200,wrapper(request,result).toString().toByteArray())
    }
    private class TestContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    private inner class Fixture(val respond: (JSONObject) -> Response) {
        val root = Files.createTempDirectory("collect-gateway-archive-backend-").toFile()
        val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) }
        val requests = mutableListOf<JSONObject>()
        val signed = mutableListOf<ByteArray>()
        val bytes = mutableListOf<ByteArray>()
        val context = TestContext(root)
        val storage = GatewayEncryptedStore(context) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 11 }, "AES"), "CollectGateway/$name/v1") }
        val backend: GatewaySignedBackend
        private val transport: GatewayHttpsTransport
        init {
            storage.saveEnrollment(JSONObject().put("contract_version", 1).put("device_id", device).put("installation_id", UUID.randomUUID().toString())
                .put("key_sha256", fingerprint).put("signing_certificate_sha256", "a".repeat(64)))
            transport = GatewayHttpsTransport({ fingerprint }, { body ->
                signed.add(body.clone())
                Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run { initSign(key.private); update(body); sign() })
            }, { url ->
                assertEquals(GatewayHttpsTransport.HOST, url.host)
                object : HttpsURLConnection(url) {
                    val output = ByteArrayOutputStream()
                    var response: Response? = null
                    override fun connect() = Unit
                    override fun disconnect() = Unit
                    override fun usingProxy() = false
                    override fun getCipherSuite() = "synthetic"
                    override fun getLocalCertificates(): Array<Certificate>? = null
                    override fun getServerCertificates(): Array<Certificate> = emptyArray()
                    override fun getOutputStream() = output
                    override fun getResponseCode(): Int {
                        val raw = output.toByteArray(); val request = JSONObject(String(raw, Charsets.UTF_8))
                        assertEquals(fingerprint, getRequestProperty("X-Collect-Gateway-Key-Id")); assertNull(getRequestProperty("Authorization"))
                        assertTrue(Signature.getInstance("SHA256withECDSA").run {
                            initVerify(key.public); update(raw); verify(Base64.getDecoder().decode(getRequestProperty("X-Collect-Gateway-Signature")))
                        })
                        bytes.add(raw); requests.add(request); response = respond(request); return response!!.status
                    }
                    override fun getInputStream() = ByteArrayInputStream(response!!.bytes)
                }
            })
            backend = GatewaySignedBackend(context, storage, GatewayDeviceIdentity(), { fingerprint }, transport)
        }
        fun recreatedBackend(offset: Int) = GatewaySignedBackend(context, storage, GatewayDeviceIdentity(), { fingerprint }, transport)
            .also { it.restoreReconciliationOffset(offset) }
        fun dispose() { AtomicFileFaults.failFinishOnce = false; root.deleteRecursively() }
    }
    private fun failClosed(block:()->Unit) {try {block(); fail("Expected failure")}catch(_:GatewayStateException){}}
    private fun sender(storage:GatewayEncryptedStore,counter:()->Unit)=object:GatewaySmsInvoker {
        override fun divide(body:String,subscriptionId:Int)=listOf(body)
        override fun invoke(grant:GatewayDispatchGrant,record:GatewayAttempt,parts:List<String>,subscriptionId:Int) {
            assertEquals(record,storage.read().attempts.single())
            assertTrue(storage.readRequests().getJSONArray("requests").toString().contains("arm_dispatch"))
            counter()
        }
    }

    private val acknowledged = mutableMapOf<String, JSONObject>()
    private var loseArchive = false
    private var lookupUnknown = false
    private var malformedArchive = false
    private var conflictBeforeArchiveReply = false
    private fun archiveResponse(f: Fixture, request: JSONObject): Response {
        val action = request.getString("action");val p = request.getJSONObject("payload")
        val result = when (action) {
            "reconcile" -> {
                val target = p.getString("target_request_id");val original = f.requests.first { it.getString("request_id") == target }
                val source = if (original.getString("action") == "callback") callbackResult(original) else recorded(original)
                JSONObject().put("target_request_id", target).put("outcome", "recorded").put("recorded_action", original.getString("action")).put("recorded_result", source)
            }
            "callback" -> callbackResult(request)
            "archive_attempt" -> {
                val ack = JSONObject().put("request_id", request.getString("request_id")).put("device_id", device)
                    .put("attempt_id", p.getString("attempt_id")).put("fence_version", p.getLong("fence_version"))
                    .put("ok", true).put("code", JSONObject.NULL).put("archive_ack_id", UUID.randomUUID().toString()).put("receipt_id", receipt)
                    .put("body_sha256", p.getString("body_sha256")).put("destination_sha256", p.getString("destination_sha256"))
                    .put("segment_count", 1).put("callback_requests", p.getJSONArray("callback_requests"))
                    .put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false)
                    .put("evidence_kind", "complete_framework_callback_observations").put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
                acknowledged[request.getString("request_id")] = JSONObject(ack.toString())
                if (conflictBeforeArchiveReply) {
                    conflictBeforeArchiveReply = false
                    val a = f.storage.read().attempts.single()
                    assertTrue(GatewayJournal(f.storage).record(GatewayCallback(a.segments[0].sentCallbackId, a.deviceId, a.attemptId, a.fence,
                        0, a.callbackNonce, CallbackKind.SENT, 1, gatewayWireTime(Instant.now()))))
                }
                if (loseArchive) throw java.io.IOException("Synthetic recorded ACK reply lost")
                if (malformedArchive) return Response(200, wrapper(request, ack).toString().replaceFirst("\"ok\":", "\"ok\":false,\"ok\":").toByteArray())
                ack
            }
            "archive_lookup" -> {
                val target = p.getString("target_request_id");val ack = if (lookupUnknown) null else acknowledged[target]
                JSONObject().put("target_request_id", target).put("outcome", if (ack == null) "unknown" else "recorded").put("recorded_result", ack ?: JSONObject.NULL)
            }
            else -> return respond(request)
        }
        return Response(200, wrapper(request, result).toString().toByteArray())
    }
    private fun callbackResult(request: JSONObject): JSONObject {
        val p = request.getJSONObject("payload");val conflict = p.getInt("result_code") != -1
        return JSONObject().put("callback_id", p.getString("callback_id")).put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false)
            .put("carrier_proof", false).put("state", if (conflict) "uncertain" else "observed_sent")
            .put("sent_observations", 1).put("delivery_observations", 1).put("conflicting_observations", conflict)
    }
    private fun fixture(): Fixture { lateinit var f: Fixture;f = Fixture { archiveResponse(f, it) };return f }
    private fun dispatched(f: Fixture, counter: () -> Unit): GatewayAttempt {
        GatewayJournal(f.storage).resume()
        return GatewayDispatchEngine(GatewayJournal(f.storage), f.backend, sender(f.storage, counter), ::observations).dispatchOne()!!
    }
    private fun observed(f: Fixture, a: GatewayAttempt) {
        for (kind in CallbackKind.entries) {
            val segment = a.segments[0]
            assertTrue(GatewayJournal(f.storage).record(GatewayCallback(if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId,
                a.deviceId, a.attemptId, a.fence, 0, a.callbackNonce, kind, -1, gatewayWireTime(Instant.now()))))
        }
    }
    @Test fun actualSignedBackendArchivesOnlyAfterBothDurableCallbackReplies() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);f.backend.reconcile(f.storage.read())
            assertEquals(1, invoked);assertEquals(2, f.requests.count { it.getString("action") == "callback" })
            assertEquals(1, f.requests.count { it.getString("action") == "archive_attempt" })
            assertTrue(f.storage.read().attempts.isEmpty());assertEquals(0, f.storage.readRequests().getJSONArray("requests").length())
            val cold = f.storage.readColdAttempt(a.attemptId)!!
            val original = GatewayStoredRequest.parse(cold.getJSONObject("archive_request"))
            val refs = original.envelope.getJSONObject("payload").getJSONArray("callback_requests")
            assertEquals(2, refs.length())
            for (i in 0 until refs.length()) {
                val r = refs.getJSONObject(i);val raw = f.bytes[f.requests.indexOfFirst { it.getString("request_id") == r.getString("request_id") }]
                assertEquals(r.getString("request_sha256"), sha256(String(raw, Charsets.UTF_8)))
            }
            assertFalse(cold.getJSONObject("acknowledgement").getBoolean("send_authority"))
        } finally { f.dispose() }
    }
    @Test fun lostArchiveReplyUsesExactOriginalUuidLookupAndNeverNewCallbackOrMutation() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);loseArchive = true
            failClosed { f.backend.reconcile(f.storage.read()) }
            val original = f.requests.single { it.getString("action") == "archive_attempt" }.getString("request_id")
            assertEquals(1, f.storage.read().attempts.size);assertEquals(3, f.storage.readRequests().getJSONArray("requests").length())
            val stale = f.storage.read();f.recreatedBackend(0).reconcile(stale)
            assertEquals(original, f.requests.single { it.getString("action") == "archive_lookup" }.getJSONObject("payload").getString("target_request_id"))
            assertEquals(1, f.requests.count { it.getString("action") == "archive_attempt" });assertEquals(2, f.requests.count { it.getString("action") == "callback" })
            assertEquals(1, invoked);assertTrue(f.storage.read().attempts.isEmpty());assertEquals(0, f.storage.readRequests().getJSONArray("requests").length())
            assertTrue(f.storage.hasArchivedAttempt(a.attemptId))
        } finally { f.dispose() }
    }
    @Test fun unknownOriginalLookupPreservesAttemptAndNeverRepeatsArchiveMutation() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);loseArchive = true;lookupUnknown = true
            failClosed { f.backend.reconcile(f.storage.read()) }
            repeat(2) { f.recreatedBackend(0).reconcile(f.storage.read()) }
            assertEquals(1, invoked);assertEquals(1, f.requests.count { it.getString("action") == "archive_attempt" })
            assertEquals(2, f.requests.count { it.getString("action") == "callback" });assertEquals(1, f.storage.read().attempts.size)
            assertNull(f.storage.readColdAttempt(a.attemptId))
        } finally { f.dispose() }
    }
    @Test fun lateContradictionWhilePausedUploadsOnceAndKeepsOriginalColdEvidence() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);f.backend.reconcile(f.storage.read())
            val original = f.storage.exportColdAttempt(a.attemptId).encryptedParts["cold-${a.attemptId}.bin"]!!
            val callback = GatewayCallback(a.segments[0].sentCallbackId, device, a.attemptId, a.fence, 0, a.callbackNonce, CallbackKind.SENT, 1, gatewayWireTime(Instant.now()))
            assertTrue(GatewayJournal(f.storage).record(callback));assertTrue(GatewayJournal(f.storage).read().emergencyPaused)
            f.backend.reconcile(f.storage.read());f.recreatedBackend(0).reconcile(f.storage.read())
            val late = f.requests.filter { it.getString("action") == "callback" && it.getJSONObject("payload").getInt("result_code") == 1 }
            assertEquals(1, late.size);assertEquals(1, invoked);assertTrue(f.storage.coldStop())
            assertArrayEquals(original, f.storage.exportColdAttempt(a.attemptId).encryptedParts["cold-${a.attemptId}.bin"])
            assertEquals(1, f.storage.coldPendingCallbacks().size)
        } finally { f.dispose() }
    }
    @Test fun malformedSuccessfulAckBytesRetainUnknownUntilOriginalLookup() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);malformedArchive = true
            failClosed { f.backend.reconcile(f.storage.read()) }
            assertEquals(1, f.storage.read().attempts.size);assertNull(f.storage.readColdAttempt(a.attemptId))
            f.recreatedBackend(0).reconcile(f.storage.read())
            assertTrue(f.storage.read().attempts.isEmpty());assertEquals(1, invoked)
            assertEquals(1, f.requests.count { it.getString("action") == "archive_attempt" });assertEquals(2, f.requests.count { it.getString("action") == "callback" })
        } finally { f.dispose() }
    }
    @Test fun serverAckCommitBeforeLocalConflictRetainsAllHotEvidenceAndAllowsRawReconciliation() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);conflictBeforeArchiveReply = true
            f.backend.reconcile(f.storage.read())
            val request = f.requests.single { it.getString("action") == "archive_attempt" }.getString("request_id")
            assertTrue(f.storage.coldStop());assertNull(f.storage.readColdAttempt(a.attemptId));assertEquals(1, f.storage.read().attempts.size)
            val retained = f.storage.readUncompactableAck(a.attemptId)!!
            assertEquals(request, GatewayStoredRequest.parse(retained.getJSONObject("archive_request")).requestId)
            assertEquals(3, f.storage.readRequests().getJSONArray("requests").length())
            f.recreatedBackend(0).reconcile(f.storage.read());f.recreatedBackend(0).reconcile(f.storage.read())
            assertEquals(1, invoked);assertEquals(1, f.requests.count { it.getString("action") == "archive_attempt" })
            assertEquals(0, f.requests.count { it.getString("action") == "archive_lookup" })
            assertEquals(1, f.requests.count { it.getString("action") == "callback" && it.getJSONObject("payload").getInt("result_code") == 1 })
            assertEquals(4, f.storage.readRequests().getJSONArray("requests").length());assertTrue(f.storage.coldStop())
            failClosed { GatewayJournal(f.storage).resume() }
        } finally { f.dispose() }
    }
    @Test fun originalAckLookupAfterLostReplyAndConflictDoesNotStarveContradictoryEvidence() {
        val f = fixture();var invoked = 0
        try {
            val a = dispatched(f) { invoked++ };observed(f, a);loseArchive = true
            failClosed { f.backend.reconcile(f.storage.read()) }
            val original = f.requests.single { it.getString("action") == "archive_attempt" }.getString("request_id")
            assertTrue(GatewayJournal(f.storage).record(GatewayCallback(a.segments[0].deliveryCallbackId, device, a.attemptId, a.fence,
                0, a.callbackNonce, CallbackKind.DELIVERY, 1, gatewayWireTime(Instant.now()))))
            f.recreatedBackend(0).reconcile(f.storage.read());f.recreatedBackend(0).reconcile(f.storage.read())
            assertEquals(original, f.requests.single { it.getString("action") == "archive_lookup" }.getJSONObject("payload").getString("target_request_id"))
            assertEquals(1, f.requests.count { it.getString("action") == "archive_attempt" });assertEquals(1, invoked)
            assertEquals(1, f.requests.count { it.getString("action") == "callback" && it.getJSONObject("payload").getInt("result_code") == 1 })
            assertEquals(1, f.storage.read().attempts.size);assertTrue(f.storage.coldStop());assertNull(f.storage.readColdAttempt(a.attemptId))
            assertEquals(original, GatewayStoredRequest.parse(f.storage.readUncompactableAck(a.attemptId)!!.getJSONObject("archive_request")).requestId)
        } finally { f.dispose() }
    }
}
