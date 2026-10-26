package app.cool.mobile.gateway

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telephony.PhoneStateListener
import android.telephony.ServiceState
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

internal class GatewayAndroidObservations(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val radio = GatewayRadioObservation()
    private var listener: PhoneStateListener? = null
    private var listenerManager: TelephonyManager? = null
    @Volatile private var closed = false

    /** The API24-compatible callback exposes only the service-state enum. It
     * does not request, read or retain network/operator/location fields. */
    private fun observeRadio(token: GatewayRadioObservation.Token) {
        main.post {
            if (closed || !radio.current(token)) return@post
            stopListener()
            if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
                radio.clear()
                return@post
            }
            try {
                val manager = context.getSystemService(TelephonyManager::class.java)
                    ?.createForSubscriptionId(token.subscriptionId) ?: run { radio.clear(); return@post }
                val callback = object : PhoneStateListener() {
                    override fun onServiceStateChanged(serviceState: ServiceState?) {
                        if (!closed && context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                            radio.accept(token, serviceState?.state == ServiceState.STATE_IN_SERVICE, SystemClock.elapsedRealtime())
                        } else {
                            radio.clear()
                        }
                    }
                }
                listener = callback
                listenerManager = manager
                manager.listen(callback, PhoneStateListener.LISTEN_SERVICE_STATE)
            } catch (_: Exception) {
                stopListener()
                radio.clear()
            }
        }
    }

    private fun stopListener() {
        val callback = listener
        val manager = listenerManager
        listener = null
        listenerManager = null
        if (callback != null && manager != null) {
            try { manager.listen(callback, PhoneStateListener.LISTEN_NONE) } catch (_: Exception) { }
        }
    }

    fun close() {
        closed = true
        radio.clear()
        main.post { stopListener() }
    }

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
        if (!closed && context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            try {
                val manager = context.getSystemService(SubscriptionManager::class.java)
                val active = manager?.activeSubscriptionInfoList.orEmpty()
                val selected = SubscriptionManager.getDefaultSmsSubscriptionId()
                // An exact active-SIM match excludes invalid/default sentinels
                // without invoking the API29-only isValidSubscriptionId.
                if (selected in 0 until Int.MAX_VALUE && active.count { it.subscriptionId == selected } == 1) {
                    subscription = selected
                    unambiguous = true
                    val telephony = context.getSystemService(TelephonyManager::class.java)?.createForSubscriptionId(selected)
                    simReady = telephony?.simState == TelephonyManager.SIM_STATE_READY
                    val observation = radio.read(selected, SystemClock.elapsedRealtime())
                    if (observation.registrationRequired) observeRadio(observation.token)
                    inService = observation.inService
                }
            } catch (_: Exception) {
                // Failed permission/telephony reads invalidate old readiness.
                radio.clear()
            }
        }
        if (subscription == null) {
            radio.clear()
            main.post { stopListener() }
        }
        return GatewayObservations(send, phone, connected, validated,
            context.packageManager.hasSystemFeature(
                if (Build.VERSION.SDK_INT >= 33) PackageManager.FEATURE_TELEPHONY_MESSAGING
                else PackageManager.FEATURE_TELEPHONY),
            simReady, inService, subscription, unambiguous)
    }
}
