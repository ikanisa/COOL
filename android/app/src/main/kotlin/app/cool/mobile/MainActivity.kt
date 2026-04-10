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
import androidx.core.view.WindowCompat
import app.cool.mobile.momo_sms.MomoSmsInboxSync
import app.cool.mobile.momo_sms.MomoSmsPrefs
import app.cool.mobile.momo_sms.MomoSmsQueueRepository
import app.cool.mobile.momo_sms.MomoSmsSyncExecutor
import app.cool.mobile.momo_sms.MomoSmsSyncWorker
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {
    private val securityChannel = "app.cool.mobile/security"
    private val deviceSettingsChannel = "app.cool.mobile/device_settings"
    private val nfcHceChannel = "app.cool.mobile/nfc_hce"
    private val momoSmsChannel = "app.cool.mobile/momo_sms"

    override fun onCreate(savedInstanceState: Bundle?) {
        // Enable edge-to-edge display for Android 15+ compatibility.
        // This handles status and navigation bar transparency and insets.
        WindowCompat.setDecorFitsSystemWindows(window, false)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, momoSmsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "configurePipeline" -> {
                        val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                        val enabled = arguments["enabled"] as? Boolean ?: false
                        val approvedSenders = (arguments["approvedSenders"] as? List<*>)
                            ?.mapNotNull { item -> item?.toString() }
                        MomoSmsPrefs.getInstance(this).configure(
                            enabled = enabled,
                            userId = arguments["userId"] as? String,
                            accessToken = arguments["accessToken"] as? String,
                            refreshToken = arguments["refreshToken"] as? String,
                            accessTokenExpiresAtEpochSeconds =
                                (arguments["accessTokenExpiresAtEpochSeconds"] as? Number)?.toLong(),
                            supabaseUrl = arguments["supabaseUrl"] as? String,
                            supabaseAnonKey = arguments["supabaseAnonKey"] as? String,
                            approvedSenderTokens = approvedSenders,
                        )
                        if (enabled) {
                            MomoSmsSyncWorker.enqueue(this)
                        }
                        result.success(true)
                    }
                    "clearPipelineSession" -> {
                        val prefs = MomoSmsPrefs.getInstance(this)
                        val userId = prefs.currentUserId()
                        prefs.clearSession()
                        if (!userId.isNullOrBlank()) {
                            MomoSmsQueueRepository.getInstance(this).deleteForUser(userId)
                        }
                        result.success(true)
                    }
                    "getQueueStatus" -> {
                        val userId = MomoSmsPrefs.getInstance(this).currentUserId().orEmpty()
                        if (userId.isBlank()) {
                            result.success(
                                mapOf(
                                    "pendingCount" to 0,
                                    "failedCount" to 0,
                                    "syncedCount" to 0,
                                    "totalCount" to 0,
                                ),
                            )
                        } else {
                            val snapshot = MomoSmsQueueRepository.getInstance(this).snapshot(userId)
                            result.success(
                                mapOf(
                                    "pendingCount" to snapshot.pendingCount,
                                    "failedCount" to snapshot.failedCount,
                                    "syncedCount" to snapshot.syncedCount,
                                    "totalCount" to snapshot.totalCount,
                                ),
                            )
                        }
                    }
                    "syncPendingNow" -> {
                        thread(name = "cool-momo-sync-now") {
                            try {
                                val stats = MomoSmsSyncExecutor(this).syncPendingNow()
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "uploadedMessages" to stats.uploadedMessages,
                                            "duplicateMessages" to stats.duplicateMessages,
                                            "failedMessages" to stats.failedMessages,
                                            "rateLimited" to stats.rateLimited,
                                            "lastError" to stats.lastError,
                                        ),
                                    )
                                }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error(
                                        "sync_pending_failed",
                                        error.message,
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    "syncInbox" -> {
                        val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                        val trigger = arguments["trigger"]?.toString()?.trim().orEmpty()
                        val cutoffIso = arguments["cutoffIso"]?.toString()?.trim().orEmpty()
                        thread(name = "cool-momo-inbox-sync") {
                            try {
                                val cutoff = cutoffIso.takeIf { it.isNotBlank() }
                                    ?.let(Instant::parse)
                                    ?: Instant.now()
                                val syncResult = MomoSmsInboxSync(this).run(
                                    cutoff = cutoff,
                                    trigger = trigger,
                                )
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "scannedMessages" to syncResult.scannedMessages,
                                            "uploadedMessages" to syncResult.uploadedMessages,
                                            "duplicateMessages" to syncResult.duplicateMessages,
                                            "queuedMessages" to syncResult.queuedMessages,
                                            "oldestMessageAt" to syncResult.oldestMessageAt?.toString(),
                                            "newestMessageAt" to syncResult.newestMessageAt?.toString(),
                                            "rateLimited" to syncResult.rateLimited,
                                        ),
                                    )
                                }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error("sync_inbox_failed", error.message, null)
                                }
                            }
                        }
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
