package app.cool.mobile.gateway

import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.UUID

/** Fixed-realm first-generation provenance only. These public, immutable records
 * contain no keys or enrollment authority. An entered generator with a missing
 * alias is an unknown outcome, never permission to generate another key. */
internal class GatewayKeyCreationCustody(private val directory: File, private val inactive: Boolean = false) {
    companion object {
        const val SIGNING_ALIAS = "collect.gateway.device.signing.v1"
        const val STORAGE_ALIAS = "collect.gateway.storage.v1"
        const val SIGNING = "key-generation-signing.bin"
        const val STORAGE = "key-generation-storage.bin"
        const val IDENTITY = "identity-publication-entered.bin"
        private const val REALM = "collect_gateway_v1"
        private const val MAX_BYTES = 2048L
        private val names = setOf(SIGNING, STORAGE, IDENTITY)
        fun recognizes(name: String): Boolean = names.any { name == it || name == "$it.bak" || name == "$it.new" }
    }

    private fun refuse(reason: String = "gateway_key_custody_invalid"): Nothing = throw GatewayStateException(reason)
    private fun active() {
        GatewayRecoveryStorage.directory(directory)
        if (inactive || Files.exists(File(directory, GatewayRecovery.INACTIVE).toPath(), LinkOption.NOFOLLOW_LINKS))
            refuse("gateway_recovery_inactive")
    }
    private fun base(name: String) = name.removeSuffix(".bak").removeSuffix(".new")
    private fun read(name: String): JSONObject? {
        val file = File(directory, name)
        if (!Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)) return null
        if (Files.isSymbolicLink(file.toPath()) || !Files.isRegularFile(file.toPath(), LinkOption.NOFOLLOW_LINKS) || file.length() !in 1..MAX_BYTES) refuse()
        val bytes = Files.newInputStream(file.toPath(), LinkOption.NOFOLLOW_LINKS).use { input ->
            val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(512)
            while (true) { val count = input.read(buffer); if (count < 0) break; if (out.size() + count > MAX_BYTES) refuse(); out.write(buffer, 0, count) }; out.toByteArray()
        }
        if (bytes.size.toLong() !in 1..MAX_BYTES) refuse()
        val text = String(bytes, Charsets.UTF_8)
        if (!text.toByteArray(Charsets.UTF_8).contentEquals(bytes)) refuse()
        return try { JSONObject(text).also { validate(base(name), it) } } catch (_: Exception) { refuse() }
    }
    private fun validate(name: String, value: JSONObject) {
        val common = setOf("contract_version", "key_realm", "state", "installation_id")
        if (name == IDENTITY) {
            requireKeys(value, common + "identity_sha256")
            if (strictString(value, "state") != "publication_entered" || !strictString(value, "identity_sha256").matches(Regex("[0-9a-f]{64}"))) refuse()
        } else {
            if (name !in setOf(SIGNING, STORAGE)) refuse()
            requireKeys(value, common + "alias")
            if (strictString(value, "state") != "generation_entered" || strictString(value, "alias") != if (name == SIGNING) SIGNING_ALIAS else STORAGE_ALIAS) refuse()
        }
        if (strictInteger(value, "contract_version") != 1L || strictString(value, "key_realm") != REALM) refuse()
        requireUuid(value, "installation_id")
    }
    /** Validate known public objects even when ciphertext remains opaque. A
     * recovered record never authorizes creation, activation or key import. */
    fun validateRetained() = synchronized(GatewayJournal.PROCESS_LOCK) {
        GatewayRecoveryStorage.directory(directory)
        for (name in names) for (suffix in listOf("", ".bak", ".new")) read(name + suffix)
        if (read(IDENTITY) != null && read(SIGNING) == null) refuse()
        val rows = names.mapNotNull { read(it) }
        if (rows.map { requireUuid(it, "installation_id") }.toSet().size > 1) refuse()
    }
    fun validateExisting() = synchronized(GatewayJournal.PROCESS_LOCK) {
        active(); validateRetained()
        if (names.any { Files.exists(File(directory, "$it.bak").toPath(), LinkOption.NOFOLLOW_LINKS) || Files.exists(File(directory, "$it.new").toPath(), LinkOption.NOFOLLOW_LINKS) })
            refuse("gateway_key_creation_incomplete")
    }
    private fun exactFreshNames(allowed: Set<String>) {
        // A positive streaming listing and regular-file checks replace nullable
        // listFiles inference. Unknown, opaque, directory and symlink history
        // cannot be treated as a new installation.
        GatewayRecoveryStorage.directory(directory)
        Files.newDirectoryStream(directory.toPath()).use { entries -> for (path in entries) {
            if (path.fileName.toString() !in allowed || Files.isSymbolicLink(path) || !Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS))
                refuse("gateway_key_history_present")
        } }
    }
    private fun publish(name: String, value: JSONObject) {
        validate(name, value)
        if (listOf("", ".bak", ".new").any { Files.exists(File(directory, name + it).toPath(), LinkOption.NOFOLLOW_LINKS) }) refuse("gateway_key_creation_incomplete")
        val file = AtomicFile(File(directory, name))
        var stream: java.io.FileOutputStream? = null
        try {
            stream = file.startWrite(); stream.write(value.toString().toByteArray(Charsets.UTF_8)); stream.fd.sync()
            file.finishWrite(stream); stream = null
            GatewayRecoveryStorage.sync(directory)
            if (!archiveJsonEqual(read(name), value)) refuse()
        } catch (error: Exception) {
            if (stream != null) file.failWrite(stream)
            throw GatewayStateException("gateway_key_creation_incomplete")
        }
    }
    fun enterSigning(storageAliasPresent: Boolean) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateExisting()
        if (read(SIGNING) != null) refuse("gateway_identity_unavailable")
        if (storageAliasPresent) refuse("gateway_key_history_present")
        exactFreshNames(emptySet())
        publish(SIGNING, JSONObject().put("contract_version", 1).put("key_realm", REALM).put("state", "generation_entered")
            .put("installation_id", UUID.randomUUID().toString()).put("alias", SIGNING_ALIAS))
    }
    fun enterStorage(signingAliasPresent: Boolean) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateExisting()
        if (read(STORAGE) != null) refuse("gateway_storage_key_unavailable")
        val signing = read(SIGNING)
        if (signing == null) {
            if (signingAliasPresent) refuse("gateway_key_history_present")
            exactFreshNames(emptySet())
        } else {
            if (!signingAliasPresent) refuse("gateway_identity_unavailable")
            exactFreshNames(setOf(SIGNING, IDENTITY))
        }
        publish(STORAGE, JSONObject().put("contract_version", 1).put("key_realm", REALM).put("state", "generation_entered")
            .put("installation_id", signing?.getString("installation_id") ?: UUID.randomUUID().toString()).put("alias", STORAGE_ALIAS))
    }
    fun identityInstallationId(): String = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateExisting()
        if (read(IDENTITY) != null) refuse("gateway_identity_unavailable")
        exactFreshNames(setOf(SIGNING, STORAGE))
        requireUuid(read(SIGNING) ?: refuse("gateway_key_history_present"), "installation_id")
    }
    fun enterIdentity(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        if (requireUuid(value, "installation_id") != identityInstallationId()) refuse()
        publish(IDENTITY, JSONObject().put("contract_version", 1).put("key_realm", REALM).put("state", "publication_entered")
            .put("installation_id", value.getString("installation_id")).put("identity_sha256", sha256(retentionCanonical(value))))
    }
    fun verifyIdentity(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateExisting(); verifyRetainedIdentity(value)
    }
    fun verifyRetainedIdentity(value: JSONObject) = synchronized(GatewayJournal.PROCESS_LOCK) {
        validateRetained()
        val signing = read(SIGNING)
        val published = read(IDENTITY)
        if (signing != null && (published == null || requireUuid(signing, "installation_id") != requireUuid(value, "installation_id"))) refuse()
        if (published != null && (requireUuid(published, "installation_id") != requireUuid(value, "installation_id") ||
                strictString(published, "identity_sha256") != sha256(retentionCanonical(value)))) refuse("gateway_identity_changed")
    }
}
