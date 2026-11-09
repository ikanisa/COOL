package rw.ikanisa.storagepolicy

import java.io.IOException
import java.nio.file.AccessDeniedException
import java.security.UnrecoverableKeyException
import java.util.Collections
import java.util.IdentityHashMap
import javax.crypto.AEADBadTagException

/** Only LOCAL storage errors belong here. No message, plaintext, path, token or key
 * material is inspected or returned. Unknown/cyclic/deep failures stay non-destructive. */
object StorageFailureClassifier {
    fun classify(error: Throwable): StorageFault {
        val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
        val found = mutableSetOf<StorageFault>()
        var current: Throwable? = error
        var remaining = 32
        while (current != null && remaining-- > 0 && seen.add(current)) {
            val fault = when {
                current is StoragePolicyFailure -> when (current.code) {
                    "storage_unsupported_version" -> StorageFault.UNSUPPORTED_VERSION
                    "storage_malformed", "invalid_stored_operation", "invalid_operation_tombstone" -> StorageFault.MALFORMED
                    "storage_key_unavailable" -> StorageFault.KEY_UNAVAILABLE
                    else -> StorageFault.UNKNOWN
                }
                current is AEADBadTagException -> StorageFault.AUTHENTICATION_FAILED
                current is UnrecoverableKeyException -> StorageFault.KEY_UNAVAILABLE
                current is AccessDeniedException || current is SecurityException -> StorageFault.PERMISSION_DENIED
                current.javaClass.name == "android.security.keystore.KeyPermanentlyInvalidatedException" -> StorageFault.KEY_PERMANENTLY_LOST
                current.javaClass.name in setOf("android.database.sqlite.SQLiteDatabaseCorruptException", "net.zetetic.database.sqlcipher.SQLiteDatabaseCorruptException") -> StorageFault.MALFORMED
                current.javaClass.name in setOf("android.database.sqlite.SQLiteFullException", "net.zetetic.database.sqlcipher.SQLiteFullException") -> StorageFault.NO_SPACE
                current is IOException || current.javaClass.name in setOf("android.database.sqlite.SQLiteDiskIOException", "net.zetetic.database.sqlcipher.SQLiteDiskIOException", "android.database.sqlite.SQLiteCantOpenDatabaseException", "net.zetetic.database.sqlcipher.SQLiteCantOpenDatabaseException") -> StorageFault.IO_UNAVAILABLE
                else -> StorageFault.UNKNOWN
            }
            found += fault
            current = current.cause
        }
        return listOf(StorageFault.KEY_PERMANENTLY_LOST, StorageFault.AUTHENTICATION_FAILED,
            StorageFault.UNSUPPORTED_VERSION, StorageFault.MALFORMED, StorageFault.KEY_UNAVAILABLE,
            StorageFault.PERMISSION_DENIED, StorageFault.NO_SPACE, StorageFault.IO_UNAVAILABLE,
            StorageFault.UNKNOWN).first { it in found }
    }
}
