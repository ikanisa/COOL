package app.cool.mobile

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "collect/receiver_mode"
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(RECEIVER_PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    prefs.edit().putBoolean(RECEIVER_ENABLED_KEY, enabled).apply()
                    result.success(null)
                }
                "isEnabled" -> result.success(
                    prefs.getBoolean(RECEIVER_ENABLED_KEY, false)
                )
                "drainPendingSms" -> {
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

    companion object {
        const val RECEIVER_PREFS = "collect_receiver_mode"
        const val RECEIVER_ENABLED_KEY = "enabled"
        const val PENDING_SMS_KEY = "pending_sms"
    }
}
