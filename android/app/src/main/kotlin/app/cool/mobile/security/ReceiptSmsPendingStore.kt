package app.cool.mobile.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.system.Os
import android.system.ErrnoException
import android.system.OsConstants
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** Separate device-only encrypted journal; never replaces another account. */
class ReceiptSmsPendingStore(context: Context) {
    private val directory = File(context.noBackupFilesDir.canonicalFile, "collect_receipt_sms_pending_v1")
    private val cipher = ReceiptSmsPendingCipher(::key)
    private val journal = ReceiptSmsPendingJournal(object : ReceiptSmsPendingCustody {
        override fun read(owner: String): ByteArray? {
            val file = file(owner)
            if (!exists(file.baseFile, false) && !exists(File(file.baseFile.path + ".bak"), false)) return null
            val retained = file.openRead().use { stream ->
                val bytes = cipher.decrypt(owner, stream.readBytesBounded(ReceiptSmsPendingCodec.MAX_BYTES + 29))
                // A previous promotion may have failed to acknowledge its sync.
                // Reconstructing custody must re-establish durability before use.
                stream.fd.sync()
                bytes
            }
            syncDirectory(directory)
            syncDirectory(directory.parentFile!!)
            return retained
        }
        override fun write(owner: String, bytes: ByteArray) {
            ReceiptSmsPendingCodec.decode(owner, bytes)
            val directoryCreated = !exists(directory, true)
            check(!directoryCreated || directory.mkdir()) { "Receipt SMS recovery unavailable" }
            check(exists(directory, true)) { "Receipt SMS recovery unavailable" }
            val file = file(owner)
            if (!exists(file.baseFile, false)) check(entries().size < 64) { "Receipt SMS recovery capacity unavailable" }
            val encrypted = cipher.encrypt(owner, bytes)
            val stream = file.startWrite()
            var promotionAttempted = false
            try {
                stream.write(encrypted)
                // AtomicFile's own sync result is logged rather than thrown on some
                // Android versions. A claim must not acknowledge that ambiguity.
                stream.fd.sync()
                promotionAttempted = true
                file.finishWrite(stream)
                syncDirectory(directory)
                if (directoryCreated) syncDirectory(directory.parentFile!!)
                val retained = read(owner)
                check(retained != null && retained.contentEquals(bytes)) { "Receipt SMS recovery readback unavailable" }
            } catch (error: Exception) {
                // A promotion may already have retained the original request. Do
                // not roll it back or replace it after an uncertain completion.
                if (!promotionAttempted) {
                    try { file.failWrite(stream) } catch (cleanup: Exception) { error.addSuppressed(cleanup) }
                }
                throw error
            }
        }
    })
    private fun file(owner: String): AtomicFile {
        validateReceiptSmsUuid(owner)
        exists(directory, true)
        val name = MessageDigest.getInstance("SHA-256").digest(owner.toByteArray(Charsets.US_ASCII)).joinToString("") { "%02x".format(it.toInt() and 255) }
        val target = File(directory,"$name.enc")
        for (candidate in listOf(target,File(target.path + ".bak"),File(target.path + ".new"))) {
            exists(candidate, false)
        }
        return AtomicFile(target)
    }
    private fun exists(value: File, directory: Boolean): Boolean {
        val metadata = try { Os.lstat(value.path) } catch (error: ErrnoException) {
            if (error.errno == OsConstants.ENOENT) return false
            throw error
        }
        check((if (directory) OsConstants.S_ISDIR(metadata.st_mode) else OsConstants.S_ISREG(metadata.st_mode)) &&
            value.canonicalFile == value.absoluteFile && (directory || metadata.st_nlink == 1L)) { "Receipt SMS recovery unavailable" }
        return true
    }
    private fun entries(): Array<File> = checkNotNull(directory.listFiles()) { "Receipt SMS recovery unavailable" }
    private fun syncDirectory(value: File) {
        check(exists(value, true)) { "Receipt SMS recovery unavailable" }
        val before = Os.lstat(value.path)
        // O_CLOEXEC is public only from API 27; keep the API 24 no-follow path.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_CLOEXEC
        } else {
            OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW
        }
        val descriptor = Os.open(value.path, flags, 0)
        try {
            val opened = Os.fstat(descriptor)
            check(OsConstants.S_ISDIR(opened.st_mode) && opened.st_dev == before.st_dev && opened.st_ino == before.st_ino) { "Receipt SMS recovery unavailable" }
            Os.fsync(descriptor)
        } finally { Os.close(descriptor) }
    }
    private fun java.io.InputStream.readBytesBounded(maximum: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(1024)
        while(true) { val count = read(buffer); if(count < 0) break
            check(output.size() + count <= maximum) { "Receipt SMS recovery limit exceeded" }; output.write(buffer,0,count) }
        return output.toByteArray()
    }
    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(KEY_ALIAS)) {
            val retained = store.getKey(KEY_ALIAS, null)
            check(retained is SecretKey && retained.algorithm == KeyProperties.KEY_ALGORITHM_AES) { "Receipt SMS recovery key unavailable" }
            return retained
        }
        check(create && (!exists(directory, true) || entries().isEmpty())) { "Receipt SMS recovery key unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build()) }.generateKey()
    }
    fun read(owner: String,group: String): Map<String,Any> = journal.read(owner,group).wire()
    private fun request(owner: String,group: String,value: Any?): ReceiptSmsPendingRecord {
        val row=ReceiptSmsPendingRecord.fromWire(value)
        check(row.userId==owner && row.collectionId==group) { "Receipt SMS recovery identity mismatch" }
        return row
    }
    fun claim(owner: String,group: String,value: Any?,fence: Boolean = false): Map<String,Any> =
        journal.claim(request(owner,group,value),fence).wire()
    fun complete(owner: String,group: String,value: Any?,head: Any?): Map<String,Any> =
        journal.complete(request(owner,group,value),receiptSmsDecisionHead(head)).wire()
    fun supersede(owner: String,group: String,known: Any?,head: Any?): Map<String,Any> {
        val values=known as? List<*> ?: error("Receipt SMS recovery cohort unavailable")
        check(values.size in 1..32)
        return journal.supersede(owner,group,values.map { request(owner,group,it) },receiptSmsDecisionHead(head)).wire()
    }
    companion object { private const val KEY_ALIAS = "collect_receipt_sms_pending_v1" }
}
