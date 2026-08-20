package app.cool.mobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import app.cool.mobile.receiver_sms.SmsQueueEventBus
import app.cool.mobile.receiver_sms.SmsQueueStore
import app.cool.mobile.receiver_sms.SmsQueueWorker
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pendingSmsAccessResult: MethodChannel.Result? = null
    private var pendingSmsOwnerUserId: String? = null
    private var smsQueueEventSink: EventChannel.EventSink? = null
    private val smsQueueListener: (Long) -> Unit = { sequence ->
        runOnUiThread {
            smsQueueEventSink?.success(
                mapOf(
                    "type" to "pending_sms",
                    "sequence" to sequence,
                ),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "collect/sms_access/events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smsQueueEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    smsQueueEventSink = null
                }
            },
        )
        SmsQueueEventBus.removeListener(smsQueueListener)
        SmsQueueEventBus.addListener(smsQueueListener)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "collect/sms_access"
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val ownerUserId = call.argument<String>("owner_user_id")?.trim().orEmpty()
                    if (!enabled) {
                        val disabled = SmsQueueStore(applicationContext).disableAndClear()
                        if (!disabled) {
                            result.error(
                                "sms_access_update_failed",
                                "Unable to disable SMS access safely",
                                smsAccessStatus(),
                            )
                        } else {
                            result.success(true)
                        }
                    } else if (ownerUserId.isEmpty()) {
                        result.error(
                            "sms_access_owner_required",
                            "SMS access must be bound to an authenticated account",
                            smsAccessStatus()
                        )
                    } else if (!supportsSmsAccess()) {
                        result.error(
                            "sms_access_unavailable",
                            "SMS access is unavailable in this Android build or device",
                            smsAccessStatus()
                        )
                    } else if (hasSmsPermissions()) {
                        if (SmsQueueStore(applicationContext).enableForOwner(ownerUserId)) {
                            result.success(true)
                        } else {
                            result.error(
                                "sms_access_update_failed",
                                "Unable to bind SMS access to this account",
                                smsAccessStatus(),
                            )
                        }
                    } else if (pendingSmsAccessResult != null) {
                        result.error(
                            "sms_access_pending",
                            "SMS access request is already pending",
                            null
                        )
                    } else if (isSmsPermissionPermanentlyDenied()) {
                        result.error(
                            "sms_permission_permanently_denied",
                            "SMS permission must be enabled in Android app settings",
                            smsAccessStatus()
                        )
                    } else {
                        pendingSmsAccessResult = result
                        pendingSmsOwnerUserId = ownerUserId
                        requestPermissions(SMS_PERMISSIONS, SMS_PERMISSION_REQUEST_CODE)
                    }
                }
                "status" -> result.success(smsAccessStatus())
                "isEnabled" -> result.success(
                    prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) &&
                        prefs.getString(
                            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
                            null,
                        ).orEmpty().trim().isNotEmpty() &&
                        supportsSmsAccess() &&
                        hasSmsPermissions()
                )
                "readPendingSms" -> {
                    if (
                        !prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) ||
                        prefs.getString(
                            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
                            null,
                        ).orEmpty().trim().isEmpty() ||
                        !supportsSmsAccess() ||
                        !hasSmsPermissions()
                    ) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    runSmsQueueTask(result) {
                        val array = SmsQueueStore(applicationContext).read()
                        val values = mutableListOf<Map<String, String>>()
                        for (index in 0 until array.length()) {
                            val item = array.optJSONObject(index) ?: JSONObject()
                            values.add(
                                mapOf(
                                    "id" to item.optString("id", ""),
                                    "owner_user_id" to item.optString("owner_user_id", ""),
                                    "raw_sender" to item.optString("raw_sender", "android_sms"),
                                    "raw_body" to item.optString("raw_body", ""),
                                    "received_at_device" to item.optString("received_at_device", "")
                                )
                            )
                        }
                        values
                    }
                }
                "ackPendingSms" -> {
                    val rawIds = call.argument<List<String>>("ids").orEmpty()
                    val ids = rawIds.map(String::trim).filter(String::isNotEmpty).toSet()
                    if (ids.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    runSmsQueueTask(result) {
                        SmsQueueStore(applicationContext).acknowledge(ids)
                    }
                }
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        SmsQueueEventBus.removeListener(smsQueueListener)
        smsQueueEventSink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun runSmsQueueTask(
        result: MethodChannel.Result,
        task: () -> Any?,
    ) {
        try {
            SmsQueueWorker.execute {
                try {
                    val value = task()
                    runOnUiThread { result.success(value) }
                } catch (_: Exception) {
                    runOnUiThread {
                        result.error(
                            "sms_queue_unavailable",
                            "Secure SMS queue is temporarily unavailable",
                            smsAccessStatus(),
                        )
                    }
                }
            }
        } catch (_: RuntimeException) {
            result.error(
                "sms_queue_unavailable",
                "Secure SMS queue worker is unavailable",
                smsAccessStatus(),
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != SMS_PERMISSION_REQUEST_CODE) return

        val granted = SMS_PERMISSIONS.all { permission ->
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
        val saved = SmsQueueStore(applicationContext).completePermissionRequest(
            granted,
            pendingSmsOwnerUserId,
        )
        if (saved) {
            pendingSmsAccessResult?.success(granted)
        } else {
            pendingSmsAccessResult?.error(
                "sms_access_update_failed",
                "Unable to save the SMS permission decision",
                smsAccessStatus(),
            )
        }
        pendingSmsAccessResult = null
        pendingSmsOwnerUserId = null
    }

    private fun hasSmsPermissions(): Boolean {
        return SMS_PERMISSIONS.all { permission ->
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun supportsSmsAccess(): Boolean {
        return packageDeclaresSmsPermissions() &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)
    }

    @Suppress("DEPRECATION")
    private fun packageDeclaresSmsPermissions(): Boolean {
        val requested = packageManager
            .getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            .orEmpty()
        return SMS_PERMISSIONS.all(requested::contains)
    }

    private fun isSmsPermissionPermanentlyDenied(): Boolean {
        val requestedBefore = getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
            .getBoolean(SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY, false)
        return supportsSmsAccess() &&
            requestedBefore &&
            !hasSmsPermissions() &&
            SMS_PERMISSIONS.none(::shouldShowRequestPermissionRationale)
    }

    private fun smsAccessStatus(): Map<String, Boolean> {
        val prefs = getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
        val supported = supportsSmsAccess()
        val granted = supported && hasSmsPermissions()
        val ownerBound = prefs.getString(
            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
            null,
        ).orEmpty().trim().isNotEmpty()
        return mapOf(
            "supported" to supported,
            "declared" to packageDeclaresSmsPermissions(),
            "enabled" to (
                granted &&
                    ownerBound &&
                    prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false)
            ),
            "granted" to granted,
            "requested_before" to prefs.getBoolean(
                SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY,
                false,
            ),
            "should_show_rationale" to SMS_PERMISSIONS.any(::shouldShowRequestPermissionRationale),
            "permanently_denied" to isSmsPermissionPermanentlyDenied(),
            "queue_overflowed" to prefs.getBoolean(
                SmsQueueStore.SMS_QUEUE_OVERFLOW_KEY,
                false,
            ),
        )
    }

    companion object {
        const val SMS_ACCESS_PREFS = "collect_sms_access"
        const val SMS_ACCESS_ENABLED_KEY = "enabled"
        private const val SMS_PERMISSION_REQUEST_CODE = 182
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS
        )
    }
}
