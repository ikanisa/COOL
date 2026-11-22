package app.cool.mobile.receiver_sms

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Copy-on-write ciphertext only. The caller serializes operations with the queue lock.
 * No cache: failed persistence must never become an in-memory duplicate on retry.
 * Android supplies directory fsync; JVM tests supply FileChannel.force.
 */
internal class BuriQueueFile(
    private val file: File,
    private val syncDirectory: (File) -> Unit,
    private val checkpoint: (String) -> Unit = {},
) {
    private val staged get() = File(file.path + ".new")
    private fun checkPath() {
        check(file.parentFile?.isDirectory == true) { "Queue directory unavailable" }
        check(!Files.isSymbolicLink(file.toPath()) && !Files.isSymbolicLink(staged.toPath())) {
            "Queue path is not a regular private file"
        }
    }
    fun read(): String? {
        checkPath()
        if (!file.exists()) {
            // Do not silently discard or blindly promote interrupted first-write evidence.
            check(!staged.exists()) { "Interrupted first queue write requires recovery" }
            return null
        }
        check(file.isFile && file.length() in 1..MAX_BYTES.toLong()) { "Queue size unavailable" }
        // Resolve an uncertain previous directory sync before a read can justify
        // a duplicate result or advancing the inbox checkpoint.
        syncDirectory(file.parentFile!!)
        return file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            val out = java.io.ByteArrayOutputStream()
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                check(out.size() + count <= MAX_BYTES) { "Queue size unavailable" }
                out.write(buffer, 0, count)
            }
            val bytes = out.toByteArray()
            check(bytes.isNotEmpty()) { "Queue size unavailable" }
            val text = bytes.toString(Charsets.UTF_8)
            check(text.toByteArray(Charsets.UTF_8).contentEquals(bytes)) { "Invalid queue encoding" }
            text
        }
    }
    fun write(ciphertext: String): Boolean {
        checkPath()
        val bytes = ciphertext.toByteArray(Charsets.UTF_8)
        if (bytes.size !in 1..MAX_BYTES) return false
        var promoted = false
        try {
            checkpoint("before_write")
            FileOutputStream(staged).use { output ->
                output.write(bytes)
                checkpoint("before_file_sync")
                output.fd.sync()
            }
            checkpoint("before_rename")
            // Same directory; fail closed when atomic replacement is unsupported.
            Files.move(staged.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING)
            promoted = true
            checkpoint("before_directory_sync")
            syncDirectory(file.parentFile!!)
            return true
        } catch (_: Exception) {
            if (!promoted) {
                try { Files.deleteIfExists(staged.toPath()) } catch (_: IOException) { }
            }
            return false
        }
    }
    companion object { const val MAX_BYTES = 16 * 1024 * 1024 }
}
