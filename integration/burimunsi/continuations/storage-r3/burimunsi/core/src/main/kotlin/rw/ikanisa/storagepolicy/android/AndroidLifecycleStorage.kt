package rw.ikanisa.storagepolicy.android

import rw.ikanisa.storagepolicy.*
import rw.ikanisa.storagepolicy.jvm.*
import java.nio.file.Path
import java.security.KeyStore
import java.security.GeneralSecurityException
import javax.crypto.SecretKey

/** AndroidKeyStore lookup via JCA. This code never creates, deletes or replaces a key.
 * The dedicated AES-256 alias must already exist, be excluded from generation cleanup,
 * and outlive every retained journal/archive record. Opening with a missing alias blocks.
 * Actual Android provider execution is a separate native acceptance requirement. */
class AndroidExistingLifecycleKey(private val alias: String): ExistingJournalKey {
    init { require(alias.isNotBlank() && alias.length <= 256 && alias.none { it.isISOControl() }) }
    override fun requireKey(): SecretKey {
        try {
            val store = KeyStore.getInstance("AndroidKeyStore")
            store.load(null)
            return store.getKey(alias, null) as? SecretKey
                ?: throw StoragePolicyFailure("journal_existing_key_missing")
        } catch (e: GeneralSecurityException) {
            throw StoragePolicyFailure("journal_existing_key_unavailable")
        }
    }
}

/** Application wiring seam. root is a pre-created private/no-backup journal directory,
 * never a database directory or cleanup target. Its ancestors must be nonsymlinks. A
 * missing directory remains an error. Use explicit audited provisioning before calling.
 * No plaintext mode or fallback is exposed through this factory. */
object AndroidLifecycleStorage {
    fun openExisting(root: Path, scope: JournalScope, alias: String,
        verifyVirginScope: (Binding) -> Boolean): AppendOnlyLifecycleJournal {
        val keys = AndroidExistingLifecycleKey(alias)
        keys.requireKey() // fail before any journal write/lock file creation
        return AppendOnlyLifecycleJournal(root, verifyVirginScope,
            protection = AesGcmJournalRecords(scope, keys))
    }
}
