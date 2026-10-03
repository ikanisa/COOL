package app.cool.mobile.gateway

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.ServiceState
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

internal class GatewayAndroidObservations(private val context: Context) {
    fun read(): GatewayObservations {
        val send = context.checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
        val phone = context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity?.getNetworkCapabilities(connectivity.activeNetwork)
        val connected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val validated = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        var subscription: Int? = null
        var unambiguous = false
        var simReady = false
        var inService = false
        if (phone) {
            try {
                val manager = context.getSystemService(SubscriptionManager::class.java)
                val active = manager?.activeSubscriptionInfoList.orEmpty()
                val selected = SubscriptionManager.getDefaultSmsSubscriptionId()
                if (SubscriptionManager.isValidSubscriptionId(selected) && active.count { it.subscriptionId == selected } == 1) {
                    subscription = selected
                    unambiguous = true
                    val telephony = context.getSystemService(TelephonyManager::class.java)?.createForSubscriptionId(selected)
                    simReady = telephony?.simState == TelephonyManager.SIM_STATE_READY
                    inService = telephony?.serviceState?.state == ServiceState.STATE_IN_SERVICE
                }
            } catch (_: Exception) {
                // Independent permission/telephony observations stay unknown
                // or false. Internet does not establish radio/SIM readiness.
            }
        }
        return GatewayObservations(send, phone, connected, validated,
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING),
            simReady, inService, subscription, unambiguous)
    }
}
