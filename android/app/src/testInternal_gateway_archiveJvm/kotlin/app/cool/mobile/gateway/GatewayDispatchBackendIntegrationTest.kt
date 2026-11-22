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

class GatewayDispatchBackendIntegrationTest {
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
    // These callback-budget fixtures have no trusted original v1 dispatch arm.
    // The separate legacy closure must remain refused, preserving their source.
    private fun legacyIncomplete(request: JSONObject): Response {
        val payload = request.getJSONObject("payload")
        val result = JSONObject().put("request_id", request.getString("request_id")).put("device_id", device)
            .put("attempt_id", payload.getString("attempt_id")).put("fence_version", payload.getLong("fence_version"))
            .put("ok", false).put("code", "CALLBACK_EVIDENCE_INCOMPLETE").put("archive_ack_id", JSONObject.NULL)
            .put("receipt_id", JSONObject.NULL).put("body_sha256", payload.getString("body_sha256"))
            .put("destination_sha256", payload.getString("destination_sha256")).put("segment_count", payload.getJSONArray("callback_requests").length() / 2)
            .put("callback_requests", JSONObject.NULL).put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false)
            .put("evidence_kind", JSONObject.NULL).put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
        return Response(200, wrapper(request, result).toString().toByteArray())
    }
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
    @Test fun realSignedTransportDurablyReservesThenBindsOriginalArmBeforeOneInvoke() {
        val f=Fixture(::respond);var calls=0
        try {
            GatewayJournal(f.storage).resume()
            val record=GatewayDispatchEngine(GatewayJournal(f.storage),f.backend,sender(f.storage){calls++},::observations).dispatchOne()!!
            assertEquals(1,calls);assertEquals(attempt,record.attemptId)
            assertEquals(listOf("heartbeat","dispatch_grant","arm_dispatch"),f.requests.map{it.getString("action")})
            assertEquals(listOf(1,2,2),f.requests.map{it.getInt("contract_version")})
            val arm=f.requests.last().getJSONObject("payload")
            assertEquals(gatewayReservationDigest(record),arm.getString("reservation_sha256"))
            assertEquals(record.segments[0].sentCallbackId,arm.getJSONArray("callbacks").getJSONObject(0).getString("sent_callback_id"))
            for(i in f.bytes.indices) assertArrayEquals(f.bytes[i],f.signed[i])
        }finally{f.dispose()}
    }
    @Test fun lostArmResponseRetainsFsyncedOriginalUUIDAndNeverInvokesOrRearmsOnRead() {
        lateinit var f:Fixture;var calls=0
        f=Fixture { request -> if(request.getString("action")=="arm_dispatch") throw java.io.IOException("Synthetic lost commit reply") else if(request.getString("action")=="reconcile") {
            val target=request.getJSONObject("payload").getString("target_request_id")
            val original=f.requests.first{it.getString("request_id")==target}
            Response(200,wrapper(request,JSONObject().put("target_request_id",target).put("outcome","recorded")
                .put("recorded_action",original.getString("action")).put("recorded_result",recorded(original))).toString().toByteArray())
        } else respond(request) }
        try {
            GatewayJournal(f.storage).resume()
            failClosed{GatewayDispatchEngine(GatewayJournal(f.storage),f.backend,sender(f.storage){calls++},::observations).dispatchOne()}
            assertEquals(0,calls);assertTrue(f.storage.read().attempts.single().invocationException)
            val armId=f.requests.first{it.getString("action")=="arm_dispatch"}.getString("request_id")
            assertTrue(f.storage.readRequests().getJSONArray("requests").toString().contains(armId))
            f.backend.reconcile(f.storage.read())
            assertEquals(1,f.requests.count{it.getString("action")=="arm_dispatch"})
            assertEquals(0,calls);assertTrue(f.storage.read().attempts.single().invocationException)
            assertEquals(0,f.storage.readRequests().getJSONArray("requests").length())
            assertEquals(3, f.requests.filter { it.getString("action") in setOf("heartbeat", "dispatch_grant", "arm_dispatch") }.count { f.storage.readRequestReceipt(it.getString("request_id")) != null })
        }finally{f.dispose()}
    }
    @Test fun malformedArmResultCannotCrossSenderAndOriginalRequestRemainsUnknown() {
        val f=Fixture{request -> if(request.getString("action")=="arm_dispatch") {
            val response=respond(request);val json=JSONObject(String(response.bytes));json.getJSONObject("result").put("reservation_sha256","f".repeat(64));Response(200,json.toString().toByteArray())
        } else respond(request)};var calls=0
        try {
            GatewayJournal(f.storage).resume()
            failClosed{GatewayDispatchEngine(GatewayJournal(f.storage),f.backend,sender(f.storage){calls++},::observations).dispatchOne()}
            assertEquals(0,calls);assertTrue(f.storage.read().attempts.single().invocationException)
            assertEquals("outcome_unknown",f.storage.readRequests().getJSONArray("requests").getJSONObject(1).getString("state"))
        }finally{f.dispose()}
    }
    @Test fun negativeGrantOriginalUUIDReconciliationArchivesOnlyRedactedRecording() {
        lateinit var f:Fixture
        f=Fixture{request -> val result=if(request.getString("action")=="dispatch_grant")
            JSONObject().put("ok",false).put("code","OPERATIONS_PAUSED").put("device_id",device).put("request_id",request.getString("request_id")).put("replay",false)
            else {
                val target=request.getJSONObject("payload").getString("target_request_id")
                val original=f.requests.first{it.getString("request_id")==target}
                JSONObject().put("target_request_id",target).put("outcome","recorded").put("recorded_action","dispatch_grant").put("recorded_result",recorded(original))
            }
            Response(200,wrapper(request,result).toString().toByteArray()) }
        try {
            assertNull(f.backend.dispatchGrant(observations()))
            val request=f.storage.readRequests().getJSONArray("requests").getJSONObject(0).getString("request_id")
            f.backend.reconcile(f.storage.read())
            assertEquals(1,f.requests.count{it.getString("action")=="dispatch_grant"})
            assertEquals(0,f.storage.readRequests().getJSONArray("requests").length())
            val ack=f.storage.readRequestReceipt(request)!!
            assertEquals(request,ack.getJSONObject("request").getString("request_id"))
            assertEquals("ORIGINAL_REQUEST_RECORDED",ack.getJSONObject("result").getString("code"))
            assertFalse(ack.toString().contains("destination_e164"))
        }finally{f.dispose()}
    }
    @Test fun recordedCallbacksDoNotConsumeBatchAndStarveLaterMultipartObservations() {
        val f=Fixture { request -> if (request.getString("action") == "archive_legacy_attempt") legacyIncomplete(request)
            else Response(200,wrapper(request,JSONObject().put("callback_id",request.getJSONObject("payload").getString("callback_id"))
            .put("recorded_at",gatewayWireTime(Instant.now())).put("replay",false).put("carrier_proof",false)).toString().toByteArray()) }
        try {
            val at=gatewayWireTime(Instant.now())
            val parts=List(3){SegmentEvidence(sent=SegmentOutcome.FRAMEWORK_SENT,delivery=SegmentOutcome.DELIVERY_CALLBACK_OBSERVED,
                sentCode=-1,deliveryCode=-1,sentObservedAt=at,deliveryObservedAt=at)}
            val record=GatewayAttempt(device,receipt,attempt,1,sha256(body),sha256(destination),Instant.now().plusSeconds(25).toString(),at,"a".repeat(64),parts)
            f.storage.commit(GatewayJournalState(false,listOf(record)))
            val prior=JSONArray()
            for(i in 0..1)for(kind in listOf("sent","delivery")) {
                val callback=if(kind=="sent")parts[i].sentCallbackId else parts[i].deliveryCallbackId
                val id=UUID.randomUUID().toString()
                val payload=JSONObject().put("callback_id",callback).put("attempt_id",attempt).put("fence_version",1).put("segment_index",i).put("segment_count",3)
                    .put("body_sha256",sha256(body)).put("destination_sha256",sha256(destination)).put("callback_kind",kind).put("result_code",-1).put("tp_status",JSONObject.NULL).put("occurred_at",at)
                val raw=JSONObject().put("contract_version",1).put("action","callback").put("device_id",device).put("request_id",id).put("issued_at",at).put("payload",payload).toString()
                prior.put(JSONObject().put("request_id",id).put("action","callback").put("state","recorded").put("callback_id",callback)
                    .put("request_sha256",sha256(raw)).put("request_bytes_base64",Base64.getEncoder().encodeToString(raw.toByteArray())))
            }
            f.storage.saveRequests(JSONObject().put("contract_version",1).put("requests",prior))
            f.backend.reconcile(f.storage.read())
            val callbackWrites = f.requests.filter { it.getString("action") == "callback" }
            assertEquals(2, callbackWrites.size)
            assertTrue(callbackWrites.all{it.getJSONObject("payload").getInt("segment_index")==2})
            assertEquals(1, f.requests.count { it.getString("action") == "archive_legacy_attempt" && it.getInt("contract_version") == 4 })
            assertEquals(7,f.storage.readRequests().getJSONArray("requests").length())
            assertEquals(record, f.storage.read().attempts.single()); assertNull(f.storage.readColdAttempt(attempt))
        }finally{f.dispose()}
    }
    @Test fun permanentlyUnknownRequestsDoNotConsumeCallbackUploadBudget() {
        val f = Fixture { request ->
            if (request.getString("action") == "archive_legacy_attempt") return@Fixture legacyIncomplete(request)
            val payload = request.getJSONObject("payload")
            val result = if (request.getString("action") == "reconcile") JSONObject().put("target_request_id", payload.getString("target_request_id"))
                .put("outcome", "unknown").put("recorded_action", JSONObject.NULL).put("recorded_result", JSONObject.NULL)
            else JSONObject().put("callback_id", payload.getString("callback_id")).put("recorded_at", gatewayWireTime(Instant.now())).put("replay", false).put("carrier_proof", false)
            Response(200, wrapper(request, result).toString().toByteArray())
        }
        try {
            val at = gatewayWireTime(Instant.now())
            val part = SegmentEvidence(sent = SegmentOutcome.FRAMEWORK_SENT, delivery = SegmentOutcome.DELIVERY_CALLBACK_OBSERVED,
                sentCode = -1, deliveryCode = -1, sentObservedAt = at, deliveryObservedAt = at)
            val record = GatewayAttempt(device, receipt, attempt, 1, sha256(body), sha256(destination), Instant.now().plusSeconds(25).toString(), at, "a".repeat(64), listOf(part))
            f.storage.commit(GatewayJournalState(false, listOf(record)))
            val rows = JSONArray()
            repeat(4) {
                val id = UUID.randomUUID().toString(); val callbackId = UUID.randomUUID().toString()
                val payload = JSONObject().put("callback_id", callbackId).put("attempt_id", UUID.randomUUID().toString()).put("fence_version", 1).put("segment_index", 0).put("segment_count", 1)
                    .put("body_sha256", sha256(body)).put("destination_sha256", sha256(destination)).put("callback_kind", "sent").put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", at)
                val raw = JSONObject().put("contract_version", 1).put("action", "callback").put("device_id", device).put("request_id", id).put("issued_at", at).put("payload", payload).toString()
                rows.put(JSONObject().put("request_id", id).put("action", "callback").put("state", "outcome_unknown").put("callback_id", callbackId)
                    .put("request_sha256", sha256(raw)).put("request_bytes_base64", Base64.getEncoder().encodeToString(raw.toByteArray())))
            }
            f.storage.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
            f.backend.reconcile(f.storage.read())
            assertEquals(2, f.requests.count { it.getString("action") == "reconcile" })
            assertEquals(2, f.requests.count { it.getString("action") == "callback" })
            assertEquals(7, f.storage.readRequests().getJSONArray("requests").length())
            assertTrue((0 until 4).all { f.storage.readRequests().getJSONArray("requests").getJSONObject(it).getString("state") == "outcome_unknown" })
            assertEquals(record, f.storage.read().attempts.single()); assertNull(f.storage.readColdAttempt(attempt))
            // New backend instance restores only a non-sensitive read
            // position. All original UUIDs stay unknown and no write is replayed.
            val offset = f.backend.reconciliationOffset()
            f.recreatedBackend(offset).reconcile(f.storage.read())
            val readIds = f.requests.filter { it.getString("action") == "reconcile" }.map { it.getJSONObject("payload").getString("target_request_id") }
            assertEquals(4, readIds.size); assertEquals(4, readIds.toSet().size)
            assertEquals((0 until 4).map { rows.getJSONObject(it).getString("request_id") }.toSet(), readIds.toSet())
            assertEquals(2, f.requests.count { it.getString("action") == "callback" })
            assertEquals(1, f.requests.count { it.getString("action") == "archive_legacy_attempt" })
            assertTrue((0 until 4).all { f.storage.readRequests().getJSONArray("requests").getJSONObject(it).getString("request_id") == rows.getJSONObject(it).getString("request_id") })
        } finally { f.dispose() }
    }

}
