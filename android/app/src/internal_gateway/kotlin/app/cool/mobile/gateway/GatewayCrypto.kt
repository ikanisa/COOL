package app.cool.mobile.gateway

import java.nio.ByteBuffer
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Algorithm/format is shared with JVM tests; production supplies a
 * non-exportable Android Keystore AES key. No plaintext storage fallback. */
internal class GatewayCrypto(private val key: SecretKey, context: String = "CollectGatewayJournal/v1") {
    private val aad = context.toByteArray(Charsets.UTF_8)

    fun encrypt(plaintext: ByteArray): ByteArray {
        if (plaintext.size > MAX_BYTES) throw GatewayStateException("gateway_journal_limit")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        if (cipher.iv.size != 12) throw GatewayStateException("gateway_journal_unavailable")
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(plaintext)
        return ByteBuffer.allocate(1 + 12 + ciphertext.size).put(1).put(cipher.iv).put(ciphertext).array()
    }

    fun decrypt(value: ByteArray): ByteArray {
        if (value.size !in 29..(MAX_BYTES + 29) || value[0] != 1.toByte()) throw GatewayStateException("gateway_journal_invalid")
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, value.copyOfRange(1, 13)))
            cipher.updateAAD(aad)
            return cipher.doFinal(value.copyOfRange(13, value.size))
        } catch (_: Exception) { throw GatewayStateException("gateway_journal_unavailable") }
    }

    companion object {
        const val MAX_BYTES = 512 * 1024
        fun nonce(): String = ByteArray(32).also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it) }
    }
}
