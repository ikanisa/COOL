package app.cool.mobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import app.cool.mobile.receiver_sms.SmsQueueStore
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pendingSmsAccessResult: MethodChannel.Result? = null
    private var standardIntegrityProvider:
        StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var pendingIntegrityResults = mutableListOf<Pair<String, MethodChannel.Result>>()
    private var preparingIntegrityProvider = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "collect/sms_access"
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (!enabled) {
                        prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, false).commit()
                        SmsQueueStore(applicationContext).clear()
                        result.success(true)
                    } else if (!supportsSmsAccess()) {
                        result.error(
                            "sms_access_unavailable",
                            "SMS access is unavailable in this Android build or device",
                            smsAccessStatus()
                        )
                    } else if (hasSmsPermissions()) {
                        prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, true).commit()
                        result.success(true)
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
                        prefs.edit()
                            .putBoolean(SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY, true)
                            .commit()
                        requestPermissions(SMS_PERMISSIONS, SMS_PERMISSION_REQUEST_CODE)
                    }
                }
                "status" -> result.success(smsAccessStatus())
                "isEnabled" -> result.success(
                    prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) &&
                        supportsSmsAccess() &&
                        hasSmsPermissions()
                )
                "readPendingSms" -> {
                    if (
                        !prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) ||
                        !supportsSmsAccess() ||
                        !hasSmsPermissions()
                    ) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    val array = SmsQueueStore(applicationContext).read()
                    val values = mutableListOf<Map<String, String>>()
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: JSONObject()
                        values.add(
                            mapOf(
                                "id" to item.optString("id", ""),
                                "raw_sender" to item.optString("raw_sender", "android_sms"),
                                "raw_body" to item.optString("raw_body", ""),
                                "received_at_device" to item.optString("received_at_device", "")
                            )
                        )
                    }
                    result.success(values)
                }
                "ackPendingSms" -> {
                    val rawIds = call.argument<List<String>>("ids").orEmpty()
                    val ids = rawIds.map(String::trim).filter(String::isNotEmpty).toSet()
                    if (ids.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val store = SmsQueueStore(applicationContext)
                    val pending = store.read()
                    val retained = JSONArray()
                    for (index in 0 until pending.length()) {
                        val item = pending.optJSONObject(index) ?: continue
                        if (!ids.contains(item.optString("id", ""))) retained.put(item)
                    }
                    result.success(store.write(retained))
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
            "collect/play_integrity"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStandardToken" -> {
                    val requestHash = call.argument<String>("request_hash")?.trim().orEmpty()
                    if (requestHash.isEmpty()) {
                        result.error("play_integrity_bad_request", "request_hash is required", null)
                        return@setMethodCallHandler
                    }
                    requestPlayIntegrityToken(requestHash, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPlayIntegrityToken(requestHash: String, result: MethodChannel.Result) {
        val cloudProjectNumber = BuildConfig.PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER
        if (cloudProjectNumber <= 0L) {
            result.error(
                "play_integrity_not_configured",
                "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER is not configured",
                null
            )
            return
        }
        val provider = standardIntegrityProvider
        if (provider != null) {
            provider.request(
                StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
                    .setRequestHash(requestHash)
                    .build()
            )
                .addOnSuccessListener { token -> result.success(token.token()) }
                .addOnFailureListener { error ->
                    result.error(
                        "play_integrity_token_failed",
                        error.message ?: "Play Integrity token request failed",
                        null
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
                    .build()
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
                        error.message ?: "Play Integrity token provider preparation failed",
                        null
                    )
                }
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
        getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(SMS_ACCESS_ENABLED_KEY, granted)
            .commit()
        pendingSmsAccessResult?.success(granted)
        pendingSmsAccessResult = null
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
        return mapOf(
            "supported" to supported,
            "declared" to packageDeclaresSmsPermissions(),
            "enabled" to (granted && prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false)),
            "granted" to granted,
            "requested_before" to prefs.getBoolean(
                SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY,
                false,
            ),
            "should_show_rationale" to SMS_PERMISSIONS.any(::shouldShowRequestPermissionRationale),
            "permanently_denied" to isSmsPermissionPermanentlyDenied(),
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
