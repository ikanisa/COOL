package app.cool.mobile.receiver_sms

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
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
    enum class AppendResult {
        STORED,
        DUPLICATE,
        FULL,
        DISABLED,
        FAILED,
    }

    fun read(): JSONArray = synchronized(lock) {
        readLocked()
    }

    fun write(queue: JSONArray): Boolean = synchronized(lock) {
        writeLocked(queue)
    }

    fun appendIfCapacity(envelope: JSONObject, maxItems: Int): AppendResult =
        synchronized(lock) {
            val prefs = preferences()
            val envelopeOwner = envelope.optString("owner_user_id", "").trim()
            val activeOwner = prefs.getString(SMS_ACCESS_OWNER_USER_ID_KEY, null)
                .orEmpty()
                .trim()
            if (!prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false) ||
                envelopeOwner.isEmpty() ||
                envelopeOwner != activeOwner
            ) {
                return@synchronized AppendResult.DISABLED
            }

            val queue = readLocked()
            val envelopeId = envelope.optString("id", "")
            for (index in 0 until queue.length()) {
                val item = queue.optJSONObject(index) ?: continue
                if (item.optString("id", "") == envelopeId) {
                    return@synchronized AppendResult.DUPLICATE
                }
            }
            if (queue.length() >= maxItems) {
                prefs.edit().putBoolean(SMS_QUEUE_OVERFLOW_KEY, true).commit()
                return@synchronized AppendResult.FULL
            }
            queue.put(envelope)
            if (writeLocked(queue)) AppendResult.STORED else AppendResult.FAILED
        }

    /** Atomically acknowledges IDs without overwriting an SMS appended mid-drain. */
    fun acknowledge(ids: Set<String>): Boolean = synchronized(lock) {
        if (ids.isEmpty()) return@synchronized true
        val pending = readLocked()
        val retained = JSONArray()
        for (index in 0 until pending.length()) {
            val item = pending.optJSONObject(index) ?: continue
            if (!ids.contains(item.optString("id", ""))) retained.put(item)
        }
        writeLocked(retained)
    }

    fun clear(): Boolean = synchronized(lock) {
        preferences().edit()
            .remove(ENCRYPTED_QUEUE_KEY)
            .remove(LEGACY_QUEUE_KEY)
            .remove(SMS_QUEUE_OVERFLOW_KEY)
            .commit()
    }

    /** Atomically binds consent to one account and clears stale-owner data. */
    fun enableForOwner(ownerUserId: String): Boolean = synchronized(lock) {
        val cleanOwner = ownerUserId.trim()
        if (cleanOwner.isEmpty()) return@synchronized false
        val prefs = preferences()
        val previousOwner = prefs.getString(SMS_ACCESS_OWNER_USER_ID_KEY, null)
            .orEmpty()
            .trim()
        val editor = prefs.edit()
            .putBoolean(SMS_ACCESS_ENABLED_KEY, true)
            .putString(SMS_ACCESS_OWNER_USER_ID_KEY, cleanOwner)
        if (previousOwner.isNotEmpty() && previousOwner != cleanOwner) {
            editor
                .remove(ENCRYPTED_QUEUE_KEY)
                .remove(LEGACY_QUEUE_KEY)
                .remove(SMS_QUEUE_OVERFLOW_KEY)
        }
        editor.commit()
    }

    /** Disables capture and destroys queued message content in one commit. */
    fun disableAndClear(): Boolean = synchronized(lock) {
        preferences().edit()
            .putBoolean(SMS_ACCESS_ENABLED_KEY, false)
            .remove(SMS_ACCESS_OWNER_USER_ID_KEY)
            .remove(ENCRYPTED_QUEUE_KEY)
            .remove(LEGACY_QUEUE_KEY)
            .remove(SMS_QUEUE_OVERFLOW_KEY)
            .commit()
    }

    /** Persists the Android permission decision and owner binding atomically. */
    fun completePermissionRequest(granted: Boolean, ownerUserId: String?): Boolean =
        synchronized(lock) {
            val cleanOwner = ownerUserId.orEmpty().trim()
            val enable = granted && cleanOwner.isNotEmpty()
            val editor = preferences().edit()
                .putBoolean(SMS_PERMISSION_REQUESTED_KEY, true)
                .putBoolean(SMS_ACCESS_ENABLED_KEY, enable)
            if (enable) {
                editor.putString(SMS_ACCESS_OWNER_USER_ID_KEY, cleanOwner)
            } else {
                editor
                    .remove(SMS_ACCESS_OWNER_USER_ID_KEY)
                    .remove(ENCRYPTED_QUEUE_KEY)
                    .remove(LEGACY_QUEUE_KEY)
                    .remove(SMS_QUEUE_OVERFLOW_KEY)
            }
            editor.commit()
        }

    private fun readLocked(): JSONArray {
        val encrypted = preferences().getString(ENCRYPTED_QUEUE_KEY, null)
            ?: return migrateLegacyQueueLocked()
        return try {
            JSONArray(decrypt(encrypted))
        } catch (_: Exception) {
            preferences().edit()
                .remove(ENCRYPTED_QUEUE_KEY)
                .remove(LEGACY_QUEUE_KEY)
                .commit()
            JSONArray()
        }
    }

    private fun writeLocked(queue: JSONArray): Boolean {
        val encrypted = encrypt(queue.toString())
        return preferences().edit()
            .putString(ENCRYPTED_QUEUE_KEY, encrypted)
            .remove(LEGACY_QUEUE_KEY)
            .commit()
    }

    private fun migrateLegacyQueueLocked(): JSONArray {
        val legacy = preferences().getString(LEGACY_QUEUE_KEY, null)
            ?: return JSONArray()
        val queue = try {
            JSONArray(legacy)
        } catch (_: Exception) {
            JSONArray()
        }
        writeLocked(queue)
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
        const val SMS_ACCESS_OWNER_USER_ID_KEY = "owner_user_id"
        const val SMS_QUEUE_OVERFLOW_KEY = "queue_overflowed"
        private const val ENCRYPTED_QUEUE_KEY = "pending_sms_encrypted_v1"
        private const val LEGACY_QUEUE_KEY = "pending_sms"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "collect_sms_queue_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private val lock = Any()
    }
}
