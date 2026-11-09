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
        check(base.packageName == "rw.ikanisa.burimunsi.gateway.nativeTest" &&
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
}
