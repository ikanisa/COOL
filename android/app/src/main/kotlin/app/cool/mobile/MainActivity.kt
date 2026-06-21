package app.cool.mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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
                        prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, false).apply()
                        result.success(true)
                    } else if (hasSmsPermissions()) {
                        prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, true).apply()
                        result.success(true)
                    } else if (pendingSmsAccessResult != null) {
                        result.error(
                            "sms_access_pending",
                            "SMS access request is already pending",
                            null
                        )
                    } else {
                        pendingSmsAccessResult = result
                        requestPermissions(SMS_PERMISSIONS, SMS_PERMISSION_REQUEST_CODE)
                    }
                }
                "isEnabled" -> result.success(
                    prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) && hasSmsPermissions()
                )
                "drainPendingSms" -> {
                    if (!prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) || !hasSmsPermissions()) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    val pending = prefs.getString(PENDING_SMS_KEY, "[]") ?: "[]"
                    val array = JSONArray(pending)
                    val values = mutableListOf<Map<String, String>>()
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: JSONObject()
                        values.add(
                            mapOf(
                                "raw_sender" to item.optString("raw_sender", "android_sms"),
                                "raw_body" to item.optString("raw_body", ""),
                                "received_at_device" to item.optString("received_at_device", "")
                            )
                        )
                    }
                    prefs.edit().putString(PENDING_SMS_KEY, "[]").apply()
                    result.success(values)
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
            .apply()
        pendingSmsAccessResult?.success(granted)
        pendingSmsAccessResult = null
    }

    private fun hasSmsPermissions(): Boolean {
        return SMS_PERMISSIONS.all { permission ->
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    companion object {
        const val SMS_ACCESS_PREFS = "collect_sms_access"
        const val SMS_ACCESS_ENABLED_KEY = "enabled"
        const val PENDING_SMS_KEY = "pending_sms"
        private const val SMS_PERMISSION_REQUEST_CODE = 182
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS
        )
    }
}
