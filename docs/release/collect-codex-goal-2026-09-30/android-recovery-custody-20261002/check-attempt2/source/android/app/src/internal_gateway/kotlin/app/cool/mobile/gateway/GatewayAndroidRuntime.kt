package app.cool.mobile.gateway

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

/** Reconstructed from durable local evidence, never a recovered send permit.
 * Background startup does not create a signing key or clear local pause. */
internal class GatewayAndroidRuntime(context: Context, val token: GatewayCycleToken = GatewayCycleToken(), reconciliationOffset: Int = 0) : AutoCloseable {
    private val context = context.applicationContext
    val store = GatewayEncryptedStore(this.context)
    val journal = GatewayJournal(store)
    val identity = GatewayDeviceIdentity()
    val observations = GatewayAndroidObservations(this.context)
    val backend = GatewaySignedBackend(this.context, store, identity)
    init { backend.restoreReconciliationOffset(reconciliationOffset) }
    private val sms = AndroidGatewaySmsInvoker(this.context)
    private val engine = GatewayDispatchEngine(journal, backend, GatewayGuardedSmsInvoker(sms, token::active), {
        val value = observations.read()
        if (token.active()) value else value.copy(networkValidated = false)
    })
    val coordinator = GatewayBackgroundCoordinator(journal, backend, observations::read, engine::dispatchOne,
        backend::configured, ::verifyEnrollment, token)

    fun verifyEnrollment() {
        store.requireActiveInstallation()
        GatewayInstalledEnrollment.verify(store.readIdentityMetadata(), store.readEnrollment(),
            identity.keyId(), identity.publicKeyBase64(), gatewaySigningCertificateSha256(context))
    }

    override fun close() { token.cancel(); observations.close() }
}

@Suppress("DEPRECATION")
internal fun gatewaySigningCertificateSha256(context: Context): String {
    val signatures = if (Build.VERSION.SDK_INT >= 28) context.packageManager.getPackageInfo(context.packageName,
        PackageManager.GET_SIGNING_CERTIFICATES).signingInfo?.apkContentsSigners else
        context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES).signatures
    if (signatures == null || signatures.size != 1) throw GatewayStateException("gateway_signing_identity_unavailable")
    return MessageDigest.getInstance("SHA-256").digest(signatures[0].toByteArray()).joinToString("") { "%02x".format(it) }
}
