package app.cool.mobile.gateway

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import app.cool.mobile.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

internal class GatewayBridge(private val activity: GatewayActivity, messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor()
    private val store by lazy { GatewayEncryptedStore(activity.applicationContext) }
    private val journal by lazy { GatewayJournal(store) }
    private val identity = GatewayDeviceIdentity()
    private val observations = GatewayAndroidObservations(activity.applicationContext)
    private val backend by lazy { GatewaySignedBackend(activity.applicationContext, store, identity) }
    private var initialized = false
    private var reason = "gateway_not_enrolled"
    private var pendingPermission: MethodChannel.Result? = null
    private val engine by lazy { GatewayDispatchEngine(journal, backend, AndroidGatewaySmsInvoker(activity.applicationContext), observations::read) }

    init {
        MethodChannel(messenger, "collect/gateway.v1").setMethodCallHandler { call, result ->
            if (BuildConfig.FLAVOR != "internal_gateway") {
                result.error("gateway_flavor_required", "Internal gateway installation required", null)
                return@setMethodCallHandler
            }
            if (call.method != "provisionEnrollment" && call.arguments != null) {
                result.error("gateway_arguments_invalid", "Gateway operation arguments are invalid", null)
                return@setMethodCallHandler
            }
            if (!initialized && call.method != "initialize") {
                result.error("gateway_entrypoint_required", "Gateway initialization required", null)
                return@setMethodCallHandler
            }
            if (call.method == "pause") {
                // Bypass queued network work. Pausing fsyncs while a grant is
                // fetched and wins the final pre-invocation local gate.
                try {
                    journal.pause()
                    result.success(snapshot())
                } catch (_: Exception) { safeError(result, "gateway_storage_unavailable") }
                return@setMethodCallHandler
            }
            if (call.method == "requestPermissions") {
                if (pendingPermission != null) {
                    safeError(result, "gateway_permission_request_pending")
                } else {
                    pendingPermission = result
                    activity.requestPermissions(arrayOf(Manifest.permission.SEND_SMS, Manifest.permission.READ_PHONE_STATE), PERMISSIONS)
                }
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    when (call.method) {
                        "initialize" -> {
                            identity.ensureKey()
                            metadata()
                            journal.read()
                            initialized = true
                            success(result, snapshot())
                        }
                        "status" -> success(result, snapshot())
                        "identity" -> success(result, metadata().toMap())
                        "heartbeat" -> {
                            backend.heartbeat(observations.read())
                            reason = "gateway_key_proof_recorded"
                            success(result, snapshot())
                        }
                        "reconcile" -> {
                            backend.reconcile(journal.read())
                            reason = "gateway_evidence_reconciled"
                            success(result, snapshot())
                        }
                        "dispatchNext" -> {
                            engine.dispatchOne()
                            success(result, snapshot())
                        }
                        "provisionEnrollment" -> {
                            val arguments = call.arguments as? Map<*, *> ?: throw GatewayStateException("gateway_enrollment_invalid")
                            provision(arguments)
                            success(result, snapshot())
                        }
                        // No local resume/force-send override: live dispatch
                        // stays paused until a reviewed authority stage exists.
                        else -> activity.runOnUiThread { result.notImplemented() }
                    }
                } catch (error: GatewayStateException) {
                    reason = error.reasonCode
                    activity.runOnUiThread { safeError(result, error.reasonCode) }
                } catch (_: Exception) {
                    reason = "gateway_operation_unavailable"
                    activity.runOnUiThread { safeError(result, reason) }
                }
            }
        }
    }

    fun permissionResult(code: Int) {
        if (code != PERMISSIONS) return
        val result = pendingPermission ?: return
        pendingPermission = null
        try { result.success(snapshot()) } catch (_: Exception) { safeError(result, "gateway_operation_unavailable") }
    }

    private fun metadata(): JSONObject {
        val existing = store.readIdentityMetadata()
        val keyId = identity.keyId()
        val certificate = certificateHash()
        if (existing != null) {
            requireKeys(existing, setOf("contract_version", "installation_id", "key_sha256", "signing_certificate_sha256", "public_key_spki_base64"))
            if (existing.get("contract_version") != 1) throw GatewayStateException("gateway_identity_changed")
            requireUuid(existing, "installation_id")
            if (strictString(existing, "key_sha256") != keyId || strictString(existing, "signing_certificate_sha256") != certificate ||
                strictString(existing, "public_key_spki_base64") != identity.publicKeyBase64()) throw GatewayStateException("gateway_identity_changed")
            return existing
        }
        return JSONObject().put("contract_version", 1).put("installation_id", UUID.randomUUID().toString())
            .put("key_sha256", keyId).put("signing_certificate_sha256", certificate)
            .put("public_key_spki_base64", identity.publicKeyBase64()).also(store::saveIdentityMetadata)
    }

    private fun certificateHash(): String {
        val info = if (Build.VERSION.SDK_INT >= 28) activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            else activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_SIGNATURES)
        val certificates = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        if (certificates == null || certificates.size != 1) throw GatewayStateException("gateway_signing_identity_unavailable")
        return MessageDigest.getInstance("SHA-256").digest(certificates[0].toByteArray()).joinToString("") { "%02x".format(it) }
    }

    private fun provision(value: Map<*, *>) {
        val keys = setOf("contract_version", "device_id", "installation_id", "key_sha256", "signing_certificate_sha256")
        if (value.keys != keys || value["contract_version"] != 1) throw GatewayStateException("gateway_enrollment_invalid")
        val device = value["device_id"] as? String ?: throw GatewayStateException("gateway_enrollment_invalid")
        val current = metadata()
        if (!validUuid(device) || value["installation_id"] != current.getString("installation_id") ||
            value["key_sha256"] != current.getString("key_sha256") || value["signing_certificate_sha256"] != current.getString("signing_certificate_sha256")) {
            throw GatewayStateException("gateway_enrollment_invalid")
        }
        val existing = store.readEnrollment()
        if (existing != null && strictString(existing, "device_id") != device) throw GatewayStateException("gateway_enrollment_conflict")
        store.saveEnrollment(JSONObject(value))
        reason = "gateway_enrollment_pending"
    }

    private fun snapshot(): Map<String, Any> {
        val state = journal.read()
        val device = observations.read()
        val provisioned = store.readEnrollment() != null
        // The initial backend does not attest activation/dispatch state in its
        // heartbeat DTO. An installed document alone remains pending.
        return mapOf("enrollment" to if (provisioned) "pending" else "not_enrolled", "emergency_paused" to state.emergencyPaused,
            "configured" to backend.configured(), "send_sms_permission" to device.sendSmsPermission,
            "read_phone_state_permission" to device.readPhoneStatePermission, "network_connected" to device.networkConnected,
            "network_validated" to device.networkValidated, "sim_ready" to device.simReady,
            "telephony_in_service" to device.telephonyInService, "subscription_selected" to device.subscriptionUnambiguous,
            "outcome_unknown_attempts" to state.attempts.count { it.outcome() == AttemptOutcome.OUTCOME_UNKNOWN },
            "framework_sent_attempts" to state.attempts.count { it.outcome() in setOf(AttemptOutcome.FRAMEWORK_SENT, AttemptOutcome.DELIVERY_CALLBACK_OBSERVED) },
            "delivery_callback_attempts" to state.attempts.count { it.outcome() == AttemptOutcome.DELIVERY_CALLBACK_OBSERVED },
            "reason_code" to reason)
    }

    private fun JSONObject.toMap(): Map<String, Any> = keys().asSequence().associateWith { get(it) }
    private fun success(result: MethodChannel.Result, value: Any) = activity.runOnUiThread { result.success(value) }
    private fun safeError(result: MethodChannel.Result, code: String) {
        val safe = if (code.matches(Regex("gateway_[a-z_]{1,80}"))) code else "gateway_operation_unavailable"
        result.error(safe, "Gateway operation unavailable", null)
    }
    companion object { private const val PERMISSIONS = 9045 }
}
