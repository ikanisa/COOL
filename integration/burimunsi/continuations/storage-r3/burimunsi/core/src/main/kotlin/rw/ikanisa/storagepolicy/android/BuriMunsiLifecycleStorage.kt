package rw.ikanisa.storagepolicy.android

import rw.ikanisa.storagepolicy.*
import rw.ikanisa.storagepolicy.jvm.*
import java.nio.file.Path

/** Source integration factory; application entry points remain on the existing store
 * until explicit migration and native acceptance are completed. No key creation/reset. */
object BuriMunsiLifecycleStorage {
    fun openExisting(root: Path, owner: String, journalId: String, alias: String,
        verifyVirginScope: (Binding) -> Boolean): AppendOnlyLifecycleJournal {
        val scope = JournalScope("burimunsi", owner, journalId)
        return AndroidLifecycleStorage.openExisting(root, scope, alias, verifyVirginScope)
    }
}
