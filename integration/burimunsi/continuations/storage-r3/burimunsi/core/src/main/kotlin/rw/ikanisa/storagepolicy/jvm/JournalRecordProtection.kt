package rw.ikanisa.storagepolicy.jvm

import rw.ikanisa.storagepolicy.*
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.security.GeneralSecurityException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Record identity excludes the transient .pending/.snapshot filename so explicit promotion
 * preserves authenticated bytes. The scope must be stable across ledger generations. */
interface JournalRecordProtection {
    val maxOverhead: Int
    val authenticated: Boolean
    fun validateBinding(binding: Binding)
    fun seal(recordId: String, plaintext: ByteArray): ByteArray
    fun open(recordId: String, record: ByteArray): ByteArray
}

/** Host-fixture compatibility ONLY. Never selected as a fallback after crypto failure. */
object UnprotectedHostRecords : JournalRecordProtection {
    override val maxOverhead = 0
    override val authenticated = false
    override fun validateBinding(binding: Binding) = Unit
    override fun seal(recordId: String, plaintext: ByteArray) = plaintext.copyOf()
    override fun open(recordId: String, record: ByteArray) = record.copyOf()
}

data class JournalScope(val product: String, val owner: String, val journalId: String) {
    init { Binding(product, owner, journalId) }
}

/** Key lookup only: missing/inaccessible keys are NOT generated or replaced. */
fun interface ExistingJournalKey { fun requireKey(): SecretKey }

/** AES-256-GCM framing using the provider's random encryption IV. Ciphertext, owner,
 * product, journal namespace, record identity and envelope version are authenticated.
 * Authentication is not freshness: a trusted external monotonic anchor is still needed
 * to detect removal of a complete valid history suffix. */
class AesGcmJournalRecords(
    private val scope: JournalScope,
    private val keys: ExistingJournalKey,
) : JournalRecordProtection {
    companion object { private const val MAGIC = 0x4c434531; private const val VERSION = 1 }
    override val maxOverhead = 36 // magic + version + 12-byte IV + 16-byte tag
    override val authenticated = true
    override fun validateBinding(binding: Binding) {
        if (binding.product != scope.product || binding.owner != scope.owner)
            throw StoragePolicyFailure("journal_crypto_scope_mismatch")
    }
    private fun aad(recordId: String): ByteArray {
        if (recordId.isBlank() || recordId.length > 128 || recordId.any { it.isISOControl() })
            throw StoragePolicyFailure("journal_invalid_record_identity")
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            out.writeInt(MAGIC); out.writeInt(VERSION)
            for (s in listOf(scope.product, scope.owner, scope.journalId, recordId)) {
                val b = s.toByteArray(Charsets.UTF_8); out.writeInt(b.size); out.write(b)
            }
        }
        return bytes.toByteArray()
    }
    private fun key(): SecretKey {
        val value = keys.requireKey()
        if (value.algorithm != "AES") throw StoragePolicyFailure("journal_key_algorithm")
        // Non-exportable Android Keystore keys have null encoding. Their provisioning
        // contract requires AES-256; do not export key material merely to inspect it.
        val raw = value.encoded
        try { if (raw != null && raw.size != 32) throw StoragePolicyFailure("journal_key_size") }
        finally { raw?.fill(0) }
        return value
    }
    override fun seal(recordId: String, plaintext: ByteArray): ByteArray {
        if (plaintext.size !in 1..(LifecycleSnapshotCodec.MAX_BYTES + 136))
            throw StoragePolicyFailure("journal_plaintext_size")
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val iv = cipher.iv
            if (iv == null || iv.size != 12) throw StoragePolicyFailure("journal_iv_size")
            cipher.updateAAD(aad(recordId))
            val encrypted = cipher.doFinal(plaintext)
            return ByteBuffer.allocate(20 + encrypted.size).putInt(MAGIC).putInt(VERSION)
                .put(iv).put(encrypted).array()
        } catch (e: GeneralSecurityException) {
            throw StoragePolicyFailure("journal_key_or_cipher_unavailable")
        }
    }
    override fun open(recordId: String, record: ByteArray): ByteArray {
        if (record.size !in 37..(LifecycleSnapshotCodec.MAX_BYTES + 136 + maxOverhead))
            throw StoragePolicyFailure("journal_envelope_size")
        val input = ByteBuffer.wrap(record)
        if (input.int != MAGIC) throw StoragePolicyFailure("journal_envelope_magic")
        if (input.int != VERSION) throw StoragePolicyFailure("journal_envelope_version")
        val iv = ByteArray(12); input.get(iv)
        val ciphertext = ByteArray(input.remaining()); input.get(ciphertext)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            cipher.updateAAD(aad(recordId))
            return cipher.doFinal(ciphertext)
        } catch (e: AEADBadTagException) {
            throw StoragePolicyFailure("journal_authentication_failed")
        } catch (e: GeneralSecurityException) {
            throw StoragePolicyFailure("journal_key_or_cipher_unavailable")
        }
    }
}
