package app.cool.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val securityChannel = "app.cool.mobile/security"
    private val deviceSettingsChannel = "app.cool.mobile/device_settings"
    private val nfcHceChannel = "app.cool.mobile/nfc_hce"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureDefaultNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSecureMode" -> {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                        result.success(null)
                    }
                    "disableSecureMode" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNfcSettings" -> {
                        result.success(openNfcSettings())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nfcHceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> {
                        result.success(isNfcHceSupported())
                    }
                    "isPaymentRequestActive" -> {
                        result.success(isPaymentRequestActive())
                    }
                    "getPaymentRequestUri" -> {
                        result.success(getPaymentRequestUri())
                    }
                    "startPaymentRequest" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank()) {
                            result.error("invalid_uri", "uri is required", null)
                        } else {
                            val prefs = getSharedPreferences(
                                CoolNfcHostApduService.PREFS_NAME,
                                MODE_PRIVATE
                            )
                            prefs.edit()
                                .putString(CoolNfcHostApduService.KEY_URI, uri)
                                .putBoolean(CoolNfcHostApduService.KEY_ENABLED, true)
                                .apply()
                            result.success(null)
                        }
                    }
                    "stopPaymentRequest" -> {
                        val prefs = getSharedPreferences(
                            CoolNfcHostApduService.PREFS_NAME,
                            MODE_PRIVATE
                        )
                        prefs.edit()
                            .putBoolean(CoolNfcHostApduService.KEY_ENABLED, false)
                            .remove(CoolNfcHostApduService.KEY_URI)
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNfcSettings(): Boolean {
        return try {
            startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
            true
        } catch (primaryError: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun isNfcHceSupported(): Boolean {
        return NfcAdapter.getDefaultAdapter(this) != null &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
    }

    private fun isPaymentRequestActive(): Boolean {
        val prefs = getSharedPreferences(CoolNfcHostApduService.PREFS_NAME, MODE_PRIVATE)
        return prefs.getBoolean(CoolNfcHostApduService.KEY_ENABLED, false) &&
            !prefs.getString(CoolNfcHostApduService.KEY_URI, null).isNullOrBlank()
    }

    private fun getPaymentRequestUri(): String? {
        if (!isPaymentRequestActive()) {
            return null
        }
        val prefs = getSharedPreferences(CoolNfcHostApduService.PREFS_NAME, MODE_PRIVATE)
        return prefs.getString(CoolNfcHostApduService.KEY_URI, null)
    }

    private fun ensureDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channelId = getString(R.string.cool_default_notification_channel_id)
        val existingChannel = notificationManager.getNotificationChannel(channelId)
        if (existingChannel != null) {
            return
        }

        val channel = NotificationChannel(
            channelId,
            getString(R.string.cool_default_notification_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = getString(R.string.cool_default_notification_channel_description)
        }
        notificationManager.createNotificationChannel(channel)
    }
}
