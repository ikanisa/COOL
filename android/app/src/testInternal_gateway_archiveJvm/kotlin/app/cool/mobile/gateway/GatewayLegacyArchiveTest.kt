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

/** SQL-produced trusted v1 arm/callback/ACK bytes drive real encrypted readers
 * and the actual signature-producing backend. No key/device/provider is used. */
class GatewayLegacyArchiveTest {
    private class LocalContext(private val root: File): Context() { override val noBackupFilesDir get()=root }
    private inner class Fixture(private val withOriginalArchive: Boolean = true) {
        val source=JSONObject(File(System.getProperty("collect.legacy.fixtures"),"native-source.json").readText())
        val attempt=archiveAttemptFromJson(source.getJSONObject("attempt"))
        val root=Files.createTempDirectory("collect-legacy-custody-").toFile()
        val key=KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val fingerprint=MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) }
        val context=LocalContext(root)
        fun store()=GatewayEncryptedStore(context) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 27 },"AES"),"CollectGateway/$name/v1") }
        val storage=store()
        val calls=mutableListOf<JSONObject>()
        var unknown=false
        var malformed=false
        var failArchiveMutation=false
        var expectedHotRows:Int?=null
        var createdArchive:String?=null
        val transport=GatewayHttpsTransport({fingerprint},{ bytes -> Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run { initSign(key.private);update(bytes);sign() }) },{ url ->
            assertEquals(GatewayHttpsTransport.HOST,url.host)
            object: HttpsURLConnection(url) {
                val output=ByteArrayOutputStream();var response=ByteArray(0)
                override fun connect()=Unit
                override fun disconnect()=Unit
                override fun usingProxy()=false
                override fun getCipherSuite()="synthetic"
                override fun getLocalCertificates():Array<Certificate>?=null
                override fun getServerCertificates():Array<Certificate> = emptyArray()
                override fun getOutputStream()=output
                override fun getResponseCode():Int {
                    val bytes=output.toByteArray();val request=JSONObject(String(bytes,Charsets.UTF_8));calls.add(request)
                    assertNull(getRequestProperty("Authorization"));assertEquals(fingerprint,getRequestProperty("X-Collect-Gateway-Key-Id"))
                    assertTrue(Signature.getInstance("SHA256withECDSA").run { initVerify(key.public);update(bytes);verify(Base64.getDecoder().decode(getRequestProperty("X-Collect-Gateway-Signature"))) })
                    if(request.getInt("contract_version")==1) {
                        val result=when(request.getString("action")) {
                            "reconcile" -> JSONObject().put("target_request_id",request.getJSONObject("payload").getString("target_request_id")).put("outcome","unknown").put("recorded_action",JSONObject.NULL).put("recorded_result",JSONObject.NULL)
                            "heartbeat" -> JSONObject().put("observation_id",UUID.randomUUID().toString()).put("ingested_at",gatewayWireTime(Instant.now())).put("replay",false).put("carrier_proof",false)
                            else -> { fail("Unexpected ordinary mutation");JSONObject() }
                        }
                        response=JSONObject().put("contract_version",1).put("action",request.getString("action")).put("device_id",attempt.deviceId).put("request_id",request.getString("request_id")).put("result",result).toString().toByteArray()
                        return 200
                    }
                    assertEquals(4,request.getInt("contract_version"))
                    val ack=JSONObject(source.getJSONObject("ack").toString()).also { if(malformed) it.put("evidence_kind","complete_framework_callback_observations") }
                    val result=if(request.getString("action")=="archive_legacy_attempt") {
                        assertFalse(withOriginalArchive)
                        createdArchive=request.getString("request_id")
                        expectedHotRows?.let { assertEquals(it.toInt(),storage.readRequests().getJSONArray("requests").length()) }
                        assertTrue(archiveJsonEqual(source.getJSONObject("payload"),request.getJSONObject("payload")))
                        ack.put("request_id",request.getString("request_id"))
                    } else {
                        assertEquals("legacy_archive_lookup",request.getString("action"))
                        val target=request.getJSONObject("payload").getString("target_request_id")
                        val retained=storage.readRequests().getJSONArray("requests")
                        val expected=if(withOriginalArchive) source.getJSONObject("archive_row").getString("request_id") else
                            createdArchive ?: (0 until retained.length()).map { GatewayStoredRequest.parse(retained.getJSONObject(it)) }.single { it.action=="archive_legacy_attempt" }.requestId
                        assertEquals(expected,target);ack.put("request_id",target)
                        JSONObject().put("target_request_id",target).put("outcome",if(unknown) "unknown" else "recorded").put("recorded_result",if(unknown) JSONObject.NULL else ack)
                    }
                    response=JSONObject().put("contract_version",4).put("action",request.getString("action")).put("device_id",attempt.deviceId).put("request_id",request.getString("request_id")).put("result",result).toString().toByteArray()
                    return if(request.getString("action")=="archive_legacy_attempt" && failArchiveMutation) 503 else 200
                }
                override fun getInputStream()=ByteArrayInputStream(response)
            }
        })
        fun backend()=GatewaySignedBackend(context,store(),GatewayDeviceIdentity(),{fingerprint},transport)
        init {
            storage.saveEnrollment(JSONObject().put("contract_version",1).put("device_id",attempt.deviceId).put("installation_id",UUID.randomUUID().toString()).put("key_sha256",fingerprint).put("signing_certificate_sha256","a".repeat(64)))
            storage.commit(GatewayJournalState(true,listOf(attempt)))
            val rows=JSONArray(source.getJSONArray("callback_rows").toString());if(withOriginalArchive) rows.put(source.getJSONObject("archive_row"))
            storage.saveRequests(JSONObject().put("contract_version",1).put("requests",rows))
        }
        fun row(action:String,payload:JSONObject,version:Int=1,state:String="recorded"):JSONObject {
            val id=UUID.randomUUID().toString();val text=JSONObject().put("contract_version",version).put("action",action).put("device_id",attempt.deviceId).put("request_id",id).put("issued_at",gatewayWireTime(Instant.now())).put("payload",payload).toString()
            return JSONObject().put("request_id",id).put("action",action).put("state",state).put("callback_id",JSONObject.NULL).put("request_sha256",sha256(text)).put("request_bytes_base64",Base64.getEncoder().encodeToString(text.toByteArray()))
        }
        fun fill(target:Int=64,unknownOrdinary:Boolean=false):List<GatewayStoredRequest> {
            val rows=store().readRequests().getJSONArray("requests");val ordinary=mutableListOf<GatewayStoredRequest>()
            while(rows.length()<target) {
                val now=gatewayWireTime(Instant.now());val payload=JSONObject().put("sms_permission",false).put("network","offline").put("telephony","unknown").put("sim_selected",false).put("sim_revision_sha256",JSONObject.NULL).put("local_pause",true).put("reported_at",now)
                val row=row("heartbeat",payload,state=if(unknownOrdinary && ordinary.isEmpty()) "outcome_unknown" else "recorded")
                ordinary.add(GatewayStoredRequest.parse(row));rows.put(row)
            }
            store().saveRequests(JSONObject().put("contract_version",1).put("requests",rows));return ordinary
        }
        fun assertOrdinaryExact(originals:List<GatewayStoredRequest>) {
            val rows=store().readRequests().getJSONArray("requests")
            val actual=(0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) }.associateBy { it.requestId }
            for(r in originals) { val kept=actual.getValue(r.requestId);requireSameRequest(r,kept);assertEquals(r.row.getString("state"),kept.row.getString("state")) }
        }
        fun maintenance()=store().readRequests().getJSONArray("requests").let { rows -> (0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) }.single { it.action=="archive_legacy_attempt" } }
        fun corruptHot(rows:JSONArray) {
            val value=JSONObject().put("contract_version",1).put("requests",rows)
            File(root,"collect_gateway_v1/requests.bin").writeBytes(GatewayCrypto(SecretKeySpec(ByteArray(32) { 27 },"AES"),"CollectGateway/requests/v1").encrypt(value.toString().toByteArray()))
        }
        fun original()=GatewayStoredRequest.parse(source.getJSONObject("archive_row"))
        fun callback(code:Int)=GatewayCallback(attempt.segments[0].deliveryCallbackId,attempt.deviceId,attempt.attemptId,attempt.fence,0,attempt.callbackNonce,CallbackKind.DELIVERY,code,gatewayWireTime(Instant.now()))
        fun dispose() { AtomicFileFaults.failFileOnce=null;AtomicFileFaults.failFinishOnce=false;root.deleteRecursively() }
    }
    private fun test(withOriginalArchive:Boolean=true,action:(Fixture)->Unit) { val f=Fixture(withOriginalArchive);try {action(f)} finally {f.dispose()} }
    private fun refuse(action:()->Unit) { try {action();fail("Expected custody refusal")} catch(_:GatewayStateException) {} }
    @Test fun originalLegacyRequestRemainsExactAndVersionFourCannotBecomeCurrentArchive()=test { f ->
        val request=f.original();assertEquals("archive_legacy_attempt",request.action);assertEquals(4L,strictInteger(request.envelope,"contract_version"))
        val row=JSONObject(request.row.toString());val envelope=JSONObject(request.envelope.toString()).put("contract_version",3)
        val text=envelope.toString();row.put("request_bytes_base64",Base64.getEncoder().encodeToString(text.toByteArray())).put("request_sha256",sha256(text))
        refuse { GatewayStoredRequest.parse(row) }
        refuse { GatewayArchiveAcknowledgement.direct(request,JSONObject().put("contract_version",4).put("action",request.action).put("device_id",request.deviceId).put("request_id",request.requestId).put("result",f.source.getJSONObject("ack"))) }
    }
    @Test fun actualPausedBackendCreatesOnlyOneSignedLegacyCustodyMutationFromExactV1Source()=test(false) { f ->
        f.backend().reconcile(f.storage.read());assertEquals(1,f.calls.size)
        val sent=f.calls.single();assertEquals("archive_legacy_attempt",sent.getString("action"));assertEquals(4,sent.getInt("contract_version"))
        val cold=f.store().readColdAttempt(f.attempt.attemptId)!!
        assertEquals(6,cold.getInt("contract_version"));assertEquals(sent.getString("request_id"),cold.getJSONObject("acknowledgement").getString("request_id"))
        assertEquals(sent.getString("request_id"),cold.getJSONObject("archive_request").getString("request_id"));assertTrue(f.store().read().attempts.isEmpty())
        assertTrue(f.store().read().emergencyPaused);assertFalse(cold.getJSONObject("acknowledgement").getBoolean("send_authority"))
        f.backend().reconcile(f.store().read());assertEquals(1,f.calls.size)
    }
    @Test fun actualSignedBackendRecoversOriginalSqlAckAndCompactsOnlyAfterImmutableLegacyColdPublication()=test { f ->
        f.backend().reconcile(f.storage.read());assertEquals(1,f.calls.size)
        assertTrue(f.store().read().attempts.isEmpty());assertEquals(0,f.store().readRequests().getJSONArray("requests").length())
        val cold=f.store().readColdAttempt(f.attempt.attemptId)!!;assertEquals(6,cold.getInt("contract_version"));assertEquals(f.attempt,archiveAttemptFromJson(cold.getJSONObject("attempt")))
        assertTrue(archiveJsonEqual(f.source.getJSONObject("ack"),cold.getJSONObject("acknowledgement")))
        for(i in 0 until f.source.getJSONArray("callback_rows").length()) { val row=f.source.getJSONArray("callback_rows").getJSONObject(i);requireSameRequest(GatewayStoredRequest.parse(row),f.store().readRetainedRequest(row.getString("request_id"))!!) }
        requireSameRequest(f.original(),f.store().readRetainedRequest(f.original().requestId)!!);assertTrue(f.store().read().emergencyPaused)
    }
    @Test fun unknownOriginalAcrossRestartNeverReplaysMutationOrFreesLegacyEvidence()=test { f ->
        f.unknown=true
        repeat(2) { f.backend().reconcile(f.store().read()) }
        assertEquals(2,f.calls.size);assertEquals(listOf(f.attempt),f.store().read().attempts);assertNull(f.store().readColdAttempt(f.attempt.attemptId))
        assertTrue(f.calls.all { it.getString("action")=="legacy_archive_lookup" });assertEquals(5,f.store().readRequests().getJSONArray("requests").length())
    }
    @Test fun currentFamilyAckCannotPruneLegacyAttemptOrOriginalRequests()=test { f ->
        f.malformed=true;refuse { f.backend().reconcile(f.storage.read()) }
        assertNull(f.store().readColdAttempt(f.attempt.attemptId));assertEquals(listOf(f.attempt),f.store().read().attempts);assertEquals(5,f.store().readRequests().getJSONArray("requests").length())
    }
    @Test fun callbackReorderingAndDigestChangeCannotCreateColdLegacyAuthority()=test { f ->
        val changed=JSONObject(f.source.getJSONObject("ack").toString());changed.put("callback_requests",JSONArray((0 until f.source.getJSONObject("payload").getJSONArray("callback_requests").length()).reversed().map { f.source.getJSONObject("payload").getJSONArray("callback_requests").getJSONObject(it) }))
        refuse { GatewayAttemptArchive(f.storage).acknowledge(f.original(),changed) }
        assertNull(f.store().readColdAttempt(f.attempt.attemptId));assertEquals(listOf(f.attempt),f.store().read().attempts)
    }
    @Test fun archiveFirstPruningCrashRepairsOnlyExactExistingLegacyAckWithoutNetworkReplay()=test { f ->
        AtomicFileFaults.failFileOnce="journal.bin";refuse { GatewayAttemptArchive(f.storage).acknowledge(f.original(),f.source.getJSONObject("ack")) }
        assertEquals(6,f.store().readColdAttempt(f.attempt.attemptId)!!.getInt("contract_version"))
        assertTrue(f.store().read().attempts.isEmpty());assertEquals(0,f.store().readRequests().getJSONArray("requests").length());assertTrue(f.calls.isEmpty())
    }
    @Test fun lateLegacyConflictRemainsPagedAndPausedWithoutMisroutingToCurrentV2()=test { f ->
        f.backend().reconcile(f.storage.read());assertTrue(GatewayJournal(f.store()).record(f.callback(1)))
        val page=f.store().coldCallbackPage(null,8);assertEquals(1,page.entries.size);assertEquals(1,page.entries.single().callback.resultCode)
        assertTrue(f.store().coldStop());assertTrue(GatewayJournal(f.store()).read().emergencyPaused)
        f.backend().reconcile(f.store().read());assertEquals(1,f.calls.size)
        assertEquals(1,f.store().coldCallbackPage(null,8).entries.single().callback.resultCode)
    }
    @Test fun fullOrdinaryJournalReservesOnlyLegacySlotAndUnknownOriginalSurvivesRestartUntilExactAck()=test(false) { f ->
        val ordinary=f.fill(unknownOrdinary=true);f.expectedHotRows=65;f.failArchiveMutation=true
        refuse { f.backend().reconcile(f.store().read()) };val original=f.maintenance()
        assertEquals(64,GatewayEncryptedStore.MAX_REQUESTS);assertEquals(65,f.store().readRequests().getJSONArray("requests").length());f.assertOrdinaryExact(ordinary)
        val calls=f.calls.size;refuse { f.backend().dispatchGrant(GatewayObservations(false,false,false,false,false,false,false,null,false)) };assertEquals(calls,f.calls.size)
        f.unknown=true;val restarted=f.backend();restarted.restoreReconciliationOffset(63);restarted.reconcile(f.store().read())
        requireSameRequest(original,f.maintenance());assertEquals(1,f.calls.count { it.getString("action")=="archive_legacy_attempt" });f.assertOrdinaryExact(ordinary)
        assertTrue(f.calls.any { it.getString("action")=="legacy_archive_lookup" && it.getJSONObject("payload").getString("target_request_id")==original.requestId })
        f.unknown=false;f.backend().reconcile(f.store().read());val cold=f.store().readColdAttempt(f.attempt.attemptId)!!
        assertEquals(6,cold.getInt("contract_version"));assertEquals(original.requestId,cold.getJSONObject("archive_request").getString("request_id"));assertEquals(60,f.store().readRequests().getJSONArray("requests").length())
        f.assertOrdinaryExact(ordinary);f.backend().heartbeat(GatewayObservations(false,false,false,false,false,false,false,null,false));f.assertOrdinaryExact(ordinary)
        assertEquals(1,f.calls.count { it.getString("action")=="heartbeat" });assertTrue(f.store().read().emergencyPaused)
    }
    @Test fun fullJournalCannotGiveCurrentV3OrOrdinaryRequestTheLegacyOverflowSlot()=test(false) { f ->
        val ordinary=f.fill();val before=f.store().readRequests().toString()
        for(row in listOf(f.row("heartbeat",JSONObject()),f.row("archive_attempt",JSONObject(f.source.getJSONObject("payload").toString()),3))) {
            val rows=JSONArray(f.store().readRequests().getJSONArray("requests").toString()).put(row)
            refuse { f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",rows)) }
        }
        assertEquals(before,f.store().readRequests().toString());f.assertOrdinaryExact(ordinary)
    }
    @Test fun secondLegacySlotAndSixtySixRowsNeverEvictAnUnknownOriginal()=test(false) { f ->
        val ordinary=f.fill(63,true);val first=f.row("archive_legacy_attempt",JSONObject(f.source.getJSONObject("payload").toString()),4,"outcome_unknown")
        val rows=JSONArray(f.store().readRequests().getJSONArray("requests").toString()).put(first);f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",rows))
        assertFalse(gatewayLegacyArchiveSlotAvailable(f.store().readRequests().getJSONArray("requests")))
        val second=f.row("archive_legacy_attempt",JSONObject(f.source.getJSONObject("payload").toString()),4,"outcome_unknown")
        refuse { f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray(rows.toString()).put(second))) }
        refuse { f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray(rows.toString()).put(f.row("heartbeat",JSONObject())).put(second))) }
        requireSameRequest(GatewayStoredRequest.parse(first),f.maintenance());f.assertOrdinaryExact(ordinary)
    }
    @Test fun legacyIntentWriteFailureHasNoNetworkEffectAndRetainsFullOrdinaryJournal()=test(false) { f ->
        val ordinary=f.fill();AtomicFileFaults.failFileOnce="retention-hot-pending.bin"
        refuse { f.backend().reconcile(f.store().read()) };assertTrue(f.calls.isEmpty());assertEquals(64,f.store().readRequests().getJSONArray("requests").length());f.assertOrdinaryExact(ordinary)
        f.backend().reconcile(f.store().read());assertEquals(1,f.calls.size);assertEquals(60,f.store().readRequests().getJSONArray("requests").length());f.assertOrdinaryExact(ordinary)
    }
    @Test fun interruptedHotPublicationRepairsOnlyDurableMaintenanceOriginalAndNeverReplaysMutation()=test(false) { f ->
        val ordinary=f.fill();AtomicFileFaults.failFileOnce="requests.bin"
        refuse { f.backend().reconcile(f.store().read()) };assertTrue(f.calls.isEmpty());val original=f.maintenance()
        assertEquals(65,f.store().readRequests().getJSONArray("requests").length());f.unknown=true;f.backend().reconcile(f.store().read())
        requireSameRequest(original,f.maintenance());assertEquals(listOf("legacy_archive_lookup"),f.calls.map { it.getString("action") });f.assertOrdinaryExact(ordinary)
        f.unknown=false;f.backend().reconcile(f.store().read());assertEquals(60,f.store().readRequests().getJSONArray("requests").length());f.assertOrdinaryExact(ordinary)
        assertTrue(f.calls.all { it.getString("action")=="legacy_archive_lookup" })
    }
    @Test fun fullJournalAckPruneCrashRecoversExactColdAckAndLeavesUnrelatedUnknowns()=test(false) { f ->
        val ordinary=f.fill(unknownOrdinary=true);f.expectedHotRows=65;AtomicFileFaults.failFileOnce="journal.bin"
        refuse { f.backend().reconcile(f.store().read()) };assertEquals(6,f.store().readColdAttempt(f.attempt.attemptId)!!.getInt("contract_version"))
        assertTrue(f.store().read().attempts.isEmpty());assertEquals(60,f.store().readRequests().getJSONArray("requests").length());f.assertOrdinaryExact(ordinary)
        assertEquals(1,f.calls.count { it.getString("action")=="archive_legacy_attempt" })
    }
    @Test fun fullUnknownMaintenanceJournalRestoresOnlyAsInactiveExactEvidence()=test(false) { f ->
        val ordinary=f.fill();f.failArchiveMutation=true;refuse { f.backend().reconcile(f.store().read()) };val original=f.maintenance()
        val exported=f.store().exportRecovery(File(f.root,"pending-export"));val restored=f.store().restoreRecovery(exported.directory,exported.manifestSha256,File(f.root,"pending-restore"))
        assertTrue(restored.keyValidated);assertTrue(File(restored.directory,GatewayRecovery.INACTIVE).isFile)
        assertTrue(File(restored.directory,"view").renameTo(File(restored.directory,"collect_gateway_v1")))
        val recovered=GatewayEncryptedStore(LocalContext(restored.directory)) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 27 },"AES"),"CollectGateway/$name/v1") }
        val rows=recovered.readRequests().getJSONArray("requests");assertEquals(65,rows.length())
        requireSameRequest(original,(0 until rows.length()).map { GatewayStoredRequest.parse(rows.getJSONObject(it)) }.single { it.action=="archive_legacy_attempt" })
        assertEquals(ordinary.size+5,rows.length());refuse { recovered.requireActiveInstallation() }
    }
    @Test fun corruptedOverflowIsRetainedOpaqueButCannotPassReadOrInactiveRestoreValidation()=test(false) { f ->
        f.fill();f.failArchiveMutation=true;refuse { f.backend().reconcile(f.store().read()) }
        val rows=JSONArray(f.store().readRequests().getJSONArray("requests").toString()).put(f.row("heartbeat",JSONObject()));f.corruptHot(rows)
        val originalBytes=File(f.root,"collect_gateway_v1/requests.bin").readBytes();refuse { f.store().readRequests() }
        val exported=f.store().exportRecovery(File(f.root,"corrupt-export"))
        refuse { f.store().restoreRecovery(exported.directory,exported.manifestSha256,File(f.root,"corrupt-restore")) }
        assertArrayEquals(originalBytes,File(f.root,"collect_gateway_v1/requests.bin").readBytes());assertTrue(File(f.root,"corrupt-restore/"+GatewayRecovery.INACTIVE).isFile)
    }
    @Test fun legacyColdEvidenceAndOriginalRequestsSurviveInactiveCiphertextRestore()=test { f ->
        f.backend().reconcile(f.storage.read());GatewayJournal(f.store()).record(f.callback(1))
        val exported=f.store().exportRecovery(File(f.root,"export"));val restored=f.store().restoreRecovery(exported.directory,exported.manifestSha256,File(f.root,"restore"))
        assertTrue(restored.keyValidated);assertTrue(File(restored.directory,GatewayRecovery.INACTIVE).isFile)
        assertTrue(File(restored.directory,"view").renameTo(File(restored.directory,"collect_gateway_v1")))
        val context=LocalContext(restored.directory);val recovered=GatewayEncryptedStore(context) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 27 },"AES"),"CollectGateway/$name/v1") }
        assertEquals(6,recovered.readColdAttempt(f.attempt.attemptId)!!.getInt("contract_version"));requireSameRequest(f.original(),recovered.readRetainedRequest(f.original().requestId)!!)
        assertTrue(recovered.coldStop());refuse { recovered.requireActiveInstallation() }
    }
}
