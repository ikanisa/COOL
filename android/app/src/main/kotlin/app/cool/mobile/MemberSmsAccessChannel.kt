package app.cool.mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.edit
import app.cool.mobile.receiver_sms.SmsQueueEventBus
import app.cool.mobile.receiver_sms.SmsQueueOwnerPolicy
import app.cool.mobile.receiver_sms.SmsQueueStore
import app.cool.mobile.receiver_sms.SmsQueueWorker
import app.cool.mobile.receiver_sms.commitReceiptState
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

internal class MemberSmsAccessChannel(private val activity: Activity) {
    private var pendingSmsAccessResult: MethodChannel.Result? = null
    private var pendingSmsOwnerUserId: String? = null
    private var pendingSmsRequestCode: Int? = null
    private var smsQueueEventSink: EventChannel.EventSink? = null
    private val smsQueueListener: (Long) -> Unit = { sequence ->
        activity.runOnUiThread {
            smsQueueEventSink?.success(
                mapOf(
                    "type" to "pending_sms",
                    "sequence" to sequence,
                ),
            )
        }
    }

    fun registerEvents(messenger: BinaryMessenger) {
        EventChannel(
            messenger,
            "collect/sms_access/events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    smsQueueEventSink = events
                    // Capture may finish before Flutter subscribes on a cold start.
                    // Replaying only the sequence prompts an owner-gated queue read.
                    val sequence = SmsQueueEventBus.currentSequence()
                    if (events != null && sequence > 0L) smsQueueListener(sequence)
                }

                override fun onCancel(arguments: Any?) {
                    smsQueueEventSink = null
                }
            },
        )
        SmsQueueEventBus.removeListener(smsQueueListener)
        SmsQueueEventBus.addListener(smsQueueListener)
    }

    fun unregisterEvents() {
        SmsQueueEventBus.removeListener(smsQueueListener)
        smsQueueEventSink = null
    }

    fun registerMethods(messenger: BinaryMessenger) {
        MethodChannel(
            messenger,
            "collect/sms_access"
        ).setMethodCallHandler { call, result ->
            val prefs = activity.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val ownerUserId = call.argument<String>("owner_user_id")?.trim().orEmpty()
                    if (!enabled) {
                        val disabled = SmsQueueStore(activity.applicationContext)
                            .disablePreservingQueue(ownerUserId)
                        if (!disabled) {
                            result.error(
                                "sms_access_update_failed",
                                "Unable to disable SMS access for this account",
                                smsAccessStatus(),
                            )
                        } else {
                            // An old account must not cancel a new account's
                            // in-flight Android permission decision.
                            if (pendingSmsOwnerUserId == ownerUserId) {
                                pendingSmsAccessResult?.success(false)
                                pendingSmsAccessResult = null
                                pendingSmsOwnerUserId = null
                            }
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
                    } else if (pendingSmsRequestCode != null) {
                        result.error(
                            "sms_access_pending",
                            "SMS access request is already pending",
                            null
                        )
                    } else if (hasSmsPermissions()) {
                        if (SmsQueueStore(activity.applicationContext).enableForOwner(ownerUserId)) {
                            app.cool.mobile.receiver_sms.MemberSmsJobs.ensure(activity.applicationContext)
                            result.success(true)
                        } else {
                            result.error(
                                "sms_access_update_failed",
                                "Unable to bind SMS access to this account",
                                smsAccessStatus(),
                            )
                        }
                    } else if (isSmsPermissionPermanentlyDenied()) {
                        result.error(
                            "sms_permission_permanently_denied",
                            "SMS permission must be enabled in Android app settings",
                            smsAccessStatus()
                        )
                    } else {
                        val requestCode = nextSmsPermissionRequestCode()
                        if (requestCode == null) {
                            result.error(
                                "sms_access_update_failed",
                                "Unable to start the SMS permission request",
                                smsAccessStatus(),
                            )
                        } else {
                            pendingSmsAccessResult = result
                            pendingSmsOwnerUserId = ownerUserId
                            pendingSmsRequestCode = requestCode
                            try {
                                activity.requestPermissions(SMS_PERMISSIONS, requestCode)
                            } catch (_: RuntimeException) {
                                pendingSmsAccessResult = null
                                pendingSmsOwnerUserId = null
                                pendingSmsRequestCode = null
                                result.error(
                                    "sms_access_update_failed",
                                    "Unable to start the SMS permission request",
                                    smsAccessStatus(),
                                )
                            }
                        }
                    }
                }
                "status" -> result.success(smsAccessStatus(call.argument<String>("owner_user_id")))
                "suspendUnlessOwner" -> {
                    val currentUserId = call.argument<String>("current_user_id")?.trim()
                    val suspended = SmsQueueStore(activity.applicationContext)
                        .suspendUnlessOwner(currentUserId)
                    if (!suspended) {
                        result.error(
                            "sms_access_update_failed",
                            "Unable to suspend SMS capture after account change",
                            smsAccessStatus(),
                        )
                    } else {
                        if (pendingSmsAccessResult != null &&
                            pendingSmsOwnerUserId != currentUserId) {
                            pendingSmsAccessResult?.success(false)
                            pendingSmsAccessResult = null
                            pendingSmsOwnerUserId = null
                        }
                        result.success(true)
                    }
                }
                "isEnabled" -> result.success(
                    prefs.getBoolean(SmsQueueStore.SMS_ACCESS_ENABLED_KEY, false) &&
                        prefs.getString(
                            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
                            null,
                        ).orEmpty().trim().isNotEmpty() &&
                        supportsSmsAccess() &&
                        hasSmsPermissions()
                )
                "parkPendingSms", "retryRejectedSms" -> {
                    val owner = call.argument<String>("owner_user_id").orEmpty()
                    runSmsQueueTask(result, stillAuthorized = {
                        SmsQueueStore(activity.applicationContext).activeCaptureOwner() == owner && hasSmsPermissions()
                    }) {
                        check(owner.isNotEmpty() && SmsQueueStore(activity.applicationContext).activeCaptureOwner() == owner && hasSmsPermissions())
                        val queue = SmsQueueStore(activity.applicationContext)
                        val changed = if (call.method == "parkPendingSms")
                            queue.parkRejected(owner, call.argument<String>("id").orEmpty(), 400)
                        else queue.retryRejected(owner)
                        if (changed) {
                            SmsQueueEventBus.notifyQueueChanged()
                            if (call.method == "retryRejectedSms") app.cool.mobile.receiver_sms.MemberSmsJobs.ensure(activity.applicationContext)
                        }
                        changed
                    }
                }
                "readPendingSms" -> {
                    val requestedOwner = call.argument<String>("owner_user_id")?.trim().orEmpty()
                    if (
                        requestedOwner.isEmpty() ||
                        !prefs.getBoolean(SmsQueueStore.SMS_ACCESS_ENABLED_KEY, false) ||
                        prefs.getString(
                            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
                            null,
                        ).orEmpty().trim() != requestedOwner ||
                        !supportsSmsAccess() ||
                        !hasSmsPermissions()
                    ) {
                        result.error("sms_access_owner_mismatch", "SMS receipt access needs review", smsAccessStatus())
                        return@setMethodCallHandler
                    }
                    runSmsQueueTask(result, stillAuthorized = {
                        val current = activity.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
                        current.getBoolean(SmsQueueStore.SMS_ACCESS_ENABLED_KEY, false) &&
                            current.getString(SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY, null)
                                .orEmpty().trim() == requestedOwner &&
                            supportsSmsAccess() && hasSmsPermissions()
                    }) {
                        val array = SmsQueueStore(activity.applicationContext).readForOwner(requestedOwner)
                        val values = mutableListOf<Map<String, String>>()
                        for (index in 0 until array.length()) {
                            val item = array.optJSONObject(index) ?: JSONObject()
                            values.add(app.cool.mobile.receiver_sms.MemberSmsUploadPolicy.flutterEnvelope(item))
                        }
                        values
                    }
                }
                "ackPendingSms" -> {
                    val owner = call.argument<String>("owner_user_id").orEmpty()
                    val hashes = call.argument<Map<String, String>>("body_hashes").orEmpty()
                    val ids = call.argument<List<String>>("ids").orEmpty()
                    if (call.argument<Int>("contract_version") != 2 || owner.isBlank() ||
                        ids.isEmpty() || ids.toSet().size != ids.size || ids.toSet() != hashes.keys) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    runSmsQueueTask(result) {
                        SmsQueueStore(activity.applicationContext).acknowledgeDurable(owner, hashes)
                    }
                }
                "openAppSettings" -> {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", activity.packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != pendingSmsRequestCode) return
        pendingSmsRequestCode = null

        if (pendingSmsAccessResult == null || pendingSmsOwnerUserId == null) {
            // A revoked or signed-out request must never activate capture when
            // Android delivers its permission callback later.
            activity.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE).edit(commit = true) {
                putBoolean(SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY, true)
            }
            return
        }

        val granted = SMS_PERMISSIONS.all { permission ->
            activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
        val saved = SmsQueueStore(activity.applicationContext).completePermissionRequest(
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

    fun runSmsQueueTask(
        result: MethodChannel.Result,
        stillAuthorized: (() -> Boolean)? = null,
        task: () -> Any?,
    ) {
        try {
            SmsQueueWorker.execute {
                try {
                    val value = task()
                    activity.runOnUiThread {
                        val authorized = runCatching { stillAuthorized?.invoke() != false }
                            .getOrDefault(false)
                        if (!authorized) {
                            result.error(
                                "sms_access_owner_mismatch",
                                "SMS receipt access changed before read completed",
                                smsAccessStatus(),
                            )
                        } else {
                            result.success(value)
                        }
                    }
                } catch (_: Exception) {
                    activity.runOnUiThread {
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

    private fun hasSmsPermissions(): Boolean {
        return SMS_PERMISSIONS.all { permission ->
            activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun supportsSmsAccess(): Boolean {
        if (BuildConfig.FLAVOR != "internal_receiver" &&
            !app.cool.mobile.receiver_sms.MomoGatewayPolicy.memberCaptureSupported(BuildConfig.FLAVOR)) return false
        val messagingFeature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            PackageManager.FEATURE_TELEPHONY_MESSAGING
        } else {
            // Android only exposes the granular messaging feature from API 33.
            PackageManager.FEATURE_TELEPHONY
        }
        return packageDeclaresSmsPermissions() &&
            activity.packageManager.hasSystemFeature(messagingFeature)
    }

    @Suppress("DEPRECATION")
    private fun packageDeclaresSmsPermissions(): Boolean {
        val requested = activity.packageManager
            .getPackageInfo(activity.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            .orEmpty()
        return SMS_PERMISSIONS.all(requested::contains)
    }

    private fun isSmsPermissionPermanentlyDenied(): Boolean {
        val requestedBefore = activity.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
            .getBoolean(SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY, false)
        return supportsSmsAccess() &&
            requestedBefore &&
            !hasSmsPermissions() &&
            SMS_PERMISSIONS.none(activity::shouldShowRequestPermissionRationale)
    }

    private fun smsAccessStatus(requestedOwner: String? = null): Map<String, Boolean> {
        val prefs = activity.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
        val supported = supportsSmsAccess()
        val granted = supported && hasSmsPermissions()
        val storedOwner = prefs.getString(
            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
            null,
        ).orEmpty().trim()
        val ownStatus = SmsQueueOwnerPolicy.canSeeCaptureStatus(storedOwner, requestedOwner)
        return mapOf(
            "owner_scoped" to (requestedOwner != null),
            "supported" to supported,
            "declared" to packageDeclaresSmsPermissions(),
            "enabled" to (
                granted &&
                    ownStatus && storedOwner.isNotEmpty() &&
                    prefs.getBoolean(SmsQueueStore.SMS_ACCESS_ENABLED_KEY, false)
            ),
            "consent_enabled" to (ownStatus && prefs.getBoolean(SmsQueueStore.SMS_ACCESS_ENABLED_KEY, false)),
            "granted" to granted,
            "requested_before" to prefs.getBoolean(
                SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY,
                false,
            ),
            "should_show_rationale" to SMS_PERMISSIONS.any(activity::shouldShowRequestPermissionRationale),
            "permanently_denied" to isSmsPermissionPermanentlyDenied(),
            "queue_unavailable" to (ownStatus && prefs.getBoolean(SmsQueueStore.SMS_QUEUE_UNAVAILABLE_KEY, false)),
            "queue_needs_review" to (ownStatus && SmsQueueStore(activity.applicationContext).hasRejectedSources()),
            "queue_overflowed" to (ownStatus && prefs.getBoolean(
                SmsQueueStore.SMS_QUEUE_OVERFLOW_KEY,
                false,
            )),
        )
    }

    private fun nextSmsPermissionRequestCode(): Int? {
        val prefs = activity.getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
        val previous = prefs.getInt(SMS_PERMISSION_REQUEST_SEQUENCE_KEY, 0)
        val next = (previous % SMS_PERMISSION_REQUEST_CODE_SPAN) + 1
        return if (prefs.commitReceiptState { putInt(SMS_PERMISSION_REQUEST_SEQUENCE_KEY, next) }) {
            SMS_PERMISSION_REQUEST_CODE_BASE + next
        } else {
            null
        }
    }

    companion object {
        private const val SMS_PERMISSION_REQUEST_CODE_BASE = 12000
        private const val SMS_PERMISSION_REQUEST_CODE_SPAN = 8000
        private const val SMS_PERMISSION_REQUEST_SEQUENCE_KEY = "permission_request_sequence"
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS
        )
    }
}
