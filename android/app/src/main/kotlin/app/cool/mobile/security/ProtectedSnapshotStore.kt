package app.cool.mobile.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** Single-account cache under noBackupFilesDir. Read failure preserves bytes. */
class ProtectedSnapshotStore internal constructor(
    noBackupDirectory: File,
    purpose: String,
    private val keyProvider: ((String, Boolean) -> SecretKey)? = null,
) {
    constructor(context: Context, purpose: String = "snapshot") : this(context.noBackupFilesDir, purpose)
    init { require(purpose in setOf("snapshot", "auth", "payment_help")) }
    private val keyAlias = when (purpose) {
        "auth" -> "collect_auth_session_v1"
        "payment_help" -> "collect_payment_help_v1"
        else -> "collect_snapshot_v5"
    }
    private val directory = File(noBackupDirectory, when (purpose) {
        "auth" -> "collect_protected_auth_session"
        "payment_help" -> "collect_protected_payment_help"
        else -> "collect_protected_snapshot"
    })
    private val cipher = SnapshotCipher(::key)
    fun read(owner: String): String? = synchronized(lock) {
        SnapshotCipher.validateOwner(owner)
        val file = file(owner)
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return@synchronized null
        // Read bounded bytes even when a local file was tampered with.
        val bytes = file.openRead().use { stream ->
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                if (out.size() + count > SnapshotCipher.MAX_BYTES + 29) throw IllegalStateException("Snapshot limit exceeded")
                out.write(buffer, 0, count)
            }
            out.toByteArray()
        }
        cipher.decrypt(owner, bytes)
    }
    fun write(owner: String, value: String): Boolean = synchronized(lock) {
        SnapshotCipher.validateOwner(owner)
        val encrypted = cipher.encrypt(owner, value)
        check(directory.isDirectory || directory.mkdirs()) { "Protected storage unavailable" }
        val destination = file(owner)
        val stream = destination.startWrite()
        try {
            stream.write(encrypted)
            destination.finishWrite(stream)
        } catch (failure: Exception) {
            destination.failWrite(stream)
            throw failure
        }
        // Only after a durable replacement may an old account's recovery cache go.
        directory.listFiles()?.filter { it.name != destination.baseFile.name }
            ?.forEach { check(it.delete()) { "Old protected snapshot could not be cleared" } }
        true
    }
    fun clear(owner: String? = null): Boolean = synchronized(lock) {
        if (owner != null) {
            SnapshotCipher.validateOwner(owner)
            val destination = file(owner).baseFile
            for (candidate in listOf(destination, File(destination.path + ".bak"), File(destination.path + ".new"))) {
                check(!candidate.exists() || candidate.delete()) { "Protected cache could not be cleared" }
            }
            return@synchronized true
        }
        directory.listFiles()?.forEach { check(it.delete()) { "Protected cache could not be cleared" } }
        true
    }
    private fun file(owner: String): AtomicFile {
        val digest = MessageDigest.getInstance("SHA-256").digest(owner.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return AtomicFile(File(directory, "$digest.enc"))
    }
    private fun key(create: Boolean): SecretKey {
        keyProvider?.let { return it(keyAlias, create) }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        check(create) { "Protected cache key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    companion object { private val lock = Any() }
}
