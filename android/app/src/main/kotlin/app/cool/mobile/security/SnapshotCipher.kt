package app.cool.mobile.security

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Owner and schema are authenticated; ciphertext cannot be moved across accounts.
 * This cache is not a financial authority. Keys are provided by the native host.
 */
class SnapshotCipher(private val key: (Boolean) -> SecretKey) {
    fun encrypt(owner: String, plaintext: String): ByteArray {
        validateOwner(owner)
        val bytes = plaintext.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_BYTES) { "Snapshot exceeds cache limit" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        cipher.updateAAD(binding(owner))
        return byteArrayOf(VERSION) + cipher.iv + cipher.doFinal(bytes)
    }
    fun decrypt(owner: String, ciphertext: ByteArray): String {
        validateOwner(owner)
        require(ciphertext.size in 29..(MAX_BYTES + 29) && ciphertext[0] == VERSION) { "Invalid protected snapshot" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, ciphertext.copyOfRange(1, 13)))
        cipher.updateAAD(binding(owner))
        val bytes = cipher.doFinal(ciphertext.copyOfRange(13, ciphertext.size))
        return StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
    }
    private fun binding(owner: String) = "collect.snapshot.v5\u0000$owner".toByteArray(Charsets.UTF_8)
    companion object {
        const val MAX_BYTES = 1024 * 1024
        private const val VERSION: Byte = 5
        fun validateOwner(owner: String) {
            require(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").matches(owner)) { "Invalid snapshot owner" }
        }
    }
}
