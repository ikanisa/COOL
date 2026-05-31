package app.cool.mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pendingSmsAccessResult: MethodChannel.Result? = null

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
