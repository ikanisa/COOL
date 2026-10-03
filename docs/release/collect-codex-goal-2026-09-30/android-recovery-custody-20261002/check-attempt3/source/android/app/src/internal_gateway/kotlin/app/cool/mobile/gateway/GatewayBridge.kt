package app.cool.mobile.gateway

import android.Manifest
import app.cool.mobile.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class GatewayBridge(private val activity: GatewayActivity, messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor()
    private val closed = AtomicBoolean(false)
    private val localIntents = GatewayLocalDispatchIntent()
    private val channel = MethodChannel(messenger, "collect/gateway.v1")
    private val store by lazy { GatewayEncryptedStore(activity.applicationContext) }
    private val journal by lazy { GatewayJournal(store) }
    private val identity = GatewayDeviceIdentity()
    private val observations = GatewayAndroidObservations(activity.applicationContext)
    private val backend by lazy { GatewaySignedBackend(activity.applicationContext, store, identity) }
    @Volatile private var initialized = false
    private var reason = "gateway_not_enrolled"
    private var pendingPermission: MethodChannel.Result? = null
    private val engine by lazy { GatewayDispatchEngine(journal, backend,
        GatewayGuardedSmsInvoker(AndroidGatewaySmsInvoker(activity.applicationContext)) { !closed.get() }, {
            val value = observations.read()
            if (closed.get()) value.copy(networkValidated = false) else value
        }) }

    init {
        channel.setMethodCallHandler { call, result ->
            if (closed.get()) { safeError(result, "gateway_cycle_stopped"); return@setMethodCallHandler }
            val admittedIntent = localIntents.generation()
            if (BuildConfig.FLAVOR != "internal_gateway") {
                result.error("gateway_flavor_required", "Internal gateway installation required", null)
                return@setMethodCallHandler
            }
            if (call.method != "provisionEnrollment" && call.arguments != null) {
                result.error("gateway_arguments_invalid", "Gateway operation arguments are invalid", null)
                return@setMethodCallHandler
            }
            if (call.method == "pause") {
                // Bypass queued network work. Pausing fsyncs while a grant is
                // fetched and wins the final pre-invocation local gate.
                try {
                    localIntents.pause(journal)
                    result.success(snapshot())
                } catch (_: Exception) { safeError(result, "gateway_storage_unavailable") }
                return@setMethodCallHandler
            }
            if (!initialized && call.method != "initialize") {
                result.error("gateway_entrypoint_required", "Gateway initialization required", null)
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
                    if (closed.get()) throw GatewayStateException("gateway_cycle_stopped")
                    when (call.method) {
                        "initialize" -> {
                            store.requireActiveInstallation()
                            identity.ensureKey()
                            metadata()
                            journal.read()
                            initialized = true
                            if (backend.configured()) {
                                verifyInstalledEnrollment()
                                GatewayBackgroundScheduler.ensure(activity.applicationContext)
                            }
                            success(result, snapshot())
                        }
                        "status" -> success(result, snapshot())
                        "identity" -> success(result, metadata().toMap())
                        "heartbeat" -> {
                            GatewayCycleGate.run { verifyInstalledEnrollment(); backend.heartbeat(observations.read()) }
                                ?: throw GatewayStateException("gateway_cycle_busy")
                            reason = "gateway_key_proof_recorded"
                            success(result, snapshot())
                        }
                        "reconcile" -> {
                            GatewayCycleGate.run { verifyInstalledEnrollment(); backend.reconcile(journal.read()); true }
                                ?: throw GatewayStateException("gateway_cycle_busy")
                            reason = "gateway_evidence_reconciled"
                            success(result, snapshot())
                        }
                        "dispatchNext" -> {
                            GatewayCycleGate.run { verifyInstalledEnrollment(); engine.dispatchOne(); true }
                                ?: throw GatewayStateException("gateway_cycle_busy")
                            success(result, snapshot())
                        }
                        "allowGovernedDispatch" -> {
                            GatewayBackgroundCoordinator(journal, backend, observations::read, engine::dispatchOne,
                                backend::configured, ::verifyInstalledEnrollment, GatewayCycleToken()).allowGovernedDispatch {
                                if (closed.get()) throw GatewayStateException("gateway_cycle_stopped")
                                localIntents.allow(admittedIntent, journal)
                            }
                            reason = "gateway_local_dispatch_allowed"
                            GatewayBackgroundScheduler.ensure(activity.applicationContext)
                            success(result, snapshot())
                        }
                        "provisionEnrollment" -> {
                            val arguments = call.arguments as? Map<*, *> ?: throw GatewayStateException("gateway_enrollment_invalid")
                            provision(arguments)
                            success(result, snapshot())
                        }
                        // No caller-supplied grant, body, destination or force-send.
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

    fun close() {
        closed.set(true)
        localIntents.invalidate()
        channel.setMethodCallHandler(null)
        observations.close()
        worker.shutdownNow()
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
        val certificate = gatewaySigningCertificateSha256(activity)
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

    private fun verifyInstalledEnrollment() {
        if (closed.get()) throw GatewayStateException("gateway_cycle_stopped")
        GatewayInstalledEnrollment.verify(store.readIdentityMetadata(), store.readEnrollment(), identity.keyId(),
            identity.publicKeyBase64(), gatewaySigningCertificateSha256(activity))
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
        if (backend.configured()) GatewayBackgroundScheduler.ensure(activity.applicationContext)
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
