package app.cool.mobile.gateway

import android.util.AtomicFileFaults
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.cert.Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.util.Base64
import javax.net.ssl.HttpsURLConnection

class GatewayLateBackendTest {
    private class Fixture {
        val f = GatewayLateFixture()
        val requests = mutableListOf<JSONObject>();val signed = mutableListOf<ByteArray>()
        val originalResults = mutableMapOf<String, JSONObject>();val unknown = mutableSetOf<String>()
        var failNextCallback = false;var failReceiptNext = false
        val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) }
        val transport: GatewayHttpsTransport
        init {
            f.storage.saveEnrollment(JSONObject().put("contract_version", 1).put("device_id", f.device).put("installation_id", f.id()).put("key_sha256", fingerprint).put("signing_certificate_sha256", "a".repeat(64)))
            transport = GatewayHttpsTransport({ fingerprint }, { body -> signed.add(body.clone());Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run { initSign(key.private);update(body);sign() }) }, { url ->
                object : HttpsURLConnection(url) {
                    val output = ByteArrayOutputStream();lateinit var response: ByteArray;var status = 200
                    override fun connect() = Unit
                    override fun disconnect() = Unit
                    override fun usingProxy() = false
                    override fun getCipherSuite() = "synthetic"
                    override fun getLocalCertificates(): Array<Certificate>? = null
                    override fun getServerCertificates(): Array<Certificate> = emptyArray()
                    override fun getOutputStream() = output
                    override fun getResponseCode(): Int {
                        val bytes = output.toByteArray();val request = JSONObject(String(bytes))
                        assertEquals(fingerprint, getRequestProperty("X-Collect-Gateway-Key-Id"));assertNull(getRequestProperty("Authorization"))
                        assertTrue(Signature.getInstance("SHA256withECDSA").run { initVerify(key.public);update(bytes);verify(Base64.getDecoder().decode(getRequestProperty("X-Collect-Gateway-Signature"))) })
                        requests.add(request);val p = request.getJSONObject("payload")
                        val result = if (request.getString("action") == "reconcile") {
                            val target = p.getString("target_request_id");val recorded = originalResults[target]
                            JSONObject().put("target_request_id", target).put("outcome", if (target in unknown || recorded == null) "unknown" else "recorded")
                                .put("recorded_action", if (target in unknown || recorded == null) JSONObject.NULL else "callback").put("recorded_result", if (target in unknown || recorded == null) JSONObject.NULL else recorded)
                        } else {
                            assertEquals("callback", request.getString("action"));val id = request.getString("request_id")
                            val recorded = JSONObject().put("callback_id", p.getString("callback_id")).put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false).put("carrier_proof", false)
                                .put("state", "uncertain").put("sent_observations", 1).put("delivery_observations", 1).put("conflicting_observations", true)
                            originalResults[id] = JSONObject(recorded.toString())
                            if (failNextCallback) { failNextCallback = false;status = 503;unknown.add(id) }
                            if (failReceiptNext) { failReceiptNext = false;AtomicFileFaults.failFileOnce = "retention-receipt-${retentionUuidKey(id)}.bin" }
                            recorded
                        }
                        response = JSONObject().put("contract_version", 2).put("action", request.getString("action")).put("device_id", f.device).put("request_id", request.getString("request_id")).put("result", result).toString().toByteArray()
                        return status
                    }
                    override fun getInputStream() = ByteArrayInputStream(response)
                }
            })
        }
        fun backend() = GatewaySignedBackend(f.context, f.store(), GatewayDeviceIdentity(), { fingerprint }, transport)
        fun cycle() = backend().reconcile(f.store().read())
        fun dispose() = f.dispose()
    }
    private fun test(action: (Fixture) -> Unit) { val f = Fixture();try { action(f) } finally { f.dispose() } }
    private fun refuse(action: () -> Unit) { try { action();fail("Expected failure") } catch (_: GatewayStateException) {} }
    @Test fun eightyLateReceiptsCrossHotRequestLimitAndEveryBodyGetsOneSignedOriginal() = test { f ->
        val a = f.f.seed(3);repeat(80) { f.f.append(a, f.f.callback(a, it, it, it % 3)) }
        repeat(80) { f.cycle() }
        val callbacks = f.requests.filter { it.getString("action") == "callback" }
        assertEquals(80, callbacks.size);assertEquals(80, callbacks.map { it.getString("request_id") }.toSet().size)
        assertEquals(0, f.f.store().readRequests().getJSONArray("requests").length());assertTrue(f.f.store().coldStop())
        assertEquals(80, f.f.pages().size);assertEquals(callbacks.size, f.signed.size)
        for (request in callbacks) assertNotNull(f.f.store().readRequestReceipt(request.getString("request_id")))
    }
    @Test fun unknownFirstFailureDoesNotStarveThreePagesAndNeverGetsAnotherMutationAfterRestart() = test { f ->
        val a = f.f.seed();repeat(19) { f.f.append(a, f.f.callback(a, it, it)) }
        f.failNextCallback = true;refuse { f.cycle() }
        val first = f.requests.single().getString("request_id");val exact = f.signed.single().clone()
        repeat(24) { f.cycle() }
        val callbacks = f.requests.filter { it.getString("action") == "callback" }
        assertEquals(19, callbacks.size);assertEquals(19, callbacks.map { it.getJSONObject("payload").getInt("result_code") }.toSet().size)
        assertEquals(1, callbacks.count { it.getString("request_id") == first })
        val originals = f.f.store().readRequests().getJSONArray("requests");assertEquals(1, originals.length());assertEquals(first, originals.getJSONObject(0).getString("request_id"))
        assertArrayEquals(exact, Base64.getDecoder().decode(originals.getJSONObject(0).getString("request_bytes_base64")))
        assertTrue(f.requests.filter { it.getString("action") == "reconcile" }.all { it.getJSONObject("payload").getString("target_request_id") == first });assertTrue(f.f.store().coldStop())
    }
    @Test fun failedReceiptPublicationKeepsOriginalUntilExactReadLookupAndThenPrunesOnlyThatTransport() = test { f ->
        val a = f.f.seed();f.f.append(a);f.failReceiptNext = true;refuse { f.cycle() }
        val first = f.requests.single().getString("request_id");assertEquals(1, f.f.store().readRequests().getJSONArray("requests").length())
        f.cycle();f.cycle()
        assertEquals(1, f.requests.count { it.getString("action") == "callback" });assertTrue(f.requests.any { it.getString("action") == "reconcile" && it.getJSONObject("payload").getString("target_request_id") == first })
        assertNotNull(f.f.store().readRequestReceipt(first));assertEquals(0, f.f.store().readRequests().getJSONArray("requests").length());assertTrue(f.f.store().coldStop())
        assertEquals(a, archiveAttemptFromJson(f.f.store().readColdAttempt(a.attemptId)!!.getJSONObject("attempt")))
    }
    @Test fun recordedWithoutReceiptNeedsLookupAndNewEvidenceAfterCapturedCeilingAppearsAfterWrap() = test { f ->
        val a = f.f.seed();repeat(18) { f.f.append(a, f.f.callback(a, it, it)) }
        f.failNextCallback = true;refuse { f.cycle() };val target = f.requests.single().getString("request_id")
        f.unknown.clear()
        val rows = f.f.store().readRequests();rows.getJSONArray("requests").getJSONObject(0).put("state", "recorded");f.f.store().saveRequests(rows)
        f.f.append(a, f.f.callback(a, 100, 100))
        repeat(24) { f.cycle() }
        assertTrue(f.requests.any { it.getString("action") == "reconcile" && it.getJSONObject("payload").getString("target_request_id") == target })
        assertEquals(19, f.requests.count { it.getString("action") == "callback" });assertEquals(0, f.f.store().readRequests().getJSONArray("requests").length())
        assertNotNull(f.f.store().readRequestReceipt(target));assertTrue(f.f.store().coldStop())
    }
}
