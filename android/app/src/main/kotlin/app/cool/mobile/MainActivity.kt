package app.cool.mobile

import app.cool.mobile.security.ProtectedSnapshotStore
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import app.cool.mobile.receiver_sms.SmsQueueEventBus
import app.cool.mobile.receiver_sms.SmsQueueStore
import app.cool.mobile.receiver_sms.commitReceiptState
import androidx.core.content.edit
import androidx.core.net.toUri
import app.cool.mobile.receiver_sms.SmsQueueWorker
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var turnstileHost: CollectTurnstileHost? = null

    override fun onDestroy() {
        turnstileHost?.dispose()
        turnstileHost = null
        super.onDestroy()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Flutter paints focus on individual controls. Android's default
            // host-view highlight adds a green frame around the whole app
            // after hardware keyboard input, including while the IME is open.
            findViewById<FlutterView>(FLUTTER_VIEW_ID)
                ?.setDefaultFocusHighlightEnabled(false)
        }
    }

    private var pendingSmsAccessResult: MethodChannel.Result? = null
    private var pendingSmsOwnerUserId: String? = null
    private var pendingSmsRequestCode: Int? = null
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

    override fun onResume() {
        super.onResume()
        app.cool.mobile.receiver_sms.MemberSmsJobs.ensure(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        turnstileHost?.dispose()
        val challengeHost = CollectTurnstileHost(this)
        turnstileHost = challengeHost
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collect/turnstile")
            .setMethodCallHandler { call, result -> challengeHost.handle(call, result) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collect/secure_snapshot")
            .setMethodCallHandler { call, result ->
                val storage = ProtectedSnapshotStore(applicationContext)
                when (call.method) {
                    "read" -> runSmsQueueTask(result) {
                        storage.read(call.argument<String>("owner_id").orEmpty())
                    }
                    "write" -> runSmsQueueTask(result) {
                        storage.write(call.argument<String>("owner_id").orEmpty(),
                            call.argument<String>("value") ?: throw IllegalArgumentException("Snapshot required"))
                    }
                    "clear" -> runSmsQueueTask(result) { storage.clear() }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collect/secure_auth_session")
            .setMethodCallHandler { call, result ->
                val storage = ProtectedSnapshotStore(applicationContext, purpose = "auth")
                when (call.method) {
                    "read" -> runSmsQueueTask(result) {
                        storage.read(call.argument<String>("owner_id").orEmpty())
                    }
                    "write" -> runSmsQueueTask(result) {
                        storage.write(call.argument<String>("owner_id").orEmpty(),
                            call.argument<String>("value") ?: throw IllegalArgumentException("Session required")).also {
                            if (it) app.cool.mobile.receiver_sms.MemberSmsJobs.ensure(applicationContext)
                        }
                    }
                    "clear" -> runSmsQueueTask(result) { storage.clear() }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collect/payment_help_pending")
            .setMethodCallHandler { call, result ->
                val storage = ProtectedSnapshotStore(applicationContext, purpose = "payment_help")
                when (call.method) {
                    "read" -> runPaymentHelpPendingTask(result) {
                        storage.read(call.argument<String>("owner_id").orEmpty())
                    }
                    "write" -> runPaymentHelpPendingTask(result) {
                        storage.write(call.argument<String>("owner_id").orEmpty(),
                            call.argument<String>("value") ?: throw IllegalArgumentException("Pending request required"))
                    }
                    "clear" -> runPaymentHelpPendingTask(result) {
                        val owner = call.argument<String>("owner_id")
                        require(!call.hasArgument("owner_id") || owner != null) { "Owner required" }
                        storage.clear(owner)
                    }
                    else -> result.notImplemented()
                }
            }

        val receiptSmsPending = app.cool.mobile.security.ReceiptSmsPendingStore(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collect/receipt_sms_pending")
            .setMethodCallHandler { call, result ->
                val owner = call.argument<String>("owner_id").orEmpty()
                val group = call.argument<String>("collection_id").orEmpty()
                when (call.method) {
                    "read" -> runReceiptSmsPendingTask(result) { receiptSmsPending.read(owner, group) }
                    "claim" -> runReceiptSmsPendingTask(result) { receiptSmsPending.claim(owner, group, call.argument<Any>("request")) }
                    "claimWithdrawalFence" -> runReceiptSmsPendingTask(result) { receiptSmsPending.claim(owner, group, call.argument<Any>("request"), true) }
                    "complete" -> runReceiptSmsPendingTask(result) { receiptSmsPending.complete(owner, group, call.argument<Any>("request"), call.argument<Any>("decision_revision")) }
                    "supersede" -> runReceiptSmsPendingTask(result) { receiptSmsPending.supersede(owner, group, call.argument<Any>("known_requests"), call.argument<Any>("decision_revision")) }
                    else -> result.notImplemented()
                }
            }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "collect/momo_gateway")
            .setMethodCallHandler { call, result ->
                if (call.method != "openMomoGateway") result.notImplemented()
                else if (BuildConfig.FLAVOR != "internal_receiver") result.success(false)
                else {
                    startActivity(Intent(this, app.cool.mobile.receiver_sms.MomoGatewayActivity::class.java))
                    result.success(true)
                }
            }

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
                        val disabled = SmsQueueStore(applicationContext)
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
                        if (SmsQueueStore(applicationContext).enableForOwner(ownerUserId)) {
                            app.cool.mobile.receiver_sms.MemberSmsJobs.ensure(applicationContext)
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
                                requestPermissions(SMS_PERMISSIONS, requestCode)
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
                "status" -> result.success(smsAccessStatus())
                "suspendUnlessOwner" -> {
                    val currentUserId = call.argument<String>("current_user_id")?.trim()
                    val suspended = SmsQueueStore(applicationContext)
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
                    prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) &&
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
                        SmsQueueStore(applicationContext).activeCaptureOwner() == owner && hasSmsPermissions()
                    }) {
                        check(owner.isNotEmpty() && SmsQueueStore(applicationContext).activeCaptureOwner() == owner && hasSmsPermissions())
                        val queue = SmsQueueStore(applicationContext)
                        val changed = if (call.method == "parkPendingSms")
                            queue.parkRejected(owner, call.argument<String>("id").orEmpty(), 400)
                        else queue.retryRejected(owner)
                        if (changed) {
                            SmsQueueEventBus.notifyQueueChanged()
                            if (call.method == "retryRejectedSms") app.cool.mobile.receiver_sms.MemberSmsJobs.ensure(applicationContext)
                        }
                        changed
                    }
                }
                "readPendingSms" -> {
                    val requestedOwner = call.argument<String>("owner_user_id")?.trim().orEmpty()
                    if (
                        requestedOwner.isEmpty() ||
                        !prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) ||
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
                        val current = getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
                        current.getBoolean(SMS_ACCESS_ENABLED_KEY, false) &&
                            current.getString(SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY, null)
                                .orEmpty().trim() == requestedOwner &&
                            supportsSmsAccess() && hasSmsPermissions()
                    }) {
                        val array = SmsQueueStore(applicationContext).readForOwner(requestedOwner)
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
                        SmsQueueStore(applicationContext).acknowledgeDurable(owner, hashes)
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

    private fun runPaymentHelpPendingTask(result: MethodChannel.Result, task: () -> Any?) {
        fun unavailable() = result.error(
            "payment_help_storage_unavailable",
            "Secure payment help recovery is unavailable; retained requests were not discarded.",
            null,
        )
        try {
            SmsQueueWorker.execute {
                try {
                    val value = task()
                    runOnUiThread { result.success(value) }
                } catch (_: Exception) {
                    runOnUiThread { unavailable() }
                }
            }
        } catch (_: RuntimeException) {
            unavailable()
        }
    }

    private fun runReceiptSmsPendingTask(result: MethodChannel.Result, task: () -> Any?) {
        fun unavailable() = result.error(
            "receipt_sms_recovery_unavailable",
            "Secure receipt SMS recovery is unavailable; retained requests were not discarded.",
            null,
        )
        try {
            SmsQueueWorker.execute {
                try {
                    val value = task()
                    runOnUiThread { result.success(value) }
                } catch (_: Exception) {
                    runOnUiThread { unavailable() }
                }
            }
        } catch (_: RuntimeException) {
            unavailable()
        }
    }

    private fun runSmsQueueTask(
        result: MethodChannel.Result,
        stillAuthorized: (() -> Boolean)? = null,
        task: () -> Any?,
    ) {
        try {
            SmsQueueWorker.execute {
                try {
                    val value = task()
                    runOnUiThread {
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
        if (requestCode != pendingSmsRequestCode) return
        pendingSmsRequestCode = null

        if (pendingSmsAccessResult == null || pendingSmsOwnerUserId == null) {
            // A revoked or signed-out request must never activate capture when
            // Android delivers its permission callback later.
            getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE).edit(commit = true) {
                putBoolean(SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY, true)
            }
            return
        }

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
            val uri = "tel:${Uri.encode(code)}".toUri()
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
        if (BuildConfig.FLAVOR != "internal_receiver" &&
            !app.cool.mobile.receiver_sms.MomoGatewayPolicy.memberCaptureSupported(BuildConfig.FLAVOR)) return false
        val messagingFeature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            PackageManager.FEATURE_TELEPHONY_MESSAGING
        } else {
            // Android only exposes the granular messaging feature from API 33.
            PackageManager.FEATURE_TELEPHONY
        }
        return packageDeclaresSmsPermissions() &&
            packageManager.hasSystemFeature(messagingFeature)
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
            "consent_enabled" to prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false),
            "granted" to granted,
            "requested_before" to prefs.getBoolean(
                SmsQueueStore.SMS_PERMISSION_REQUESTED_KEY,
                false,
            ),
            "should_show_rationale" to SMS_PERMISSIONS.any(::shouldShowRequestPermissionRationale),
            "permanently_denied" to isSmsPermissionPermanentlyDenied(),
            "queue_unavailable" to prefs.getBoolean(SmsQueueStore.SMS_QUEUE_UNAVAILABLE_KEY, false),
            "queue_needs_review" to SmsQueueStore(applicationContext).hasRejectedSources(),
            "queue_overflowed" to prefs.getBoolean(
                SmsQueueStore.SMS_QUEUE_OVERFLOW_KEY,
                false,
            ),
        )
    }

    private fun nextSmsPermissionRequestCode(): Int? {
        val prefs = getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
        val previous = prefs.getInt(SMS_PERMISSION_REQUEST_SEQUENCE_KEY, 0)
        val next = (previous % SMS_PERMISSION_REQUEST_CODE_SPAN) + 1
        return if (prefs.commitReceiptState { putInt(SMS_PERMISSION_REQUEST_SEQUENCE_KEY, next) }) {
            SMS_PERMISSION_REQUEST_CODE_BASE + next
        } else {
            null
        }
    }

    companion object {
        const val SMS_ACCESS_PREFS = "collect_sms_access"
        const val SMS_ACCESS_ENABLED_KEY = "enabled"
        private const val SMS_PERMISSION_REQUEST_CODE_BASE = 12000
        private const val SMS_PERMISSION_REQUEST_CODE_SPAN = 8000
        private const val SMS_PERMISSION_REQUEST_SEQUENCE_KEY = "permission_request_sequence"
        private const val MOMO_USSD_PERMISSION_REQUEST_CODE = 183
        private val MOMO_USSD_PATTERN = Regex(
            "^(?:\\*182\\*\\*8\\*1\\*[0-9]{4,12}\\*[1-9][0-9]{0,8}|\\*182\\*8\\*1)#$",
        )
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS
        )
    }
}
