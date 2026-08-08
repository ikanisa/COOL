package app.cool.mobile.receiver_sms

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small encrypted, bounded queue for consented financial SMS messages.
 *
 * The queue is deliberately device-local, excluded from backup, and retained
 * until Flutter explicitly acknowledges successful ingestion. Corrupt or
 * invalidated ciphertext fails closed instead of exposing or crashing on raw
 * message data.
 */
class SmsQueueStore(private val context: Context) {
    fun read(): JSONArray = synchronized(lock) {
        val encrypted = preferences().getString(ENCRYPTED_QUEUE_KEY, null)
            ?: return@synchronized migrateLegacyQueue()
        try {
            JSONArray(decrypt(encrypted))
        } catch (_: Exception) {
            preferences().edit()
                .remove(ENCRYPTED_QUEUE_KEY)
                .remove(LEGACY_QUEUE_KEY)
                .commit()
            JSONArray()
        }
    }

    fun write(queue: JSONArray): Boolean = synchronized(lock) {
        val encrypted = encrypt(queue.toString())
        preferences().edit()
            .putString(ENCRYPTED_QUEUE_KEY, encrypted)
            .remove(LEGACY_QUEUE_KEY)
            .commit()
    }

    fun clear(): Boolean = synchronized(lock) {
        preferences().edit()
            .remove(ENCRYPTED_QUEUE_KEY)
            .remove(LEGACY_QUEUE_KEY)
            .commit()
    }

    private fun migrateLegacyQueue(): JSONArray {
        val legacy = preferences().getString(LEGACY_QUEUE_KEY, null)
            ?: return JSONArray()
        val queue = try {
            JSONArray(legacy)
        } catch (_: Exception) {
            JSONArray()
        }
        write(queue)
        return queue
    }

    private fun preferences() = context.getSharedPreferences(
        SMS_ACCESS_PREFS,
        Context.MODE_PRIVATE,
    )

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return listOf(cipher.iv, ciphertext).joinToString(".") {
            Base64.encodeToString(it, Base64.NO_WRAP)
        }
    }

    private fun decrypt(value: String): String {
        val parts = value.split('.', limit = 2)
        require(parts.size == 2) { "Invalid encrypted SMS queue" }
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                        KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setRandomizedEncryptionRequired(true)
                        .build(),
                )
            }
            .generateKey()
    }

    companion object {
        const val SMS_ACCESS_PREFS = "collect_sms_access"
        const val SMS_ACCESS_ENABLED_KEY = "enabled"
        const val SMS_PERMISSION_REQUESTED_KEY = "permission_requested"
        private const val ENCRYPTED_QUEUE_KEY = "pending_sms_encrypted_v1"
        private const val LEGACY_QUEUE_KEY = "pending_sms"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "collect_sms_queue_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private val lock = Any()
    }
}
