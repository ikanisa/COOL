package rw.ikanisa.burimunsi

import android.content.ComponentName
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.cool.mobile.BuildConfig
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.gateway.GatewayFactory

/** Installed-package assertions; no production account, SMS, backend or test bypass. */
@RunWith(AndroidJUnit4::class)
class NativeSandboxContractTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun installationUsesOnlyDedicatedSandboxIdentity() {
        val role=if(BuildConfig.IS_GATEWAY) "gateway" else "staff"
        assertEquals("rw.ikanisa.burimunsi.$role.nativeTest", context.packageName)
        assertEquals("nativeTest", BuildConfig.BUILD_TYPE)
        assertTrue(BuildConfig.DEBUG)
        assertTrue(BuildConfig.IS_QUALIFICATION)
    }
    @Test fun installedSandboxHasNoInternetBackupOrCleartext() {
        @Suppress("DEPRECATION")
        val info=context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        assertFalse(info.requestedPermissions.orEmpty().contains("android.permission.INTERNET"))
        val flags=context.applicationInfo.flags
        assertTrue(flags and ApplicationInfo.FLAG_TEST_ONLY != 0)
        assertEquals(0, flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
        assertEquals(0, flags and ApplicationInfo.FLAG_USES_CLEARTEXT_TRAFFIC)
    }
    @Test fun compiledConfigurationContainsNoLiveEndpointOrBinding() {
        for(value in listOf(BuildConfig.BURI_API_ORIGIN, BuildConfig.COLLECT_API_HOST,
            BuildConfig.COLLECT_API_PATH_PREFIX, BuildConfig.COLLECT_PUBLISHABLE_KEY,
            BuildConfig.RECEIVER_API_BASE_URL, BuildConfig.COLLECT_RECEIVER_API_BASE_URL,
            BuildConfig.BURI_GROUP_ID, BuildConfig.RECEIPT_PROFILE_VERSION)) assertEquals("", value)
        assertEquals(Int.MAX_VALUE, BuildConfig.RECEIPT_UTC_OFFSET)
    }
    @Test fun launcherActivityBelongsToSandbox() {
        @Suppress("DEPRECATION")
        val activity=context.packageManager.getActivityInfo(ComponentName(context, MainActivity::class.java), 0)
        assertEquals(context.packageName, activity.packageName)
        assertTrue(activity.exported)
        assertNotNull(context.packageManager.getLaunchIntentForPackage(context.packageName))
    }
    @Test fun gatewayCannotBindOrResumeInSandbox() {
        val gateway=GatewayFactory.create(context)
        assertFalse(gateway.bound())
        gateway.start() // Both flavors must remain unbound; this must not start live collection.
        assertFalse(gateway.bound())
        for(action in listOf<()->Unit>({gateway.pair("synthetic-test-only")}, {gateway.setPaused(false)})) {
            try { action(); fail("Sandbox must reject gateway activation") }
            catch (_: IllegalStateException) { /* Expected fail-closed behavior. */ }
        }
    }
}
