package app.cool.mobile.receiver_sms
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Real AES-GCM; the platform supplies the key and base64 codec. */
class ReceiptCipher(
    private val key: () -> SecretKey,
    private val encode: (ByteArray) -> String,
    private val decode: (String) -> ByteArray,
) {
    fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return encode(cipher.iv) + "." + encode(ciphertext)
    }
    fun decrypt(value: String): String {
        val parts = value.split('.', limit = 2)
        require(parts.size == 2) { "Invalid protected receipt" }
        val iv = decode(parts[0])
        require(iv.size == 12) { "Invalid protected receipt" }
        val ciphertext = decode(parts[1])
        require(ciphertext.size >= 16) { "Invalid protected receipt" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }
}
