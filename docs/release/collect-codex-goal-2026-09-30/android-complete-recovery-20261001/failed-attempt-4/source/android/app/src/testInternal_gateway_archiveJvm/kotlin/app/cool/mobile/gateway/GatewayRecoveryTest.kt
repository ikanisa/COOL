package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.spec.ECGenParameterSpec
import javax.crypto.spec.SecretKeySpec

class GatewayRecoveryTest {
    private class LocalContext(private val root: File): Context() { override val noBackupFilesDir get()=root }
    private fun test(action:(GatewayLateFixture)->Unit) { val f=GatewayLateFixture();try { action(f) } finally { f.dispose() } }
    private fun refuse(code:String?=null, action:()->Unit) { try { action();fail("Expected refusal") } catch(e:Exception) { if(code!=null) { assertTrue(e is GatewayStateException);assertEquals(code,(e as GatewayStateException).reasonCode) } } }
    private fun export(f:GatewayLateFixture):GatewayRecoveryArchive = f.store().exportRecovery(File(f.root,"export-${f.id()}"))
    private fun restore(f:GatewayLateFixture,a:GatewayRecoveryArchive):GatewayRecoveryResult = f.store().restoreRecovery(a.directory,a.manifestSha256,File(f.root,"restore-${f.id()}"))
    private fun opened(f:GatewayLateFixture,result:GatewayRecoveryResult):GatewayEncryptedStore {
        val view=File(result.directory,"view");val installation=File(result.directory,"collect_gateway_v1")
        if(!installation.exists()) assertTrue(view.renameTo(installation))
        return GatewayEncryptedStore(LocalContext(result.directory)) { name -> f.crypto(name) }
    }
    private fun bytes(directory:File)=directory.listFiles()!!.associate { it.name to it.readBytes() }
    private fun same(before:Map<String,ByteArray>,after:File) { assertEquals(before.keys,after.list()!!.toSet());for((name,value) in before) assertArrayEquals(name,value,File(after,name).readBytes()) }
    @Test fun fullMultiPageInventoryRestoresHotUnknownOriginalsColdTerminalAndExactLateEvidenceInactive() = test { f ->
        val cold=f.seed(2);repeat(10) { f.append(cold,f.callback(cold,it,it,it%2)) };f.store().nextColdCallbackPage(8)
        val unknown=cold.copy(attemptId=f.id(),jobId=f.id(),segments=listOf(SegmentEvidence(f.id(),f.id())),invocationException=true)
        f.storage.commit(GatewayJournalState(false,listOf(unknown)))
        val request=f.request("heartbeat",JSONObject(),1);f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray().put(request)))
        val before=bytes(f.directory);var pages=0
        assertEquals(before.size.toLong(),GatewayRecovery.inventory(f.directory) { assertTrue(it.size in 1..8);pages++ });assertTrue(pages>2)
        val archive=export(f);same(before,f.directory);same(before,File(archive.directory,"objects"))
        val result=restore(f,archive);assertTrue(result.keyValidated);assertTrue(result.requiresReEnrollment);same(before,File(result.directory,"original"));same(before,f.directory)
        val recovered=opened(f,result);assertEquals(listOf(unknown),recovered.read().attempts);assertTrue(GatewayJournal(recovered).read().emergencyPaused)
        assertEquals(request.getString("request_bytes_base64"),recovered.readRetainedRequest(request.getString("request_id"))!!.row.getString("request_bytes_base64"));assertNull(recovered.readRequestReceipt(request.getString("request_id")))
        assertEquals(cold,archiveAttemptFromJson(recovered.readColdAttempt(cold.attemptId)!!.getJSONObject("attempt")))
        val all=mutableListOf<GatewayCallback>();var cursor:String?=null
        do { val page=recovered.coldCallbackPage(cursor,8);all.addAll(page.entries.map { it.callback });cursor=page.nextCursor } while(cursor!=null)
        assertEquals(10,all.size);assertTrue(recovered.coldStop())
        refuse("gateway_recovery_inactive") { GatewayJournal(recovered).resume() }
        refuse("gateway_recovery_inactive") { GatewayJournal(recovered).reserveInvocation(unknown.copy(attemptId=f.id(),invocationException=false)) }
    }
    @Test fun rawAtomicBackupAndPartialNewBytesRemainLosslessWhileValidationUsesCommittedBackup() = test { f ->
        f.storage.commit(GatewayJournalState(true))
        val committed=File(f.directory,"journal.bin").readBytes();File(f.directory,"journal.bin.bak").writeBytes(committed)
        File(f.directory,"journal.bin").writeBytes(byteArrayOf(1,2,3));File(f.directory,"journal.bin.new").writeBytes(byteArrayOf(9,8,7,6))
        val before=bytes(f.directory);val archive=export(f);same(before,f.directory)
        val result=restore(f,archive);same(before,File(result.directory,"original"));same(before,f.directory)
        assertTrue(opened(f,result).read().attempts.isEmpty());assertArrayEquals(byteArrayOf(9,8,7,6),File(result.directory,"collect_gateway_v1/journal.bin.new").readBytes())
    }
    @Test fun interruptedPendingHotOriginalRepairsExactBytesOnlyInInactiveView() = test { f ->
        val callback=f.id();val row=f.request("callback",JSONObject().put("callback_id",callback).put("attempt_id",f.id()),2)
        val key=sha256(callback+"\n"+retentionCanonical(GatewayStoredRequest.parse(row).envelope.getJSONObject("payload"))).take(32)
        AtomicFileFaults.failFileOnce="retention-callback-body-$key.bin"
        refuse("gateway_storage_unavailable") { f.store().saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray().put(row))) }
        val before=bytes(f.directory);val archive=export(f);val result=restore(f,archive);same(before,f.directory);same(before,File(result.directory,"original"))
        val recovered=opened(f,result);val restored=recovered.readRequests().getJSONArray("requests").getJSONObject(0)
        assertEquals(row.getString("request_id"),restored.getString("request_id"));assertEquals(row.getString("request_bytes_base64"),restored.getString("request_bytes_base64"));assertEquals("outcome_unknown",restored.getString("state"))
        assertNull(recovered.readRequestReceipt(row.getString("request_id")));assertTrue(recovered.coldStop())
    }
    @Test fun interruptedLatePendingPublicationRepairsOriginalWithoutResettingStopOrCursorAuthority() = test { f ->
        val a=f.seed();val callback=f.callback(a)
        val key=sha256(retentionCanonical(JSONObject().put("contract_version",5).put("attempt_id",a.attemptId).put("callback",gatewayLateCallbackJson(callback)))).take(32)
        AtomicFileFaults.failFileOnce="retention-late-evidence-$key.bin";refuse { f.append(a,callback) }
        val before=bytes(f.directory);val result=restore(f,export(f));same(before,f.directory);same(before,File(result.directory,"original"))
        val recovered=opened(f,result);assertEquals(callback,recovered.coldCallbackPage(null,8).entries.single().callback);assertTrue(recovered.coldStop());assertTrue(recovered.readRequests().getJSONArray("requests").length()==0)
    }
    @Test fun missingIndexedObjectNodeColdSourceOrLegacyCatalogReferenceFailsClosedAndRetainsOriginal() {
        for(fault in listOf("object","node","cold","legacy")) test { f ->
            val a=f.seed();f.append(a);val entry=f.pages().single()
            when(fault) {
                "object" -> assertTrue(File(f.directory,"retention-late-evidence-${entry.evidenceKey}.bin").delete())
                "node" -> assertTrue(File(f.directory,"retention-index-late-work-${entry.cursorKey.take(2)}.bin").delete())
                "cold" -> assertTrue(File(f.directory,"cold-${a.attemptId}.bin").delete())
                else -> f.write("cold-control",f.read("cold-control").put("cold_shards",JSONArray().put("ff")))
            }
            val before=bytes(f.directory);val archive=export(f);val target=File(f.root,"failed-${f.id()}")
            refuse { f.store().restoreRecovery(archive.directory,archive.manifestSha256,target) }
            same(before,File(target,"original"));assertTrue(File(target,GatewayRecovery.INACTIVE).isFile);assertFalse(File(target,"RESULT.json").exists());same(before,f.directory)
        }
    }
    @Test fun wrongKeyRefusesDecryptionAndOpaqueArchiveCanBePreservedWithoutClaimingValidation() = test { f ->
        f.storage.commit(GatewayJournalState(false));val before=bytes(f.directory);val archive=export(f)
        val wrong=GatewayEncryptedStore(f.context) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 88 },"AES"),"CollectGateway/$name/v1") }
        val target=File(f.root,"wrong-${f.id()}");refuse { wrong.restoreRecovery(archive.directory,archive.manifestSha256,target) };same(before,File(target,"original"));assertTrue(File(target,GatewayRecovery.INACTIVE).isFile)
        val opaque=GatewayRecovery.restore(archive.directory,archive.manifestSha256,File(f.root,"opaque-${f.id()}"),f.directory) { _,_ -> false }
        assertFalse(opaque.keyValidated);assertTrue(opaque.requiresReEnrollment);same(before,File(opaque.directory,"original"));same(before,f.directory)
    }
    @Test fun changedSourceCancellationAndBusyCycleNeverPublishCompleteExport() = test { f ->
        f.storage.commit(GatewayJournalState(true));val target=File(f.root,"cancelled-${f.id()}")
        refuse("gateway_recovery_cancelled") { f.store().exportRecovery(target) { true } };assertFalse(File(target,"SEALED.json").exists())
        val busy=File(f.root,"busy-${f.id()}")
        GatewayCycleGate.run { refuse("gateway_cycle_busy") { f.store().exportRecovery(busy) } };assertFalse(busy.exists())
        val changed=File(f.root,"changed-${f.id()}");var reads=0
        refuse { f.store().exportRecovery(changed) { if(++reads==3) File(f.directory,"journal.bin").writeBytes(byteArrayOf(1,2,3));false } }
        assertFalse(File(changed,"SEALED.json").exists())
    }
    @Test fun strictManifestDigestMissingTamperedExtrasSymlinksAndFreshTargetRejectWithoutActiveOverwrite() {
        for(fault in listOf("digest","missing","tamper","extra","symlink")) test { f ->
            f.storage.commit(GatewayJournalState(true));val before=bytes(f.directory);val archive=export(f);val first=File(archive.directory,"objects").listFiles()!!.first()
            when(fault) { "missing" -> assertTrue(first.delete());"tamper" -> first.appendBytes(byteArrayOf(1));"extra" -> File(first.parentFile,"extra.bin").writeBytes(byteArrayOf(1));"symlink" -> { val old=first.readBytes();assertTrue(first.delete());val external=File(f.root,"external.bin");external.writeBytes(old);Files.createSymbolicLink(first.toPath(),external.toPath()) } }
            refuse { f.store().restoreRecovery(archive.directory,if(fault=="digest") "0".repeat(64) else archive.manifestSha256,File(f.root,"denied-${f.id()}")) };same(before,f.directory)
            refuse { f.store().restoreRecovery(archive.directory,archive.manifestSha256,f.directory) };same(before,f.directory)
            val occupied=File(f.root,"occupied-${f.id()}");occupied.mkdir();File(occupied,"keep").writeText("preserve")
            refuse { f.store().restoreRecovery(archive.directory,archive.manifestSha256,occupied) };assertEquals("preserve",File(occupied,"keep").readText())
        }
    }
    @Test fun restoredHistoricalEnrollmentCannotConfigureProvisionResumeOrReachSignedTransport() = test { f ->
        val key=KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val hash=MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") { "%02x".format(it) };val installed=f.id()
        val metadata=JSONObject().put("contract_version",1).put("installation_id",installed).put("key_sha256",hash).put("signing_certificate_sha256","a".repeat(64)).put("public_key_spki_base64",java.util.Base64.getEncoder().encodeToString(key.public.encoded))
        val enrollment=JSONObject().put("contract_version",1).put("device_id",f.device).put("installation_id",installed).put("key_sha256",hash).put("signing_certificate_sha256","a".repeat(64))
        f.storage.saveIdentityMetadata(metadata);f.storage.saveEnrollment(enrollment);f.storage.commit(GatewayJournalState(false))
        val result=restore(f,export(f));val recovered=opened(f,result)
        assertEquals(f.device,GatewayInstalledEnrollment.verify(recovered.readIdentityMetadata(),recovered.readEnrollment(),hash,metadata.getString("public_key_spki_base64"),"a".repeat(64)))
        var connections=0;var signatures=0
        val transport=GatewayHttpsTransport({hash},{ signatures++;"unused" },{ connections++;throw java.io.IOException("Must not connect") })
        val backend=GatewaySignedBackend(LocalContext(result.directory),recovered,GatewayDeviceIdentity(),{hash},transport)
        refuse("gateway_recovery_inactive") { backend.configured() };refuse("gateway_recovery_inactive") { backend.reconcile(recovered.read()) }
        refuse("gateway_recovery_inactive") { backend.dispatchGrant(GatewayObservations(false,false,false,false,false,false,false,null,false)) }
        refuse("gateway_recovery_inactive") { recovered.saveEnrollment(enrollment) };refuse("gateway_recovery_inactive") { recovered.saveIdentityMetadata(metadata) };refuse("gateway_recovery_inactive") { GatewayJournal(recovered).resume() }
        assertEquals(0,connections);assertEquals(0,signatures);assertTrue(recovered.coldStop());assertTrue(GatewayJournal(recovered).read().emergencyPaused)
    }
}
