package app.cool.mobile.security

import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class ReceiptSmsPendingCipher(private val key: (Boolean) -> SecretKey) {
    private fun aad(owner: String): ByteArray { validateReceiptSmsUuid(owner)
        return ("collect.receipt-sms-pending.v1\u0000" + owner).toByteArray(Charsets.UTF_8) }
    fun encrypt(owner: String, bytes: ByteArray): ByteArray {
        ReceiptSmsPendingCodec.decode(owner, bytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key(true)); cipher.updateAAD(aad(owner))
        return byteArrayOf(1) + cipher.iv + cipher.doFinal(bytes)
    }
    fun decrypt(owner: String, encrypted: ByteArray): ByteArray {
        require(encrypted.size in 37..(ReceiptSmsPendingCodec.MAX_BYTES + 29) && encrypted[0] == 1.toByte())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, encrypted.copyOfRange(1,13))); cipher.updateAAD(aad(owner))
        val bytes = cipher.doFinal(encrypted.copyOfRange(13,encrypted.size)); ReceiptSmsPendingCodec.decode(owner,bytes); return bytes
    }
}
