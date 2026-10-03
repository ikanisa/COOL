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

class GatewayArchiveBackendIntegrationTest {
    private val device = "00000000-0000-0000-0000-000000000001"
    private fun observations() = GatewayObservations(true, true, true, true, true, true, true, 1, true)
    private data class Response(val status: Int, val bytes: ByteArray)
    private fun heartbeatResult() = JSONObject().put("observation_id", UUID.randomUUID().toString()).put("ingested_at", gatewayWireTime(Instant.now()))
        .put("replay", false).put("carrier_proof", false)
    private fun wrapper(request: JSONObject, result: JSONObject): JSONObject = JSONObject().put("contract_version", 1).put("action", request.getString("action"))
        .put("device_id", request.getString("device_id")).put("request_id", request.getString("request_id")).put("result", result)
    private fun retained(action: String, state: String): JSONObject {
        val callback = UUID.randomUUID().toString()
        val payload = if (action != "callback") JSONObject() else JSONObject().put("callback_id", callback)
            .put("attempt_id", UUID.randomUUID().toString()).put("fence_version", 1).put("segment_index", 0).put("segment_count", 1)
            .put("body_sha256", "b".repeat(64)).put("destination_sha256", "c".repeat(64)).put("callback_kind", "sent")
            .put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", gatewayWireTime(Instant.now()))
        val id = UUID.randomUUID().toString()
        val envelope = JSONObject().put("contract_version", 1).put("action", action).put("device_id", device).put("request_id", id)
            .put("issued_at", gatewayWireTime(Instant.now())).put("payload", payload).toString()
        return JSONObject().put("request_id", id).put("action", action).put("state", state)
            .put("callback_id", if (action == "callback") callback else JSONObject.NULL).put("request_sha256", sha256(envelope))
            .put("request_bytes_base64", Base64.getEncoder().encodeToString(envelope.toByteArray()))
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
        init {
            storage.saveEnrollment(JSONObject().put("contract_version", 1).put("device_id", device).put("installation_id", UUID.randomUUID().toString())
                .put("key_sha256", fingerprint).put("signing_certificate_sha256", "a".repeat(64)))
            val transport = GatewayHttpsTransport({ fingerprint }, { body ->
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
        fun dispose() { AtomicFileFaults.failFinishOnce = false; root.deleteRecursively() }
    }
    private fun reject(block: () -> Unit) { try { block(); fail("Expected uncertain/refused outcome") } catch (_: GatewayStateException) { } }
    @Test fun exactAuthenticatedHeartbeatArchivesResponseAndOriginalSignedDigest() {
        val fixture = Fixture { request -> Response(200, wrapper(request, heartbeatResult()).toString().toByteArray()) }
        try {
            val authority = fixture.backend.heartbeat(observations())
            assertEquals(GatewayEnrollmentState.UNKNOWN, authority.state); assertFalse(authority.dispatchEnabled)
            assertEquals(0, fixture.storage.readRequests().getJSONArray("requests").length())
            val entry = fixture.storage.readArchive().getJSONArray("requests").getJSONObject(0)
            val original = entry.getJSONObject("request")
            assertEquals(sha256(String(fixture.bytes.single(), Charsets.UTF_8)), original.getString("request_sha256"))
            assertArrayEquals(fixture.bytes.single(), fixture.signed.single())
            assertArrayEquals(fixture.bytes.single(), Base64.getDecoder().decode(original.getString("request_bytes_base64")))
            assertEquals(fixture.requests.single().getString("request_id"), entry.getJSONObject("evidence").getString("request_id"))
        } finally { fixture.dispose() }
    }
    @Test fun authenticatedAuthorityPendingRefusalIsArchivedWithoutAGrant() {
        val fixture = Fixture { request -> Response(200, wrapper(request, JSONObject().put("ok", false).put("code", "GATEWAY_DISPATCH_AUTHORITY_PENDING")
            .put("device_id", device).put("request_id", request.getString("request_id")).put("replay", false)).toString().toByteArray()) }
        try {
            assertNull(fixture.backend.dispatchGrant(observations()))
            assertEquals(0, fixture.storage.readRequests().getJSONArray("requests").length())
            assertFalse(fixture.storage.readArchive().getJSONArray("requests").getJSONObject(0).getJSONObject("result").getBoolean("ok"))
        } finally { fixture.dispose() }
    }
    @Test fun nonSuccessMalformedAndWrongBoundResponsesKeepOriginalUnknownRequest() {
        for (kind in listOf("http", "utf8", "binding", "private")) {
            val fixture = Fixture { request -> when (kind) {
                "http" -> Response(500, ByteArray(0))
                "utf8" -> Response(200, byteArrayOf(0xff.toByte()))
                "binding" -> Response(200, wrapper(request, heartbeatResult()).put("request_id", UUID.randomUUID().toString()).toString().toByteArray())
                else -> Response(200, wrapper(request, heartbeatResult().put("destination", "private")).toString().toByteArray())
            } }
            try {
                reject { fixture.backend.heartbeat(observations()) }
                assertEquals(1, fixture.requests.size)
                val row = fixture.storage.readRequests().getJSONArray("requests").getJSONObject(0)
                assertEquals("outcome_unknown", row.getString("state")); assertEquals(fixture.requests.single().getString("request_id"), row.getString("request_id"))
                assertEquals(0, fixture.storage.readArchive().getJSONArray("requests").length())
            } finally { fixture.dispose() }
        }
    }
    @Test fun postCommitDisconnectReconcilesOnlyOriginalUuidWithoutMutationReplay() {
        lateinit var original: JSONObject
        val recorded = heartbeatResult()
        val fixture = Fixture { request ->
            if (request.getString("action") == "heartbeat") { original = request; Response(500, ByteArray(0)) }
            else {
                assertEquals(original.getString("request_id"), request.getJSONObject("payload").getString("target_request_id"))
                Response(200, wrapper(request, JSONObject().put("target_request_id", original.getString("request_id")).put("outcome", "recorded")
                    .put("recorded_action", "heartbeat").put("recorded_result", recorded)).toString().toByteArray())
            }
        }
        try {
            reject { fixture.backend.heartbeat(observations()) }
            fixture.backend.reconcile(fixture.storage.read())
            assertEquals(listOf("heartbeat", "reconcile"), fixture.requests.map { it.getString("action") })
            assertEquals(0, fixture.storage.readRequests().getJSONArray("requests").length())
            val receipt = fixture.storage.readArchive().getJSONArray("requests").getJSONObject(0)
            assertEquals(original.getString("request_id"), receipt.getJSONObject("request").getString("request_id"))
            assertEquals("reconcile", receipt.getJSONObject("evidence").getString("action"))
        } finally { fixture.dispose() }
    }
    @Test fun unknownReconciliationDoesNotCompactOrReplay() {
        val fixture = Fixture { request -> if (request.getString("action") == "heartbeat") Response(500, ByteArray(0)) else
            Response(200, wrapper(request, JSONObject().put("target_request_id", request.getJSONObject("payload").getString("target_request_id"))
                .put("outcome", "unknown").put("recorded_action", JSONObject.NULL).put("recorded_result", JSONObject.NULL)).toString().toByteArray()) }
        try {
            reject { fixture.backend.heartbeat(observations()) }; fixture.backend.reconcile(fixture.storage.read())
            assertEquals(1, fixture.storage.readRequests().getJSONArray("requests").length()); assertEquals(0, fixture.storage.readArchive().getJSONArray("requests").length())
            assertEquals(listOf("heartbeat", "reconcile"), fixture.requests.map { it.getString("action") })
        } finally { fixture.dispose() }
    }
    @Test fun archiveWriteFailureAfterResponseLeavesAnOriginalUuidForReadRecovery() {
        val fixture = Fixture { request ->
            // Mutation reservation has already been fsynced. Fail only the first
            // archive-marker atomic finish after a strictly valid server reply.
            AtomicFileFaults.failFinishOnce = true
            Response(200, wrapper(request, heartbeatResult()).toString().toByteArray())
        }
        try {
            reject { fixture.backend.heartbeat(observations()) }
            assertEquals(1, fixture.requests.size)
            val pending = fixture.storage.readRequests().getJSONArray("requests").getJSONObject(0)
            assertEquals("outcome_unknown", pending.getString("state"))
            assertEquals(fixture.requests.single().getString("request_id"), pending.getString("request_id"))
            assertEquals(0, fixture.storage.readArchive().getJSONArray("requests").length())
        } finally { fixture.dispose() }
    }
    @Test fun newHeartbeatCompactionPreservesLegacyRecordedAndCallbackRows() {
        val fixture = Fixture { request -> Response(200, wrapper(request, heartbeatResult()).toString().toByteArray()) }
        try {
            val legacy = retained("heartbeat", "recorded"); val callback = retained("callback", "recorded")
            fixture.storage.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(legacy, callback))))
            fixture.backend.heartbeat(observations())
            val active = fixture.storage.readRequests().getJSONArray("requests")
            assertEquals(2, active.length()); assertEquals(legacy.toString(), active.getJSONObject(0).toString()); assertEquals(callback.toString(), active.getJSONObject(1).toString())
            assertEquals(1, fixture.storage.readArchive().getJSONArray("requests").length())
        } finally { fixture.dispose() }
    }
    @Test fun mixedRecoveryDoesNotReintroduceArchivedHeartbeatWhenCallbackBecomesRecorded() {
        val heartbeat = retained("heartbeat", "outcome_unknown"); val callback = retained("callback", "outcome_unknown")
        val rows = listOf(heartbeat, callback).associateBy { it.getString("request_id") }
        val fixture = Fixture { request ->
            val target = request.getJSONObject("payload").getString("target_request_id"); val row = rows.getValue(target)
            val result = if (row.getString("action") == "heartbeat") heartbeatResult() else JSONObject().put("callback_id", row.getString("callback_id"))
                .put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false).put("carrier_proof", false)
            Response(200, wrapper(request, JSONObject().put("target_request_id", target).put("outcome", "recorded")
                .put("recorded_action", row.getString("action")).put("recorded_result", result)).toString().toByteArray())
        }
        try {
            fixture.storage.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(heartbeat, callback))))
            fixture.backend.reconcile(fixture.storage.read())
            val active = fixture.storage.readRequests().getJSONArray("requests")
            assertEquals(1, active.length()); assertEquals(callback.getString("request_id"), active.getJSONObject(0).getString("request_id"))
            assertEquals("recorded", active.getJSONObject(0).getString("state"))
            assertEquals(2, fixture.requests.size); assertTrue(fixture.requests.all { it.getString("action") == "reconcile" })
        } finally { fixture.dispose() }
    }
}
