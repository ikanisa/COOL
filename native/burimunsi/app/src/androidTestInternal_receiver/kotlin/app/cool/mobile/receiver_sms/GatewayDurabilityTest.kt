package app.cool.mobile.receiver_sms

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.cool.mobile.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.core.*
import java.io.File
import java.util.UUID

/** Real Android storage/JSON/Keystore tests. Execute only in the offline nativeTest sandbox.
 * Each test owns unique preferences and a private no-backup directory. Never clear app data,
 * remove a production key, change a SIM, contact a server or access a real SMS inbox here.
 */
@RunWith(AndroidJUnit4::class)
class GatewayDurabilityTest {
    private lateinit var context: Context
    private lateinit var root: File
    private val owner = "synthetic-owner"
    private lateinit var base: Context
    private lateinit var prefix: String
    @Before fun isolatedStorage() {
        base = InstrumentationRegistry.getInstrumentation().targetContext
        check(base.packageName == "rw.ikanisa.burimunsi.gateway.cloud.nativeTest" &&
            BuildConfig.APPLICATION_ID == base.packageName && BuildConfig.BUILD_TYPE == "nativeTest" &&
            BuildConfig.IS_GATEWAY && BuildConfig.IS_QUALIFICATION && BuildConfig.DEBUG) {
            "Dedicated offline receiver sandbox required"
        }
        val flags = base.applicationInfo.flags
        check(flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 && flags and ApplicationInfo.FLAG_TEST_ONLY != 0)
        check(flags and ApplicationInfo.FLAG_ALLOW_BACKUP == 0 && flags and ApplicationInfo.FLAG_USES_CLEARTEXT_TRAFFIC == 0)
        @Suppress("DEPRECATION")
        val info = base.packageManager.getPackageInfo(base.packageName, PackageManager.GET_PERMISSIONS)
        check("android.permission.INTERNET" !in info.requestedPermissions.orEmpty()) {
            "Sandbox must have no network permission"
        }
        check(listOf("android.permission.READ_SMS", "android.permission.RECEIVE_SMS",
            "android.permission.SEND_SMS", "android.permission.READ_PHONE_STATE").all {
            base.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }) { "Sandbox must have no granted SMS or phone permissions" }
        prefix = "sms_r1_test_" + UUID.randomUUID().toString()
        root = File(base.noBackupFilesDir, prefix).apply { check(mkdir()) }
        context = object : ContextWrapper(base) {
            override fun getNoBackupFilesDir(): File = root
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                base.getSharedPreferences(prefix + "_" + name, mode)
        }
        assertTrue(SmsQueueStore(context).enableForOwner(owner))
    }
    @After fun removeOnlyThisTestsStorage() {
        if (::root.isInitialized) { check(root.name == prefix); root.deleteRecursively() }
        if (::base.isInitialized && ::prefix.isInitialized) base.deleteSharedPreferences(prefix + "_" + SmsQueueStore.SMS_ACCESS_PREFS)
    }
    private fun envelope(id: String = "synthetic-id", body: String = "Synthetic receipt — not a carrier observation") =
        JSONObject().put("id", id).put("owner_user_id", owner).put("raw_body", body)
            .put("captured_at", "2026-11-09T00:00:00Z")
    @Test fun retainedCiphertextReopensInAnotherStoreInstance() {
        val row = envelope()
        assertEquals(SmsQueueStore.AppendResult.STORED, SmsQueueStore(context).appendIfCapacity(row, 4))
        val reopened = SmsQueueStore(context).readForOwner(owner)
        assertEquals(row.getString("raw_body"), reopened.getJSONObject(0).getString("raw_body"))
        val disk = File(root, "burimunsi_sms_queue_v2.enc").readText()
        assertFalse(disk.contains(row.getString("raw_body")))
    }
    @Test fun duplicateIdentityCannotHideDifferentEvidence() {
        val queue = SmsQueueStore(context)
        assertEquals(SmsQueueStore.AppendResult.STORED, queue.appendIfCapacity(envelope(), 4))
        assertEquals(SmsQueueStore.AppendResult.DUPLICATE, queue.appendIfCapacity(envelope(), 4))
        assertEquals(SmsQueueStore.AppendResult.FAILED, queue.appendIfCapacity(envelope(body="Changed evidence"), 4))
        assertEquals(1, queue.readForOwner(owner).length())
    }
    @Test fun durableAcknowledgementAndTombstoneSurviveReopen() {
        val row = envelope(); val queue = SmsQueueStore(context)
        assertEquals(SmsQueueStore.AppendResult.STORED, queue.appendIfCapacity(row, 4))
        val proof = mapOf(row.getString("id") to ReceiptAckPolicy.sha256(row.getString("raw_body")))
        assertFalse(queue.acknowledgeDurable("different-owner", proof))
        assertFalse(queue.acknowledgeDurable(owner, mapOf(row.getString("id") to "a".repeat(64))))
        assertTrue(queue.acknowledgeDurable(owner, proof))
        val reopened = SmsQueueStore(context)
        assertEquals(0, reopened.readForOwner(owner).length())
        assertTrue(reopened.acknowledgeDurable(owner, proof))
        assertEquals(SmsQueueStore.AppendResult.DUPLICATE, reopened.appendIfCapacity(row, 4))
    }
    @Test fun capacityPreservesExistingEvidenceAndLiveReserve() {
        val queue = SmsQueueStore(context)
        assertEquals(SmsQueueStore.AppendResult.STORED, queue.appendIfCapacity(envelope("one"), 2))
        assertEquals(SmsQueueStore.AppendResult.RESERVED, queue.appendIfCapacity(envelope("two"), 2, 1))
        assertEquals(SmsQueueStore.AppendResult.STORED, queue.appendIfCapacity(envelope("two"), 2))
        assertEquals(SmsQueueStore.AppendResult.FULL, queue.appendIfCapacity(envelope("three"), 2))
        assertEquals(2, queue.readForOwner(owner).length())
    }
    @Test fun pauseAndOwnerChangeNeverDiscardPendingEvidence() {
        val queue = SmsQueueStore(context)
        assertEquals(SmsQueueStore.AppendResult.STORED, queue.appendIfCapacity(envelope(), 4))
        assertTrue(queue.disablePreservingQueue(owner))
        assertFalse(queue.enableForOwner("different-owner"))
        assertEquals(1, queue.readForGateway(owner).length())
        assertTrue(queue.enableForOwner(owner))
        assertEquals(1, queue.readForOwner(owner).length())
    }
    @Test fun legacyControlTransitionReopensEncryptedAndHoldsObservation() {
        val queue = SmsQueueStore(context)
        assertEquals(SmsQueueStore.AppendResult.STORED, queue.appendIfCapacity(envelope(), 4))
        val marker = JSONObject().put("kind", "resume").put("collectionId", "synthetic-group")
            .put("accountId", "synthetic-admin").put("bindingId", "synthetic-binding").put("bindingVersion", 1)
        MomoGatewayStore(context).update { it.put("control_transition", marker) }
        val reopened = MomoGatewayStore(context).read()!!.getJSONObject("control_transition")
        assertEquals("synthetic-binding", reopened.getString("bindingId"))
        assertFalse(ObservationLegacyOwnership.controlTransitionClear(context))
        assertEquals(1, SmsQueueStore(context).readForOwner(owner).length())
        assertFalse(File(root, "collect_momo_gateway_v1.enc").readText().contains("synthetic-binding"))
        MomoGatewayStore(context).update { it.remove("control_transition") }
        assertTrue(ObservationLegacyOwnership.controlTransitionClear(context))
        assertEquals(1, SmsQueueStore(context).readForOwner(owner).length())
    }
    @Test fun legacyMigrationCopiesBeforeDeletingOriginal() {
        val prefs = context.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
        check(prefs.edit().putString("pending_sms", JSONArray().put(envelope()).toString()).commit())
        assertEquals(1, SmsQueueStore(context).readForOwner(owner).length())
        assertTrue(File(root, "burimunsi_sms_queue_v2.enc").isFile)
        assertFalse(prefs.contains("pending_sms"))
    }
    @Test fun corruptCiphertextBlocksOwnerResetAndPreservesBytes() {
        val file = File(root, "burimunsi_sms_queue_v2.enc")
        file.writeText("intentionally-corrupt-test-ciphertext")
        assertFalse(SmsQueueStore(context).enableForOwner(owner))
        assertEquals("intentionally-corrupt-test-ciphertext", file.readText())
    }
    @Test fun unresolvedObservationsStayEncryptedAndScopedAcrossReopen() {
        val body="You have received 1000 RWF from EXAMPLE (*****001) at 2026-11-07 12:00:00. Balance: 2000 RWF. FT Id: 123456789."
        val now=System.currentTimeMillis()
        val profile=ObservationProfile(ReceiptProfile("synthetic-profile",setOf("M-Money"),120,
            setOf("You have received"),setOf("RWF"),setOf("FT Id:")),now,now+86_400_000)
        val observation=SmsObservation(UUID.randomUUID().toString(),"M-Money",body,"catch_up",false,
            "2026-11-07T10:00:00Z",null,"2026-11-07T10:00:00Z",null,
            ObservationSourceIdentity.reinstallStable("1234567890abcdef","synthetic-group",101L,"2026-11-07T10:00:00Z"))
        val scope=ObservationOwner("synthetic-group","synthetic-admin");val rowId=101L
        val source=ObservationSourceIdentity.inbox("50000000-0000-4000-8000-000000000001",scope,rowId)
        assertEquals(ObservationAppend.STORED,ObservationJournal(ObservationStateStore(context)).append(scope,source,rowId,observation,profile,now))
        val file=File(root,"buri-observation-journal.v1")
        assertTrue(file.isFile);assertFalse(file.readBytes().toString(Charsets.ISO_8859_1).contains(body))
        val reopened=ObservationJournal(ObservationStateStore(context))
        assertEquals(observation,reopened.pending(scope).single().observation)
        assertTrue(reopened.pending(ObservationOwner("different-group","synthetic-admin")).isEmpty())
        assertFalse(reopened.acknowledge(scope,observation.requestId,ObservationAck(observation.requestId,"synthetic-source","0".repeat(64),"source_unresolved",0)))
        assertEquals(1,reopened.pending(scope).size)
    }
    @Test fun corruptObservationCiphertextDoesNotResetTheQueue() {
        val file=File(root,"buri-observation-journal.v1");file.writeText("synthetic-corrupt-ciphertext")
        assertTrue(runCatching{ObservationStateStore(context).read()}.isFailure)
        assertEquals("synthetic-corrupt-ciphertext",file.readText())
    }
    @Test fun observationProfileAndConsentAreEncryptedAndAccountScoped() {
        val now=System.currentTimeMillis();val scope=ObservationOwner("synthetic-group","synthetic-admin")
        val profile=JSONObject().put("profileVersion","synthetic-profile").put("senders",JSONArray().put("M-Money"))
            .put("incomingPrefixes",JSONArray().put("You have received")).put("currencyAliases",JSONArray().put("RWF"))
            .put("transactionIdPrefixes",JSONArray().put("FT Id:")).put("offsetMinutes",120)
            .put("issuedAt",now).put("expiresAt",now+86_400_000)
        val config=ObservationConfigStore(context);config.saveProfile(scope,profile,now)
        val consent=ObservationConsentState(ObservationConsentRevision(true,1),true);config.saveConsent(scope,consent)
        val reopened=ObservationConfigStore(context)
        assertEquals("synthetic-profile",reopened.profile(scope,now)?.receipt?.version);assertEquals(consent,reopened.consent(scope))
        assertNull(reopened.profile(ObservationOwner("other-group","synthetic-admin"),now))
        assertNull(reopened.consent(ObservationOwner("synthetic-group","other-admin")))
        assertFalse(File(root,"buri-observation-profile.v1").readBytes().toString(Charsets.ISO_8859_1).contains("synthetic-profile"))
    }
    @Test fun observationPauseIsEncryptedAndSurvivesAnotherAccount() {
        val owner=ObservationOwner("synthetic-group","synthetic-admin")
        val other=ObservationOwner("synthetic-group","synthetic-staff")
        val config=ObservationConfigStore(context)
        assertFalse(config.paused(owner));config.setPaused(owner,true);config.setPaused(other,true);config.setPaused(other,false)
        assertTrue(ObservationConfigStore(context).paused(owner));assertFalse(ObservationConfigStore(context).paused(other))
        val files=root.listFiles()!!.filter{it.name.startsWith("buri-observation-control-")}
        assertEquals(2,files.size)
        assertTrue(files.all{!it.readBytes().toString(Charsets.ISO_8859_1).contains("synthetic-admin")})
    }
    @Test fun pduCorrelationEvidenceIsEncryptedAndNeverPosts() {
        val now=System.currentTimeMillis();val owner=ObservationOwner("synthetic-group","synthetic-admin")
        val install="50000000-0000-4000-8000-000000000001"
        val text="You have received 1000 RWF. FT Id: 123456789."
        val data=text.toByteArray(Charsets.UTF_8)
        val pdu=byteArrayOf(0,0,2,0x91.toByte(),0x21,0,4,0,0,0,0,0,0,0,data.size.toByte())+data
        val profile=ObservationProfile(ReceiptProfile("synthetic-profile",setOf("M-Money"),120,
            setOf("You have received"),setOf("RWF"),setOf("FT Id:")),now,now+86_400_000)
        val witness=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,install,profile,now,3,"3gpp",
            listOf("M-Money"),listOf(now-1000),listOf(text),listOf(pdu))!!
        val row=PduInboxCorrelation.inbox(UUID.randomUUID().toString(),owner,install,profile,now,101,"M-Money",text,now-1000,now,3)!!
        val store=PduCorrelationStore(context)
        assertEquals(CorrelationWrite.STORED,store.record(witness));assertEquals(CorrelationWrite.STORED,store.record(row))
        val file=File(root,"buri-pdu-correlation.v1");assertTrue(file.isFile)
        assertFalse(file.readBytes().toString(Charsets.ISO_8859_1).contains(text))
        val reopened=PduCorrelationStore(context).read()
        assertEquals(CorrelationStatus.CORRELATED_UNVERIFIED,PduInboxCorrelation.status(reopened,witness.witnessId))
        val limited=PduCorrelationStore(context,pduLimit=1)
        assertEquals(CorrelationWrite.FULL,limited.record(witness.copy(witnessId=UUID.randomUUID().toString())))
        assertEquals(CorrelationStatus.AMBIGUOUS,PduInboxCorrelation.status(PduCorrelationStore(context).read(),witness.witnessId))
    }
    @Test fun offlineSandboxCannotCaptureObservations() {
        val session=ObservationSessionOwner(ObservationOwner("synthetic-group","synthetic-admin"),0)
        assertEquals(ObservationCapture.Result.UNAVAILABLE,ObservationCapture.retain(context,session,"0".repeat(64),"synthetic-id","M-Money","synthetic receipt","live",true,null,null,null))
        assertFalse(File(root,"buri-observation-journal.v1").exists())
    }
    @Test fun offlineSandboxCannotScanSmsInbox() {
        assertFalse(ObservationRecovery(context).scan())
        assertFalse(File(root,"buri-observation-cursors.v1").exists())
    }
    @Test fun continuousSupervisorRemainsOfflineInQualificationSandbox() {
        BuriContinuousSupervisor.recover(context,true)
        BuriContinuousSupervisor.start(context)
        assertFalse(BuriContinuousSupervisor.health().running)
        val scheduler=base.getSystemService(android.app.job.JobScheduler::class.java)
        assertTrue(listOf(904711,904712,904713).all{scheduler.getPendingJob(it)==null})
        assertFalse(File(root,"buri-observation-journal.v1").exists())
        val info=base.packageManager.getServiceInfo(android.content.ComponentName(base,BuriContinuousSyncService::class.java),0)
        assertFalse(info.exported)
        assertEquals(0,info.flags and android.content.pm.ServiceInfo.FLAG_STOP_WITH_TASK)
        if(android.os.Build.VERSION.SDK_INT>=34)
            assertTrue(info.foregroundServiceType and android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE!=0)
    }
    @Test fun continuousExecutionLeaseSurvivesAnInterruptedCallerUntilItsActualExit() {
        val gate=ContinuousSyncWorkGate()
        val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
        val failed=java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val task=Thread{try{gate.runIfIdle{entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS))}}catch(error:Throwable){failed.set(error)}}
        task.start()
        try{
            assertTrue(entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            assertNull(gate.runIfIdle{error("A second worker entered while its predecessor still owned I/O")})
        }finally{release.countDown();task.join(5000)}
        assertFalse(task.isAlive);assertNull(failed.get());assertEquals(true,gate.runIfIdle{true})
    }
    @Test fun continuousCycleBudgetAndFailureRetryRemainBounded() {
        var at=1000L;var cancelled=false
        val budget=ContinuousSyncBudget({at},{cancelled},2000)
        assertFalse(budget.stopped());at=3000;assertTrue(budget.stopped())
        at=1000;val stopped=ContinuousSyncBudget({at},{cancelled});cancelled=true;assertTrue(stopped.stopped())
        val retry=ContinuousSyncRetry()
        assertEquals(15000L,retry.next(false,true));assertEquals(30000L,retry.next(false,true))
        repeat(8){assertEquals(60000L,retry.next(false,true))}
        assertEquals(2000L,retry.next(true,true));assertEquals(15000L,retry.next(false,true))
    }
}
