package app.cool.mobile.gateway

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.security.KeyStore
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.SecretKey

/** Actual Bridge pause/epoch, RecoveryOperator channel and Store export callers.
 * Platform/observations/scheduler are explicit offline adapters; keys are legacy
 * software JCA fixtures. Neither a physical SDK send nor backend owner action. */
class GatewayRealmPreparationOperatorTest {
    private fun id()=UUID.randomUUID().toString()
    private class Reply:MethodChannel.Result {
        val value=CompletableFuture<Map<String,Any?>>()
        override fun success(result:Any?) { @Suppress("UNCHECKED_CAST") value.complete(result as Map<String,Any?>) }
        override fun error(code:String,message:String?,details:Any?) { value.complete(mapOf("state" to "failed","reason_code" to code)) }
        override fun notImplemented() { value.completeExceptionally(AssertionError("Missing operation")) }
        fun await()=value.get(30,TimeUnit.SECONDS)
    }
    private inner class Fixture(val family:String="primary"):AutoCloseable {
        val root=Files.createTempDirectory("collect-preparation-").toFile()
        val activity=GatewayActivity(root)
        val messenger=object:BinaryMessenger {}
        val store:GatewayEncryptedStore
        val bridge:GatewayBridge
        val operator:GatewayRecoveryOperator
        val realm get()=File(root,"collect_gateway_v1")
        val identity=GatewayDeviceIdentity()
        val device=id()
        val refs=GatewayRealmPreparation.References(id(),id(),id())
        val route=when(family) { "primary" -> GatewayDispatchRoute.PrimaryV2;"successor" -> GatewayDispatchRoute.ReceiptSuccessorV1(id(),id(),id());else -> GatewayDispatchRoute.ReceiptNoticeV1(id(),id(),id(),family) }
        val at=Instant.now()
        val attempt=GatewayAttempt(device,when(val r=route) { is GatewayDispatchRoute.PrimaryV2 -> id();is GatewayDispatchRoute.ReceiptSuccessorV1 -> r.dispatchJobId;is GatewayDispatchRoute.ReceiptNoticeV1 -> r.noticeJobId },id(),1,"a".repeat(64),"b".repeat(64),at.plusSeconds(120).toString(),at.toString(),"c".repeat(64),listOf(SegmentEvidence()),dispatchRoute=route)
        init {
            GatewaySyntheticKeyStore.install();GatewaySyntheticKeyStore.legacySigning();GatewaySyntheticKeyStore.legacyStorage()
            store=GatewayEncryptedStore(activity)
            // Existing legacy metadata is fixture source. Creating new identity
            // metadata beside retained aliases is correctly refused by custody.
            val metadata=JSONObject().put("contract_version",1).put("installation_id",id()).put("key_sha256",identity.keyId())
                .put("signing_certificate_sha256","d".repeat(64)).put("public_key_spki_base64",identity.publicKeyBase64())
            File(realm,"identity.bin").writeBytes(crypto("identity").encrypt(metadata.toString().toByteArray()))
            store.saveEnrollment(JSONObject().put("contract_version",1).put("device_id",device).put("installation_id",metadata.getString("installation_id"))
                .put("key_sha256",identity.keyId()).put("signing_certificate_sha256","d".repeat(64)))
            val journal=GatewayJournal(store);journal.resume();journal.reserveInvocation(attempt);journal.prepareInvocation(attempt)
            bridge=GatewayBridge(activity,messenger);operator=GatewayRecoveryOperator(activity,messenger,bridge::pauseForPreparation)
        }
        fun arguments(ref:GatewayRealmPreparation.References=refs)=mapOf("contract_version" to 1,"preparation_request_id" to ref.preparation,"revoke_request_id" to ref.revoke,"enrollment_request_id" to ref.enroll)
        fun call(arguments:Any?=arguments()):Reply=Reply().also { MethodChannel.invoke(messenger,"collect/gateway.recovery.v1","prepareReEnrollment",arguments,it) }
        fun plan(ref:GatewayRealmPreparation.References=refs)=File(root,"${GatewayRealmPreparation.NAMESPACE}/plans/${ref.preparation}")
        fun raw()=realm.listFiles()!!.filter { it.isFile }.associate { it.name to it.readBytes() }
        fun crypto(name:String):GatewayCrypto { val keys=KeyStore.getInstance("AndroidKeyStore").also { it.load(null) };return GatewayCrypto(keys.getKey(GatewayKeyCreationCustody.STORAGE_ALIAS,null) as SecretKey,"CollectGateway/$name/v1") }
        fun requirePause()=GatewayRecoveryPause.require(realm,::crypto)
        fun noGeneration() { assertEquals(0,GatewaySyntheticKeyStore.signingGenerations);assertEquals(0,GatewaySyntheticKeyStore.storageGenerations) }
        override fun close() { operator.close();bridge.close();GatewaySyntheticKeyStore.remove();root.deleteRecursively() }
    }
    private fun fixture(family:String="primary", action:(Fixture)->Unit) { Fixture(family).use(action) }
    private fun retained(f:Fixture):Map<String,Any?> {
        val identity=f.raw().getValue("identity.bin");val enrolled=f.raw().getValue("enrollment.bin")
        val source=f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE,f.attempt.attemptId)!!.toString()
        val result=f.call().await();assertEquals("complete",result["state"]);assertEquals(true,result["inactive"])
        assertEquals(false,result["backend_revocation_proven"]);assertEquals(false,result["dispatch_authority"]);f.requirePause()
        val intent=JSONObject(File(f.plan(),"intent.json").readText());assertEquals(f.device,intent.getJSONObject("old_enrollment").getString("device_id"))
        assertEquals(f.refs.revoke,intent.getString("revoke_request_id"));assertEquals(f.refs.enroll,intent.getString("enrollment_request_id"))
        val snapshot=File(f.plan(),"snapshot/objects");f.raw().forEach { (name,bytes) -> assertArrayEquals(name,bytes,File(snapshot,name).readBytes()) }
        assertArrayEquals(identity,File(f.realm,"identity.bin").readBytes());assertArrayEquals(enrolled,File(f.realm,"enrollment.bin").readBytes())
        assertEquals(source,f.store.readInvocationRecord(GatewayInvocationCustody.PREPARE,f.attempt.attemptId)!!.toString())
        assertNull(f.store.readInvocationRecord(GatewayInvocationCustody.TERMINAL,f.attempt.attemptId));assertEquals(AttemptOutcome.OUTCOME_UNKNOWN,f.store.read().attempts.single().outcome());f.noGeneration()
        return result
    }
    @Test fun actualOperatorPrimaryPauseAndExactOriginalExport()=fixture { retained(it) }
    @Test fun actualOperatorSuccessorV2PreservesPreparedUnknown()=fixture("successor") { retained(it) }
    @Test fun actualOperatorNoticeV2PreservesPreparedUnknown()=fixture("duplicate_copy") { retained(it) }
    @Test fun originalUuidReplayReadsOriginalCompletedSnapshot()=fixture { f ->
        val first=retained(f);val plan=f.plan();val before=plan.walkTopDown().filter { it.isFile }.associate { it.relativeTo(plan).path to it.readBytes() }
        val second=f.call().await();assertEquals(first,second);before.forEach { (name,bytes) -> assertArrayEquals(name,bytes,File(plan,name).readBytes()) };f.noGeneration()
    }
    @Test fun originalUuidConflictingReferencesRefuseWithoutChangingOriginal()=fixture { f ->
        retained(f);val original=File(f.plan(),"intent.json").readBytes();val reply=f.call(f.arguments(f.refs.copy(revoke=id()))).await()
        assertEquals("gateway_preparation_conflict",reply["reason_code"]);assertArrayEquals(original,File(f.plan(),"intent.json").readBytes());f.requirePause();f.noGeneration()
    }
    @Test fun ownerUuidCannotCrossToAnotherPreparation()=fixture { f ->
        retained(f);val original=File(f.plan(),"complete.json").readBytes();val other=GatewayRealmPreparation.References(id(),f.refs.revoke,id())
        assertEquals("gateway_preparation_conflict",f.call(f.arguments(other)).await()["reason_code"])
        assertTrue(File(f.plan(other),"intent.json").isFile);assertFalse(File(f.plan(other),"snapshot").exists());assertArrayEquals(original,File(f.plan(),"complete.json").readBytes())
    }
    @Test fun completionLossKeepsOriginalSnapshotUnknownWithoutRegeneration()=fixture { f ->
        retained(f);val snapshot=File(f.plan(),"snapshot");val before=File(snapshot,"manifest.ndjson").readBytes();assertTrue(File(f.plan(),"complete.json").delete())
        assertEquals("gateway_preparation_unknown",f.call().await()["reason_code"]);assertArrayEquals(before,File(snapshot,"manifest.ndjson").readBytes());assertFalse(File(f.plan(),"complete.json").exists());f.requirePause()
    }
    @Test fun uuidIndexLossIsUnknownAndNeverRecreated()=fixture { f ->
        retained(f);val file=File(f.root,"${GatewayRealmPreparation.NAMESPACE}/requests/${f.refs.revoke}.json");assertTrue(file.delete())
        assertEquals("gateway_preparation_unknown",f.call().await()["reason_code"]);assertFalse(file.exists());f.requirePause()
    }
    @Test fun partialIntentCancellationRetainsUnknownOriginalUuid()=fixture { f ->
        val certificate=f.bridge.pauseForPreparation();var checks=0
        try { GatewayRealmPreparation(f.root,f.store).prepare(f.refs,certificate,{++checks==2},f::requirePause);fail("Cancellation expected") } catch(e:GatewayStateException) { assertEquals("gateway_recovery_cancelled",e.reasonCode) }
        assertTrue(File(f.plan(),"intent.json").isFile);assertFalse(File(f.plan(),"snapshot").exists())
        assertEquals("gateway_preparation_unknown",f.call().await()["reason_code"]);assertFalse(File(f.plan(),"snapshot").exists());f.requirePause();f.noGeneration()
    }
    @Test fun busyNetworkGateLeavesPauseAndRetainedIntent()=fixture { f ->
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val task=CompletableFuture.runAsync { GatewayCycleGate.run { entered.countDown();release.await(20,TimeUnit.SECONDS) } }
        assertTrue(entered.await(10,TimeUnit.SECONDS));try { assertEquals("gateway_cycle_busy",f.call().await()["reason_code"]);f.requirePause();assertTrue(File(f.plan(),"intent.json").isFile) } finally { release.countDown();task.get(30,TimeUnit.SECONDS) }
        assertEquals("gateway_preparation_unknown",f.call().await()["reason_code"]);f.noGeneration()
    }
    @Test fun bridgePauseDrainsFinalLockAndRejectsEveryEarlierAllowEpoch()=fixture { f ->
        val field=GatewayBridge::class.java.getDeclaredField("localIntents").apply { isAccessible=true };val intents=field.get(f.bridge) as GatewayLocalDispatchIntent
        val epochs=List(4) { intents.generation() };val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val finalSeam=CompletableFuture.runAsync { synchronized(GatewayJournal.PROCESS_LOCK) { entered.countDown();release.await(20,TimeUnit.SECONDS) } }
        assertTrue(entered.await(10,TimeUnit.SECONDS));val reply=f.call();Thread.sleep(100);assertFalse(reply.value.isDone);release.countDown();finalSeam.get(30,TimeUnit.SECONDS)
        assertEquals("complete",reply.await()["state"])
        epochs.forEach { epoch -> try { intents.allow(epoch,GatewayJournal(f.store));fail("Superseded allow") } catch(e:GatewayStateException) { assertEquals("gateway_local_intent_superseded",e.reasonCode) } }
        f.requirePause();intents.allow(intents.generation(),GatewayJournal(f.store));assertFalse(f.store.read().emergencyPaused) // later manual intent is separate
    }
    @Test fun initialPreparationStatusNeverAttestsInactiveBeforePauseCompletes()=fixture { f ->
        assertFalse(f.store.read().emergencyPaused)
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val held=CompletableFuture.runAsync { synchronized(GatewayJournal.PROCESS_LOCK) { entered.countDown();release.await(20,TimeUnit.SECONDS) } }
        assertTrue(entered.await(10,TimeUnit.SECONDS))
        try {
            val reply=f.call();val status=Reply()
            MethodChannel.invoke(f.messenger,"collect/gateway.recovery.v1","status",null,status)
            val initial=status.await();assertEquals("working",initial["state"]);assertEquals("pausing",initial["phase"])
            assertEquals(false,initial["inactive"]);assertFalse(reply.value.isDone)
            release.countDown();held.get(30,TimeUnit.SECONDS)
            val complete=reply.await();assertEquals("complete",complete["state"]);assertEquals(true,complete["inactive"])
            f.requirePause();f.noGeneration()
        } finally { release.countDown();held.get(30,TimeUnit.SECONDS) }
    }
    @Test fun lostSigningOrStorageAliasNeverGeneratesReplacement() { for(alias in listOf(GatewayKeyCreationCustody.SIGNING_ALIAS,GatewayKeyCreationCustody.STORAGE_ALIAS)) fixture { f ->
        assertFalse(f.store.read().emergencyPaused);val before=f.raw()
        GatewaySyntheticKeyStore.lose(alias);val reply=f.call().await()
        assertEquals("gateway_preparation_source_unavailable",reply["reason_code"]);assertEquals(false,reply["inactive"])
        val after=f.raw();assertEquals(before.keys,after.keys);before.forEach { (name,bytes) -> assertArrayEquals(name,bytes,after[name]) }
        assertFalse(File(f.root,GatewayRealmPreparation.NAMESPACE).exists());f.noGeneration()
    } }
    @Test fun untrustedArgumentsRefuseBeforePauseOrEvidence()=fixture { f ->
        val args=f.arguments().toMutableMap<String,Any>();args["destination"]="+250000000000"
        assertEquals("gateway_preparation_arguments_invalid",f.call(args).await()["reason_code"]);assertFalse(f.store.read().emergencyPaused);assertFalse(File(f.root,GatewayRealmPreparation.NAMESPACE).exists())
    }
    @Test fun retainedBackupsAndStagesRefuseBeforeReaderRepair() {
        for(name in listOf("identity","enrollment","journal"))for(suffix in listOf("bak","new"))fixture { f ->
            assertFalse(f.store.read().emergencyPaused)
            File(f.realm,"$name.bin.$suffix").writeBytes(File(f.realm,"$name.bin").readBytes());val before=f.raw()
            val reply=f.call().await();assertEquals("gateway_preparation_source_ambiguous",reply["reason_code"]);assertEquals(false,reply["inactive"])
            val after=f.raw();assertEquals(before.keys,after.keys);before.forEach { (key,bytes) -> assertArrayEquals(key,bytes,after[key]) }
            assertFalse(File(f.root,GatewayRealmPreparation.NAMESPACE).exists());f.noGeneration()
        }
    }
    @Test fun opaqueSourceSymlinkRefusesWithoutTouchingRetainedBytes()=fixture { f ->
        val original=File(f.realm,"identity.bin").readBytes();val external=File(f.root,"foreign.bin");external.writeBytes(byteArrayOf(1,2,3))
        Files.createSymbolicLink(File(f.realm,"opaque.bin").toPath(),external.toPath())
        assertEquals("gateway_preparation_source_ambiguous",f.call().await()["reason_code"])
        assertArrayEquals(original,File(f.realm,"identity.bin").readBytes());assertArrayEquals(byteArrayOf(1,2,3),external.readBytes());f.noGeneration()
    }
    @Test fun completedSnapshotSymlinkRefusesWithoutReadingForeignRealm()=fixture { f ->
        retained(f);val snapshot=File(f.plan(),"snapshot");val original=File(f.plan(),"retained-original-snapshot")
        assertTrue(snapshot.renameTo(original));Files.createSymbolicLink(snapshot.toPath(),original.toPath())
        // Keep the closed plan shape while the foreign source is outside it.
        val outside=File(f.root,"original-snapshot");assertTrue(original.renameTo(outside));Files.delete(snapshot.toPath());Files.createSymbolicLink(snapshot.toPath(),outside.toPath())
        assertEquals("gateway_recovery_invalid",f.call().await()["reason_code"]);assertTrue(File(outside,"manifest.ndjson").isFile);f.requirePause()
    }
    @Test fun symlinkNamespaceRefusesAndRetainsPause()=fixture { f ->
        val target=Files.createTempDirectory("collect-preparation-foreign-").toFile();try { Files.createSymbolicLink(File(f.root,GatewayRealmPreparation.NAMESPACE).toPath(),target.toPath())
            assertEquals("gateway_recovery_invalid",f.call().await()["reason_code"]);assertEquals(0,target.listFiles()!!.size);f.requirePause();f.noGeneration()
        } finally { target.deleteRecursively() }
    }
}
