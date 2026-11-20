package rw.ikanisa.burimunsi

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.content.pm.PackageManager
import app.cool.mobile.BuildConfig
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StaffPackageIsolationTest {
    @Test fun installedPackageEnforcesRoleBoundary(){
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        @Suppress("DEPRECATION") val info=context.packageManager.getPackageInfo(context.packageName,PackageManager.GET_PERMISSIONS or PackageManager.GET_RECEIVERS or PackageManager.GET_SERVICES)
        val prohibited=setOf("android.permission.READ_SMS","android.permission.RECEIVE_SMS","android.permission.SEND_SMS","android.permission.RECEIVE_MMS","android.permission.RECEIVE_WAP_PUSH","android.permission.BIND_NOTIFICATION_LISTENER_SERVICE")
        if (BuildConfig.IS_GATEWAY) {
            val requested=info.requestedPermissions.orEmpty().toSet()
            assertTrue(requested.containsAll(setOf("android.permission.READ_SMS", "android.permission.RECEIVE_SMS")))
            assertFalse(requested.contains("android.permission.SEND_SMS"))
            val receiver=info.receivers.orEmpty().single{it.name=="app.cool.mobile.receiver_sms.CollectSmsReceiver"}
            assertTrue(receiver.exported)
            assertEquals("android.permission.BROADCAST_SMS", receiver.permission)
            val recovery=info.receivers.orEmpty().single{it.name=="app.cool.mobile.receiver_sms.MomoGatewayRecoveryReceiver"}
            assertFalse(recovery.exported)
            for (name in listOf("MomoGatewayJobService", "MomoGatewayLocalRecoveryService")) {
                val service=info.services.orEmpty().single{it.name=="app.cool.mobile.receiver_sms.$name"}
                assertEquals("android.permission.BIND_JOB_SERVICE", service.permission)
            }
            assertNotNull(Class.forName("app.cool.mobile.receiver_sms.CollectSmsReceiver"))
            return
        }
        assertTrue(info.requestedPermissions.orEmpty().none{it in prohibited})
        assertTrue(info.receivers.orEmpty().none{it.name.contains("SmsReceiver")||it.name.contains("MomoGateway")})
        assertTrue(info.services.orEmpty().none{it.name.contains("MomoGateway")||it.permission=="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"})
        try{Class.forName("app.cool.mobile.receiver_sms.CollectSmsReceiver");fail("SMS receiver code packaged in Staff")}
        catch(_:ClassNotFoundException){ }
    }
}
