package rw.ikanisa.sms.policy

import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Fixed configured identity, never selected from an untrusted ciphertext header. */
data class StorageBinding(val scope: OwnerScope, val storeId: String, val keyAlias: String) {
    fun valid() = scope.valid() && EvidenceHash.identity(storeId) && EvidenceHash.identity(keyAlias)
    val contextHash: String get() = EvidenceHash.framed(listOf("sms-encrypted-journal-v1") + scope.fields() + listOf(storeId,keyAlias))
}

enum class SecureCode { FORMAT, VERSION, CONTEXT, SEQUENCE, SIZE, KEY_UNAVAILABLE, CRYPTO_UNAVAILABLE, AUTHENTICATION }
class SecureStorageException(val code: SecureCode): Exception(code.name)
private fun secureRequire(ok: Boolean, code: SecureCode) { if(!ok) throw SecureStorageException(code) }

/** Must only resolve an existing key. Missing, locked or invalidated keys must never be regenerated. */
fun interface ExistingAesKey { fun resolve(alias: String): SecretKey? }

/** Compiles on JVM; the AndroidKeyStore provider exists only on Android. Lookup only; no key creation. */
class ExistingAndroidKeystoreKey: ExistingAesKey {
    override fun resolve(alias: String): SecretKey? {
        val store=KeyStore.getInstance("AndroidKeyStore")
        store.load(null)
        return store.getKey(alias,null) as? SecretKey
    }
}

/**
 * AES-GCM envelope. Each seal uses a fresh Cipher and provider-generated IV, never a caller IV.
 * No key export, plaintext fallback, nonce reset, algorithm negotiation or automatic key creation.
 * Keys must be provisioned as AES-256 with an approved provider; non-exportable key strength is a
 * provisioning/attestation responsibility. Android provider behavior still requires native tests.
 */
class AesGcmJournalCipher(private val keys: ExistingAesKey) {
    companion object {
        const val VERSION=1
        const val HEADER_BYTES=64
        const val TAG_BYTES=16
        const val IV_BYTES=12
        const val MAX_BYTES=JournalFormat.MAX_BYTES+HEADER_BYTES+TAG_BYTES
        private const val MAGIC=0x534d5345 // SMSE
        private fun unhex(s: String)=ByteArray(32) { s.substring(it*2,it*2+2).toInt(16).toByte() }
    }
    private fun key(binding: StorageBinding): SecretKey = try {
        keys.resolve(binding.keyAlias)?.takeIf { it.algorithm.equals("AES",true) }
            ?: throw SecureStorageException(SecureCode.KEY_UNAVAILABLE)
    } catch(e: SecureStorageException) { throw e }
      catch(_: Exception) { throw SecureStorageException(SecureCode.KEY_UNAVAILABLE) }

    fun seal(plaintext: ByteArray, binding: StorageBinding, sequence: Long): ByteArray {
        secureRequire(binding.valid(),SecureCode.CONTEXT)
        secureRequire(sequence in 0..JournalFormat.MAX_RECORDS.toLong(),SecureCode.SEQUENCE)
        secureRequire(plaintext.size in JournalFormat.HEADER_BYTES..JournalFormat.MAX_BYTES,SecureCode.SIZE)
        val input=plaintext.copyOf()
        try {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE,key(binding))
            val iv=cipher.iv ?: throw SecureStorageException(SecureCode.CRYPTO_UNAVAILABLE)
            val params=cipher.parameters.getParameterSpec(GCMParameterSpec::class.java)
            secureRequire(iv.size==IV_BYTES && params.tLen==128,SecureCode.CRYPTO_UNAVAILABLE)
            val header=ByteBuffer.allocate(HEADER_BYTES).putInt(MAGIC).putInt(VERSION)
                .put(unhex(binding.contextHash)).putLong(sequence).putInt(input.size+TAG_BYTES).put(iv).array()
            cipher.updateAAD(header)
            return header+cipher.doFinal(input)
        } catch(e: SecureStorageException) { throw e }
          catch(_: Exception) { throw SecureStorageException(SecureCode.CRYPTO_UNAVAILABLE) }
        finally { input.fill(0) }
    }

    fun open(envelope: ByteArray, binding: StorageBinding, sequence: Long): ByteArray {
        secureRequire(binding.valid(),SecureCode.CONTEXT)
        secureRequire(sequence in 0..JournalFormat.MAX_RECORDS.toLong(),SecureCode.SEQUENCE)
        secureRequire(envelope.size in (HEADER_BYTES+TAG_BYTES+JournalFormat.HEADER_BYTES)..MAX_BYTES,SecureCode.SIZE)
        val retained=envelope.copyOf()
        try {
            val r=ByteBuffer.wrap(retained)
            secureRequire(r.int==MAGIC,SecureCode.FORMAT)
            secureRequire(r.int==VERSION,SecureCode.VERSION)
            val context=ByteArray(32); r.get(context)
            secureRequire(MessageDigest.isEqual(context,unhex(binding.contextHash)),SecureCode.CONTEXT)
            secureRequire(r.long==sequence,SecureCode.SEQUENCE)
            val length=r.int
            secureRequire(length==retained.size-HEADER_BYTES,SecureCode.SIZE)
            val iv=ByteArray(IV_BYTES); r.get(iv)
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,key(binding),GCMParameterSpec(128,iv))
            cipher.updateAAD(retained,0,HEADER_BYTES)
            return cipher.doFinal(retained,HEADER_BYTES,length)
        } catch(e: SecureStorageException) { throw e }
          catch(_: AEADBadTagException) { throw SecureStorageException(SecureCode.AUTHENTICATION) }
          catch(_: Exception) { throw SecureStorageException(SecureCode.CRYPTO_UNAVAILABLE) }
    }
}
