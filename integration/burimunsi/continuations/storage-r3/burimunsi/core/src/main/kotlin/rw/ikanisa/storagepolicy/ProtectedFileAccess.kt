package rw.ikanisa.storagepolicy

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.attribute.BasicFileAttributes

/** Non-following host/Android-API-26 file observations. Not a cross-process lock or a
 * durability guarantee. Callers hold the process-wide store lock for observation + I/O. */
object ProtectedFileAccess {
    fun members(base: File): List<File> = listOf(base, File(base.path + ".bak"), File(base.path + ".new"))
    fun shape(file: File): ArtifactShape = try {
        val a = Files.readAttributes(file.toPath(), BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
        when { !a.isRegularFile || a.isSymbolicLink -> ArtifactShape.UNSAFE
            a.size() == 0L -> ArtifactShape.EMPTY
            else -> ArtifactShape.FILE }
    } catch (_: NoSuchFileException) { ArtifactShape.ABSENT }
      catch (_: IOException) { ArtifactShape.UNREADABLE }
      catch (_: SecurityException) { ArtifactShape.UNREADABLE }
    fun inventory(base: File): RecordInventory {
        requireDirectory(base.parentFile)
        val parts = members(base).map(::shape)
        return RecordInventory(parts[0], parts[1], parts[2])
    }
    fun requireDirectory(directory: File) {
        val a = try { Files.readAttributes(directory.toPath(), BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS) }
        catch (_: Exception) { throw StoragePolicyFailure("store_directory_unavailable") }
        if (!a.isDirectory || a.isSymbolicLink) throw StoragePolicyFailure("store_directory_unsafe")
    }
    fun readable(base: File): File? = when (RecordOpeningPolicy.decide(inventory(base))) {
        OpenDecision.FRESH -> null
        OpenDecision.READ_EXISTING -> base
        OpenDecision.PENDING_WRITE -> throw StoragePolicyFailure("storage_pending_write")
        OpenDecision.BACKUP_REQUIRES_RECOVERY -> throw StoragePolicyFailure("storage_backup_requires_recovery")
        OpenDecision.CORRUPT -> throw StoragePolicyFailure("storage_malformed")
        OpenDecision.UNSAFE -> throw StoragePolicyFailure("storage_unsafe_path")
        OpenDecision.UNREADABLE -> throw StoragePolicyFailure("storage_unreadable")
    }
    fun requireWritable(base: File) { readable(base) }
    fun hasSiblingEvidence(directory: File, prefix: String): Boolean {
        requireDirectory(directory)
        return Files.newDirectoryStream(directory.toPath()).use { stream ->
            stream.any { it.fileName.toString().startsWith(prefix) }
        }
    }
    /** Only explicit deletion or a durable tombstone may authorize this operation.
     * Preflight all paths. Do not follow symlinks, recurse or remove unknown artifacts. */
    fun deleteVerified(base: File) {
        requireDirectory(base.parentFile)
        val parts = members(base)
        if (parts.any { shape(it) in setOf(ArtifactShape.UNREADABLE, ArtifactShape.UNSAFE) })
            throw StoragePolicyFailure("storage_delete_unsafe_or_unreadable")
        for (file in parts) {
            if (shape(file) != ArtifactShape.ABSENT) Files.delete(file.toPath())
        }
        if (parts.any { shape(it) != ArtifactShape.ABSENT }) throw StoragePolicyFailure("storage_delete_pending")
    }
}
