package app.cool.mobile.gateway

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.security.KeyStore
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import javax.crypto.SecretKey

/** Actual unchanged operator/channel/picker/transfer/readback/custody callers.
 * Activity, SAF and software JCA provider are explicit offline platform seams. */
class GatewayRecoveryOperatorV2Test {
    private fun id() = UUID.randomUUID().toString()
    private class Reply : MethodChannel.Result {
        val result = CompletableFuture<Map<String,Any?>>()
        override fun success(value: Any?) { @Suppress("UNCHECKED_CAST") result.complete(value as Map<String,Any?>) }
        override fun error(code: String, message: String?, details: Any?) { result.complete(mapOf("state" to "failed", "reason_code" to code)) }
        override fun notImplemented() { result.completeExceptionally(AssertionError("Operation unavailable")) }
        fun await() = result.get(30, TimeUnit.SECONDS)
    }
    private inner class Fixture(val family: String, val version: Int) : AutoCloseable {
        val root = Files.createTempDirectory("collect-operator-v2-").toFile()
        val activity = GatewayActivity(root)
        val messenger = object : BinaryMessenger {}
        val store: GatewayEncryptedStore
        val operator: GatewayRecoveryOperator
        val directory get() = File(root, "collect_gateway_v1")
        val device = id()
        val route = when(family) {
            "primary" -> GatewayDispatchRoute.PrimaryV2
            "successor" -> GatewayDispatchRoute.ReceiptSuccessorV1(id(), id(), id())
            else -> GatewayDispatchRoute.ReceiptNoticeV1(id(), id(), id(), family)
        }
        val at = Instant.now()
        val attempt = GatewayAttempt(device, when(val r=route) {
            is GatewayDispatchRoute.PrimaryV2 -> id()
            is GatewayDispatchRoute.ReceiptSuccessorV1 -> r.dispatchJobId
            is GatewayDispatchRoute.ReceiptNoticeV1 -> r.noticeJobId
        }, id(), 1, "a".repeat(64), "b".repeat(64), at.plusSeconds(120).toString(), at.toString(), "c".repeat(64),
            listOf(SegmentEvidence()), dispatchRoute=route)
        init {
            GatewaySyntheticKeyStore.install(); GatewaySyntheticKeyStore.legacySigning(); GatewaySyntheticKeyStore.legacyStorage()
            store=GatewayEncryptedStore(activity)
            store.saveEnrollment(JSONObject().put("contract_version",1).put("device_id",device).put("installation_id",id())
                .put("key_sha256",GatewayDeviceIdentity().keyId()).put("signing_certificate_sha256","d".repeat(64)))
            val journal=GatewayJournal(store);journal.resume();journal.reserveInvocation(attempt);journal.prepareInvocation(attempt);journal.pause()
            if(version==2 && family=="primary") raw("journal", JSONObject().put("contract_version",2).put("emergency_paused",true).put("attempts",JSONArray(listOf(journalAttemptJsonV2(attempt)))))
            operator=GatewayRecoveryOperator(activity,messenger)
        }
        fun crypto(name: String): GatewayCrypto {
            val keys=KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }
            return GatewayCrypto(keys.getKey(GatewayKeyCreationCustody.STORAGE_ALIAS,null) as SecretKey, "CollectGateway/$name/v1")
        }
        fun raw(name: String, value: JSONObject) { File(directory,"$name.bin").writeBytes(crypto(name).encrypt(value.toString().toByteArray())) }
        fun journal() = JSONObject(String(crypto("journal").decrypt(File(directory,"journal.bin").readBytes())))
        fun bytes() = directory.listFiles()!!.filter { it.isFile }.associate { it.name to it.readBytes() }
        fun unchanged(before: Map<String,ByteArray>) { val after=bytes();assertEquals(before.keys,after.keys);before.forEach { (n,b) -> assertArrayEquals(n,b,after[n]) } }
        fun call(method: String, arguments: Any?=null): Reply = Reply().also { MethodChannel.invoke(messenger,"collect/gateway.recovery.v1",method,arguments,it) }
        fun picker(method: String, target: File, arguments: Any?=null): Map<String,Any?> {
            val reply=call(method,arguments);val picked=activity.picked.poll(30,TimeUnit.SECONDS) ?: throw AssertionError("Actual operator did not launch picker: "+reply.result.getNow(null))
            assertEquals(if(method=="export")Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT,picked.second.action)
            assertTrue(operator.activityResult(picked.first,Activity.RESULT_OK,Intent().apply { data=Uri.parse(target.absolutePath) }))
            return reply.await()
        }
        fun requirePause()=GatewayRecoveryPause.require(directory, ::crypto)
        fun noGeneration() { assertEquals(0,GatewaySyntheticKeyStore.signingGenerations);assertEquals(0,GatewaySyntheticKeyStore.storageGenerations) }
        override fun close() { operator.close(); GatewaySyntheticKeyStore.remove(); root.deleteRecursively() }
    }
    private fun fixture(family: String="primary",version: Int=1,action: (Fixture)->Unit) { Fixture(family,version).use(action) }
    private fun exportRestore(family: String,version: Int) = fixture(family,version) { f ->
        val before=f.bytes();val source=f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE,f.attempt.attemptId)!!.toString()
        assertEquals(version,f.journal().getInt("contract_version"));val output=File(f.root,"operator.collect-gateway")
        val exported=f.picker("export",output);assertEquals("complete",exported["state"]);assertTrue(output.length()>0)
        val sha=exported["manifest_sha256"] as String
        val restored=f.picker("restore",output,mapOf("manifest_sha256" to sha));assertEquals("complete",restored["state"])
        assertEquals(true,restored["inactive"]);assertEquals(true,restored["requires_re_enrollment"]);assertEquals(true,restored["key_validated"])
        f.unchanged(before);assertEquals(source,f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE,f.attempt.attemptId)!!.toString());f.noGeneration()
        val recovery=File(f.root,"collect_gateway_recovery").listFiles()!!.map { File(it,"inactive") }.single { it.exists() }
        assertTrue(File(recovery,GatewayRecovery.INACTIVE).isFile)
        before.forEach { (name,bytes) -> assertArrayEquals("Original "+name,bytes,File(recovery,"original/$name").readBytes()) }
        assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL,f.attempt.attemptId));assertEquals(AttemptOutcome.OUTCOME_UNKNOWN,f.store.read().attempts.single().outcome())
    }
    @Test fun actualOperatorPreservesPausedPrimaryV1Custody()=exportRestore("primary",1)
    @Test fun actualOperatorPreservesPausedPrimaryV2Custody()=exportRestore("primary",2)
    @Test fun actualOperatorPreservesPausedSuccessorV2Custody()=exportRestore("successor",2)
    @Test fun actualOperatorPreservesPausedDuplicateCopyNoticeV2Custody()=exportRestore("duplicate_copy",2)
    @Test fun actualOperatorPreservesPausedReversalNoticeV2Custody()=exportRestore("reversal_notice",2)
    @Test fun actualOperatorUnpausedV2RefusesBeforePickerAndRetainsOriginals()=fixture("successor",2) { f ->
        f.raw("journal",f.journal().put("emergency_paused",false));val before=f.bytes();val reply=f.call("export").await()
        assertEquals("failed",reply["state"]);assertEquals("gateway_recovery_pause_required",reply["reason_code"]);assertNull(f.activity.picked.poll());f.unchanged(before);f.noGeneration()
    }
    @Test fun actualOperatorMissingStorageAliasNeverGeneratesOrReplacesKey()=fixture("duplicate_copy",2) { f ->
        val before=f.bytes();GatewaySyntheticKeyStore.lose(GatewayKeyCreationCustody.STORAGE_ALIAS);val reply=f.call("export").await()
        assertEquals("gateway_storage_key_unavailable",reply["reason_code"]);assertNull(f.activity.picked.poll());f.unchanged(before);f.noGeneration()
    }
    @Test fun closedVersionTwoRejectsMissingUnknownOrCrossedFamilyWithoutMutation()=fixture("duplicate_copy",2) { f ->
        val original=f.journal();val row=original.getJSONArray("attempts").getJSONObject(0)
        val bad=listOf(JSONObject(row.toString()).also { it.remove("record_kind") },JSONObject(row.toString()).put("record_kind","arbitrary"),JSONObject(row.toString()).put("record_kind","primary_v2"),
            JSONObject(row.toString()).put("route",noticeRouteJson((f.route as GatewayDispatchRoute.ReceiptNoticeV1).copy(noticeJobId=id()))),JSONObject(row.toString()).put("extra",true))
        for(value in bad) { f.raw("journal",JSONObject(original.toString()).put("attempts",JSONArray(listOf(value))));val before=f.bytes();try { f.requirePause();fail("Bad closed v2 admitted") } catch(_:GatewayStateException) {} ;f.unchanged(before) }
        f.noGeneration()
    }
    @Test fun duplicateOrOverCapacityRowsCannotCreatePauseAuthority()=fixture("successor",2) { f ->
        val row=f.journal().getJSONArray("attempts").getJSONObject(0)
        for(rows in listOf(JSONArray(listOf(row,row)),JSONArray(List(101){row}))) { f.raw("journal",f.journal().put("attempts",rows));val before=f.bytes();try { f.requirePause();fail("Bound refused") } catch(_:GatewayStateException) {} ;f.unchanged(before) };f.noGeneration()
    }
    @Test fun historicalVersionOneCannotAcquireTaggedNoticeOrFutureVersion()=fixture("duplicate_copy",2) { f ->
        for(version in listOf(0,1,3)) { f.raw("journal",f.journal().put("contract_version",version));val before=f.bytes();try { f.requirePause();fail("Historical shape upgraded") } catch(_:GatewayStateException) {} ;f.unchanged(before) };f.noGeneration()
    }
    @Test fun backupPauseReadIsExactReadOnlyAndDoesNotRepairCrashBytes()=fixture("successor",2) { f ->
        val journal=File(f.directory,"journal.bin");File(f.directory,"journal.bin.bak").writeBytes(journal.readBytes());journal.writeBytes(byteArrayOf(3,2,1))
        val before=f.bytes();f.requirePause();f.unchanged(before);f.noGeneration()
        val backup=File(f.directory,"journal.bin.bak");backup.writeBytes(f.crypto("journal").encrypt(f.journalFromBackup().put("emergency_paused",false).toString().toByteArray()))
        val changed=f.bytes();try { f.requirePause();fail("Unpaused committed backup admitted") } catch(_:GatewayStateException) {} ;f.unchanged(changed)
    }
    private fun Fixture.journalFromBackup()=JSONObject(String(crypto("journal").decrypt(File(directory,"journal.bin.bak").readBytes())))
    @Test fun missingMarkerCorruptCiphertextAndInactiveEvidenceRemainRefused()=fixture("successor",2) { f ->
        val marker=File(f.directory,"journal-marker.bin");val original=marker.readBytes();marker.delete();var before=f.bytes();try { f.requirePause();fail("Missing marker admitted") } catch(_:GatewayStateException) {};f.unchanged(before);marker.writeBytes(original)
        val journal=File(f.directory,"journal.bin");journal.writeBytes(byteArrayOf(1));before=f.bytes();try { f.requirePause();fail("Corrupt ciphertext admitted") } catch(_:Exception) {};f.unchanged(before)
        File(f.directory,GatewayRecovery.INACTIVE).writeText("inactive");before=f.bytes();try { f.requirePause();fail("Inactive evidence admitted") } catch(_:Exception) {};f.unchanged(before);f.noGeneration()
    }
    @Test fun actualOperatorWrongManifestRetainsActiveEvidenceAndQuarantine()=fixture("duplicate_copy",2) { f ->
        val before=f.bytes();val output=File(f.root,"operator.collect-gateway");assertEquals("complete",f.picker("export",output)["state"])
        val reply=f.picker("restore",output,mapOf("manifest_sha256" to "e".repeat(64)));assertEquals("failed",reply["state"])
        assertEquals(true,reply["inactive"]);f.unchanged(before);f.noGeneration()
    }
}
