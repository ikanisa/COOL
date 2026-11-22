package app.cool.mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.net.toUri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class MemberMomoChannel(private val activity: Activity) {
    private var pendingMomoPermissionResult: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(
            messenger,
            "collect/momo_ussd",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensurePermission" -> requestMomoPermission(result)
                "launch" -> {
                    val code = call.argument<String>("ussd_code")?.trim().orEmpty()
                    if (!MOMO_USSD_PATTERN.matches(code)) {
                        result.error("momo_ussd_invalid", "Unsupported MoMo USSD request", null)
                        return@setMethodCallHandler
                    }
                    launchMomoUssd(code, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != MOMO_USSD_PERMISSION_REQUEST_CODE) return false
        val result = pendingMomoPermissionResult
        pendingMomoPermissionResult = null
        result?.success(
            activity.checkSelfPermission(Manifest.permission.CALL_PHONE) ==
                PackageManager.PERMISSION_GRANTED,
        )
        return true
    }

    private fun requestMomoPermission(result: MethodChannel.Result) {
        if (pendingMomoPermissionResult != null) {
            result.error("momo_ussd_pending", "A phone permission request is already pending", null)
            return
        }
        if (activity.checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingMomoPermissionResult = result
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.CALL_PHONE),
                MOMO_USSD_PERMISSION_REQUEST_CODE,
            )
        } catch (_: Exception) {
            if (pendingMomoPermissionResult === result) {
                pendingMomoPermissionResult = null
                result.success(false)
            }
        }
    }

    fun cancelPendingPermission() {
        val result = pendingMomoPermissionResult
        pendingMomoPermissionResult = null
        try {
            result?.success(false)
        } catch (_: Exception) {
            // The engine may already be detached; never retain a pending code.
        }
    }

    private fun launchMomoUssd(code: String, result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.CALL_PHONE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(false)
            return
        }
        try {
            val uri = "tel:${Uri.encode(code)}".toUri()
            activity.startActivity(Intent(Intent.ACTION_CALL, uri))
            result.success(true)
        } catch (_: Exception) {
            result.error(
                "momo_ussd_unavailable",
                "MoMo USSD is unavailable on this device",
                null,
            )
        }
    }

    companion object {
        private const val MOMO_USSD_PERMISSION_REQUEST_CODE = 183
        private val MOMO_USSD_PATTERN = Regex(
            "^(?:\\*182\\*\\*8\\*1\\*[0-9]{4,12}\\*[1-9][0-9]{0,8}|\\*182\\*8\\*1)#$",
        )
    }
}
