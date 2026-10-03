package app.cool.mobile.gateway

import android.util.AtomicFileFaults
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.io.File
import java.net.SocketTimeoutException
import javax.net.ssl.SSLHandshakeException
import org.json.JSONArray
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

class GatewayLookupFairnessTest {
    private class Fixture {
        val f = GatewayLateFixture()
        val requests = mutableListOf<JSONObject>();val signed = mutableListOf<ByteArray>()
        val originalResults = mutableMapOf<String, JSONObject>();val unknown = mutableSetOf<String>()
        var failNextCallback = false;var failReceiptNext = false
        var lookupFault: String? = null;var onReadFailure: (() -> Unit)? = null
        val key = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) }
        val transport: GatewayHttpsTransport
        init {
            f.storage.saveEnrollment(JSONObject().put("contract_version", 1).put("device_id", f.device).put("installation_id", f.id()).put("key_sha256", fingerprint).put("signing_certificate_sha256", "a".repeat(64)))
            transport = GatewayHttpsTransport({ if (lookupFault == "identity") "bad-key" else fingerprint }, { body -> if (lookupFault == "signer" && JSONObject(String(body)).getString("action") in setOf("reconcile", "archive_lookup")) throw IOException("signing key unavailable");signed.add(body.clone());Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run { initSign(key.private);update(body);sign() }) }, { url ->
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
                        val result = if (request.getString("action") in setOf("reconcile", "archive_lookup")) {
                            when (lookupFault) {
                                "network" -> { onReadFailure?.invoke();throw SocketTimeoutException("read timed out") }
                                "deadline" -> Thread.sleep(1_000)
                                "tls" -> throw SSLHandshakeException("certificate rejected")
                                "wrapped-tls" -> throw IOException("trust failure", SSLHandshakeException("certificate rejected"))
                            }
                            lookupFault?.removePrefix("status-")?.toIntOrNull()?.let { status = it }
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
                        response = JSONObject().put("contract_version", request.getInt("contract_version")).put("action", request.getString("action")).put("device_id", f.device).put("request_id", request.getString("request_id")).put("result", result).toString().toByteArray()
                        if (request.getString("action") in setOf("reconcile", "archive_lookup")) {
                            if (lookupFault == "malformed") response = "{}".toByteArray()
                            if (lookupFault == "binding") response = JSONObject(String(response)).also { it.getJSONObject("result").put("target_request_id", f.id()) }.toString().toByteArray()
                        }
                        return status
                    }
                    override fun getInputStream() = ByteArrayInputStream(response)
                }
            }, deadlineMs = 200)
        }
        fun backend() = GatewaySignedBackend(f.context, f.store(), GatewayDeviceIdentity(), { fingerprint }, transport)
        fun cycle() = backend().reconcile(f.store().read())
        fun dispose() = f.dispose()
    }
    private fun test(action: (Fixture) -> Unit) { val f = Fixture();try { action(f) } finally { f.dispose() } }
    private fun refuse(action: () -> Unit) { try { action();fail("Expected failure") } catch (_: GatewayStateException) {} }
    private fun startUnknown(f: Fixture): Pair<GatewayAttempt, ByteArray> {
        val a=f.f.seed();f.f.append(a,f.f.callback(a,0,0));f.failNextCallback=true;refuse { f.cycle() }
        return a to f.signed.single().clone()
    }
    private fun callbackCount(f: Fixture)=f.requests.count { it.getString("action")=="callback" }
    private fun assertOriginal(f: Fixture, exact: ByteArray) {
        val target=JSONObject(String(exact)).getString("request_id")
        val rows=f.f.store().readRequests().getJSONArray("requests")
        val original=(0 until rows.length()).map { rows.getJSONObject(it) }.single { it.getString("request_id")==target }
        assertArrayEquals(exact,Base64.getDecoder().decode(original.getString("request_bytes_base64")))
        assertEquals("outcome_unknown",original.getString("state"));assertNull(f.f.store().readRequestReceipt(target))
        assertEquals(1,f.requests.count { it.getString("action")=="callback" && it.getString("request_id")==target })
    }
    @Test fun throwingOriginalReadsStillVisitThreePagesAcrossRestartWithoutReplayingUnknown() = test { f ->
        val (a,exact)=startUnknown(f);repeat(18) { f.f.append(a,f.f.callback(a,it+1,it+1)) };f.lookupFault="network"
        repeat(24) {
            val start=f.requests.size;f.cycle();val cycle=f.requests.drop(start)
            assertTrue(cycle.count { it.getString("action")=="reconcile" } in 1..2)
            assertTrue(cycle.count { it.getString("action")=="callback" }<=2)
            assertEquals("reconcile",cycle.first().getString("action"))
        }
        assertEquals(19,callbackCount(f));assertEquals(19,f.requests.filter { it.getString("action")=="callback" }.map { it.getJSONObject("payload").getInt("result_code") }.toSet().size)
        assertOriginal(f,exact);assertEquals(1,f.f.store().readRequests().getJSONArray("requests").length());assertTrue(f.f.store().coldStop())
    }
    @Test fun lookupDeadlineDefersReadAndAllowsLaterEvidenceWithStopStillLatched() = test { f ->
        val (a,exact)=startUnknown(f);repeat(2) { f.f.append(a,f.f.callback(a,it+1,it+1)) };f.lookupFault="deadline"
        f.cycle();assertEquals(3,callbackCount(f));assertOriginal(f,exact);assertTrue(f.f.store().coldStop())
    }
    @Test fun transientReadStatusesDoNotBecomeMutationRetries() {
        for(status in listOf(408,429,503)) test { f ->
            val (a,exact)=startUnknown(f);f.f.append(a,f.f.callback(a,1,1));f.lookupFault="status-$status";f.cycle()
            assertEquals(2,callbackCount(f));assertOriginal(f,exact);assertTrue(f.f.store().coldStop())
        }
    }
    @Test fun credentialTrustIdentityMalformedAndBindingFailuresStayClosedBeforeLaterMutations() {
        for(fault in listOf("signer","identity","tls","wrapped-tls","status-401","status-403","status-302","status-404","malformed","binding")) test { f ->
            val (a,exact)=startUnknown(f);f.f.append(a,f.f.callback(a,1,1));val reader=File(f.f.directory,"late-retention-reader.bin").readBytes();f.lookupFault=fault
            refuse { f.cycle() };assertEquals(1,callbackCount(f));assertOriginal(f,exact)
            assertArrayEquals(reader,File(f.f.directory,"late-retention-reader.bin").readBytes());assertTrue(f.f.store().coldStop())
        }
    }
    @Test fun stopCorruptionOrEnrollmentRevocationDuringFailedReadNeverPermitsLaterMutation() {
        for(fault in listOf("stop","enrollment")) test { f ->
            val (a,exact)=startUnknown(f);f.f.append(a,f.f.callback(a,1,1));f.lookupFault="network"
            val hotFile=File(f.f.directory,"requests.bin");val hotBefore=hotFile.readBytes()
            f.onReadFailure={ if(fault=="enrollment") assertTrue(File(f.f.directory,"enrollment.bin").delete()) else File(f.f.directory,"cold-control.bin").writeBytes(byteArrayOf(1,2,3)) }
            refuse { f.cycle() };assertEquals(1,callbackCount(f));assertArrayEquals(hotBefore,hotFile.readBytes())
            // Corrupt control must still refuse validated readers. Verify the
            // retained encrypted original without treating that refusal as loss.
            val row=f.f.read("requests").getJSONArray("requests").getJSONObject(0)
            assertArrayEquals(exact,Base64.getDecoder().decode(row.getString("request_bytes_base64")));assertEquals("outcome_unknown",row.getString("state"))
        }
    }
    @Test fun laterReceiptFailureRemainsUnknownUntilExactReadRecoveryAndNeverReplays() = test { f ->
        val (a,exact)=startUnknown(f);f.f.append(a,f.f.callback(a,1,1));f.lookupFault="network";f.failReceiptNext=true
        refuse { f.cycle() };assertEquals(2,callbackCount(f));assertOriginal(f,exact);assertEquals(2,f.f.store().readRequests().getJSONArray("requests").length())
        f.lookupFault=null;f.unknown.clear();repeat(3) { f.cycle() }
        assertEquals(2,callbackCount(f));assertEquals(0,f.f.store().readRequests().getJSONArray("requests").length());assertTrue(f.f.store().coldStop())
    }
    @Test fun unavailableArchiveLookupKeepsPendingArchiveOriginalAndAllowsLateEvidence() = test { f ->
        val a=f.f.seed();val cold=f.f.store().readColdAttempt(a.attemptId)!!
        val original=f.f.request("archive_attempt",cold.getJSONObject("archive_request").let { GatewayStoredRequest.parse(it).envelope.getJSONObject("payload") },3)
        val exact=Base64.getDecoder().decode(original.getString("request_bytes_base64"))
        f.f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray().put(original)))
        f.f.append(a,f.f.callback(a,1,1));f.lookupFault="network";f.cycle()
        assertEquals("archive_lookup",f.requests.first().getString("action"));assertEquals(1,callbackCount(f))
        val retained=f.f.store().readRequests().getJSONArray("requests").getJSONObject(0)
        assertEquals(original.getString("request_id"),retained.getString("request_id"));assertArrayEquals(exact,Base64.getDecoder().decode(retained.getString("request_bytes_base64")));assertTrue(f.f.store().coldStop())
    }
}
