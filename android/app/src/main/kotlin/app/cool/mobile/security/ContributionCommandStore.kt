package app.cool.mobile.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.channels.OverlappingFileLockException
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** Separate, device-only, multi-owner journal. Uncertain staging bytes are retained. */
class ContributionCommandStore(context: Context) {
    private val directory = File(context.noBackupFilesDir.canonicalFile, "collect_contribution_commands_v1")
    private val cipher = ContributionCommandCipher(::key)
    private val journal = ContributionCommandJournal(object : ContributionCommandCustody {
        override fun <T> exclusive(block: () -> T): T = locked(block)
        override fun load(partition: String): ContributionCommandSnapshot = loadSnapshot(partition)
        override fun persist(snapshot: ContributionCommandSnapshot) = persistSnapshot(snapshot)
    })
    fun read(partition: String): Map<String, Any?> = journal.read(partition)
    fun compareAndSet(partition: String, expected: Any?, payload: String): Map<String, Any?> {
        val revision = when (expected) { is Int -> expected.toLong(); is Long -> expected; else -> error("Revision required") }
        return journal.compareAndSet(partition, revision, payload)
    }
    private fun path(partition: String): File {
        ContributionCommandCipher.validatePartition(partition)
        return File(directory, "$partition.enc")
    }
    private fun metadata(file: File, isDirectory: Boolean = false): android.system.StructStat? {
        val value = try { Os.lstat(file.path) } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) return null
            throw error
        }
        check((if (isDirectory) OsConstants.S_ISDIR(value.st_mode) else OsConstants.S_ISREG(value.st_mode)) &&
            file.absoluteFile == file.canonicalFile && (isDirectory || value.st_nlink == 1L)) { "Contribution recovery unavailable" }
        return value
    }
    private fun ensureDirectory() {
        val created = metadata(directory, true) == null
        check(!created || directory.mkdir()) { "Contribution recovery unavailable" }
        check(metadata(directory, true) != null)
        if (created) syncDirectory(directory.parentFile!!)
    }
    private fun entries(): List<File> {
        val entries = checkNotNull(directory.listFiles()) { "Contribution recovery unavailable" }.toList()
        for (file in entries) {
            val value = checkNotNull(metadata(file))
            if (file.name == ".lock") check(value.st_size == 0L)
            else {
                // A crash or lost write acknowledgement must never be silently repaired.
                check(Regex("^[0-9a-f]{64}\\.enc$").matches(file.name)) { "Contribution recovery requires reconciliation" }
                check(value.st_size in 38..ContributionCommandCipher.MAX_CIPHERTEXT_BYTES.toLong())
            }
        }
        val retained = entries.filter { it.name != ".lock" }
        check(retained.size <= ContributionCommandCipher.MAX_PARTITIONS)
        check(retained.sumOf { checkNotNull(metadata(it)).st_size } <= ContributionCommandCipher.MAX_AGGREGATE_BYTES)
        return retained
    }
    private fun <T> locked(block: () -> T): T {
        check(processLock.tryLock(2, TimeUnit.SECONDS)) { "Contribution recovery busy" }
        try {
            ensureDirectory()
            val lockFile = File(directory, ".lock"); val before = metadata(lockFile)
            val descriptor = Os.open(lockFile.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_NOFOLLOW, 384)
            val opened = Os.fstat(descriptor)
            try {
                check(OsConstants.S_ISREG(opened.st_mode) && opened.st_nlink == 1L && opened.st_size == 0L &&
                    (before == null || (before.st_dev == opened.st_dev && before.st_ino == opened.st_ino)))
            } catch (error: Exception) { Os.close(descriptor); throw error }
            FileOutputStream(descriptor).use { stream ->
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
                var lock: java.nio.channels.FileLock? = null
                while (lock == null && System.nanoTime() < deadline) {
                    lock = try { stream.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
                    if (lock == null) Thread.sleep(10)
                }
                checkNotNull(lock) { "Contribution recovery busy" }.use {
                    val pinned = checkNotNull(metadata(lockFile))
                    check(pinned.st_dev == opened.st_dev && pinned.st_ino == opened.st_ino)
                    return block()
                }
            }
        } finally { processLock.unlock() }
    }
    private fun loadSnapshot(partition: String): ContributionCommandSnapshot {
        val retained = entries()
        // Missing keys alongside any retained ciphertext are an error, never an empty account.
        if (retained.isNotEmpty()) key(false)
        val file = path(partition); val before = metadata(file)
            ?: return ContributionCommandSnapshot(partition, 0, null)
        val descriptor = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        FileInputStream(descriptor).use { stream ->
            val opened = Os.fstat(descriptor)
            check(opened.st_dev == before.st_dev && opened.st_ino == before.st_ino && opened.st_nlink == 1L)
            val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
            while (true) {
                val count = stream.read(buffer); if (count < 0) break
                check(output.size() + count <= ContributionCommandCipher.MAX_CIPHERTEXT_BYTES)
                output.write(buffer, 0, count)
            }
            val snapshot = cipher.decrypt(partition, output.toByteArray())
            stream.fd.sync(); syncDirectory(directory); syncDirectory(directory.parentFile!!)
            return snapshot
        }
    }
    private fun persistSnapshot(snapshot: ContributionCommandSnapshot) {
        val retained = entries(); val target = path(snapshot.partitionId)
        val encrypted = cipher.encrypt(snapshot)
        check(retained.any { it == target } || retained.size < ContributionCommandCipher.MAX_PARTITIONS)
        check(retained.filter { it != target }.sumOf { checkNotNull(metadata(it)).st_size } + encrypted.size <= ContributionCommandCipher.MAX_AGGREGATE_BYTES)
        val staging = File(target.path + ".new")
        check(metadata(staging) == null)
        val descriptor = Os.open(staging.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
        FileOutputStream(descriptor).use { stream -> stream.write(encrypted); stream.fd.sync() }
        // No cleanup on failure: an unconfirmed promotion never grants a caller a dispatch permit.
        Os.rename(staging.path, target.path)
        syncDirectory(directory); syncDirectory(directory.parentFile!!)
        check(loadSnapshot(snapshot.partitionId) == snapshot) { "Contribution recovery commit unavailable" }
    }
    private fun syncDirectory(file: File) {
        val before = checkNotNull(metadata(file, true))
        val descriptor = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try {
            val opened = Os.fstat(descriptor)
            check(OsConstants.S_ISDIR(opened.st_mode) && opened.st_dev == before.st_dev && opened.st_ino == before.st_ino)
            Os.fsync(descriptor)
        } finally { Os.close(descriptor) }
    }
    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(KEY_ALIAS)) {
            val retained = store.getKey(KEY_ALIAS, null)
            check(retained is SecretKey && retained.algorithm == KeyProperties.KEY_ALGORITHM_AES)
            return retained
        }
        // The dedicated zero-byte lock is not encrypted history.
        check(create && entries().isEmpty()) { "Contribution recovery key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    companion object {
        private const val KEY_ALIAS = "collect_contribution_commands_v1"
        private val processLock = ReentrantLock()
    }
}
