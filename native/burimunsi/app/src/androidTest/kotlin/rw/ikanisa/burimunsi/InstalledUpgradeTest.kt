package rw.ikanisa.burimunsi

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.gateway.GatewayFactory
import rw.ikanisa.burimunsi.storage.DeviceProvisioning
import rw.ikanisa.burimunsi.storage.SecureStore
import java.io.File
import java.security.MessageDigest

/** Serialized by the v48 format. All record fields here are synthetic. */
object Code48HeldFixture {
    val phases = listOf("PREPARED", "ATTEMPTING", "CONFIRMED", "MATCHED_EXISTING")
    const val group = "synthetic-group"
    const val account = "synthetic-admin"
    val device = Values.sha256("synthetic-upgrade-device")
    private const val body = "Synthetic held receipt"
    private const val time = "2026-11-07T10:00:00Z"

    fun key(phase: String) = Values.sha256("synthetic-held-source-" + phase)
    private fun request(phase: String) = "50000000-0000-4000-8000-00000000000" + (phases.indexOf(phase) + 1)
    fun name(installation: String, phase: String): String {
        val fields = listOf("held-recovery-v1", group, account, installation, device, key(phase))
        return "observation-held-recovery-" + Values.sha256(fields.joinToString("") { "${it.length}:$it" })
    }
    fun original(installation: String, phase: String): String = JSONObject()
        .put("version", 1).put("collectionId", group).put("accountId", account).put("installationId", installation)
        .put("deviceScope", device).put("rowId", 7L).put("phase", phase).put("requestId", request(phase))
        .put("rawSender", "Synthetic").put("rawBody", body).put("sourceMode", "catch_up").put("complete", false)
        .put("capturedAt", time).put("serviceCentreAt", JSONObject.NULL).put("inboxReceivedAt", time)
        .put("subscriptionId", JSONObject.NULL).put("sourceKey", key(phase)).also {
            if (phase == "CONFIRMED" || phase == "MATCHED_EXISTING") it.put("terminalSourceId", "synthetic-source")
        }.toString()
    fun assertCompact(encoded: String, phase: String) {
        val value = JSONObject(encoded)
        assertEquals(setOf("version","phase","requestId","sourceId","rowDigest"), value.keys().asSequence().toSet())
        assertEquals(2, value.getInt("version"))
        assertEquals(phase, value.getString("phase"))
        assertEquals(request(phase), value.getString("requestId"))
        assertEquals("synthetic-source", value.getString("sourceId"))
        val fields = listOf("burimunsi-held-row-v2", "7", key(phase), "Synthetic", Values.sha256(body), time, "0", "0")
        assertEquals(Values.sha256(fields.joinToString("") { "${it.length}:$it" }), value.getString("rowDigest"))
    }
    fun ciphertext(context: Context, name: String): String {
        val bytes = File(context.noBackupFilesDir, "buri-$name.v1").readBytes()
        assertFalse(bytes.toString(Charsets.ISO_8859_1).contains(body))
        return MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

/** Run explicitly with -e upgradeStage seed on v48, then verify after an in-place APK replacement. */
@RunWith(AndroidJUnit4::class)
class InstalledUpgradeTest {
    @Test fun protectedDataSurvivesPackageReplacement() {
        val stage = InstrumentationRegistry.getArguments().getString("upgradeStage")
        assumeTrue("Requires the separate two-stage predecessor package replacement run", stage in setOf("seed", "verify"))
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val packages = setOf("rw.ikanisa.burimunsi.staff.cloud.nativeTest", "rw.ikanisa.burimunsi.gateway.cloud.nativeTest")
        check(context.packageName in packages)
        check(context.checkSelfPermission(Manifest.permission.INTERNET) != PackageManager.PERMISSION_GRANTED)
        check(context.checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED)
        val pkg = context.packageManager.getPackageInfo(context.packageName, 0)
        val admin = context.packageName.contains(".gateway.")
        val fields = context.getSharedPreferences("synthetic-in-place-update", Context.MODE_PRIVATE)
        val install = DeviceProvisioning(context).installationId
        val marker = SecureStore(context, "synthetic-in-place-update")
        when (stage) {
            "seed" -> {
                assertEquals(48L, pkg.longVersionCode)
                check(fields.all.isEmpty() && marker.read() == null)
                marker.write(install)
                val edit = fields.edit().putLong("installedAt", pkg.firstInstallTime).putInt("uid", context.applicationInfo.uid)
                if (admin) for (phase in Code48HeldFixture.phases) {
                    val name = Code48HeldFixture.name(install, phase)
                    SecureStore(context, name).write(Code48HeldFixture.original(install, phase))
                    edit.putString(phase, Code48HeldFixture.ciphertext(context, name))
                }
                assertTrue(edit.commit())
            }
            "verify" -> {
                assertTrue(app.cool.mobile.BuildConfig.VERSION_CODE > 48)
                assertEquals(app.cool.mobile.BuildConfig.VERSION_CODE.toLong(), pkg.longVersionCode)
                assertEquals(fields.getLong("installedAt", -1L), pkg.firstInstallTime)
                assertEquals(fields.getInt("uid", -1), context.applicationInfo.uid)
                assertEquals(marker.read(), install)
                if (admin) {
                    GatewayFactory.create(context).foregroundChanged(true)
                    val deadline = SystemClock.elapsedRealtime() + 10_000
                    for (phase in Code48HeldFixture.phases) {
                        val name = Code48HeldFixture.name(install, phase)
                        val store = SecureStore(context, name)
                        if (phase == "PREPARED" || phase == "ATTEMPTING") {
                            assertEquals(Code48HeldFixture.original(install, phase), store.read())
                            assertEquals(fields.getString(phase, null), Code48HeldFixture.ciphertext(context, name))
                        } else {
                            while (JSONObject(checkNotNull(store.read())).getInt("version") == 1 &&
                                SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(25)
                            Code48HeldFixture.assertCompact(checkNotNull(store.read()), phase)
                        }
                    }
                }
            }
            else -> error("A dedicated two-stage upgrade run is required")
        }
    }
}
