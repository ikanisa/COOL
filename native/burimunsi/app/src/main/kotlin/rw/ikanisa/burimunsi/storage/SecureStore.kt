package rw.ikanisa.burimunsi.storage

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Per-installation Keystore key, never derived from the four-digit passcode.
 * Operator files are separate from Collect's independent receiving queue.
 */
class SecureStore(context: Context, private val name: String) {
    // Distinct repository instances share files and one Keystore alias.
    // AtomicFile and first-use key creation require process-wide exclusion.
    companion object { private val processLock=Any() }
    private val file = AtomicFile(File(context.noBackupFilesDir, "buri-$name.v1"))
    private val alias = context.packageName + ".burimunsi.operator.v1"
    private val aad = ("burimunsi:" + name + ":1").toByteArray(Charsets.UTF_8)
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    fun read(): String? = synchronized(processLock) {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return@synchronized null
        val bytes = file.openRead().use { input ->
            val limit = 2_097_152
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) { val n = input.read(buffer); if (n < 0) break; check(out.size() + n <= limit); out.write(buffer, 0, n) }
            out.toByteArray()
        }
        check(bytes.size >= 29 && bytes[0].toInt() == 1) { "Protected store unavailable" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
        cipher.updateAAD(aad)
        cipher.doFinal(bytes.copyOfRange(13, bytes.size)).toString(Charsets.UTF_8)
    }
    fun write(value: String) = synchronized(processLock) {
        val body = value.toByteArray(Charsets.UTF_8)
        require(body.size <= 2_000_000)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key()); cipher.updateAAD(aad)
        check(cipher.iv.size == 12)
        val bytes = byteArrayOf(1) + cipher.iv + cipher.doFinal(body)
        var output: java.io.FileOutputStream? = null
        try { output = file.startWrite(); output.write(bytes); output.fd.sync(); file.finishWrite(output) }
        catch (e: Exception) { if (output != null) file.failWrite(output); throw e }
    }
    fun clear() = synchronized(processLock) { file.delete() }
}
