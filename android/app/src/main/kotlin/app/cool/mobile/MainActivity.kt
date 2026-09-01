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
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pendingSmsAccessResult: MethodChannel.Result? = null
    private var pendingSmsOwnerUserId: String? = null
    private var pendingMomoUssdResult: MethodChannel.Result? = null
    private var pendingMomoUssdCode: String? = null
    private var standardIntegrityProvider:
        StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private val pendingIntegrityResults = mutableListOf<Pair<String, MethodChannel.Result>>()
    private var preparingIntegrityProvider = false
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "collect/momo_ussd",
        ).setMethodCallHandler { call, result ->
            if (call.method != "launch") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val code = call.argument<String>("ussd_code")?.trim().orEmpty()
            if (!MOMO_USSD_PATTERN.matches(code)) {
                result.error("momo_ussd_invalid", "Unsupported MoMo USSD request", null)
                return@setMethodCallHandler
            }
            launchMomoUssd(code, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "collect/play_integrity",
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestStandardToken") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val requestHash = call.argument<String>("request_hash")?.trim().orEmpty()
            if (!requestHash.matches(Regex("^[0-9a-f]{64}$"))) {
                result.error("play_integrity_bad_request", "request_hash is invalid", null)
                return@setMethodCallHandler
            }
            requestPlayIntegrityToken(requestHash, result)
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
        if (requestCode == MOMO_USSD_PERMISSION_REQUEST_CODE) {
            val result = pendingMomoUssdResult
            val code = pendingMomoUssdCode
            pendingMomoUssdResult = null
            pendingMomoUssdCode = null
            if (
                result != null &&
                code != null &&
                checkSelfPermission(Manifest.permission.CALL_PHONE) ==
                    PackageManager.PERMISSION_GRANTED
            ) {
                launchMomoUssd(code, result)
            } else {
                result?.error(
                    "momo_ussd_permission_denied",
                    "Phone permission is required to open the MoMo USSD request",
                    null,
                )
            }
            return
        }
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

    private fun launchMomoUssd(code: String, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingMomoUssdResult != null) {
                result.error("momo_ussd_pending", "A MoMo request is already pending", null)
                return
            }
            pendingMomoUssdResult = result
            pendingMomoUssdCode = code
            requestPermissions(
                arrayOf(Manifest.permission.CALL_PHONE),
                MOMO_USSD_PERMISSION_REQUEST_CODE,
            )
            return
        }
        try {
            val uri = Uri.parse("tel:${Uri.encode(code)}")
            startActivity(Intent(Intent.ACTION_CALL, uri))
            result.success(true)
        } catch (_: Exception) {
            result.error(
                "momo_ussd_unavailable",
                "MoMo USSD is unavailable on this device",
                null,
            )
        }
    }

    private fun requestPlayIntegrityToken(
        requestHash: String,
        result: MethodChannel.Result,
    ) {
        val cloudProjectNumber = BuildConfig.PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER
        if (cloudProjectNumber <= 0L) {
            result.error(
                "play_integrity_not_configured",
                "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER is not configured",
                null,
            )
            return
        }
        val provider = standardIntegrityProvider
        if (provider != null) {
            provider.request(
                StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
                    .setRequestHash(requestHash)
                    .build(),
            ).addOnSuccessListener { token -> result.success(token.token()) }
                .addOnFailureListener { error ->
                    result.error(
                        "play_integrity_token_failed",
                        error.message ?: "Play Integrity token request failed",
                        null,
                    )
                }
            return
        }
        pendingIntegrityResults.add(Pair(requestHash, result))
        if (preparingIntegrityProvider) return
        preparingIntegrityProvider = true
        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
                    .setCloudProjectNumber(cloudProjectNumber)
                    .build(),
            )
            .addOnSuccessListener { prepared ->
                standardIntegrityProvider = prepared
                preparingIntegrityProvider = false
                val pending = pendingIntegrityResults.toList()
                pendingIntegrityResults.clear()
                pending.forEach { requestPlayIntegrityToken(it.first, it.second) }
            }
            .addOnFailureListener { error ->
                preparingIntegrityProvider = false
                val pending = pendingIntegrityResults.toList()
                pendingIntegrityResults.clear()
                pending.forEach {
                    it.second.error(
                        "play_integrity_prepare_failed",
                        error.message ?: "Play Integrity preparation failed",
                        null,
                    )
                }
            }
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
        private const val MOMO_USSD_PERMISSION_REQUEST_CODE = 183
        private val MOMO_USSD_PATTERN = Regex(
            "^(?:\\*182\\*\\*8\\*1\\*[0-9]{4,12}\\*[1-9][0-9]{0,8}|\\*182\\*8\\*1)#$",
        )
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS
        )
    }
}
