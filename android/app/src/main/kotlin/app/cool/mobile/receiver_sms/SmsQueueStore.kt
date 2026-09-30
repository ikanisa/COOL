package app.cool.mobile.receiver_sms

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

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

    /** The caller's authenticated account must match both consent and every item. */
    fun readForOwner(ownerUserId: String): JSONArray = synchronized(lock) {
        val prefs = preferences()
        val activeOwner = prefs.getString(SMS_ACCESS_OWNER_USER_ID_KEY, null).orEmpty().trim()
        check(SmsQueueOwnerPolicy.canRead(
            prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false), activeOwner, ownerUserId,
        )) { "Secure receipt queue owner mismatch" }
        val queue = readLocked()
        validateQueueOwner(queue, activeOwner)
        queue
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
            validateQueueOwner(queue, activeOwner)
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

    /** Only the current owner's exact server-acknowledged body may be removed. */
    fun acknowledgeDurable(ownerUserId: String, hashes: Map<String, String>): Boolean = synchronized(lock) {
        val activeOwner = preferences().getString(SMS_ACCESS_OWNER_USER_ID_KEY, null).orEmpty()
        if (!preferences().getBoolean(SMS_ACCESS_ENABLED_KEY, false)) return@synchronized false
        val pending = readLocked()
        val envelopes = mutableListOf<ReceiptAckPolicy.Envelope>()
        for (index in 0 until pending.length()) {
            val item = pending.optJSONObject(index) ?: return@synchronized false
            envelopes.add(ReceiptAckPolicy.Envelope(item.optString("id", ""),
                item.optString("owner_user_id", ""), item.optString("raw_body", "")))
        }
        if (!ReceiptAckPolicy.canAcknowledge(activeOwner, ownerUserId, hashes, envelopes)) return@synchronized false
        val retained = JSONArray()
        for (index in 0 until pending.length()) {
            val item = pending.getJSONObject(index)
            if (!hashes.containsKey(item.getString("id"))) retained.put(item)
        }
        writeLocked(retained)
    }

    @Deprecated("A server-confirmed owner and body hash are required")
    fun acknowledge(ids: Set<String>): Boolean = ids.isEmpty()

    /** Binds consent to one account, preserving unacknowledged old-owner evidence. */
    fun enableForOwner(ownerUserId: String): Boolean = synchronized(lock) {
        bindOwnerLocked(ownerUserId.trim(), markPermissionRequested = false)
    }

    private fun bindOwnerLocked(cleanOwner: String, markPermissionRequested: Boolean): Boolean {
        if (cleanOwner.isEmpty()) return false
        val prefs = preferences()
        val previousOwner = prefs.getString(SMS_ACCESS_OWNER_USER_ID_KEY, null)
            .orEmpty()
            .trim()
        val pending = try {
            readLocked().also { queue ->
                if (previousOwner.isNotEmpty()) validateQueueOwner(queue, previousOwner)
            }
        } catch (_: Exception) {
            // A locked/lost key or damaged queue must not be overwritten by a
            // new empty queue when consent is resumed or the account changes.
            prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, false)
                .putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, true)
                .putBoolean(SMS_PERMISSION_REQUESTED_KEY, markPermissionRequested ||
                    prefs.getBoolean(SMS_PERMISSION_REQUESTED_KEY, false)).commit()
            return false
        }
        if (previousOwner != cleanOwner && pending.length() != 0) {
            // Do not rebind the old owner's ciphertext or make it visible to
            // a new account. An ordinary disable does not discard evidence.
            prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, false)
                .putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, true)
                .putBoolean(SMS_PERMISSION_REQUESTED_KEY, markPermissionRequested ||
                    prefs.getBoolean(SMS_PERMISSION_REQUESTED_KEY, false)).commit()
            return false
        }
        val editor = prefs.edit()
            .putBoolean(SMS_ACCESS_ENABLED_KEY, true)
            .putString(SMS_ACCESS_OWNER_USER_ID_KEY, cleanOwner)
        if (markPermissionRequested) editor.putBoolean(SMS_PERMISSION_REQUESTED_KEY, true)
        if (previousOwner != cleanOwner) {
            editor
                .remove(ENCRYPTED_QUEUE_KEY)
                .remove(LEGACY_QUEUE_KEY)
                .remove(SMS_QUEUE_OVERFLOW_KEY)
                .remove(SMS_QUEUE_UNAVAILABLE_KEY)
        }
        return editor.commit()
    }

    /** Stops capture without deleting unacknowledged owner-bound receipts. */
    fun disablePreservingQueue(ownerUserId: String): Boolean = synchronized(lock) {
        val prefs = preferences()
        val activeOwner = prefs.getString(SMS_ACCESS_OWNER_USER_ID_KEY, null).orEmpty().trim()
        if (!SmsQueueOwnerPolicy.canDisable(activeOwner, ownerUserId.trim())) {
            return@synchronized false
        }
        prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, false).commit()
    }

    /** Suspends a prior session on cold start or an external auth change. */
    fun suspendUnlessOwner(currentUserId: String?): Boolean = synchronized(lock) {
        val prefs = preferences()
        val activeOwner = prefs.getString(SMS_ACCESS_OWNER_USER_ID_KEY, null).orEmpty().trim()
        if (activeOwner.isEmpty() || activeOwner == currentUserId?.trim()) {
            return@synchronized true
        }
        prefs.edit().putBoolean(SMS_ACCESS_ENABLED_KEY, false).commit()
    }

    /** Persists the Android permission decision and owner binding atomically. */
    fun completePermissionRequest(granted: Boolean, ownerUserId: String?): Boolean =
        synchronized(lock) {
            val cleanOwner = ownerUserId.orEmpty().trim()
            val enable = granted && cleanOwner.isNotEmpty()
            if (enable) return@synchronized bindOwnerLocked(cleanOwner, markPermissionRequested = true)
            // A denied permission request stops capture. It is not an explicit
            // consent revocation or sign-out, so pending receipts from an
            // earlier owner must remain encrypted for an authorized recovery.
            val editor = preferences().edit()
                .putBoolean(SMS_PERMISSION_REQUESTED_KEY, true)
                .putBoolean(SMS_ACCESS_ENABLED_KEY, false)
            editor.commit()
        }

    private fun validateQueueOwner(queue: JSONArray, owner: String) {
        val owners = (0 until queue.length()).map { index ->
            val item = queue.optJSONObject(index)
                ?: run {
                    preferences().edit().putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, true).commit()
                    throw IllegalStateException("Secure receipt queue contains an invalid item")
                }
            item.optString("owner_user_id", "").trim()
        }
        if (!SmsQueueOwnerPolicy.canRead(true, owner, owner, owners)) {
            preferences().edit().putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, true).commit()
            throw IllegalStateException("Secure receipt queue contains another account's item")
        }
    }

    private fun readLocked(): JSONArray {
        val encrypted = preferences().getString(ENCRYPTED_QUEUE_KEY, null)
            ?: return migrateLegacyQueueLocked()
        return try {
            val queue = JSONArray(decrypt(encrypted))
            preferences().edit().putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, false).commit()
            queue
        } catch (error: Exception) {
            // Keystore may be temporarily locked. Preserve ciphertext for retry;
            // corrupt data needs explicit, separately approved recovery, not deletion.
            preferences().edit().putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, true).commit()
            throw IllegalStateException("Secure receipt queue unavailable", error)
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
        val legacy = preferences().getString(LEGACY_QUEUE_KEY, null) ?: return JSONArray()
        try {
            val queue = JSONArray(legacy)
            if (!writeLocked(queue)) throw IllegalStateException("Queue persistence failed")
            preferences().edit().putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, false).commit()
            return queue
        } catch (error: Exception) {
            preferences().edit().putBoolean(SMS_QUEUE_UNAVAILABLE_KEY, true).commit()
            throw IllegalStateException("Secure receipt queue unavailable", error)
        }
    }

    private fun preferences() = context.getSharedPreferences(
        SMS_ACCESS_PREFS,
        Context.MODE_PRIVATE,
    )

    private fun receiptCipher() = ReceiptCipher(
        key = { secretKey() },
        encode = { Base64.encodeToString(it, Base64.NO_WRAP) },
        decode = { Base64.decode(it, Base64.NO_WRAP) },
    )
    private fun encrypt(value: String): String = receiptCipher().encrypt(value)
    private fun decrypt(value: String): String = receiptCipher().decrypt(value)

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
        const val SMS_QUEUE_UNAVAILABLE_KEY = "queue_unavailable"
        private const val ENCRYPTED_QUEUE_KEY = "pending_sms_encrypted_v1"
        private const val LEGACY_QUEUE_KEY = "pending_sms"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "collect_sms_queue_v1"
        private val lock = Any()
    }
}
