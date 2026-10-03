package app.cool.mobile.gateway

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec

internal class GatewayDeviceIdentity {
    private val alias = "collect.gateway.device.signing.v1"
    private fun store(): KeyStore = KeyStore.getInstance("AndroidKeyStore").also { it.load(null) }
    fun ensureKey() {
        if (store().containsAlias(alias)) return
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
            initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false).build())
            generateKeyPair()
        }
    }
    fun publicKeyBytes(): ByteArray = store().getCertificate(alias)?.publicKey?.encoded
        ?: throw GatewayStateException("gateway_identity_unavailable")
    fun keyId(): String = MessageDigest.getInstance("SHA-256").digest(publicKeyBytes()).joinToString("") { "%02x".format(it) }
    fun publicKeyBase64(): String = Base64.encodeToString(publicKeyBytes(), Base64.NO_WRAP)
    fun signExact(bytes: ByteArray): String {
        if (bytes.size !in 1..(32 * 1024)) throw GatewayStateException("gateway_request_invalid")
        val key = store().getKey(alias, null) as? java.security.PrivateKey ?: throw GatewayStateException("gateway_identity_unavailable")
        return Base64.encodeToString(Signature.getInstance("SHA256withECDSA").run {
            initSign(key)
            update(bytes)
            sign()
        }, Base64.NO_WRAP)
    }
}
