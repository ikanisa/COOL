package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.ContextWrapper
import android.content.pm.PackageManager
import app.cool.mobile.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Test

class MomoGatewaySchedulingPermissionTest {
    private class DeniedContext : ContextWrapper(null) {
        var permissionChecks = 0
        override fun checkSelfPermission(permission: String): Int {
            assertEquals(Manifest.permission.RECEIVE_BOOT_COMPLETED, permission)
            permissionChecks++
            return PackageManager.PERMISSION_DENIED
        }
    }

    @Test fun missingBootPermissionCannotReachPersistedScheduling() {
        // Android's host-unit Context constructor throws. Allocate only this
        // controlled fixture without invoking it; every unmocked scheduler or
        // JobInfo API still throws, making any premature OS access fail here.
        val allocator = Class.forName("sun.misc.Unsafe")
        val field = allocator.getDeclaredField("theUnsafe").apply { isAccessible = true }
        val context = allocator.getMethod("allocateInstance", Class::class.java)
            .invoke(field.get(null), DeniedContext::class.java) as DeniedContext
        MomoGatewayJobs.ensure(context)
        MomoGatewayJobs.signal(context)
        assertEquals(if (BuildConfig.FLAVOR == "internal_receiver") 2 else 0, context.permissionChecks)
    }
}
