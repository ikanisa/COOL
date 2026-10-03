package app.cool.mobile.gateway

import org.json.JSONObject
import java.io.*
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.util.UUID

internal data class GatewayRecoveryEntry(val name: String, val size: Long, val sha256: String)
internal data class GatewayRecoveryArchive(val directory: File, val manifestSha256: String, val files: Long)
internal data class GatewayRecoveryResult(val directory: File, val files: Long, val keyValidated: Boolean, val requiresReEnrollment: Boolean = true)

/** Recovery may retain partial input, but must leave room for the active journal.
 * This is admission for new writes, not authority to delete retained evidence.
 * Space is observed before every bounded write; unrelated writers can still
 * exhaust the filesystem, which remains a failed recovery operation. */
internal object GatewayRecoveryStorage {
    const val MIN_AVAILABLE_BYTES = 32L * 1024 * 1024
    fun directory(file: File) {
        if (android.os.Build.VERSION.SDK_INT < 26) throw GatewayStateException("gateway_recovery_api_required")
        if (Files.isSymbolicLink(file.toPath()) || !Files.isDirectory(file.toPath(), LinkOption.NOFOLLOW_LINKS))
            throw GatewayStateException("gateway_recovery_invalid")
    }
    fun sync(dir: File) {
        directory(dir)
        val fd = android.system.Os.open(dir.path, android.system.OsConstants.O_RDONLY, 0)
        try { android.system.Os.fsync(fd) } finally { android.system.Os.close(fd) }
    }
    fun fresh(file: File) {
        directory(file.parentFile)
        if (Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)) throw GatewayStateException("gateway_recovery_invalid")
        Files.createDirectory(file.toPath())
        directory(file);sync(file.parentFile)
    }
    fun workspace(root: File, runId: String = UUID.randomUUID().toString()): File {
        directory(root)
        if (!validUuid(runId)) throw GatewayStateException("gateway_recovery_invalid")
        val parent = File(root, "collect_gateway_recovery")
        if (!Files.exists(parent.toPath(), LinkOption.NOFOLLOW_LINKS)) fresh(parent)
        directory(parent)
        return File(parent, runId).also { fresh(it) }
    }
    fun guarded(output: OutputStream, available: () -> Long): OutputStream = object : FilterOutputStream(output) {
        private fun admit(size: Int) {
            val remaining = available()
            if (size < 0 || remaining < MIN_AVAILABLE_BYTES || size.toLong() > remaining - MIN_AVAILABLE_BYTES)
                throw GatewayStateException("gateway_recovery_storage_full")
        }
        override fun write(value: Int) { admit(1);out.write(value) }
        override fun write(bytes: ByteArray, offset: Int, size: Int) {
            if (offset < 0 || size < 0 || offset > bytes.size - size) throw IndexOutOfBoundsException()
            if (size == 0) return
            admit(size);out.write(bytes, offset, size)
        }
    }
    fun output(file: File, available: () -> Long = { file.parentFile.usableSpace }): OutputStream {
        directory(file.parentFile)
        return guarded(Files.newOutputStream(file.toPath(), StandardOpenOption.CREATE_NEW,
            StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS), available)
    }
    fun syncFile(file: File) {
        directory(file.parentFile)
        if (Files.isSymbolicLink(file.toPath()) || !Files.isRegularFile(file.toPath(), LinkOption.NOFOLLOW_LINKS))
            throw GatewayStateException("gateway_recovery_invalid")
        FileOutputStream(file, true).use { it.fd.sync() };sync(file.parentFile)
    }
}

/** Raw, complete evidence snapshots, never a key backup or authority transfer.
 * The caller owns an unused directory and the out-of-band manifest digest.
 * Inventory pages hold <=8 names; file copying holds one 4 KiB buffer. There is
 * no lifetime object-count eviction. Total time/disk scales with evidence. */
internal object GatewayRecovery {
    const val INACTIVE = "RECOVERY_INACTIVE"
    private const val MANIFEST = "manifest.ndjson"
    private const val SEAL = "SEALED.json"
    private const val MAX_FILE = GatewayCrypto.MAX_BYTES + 29L
    private val names = Regex("[a-z0-9][a-z0-9-]{0,180}\\.bin(?:\\.bak|\\.new)?")
    private fun refuse(): Nothing = throw GatewayStateException("gateway_recovery_invalid")
    private fun cancelled(check: () -> Boolean) { if (check()) throw GatewayStateException("gateway_recovery_cancelled") }
    private fun safeDirectory(dir: File) {
        GatewayRecoveryStorage.directory(dir)
    }
    private fun fresh(dir: File) {
        GatewayRecoveryStorage.fresh(dir)
    }
    private fun regular(file: File) {
        if (Files.isSymbolicLink(file.toPath()) || !Files.isRegularFile(file.toPath(), LinkOption.NOFOLLOW_LINKS)) refuse()
    }
    private fun sync(dir: File) {
        GatewayRecoveryStorage.sync(dir)
    }
    private fun digest(file: File, max: Long = MAX_FILE): GatewayRecoveryEntry {
        regular(file); val md = MessageDigest.getInstance("SHA-256");var size = 0L
        FileInputStream(file).use { input -> val buffer = ByteArray(4096)
            while (true) { val n = input.read(buffer);if (n < 0) break;size += n;if (size > max) refuse();md.update(buffer,0,n) }
        }
        return GatewayRecoveryEntry(file.name,size,md.digest().joinToString("") { "%02x".format(it) })
    }
    internal fun anyFile(directory: File, predicate: (String) -> Boolean): Boolean {
        safeDirectory(directory)
        Files.newDirectoryStream(directory.toPath()).use { entries -> for(path in entries) if(predicate(path.fileName.toString())) return true }
        return false
    }
    internal fun eachFile(directory: File, cancelled: () -> Boolean, visit: (String) -> Unit) {
        safeDirectory(directory)
        Files.newDirectoryStream(directory.toPath()).use { entries -> for(path in entries) { cancelled(cancelled);regular(path.toFile());visit(path.fileName.toString()) } }
    }
    /** No AtomicFile reader is used: .bak/.new remain exact independent bytes. */
    fun inventory(directory: File, cancelled: () -> Boolean = { false }, page: (List<GatewayRecoveryEntry>) -> Unit): Long {
        safeDirectory(directory);var total=0L;val rows=ArrayList<GatewayRecoveryEntry>(8)
        Files.newDirectoryStream(directory.toPath()).use { entries -> for (path in entries) {
            cancelled(cancelled);val file=path.toFile();if (!names.matches(file.name)) refuse()
            rows.add(digest(file));total++;if (rows.size==8) { page(rows.toList());rows.clear() }
        } }
        if (rows.isNotEmpty()) page(rows.toList());return total
    }
    private fun copyExact(source: File, target: File, expected: GatewayRecoveryEntry) {
        regular(source)
        GatewayRecoveryStorage.output(target).use { output ->
            FileInputStream(source).use { input -> val buffer=ByteArray(4096);var total=0L
                while (true) { val n=input.read(buffer);if(n<0)break;total+=n;if(total>MAX_FILE)refuse();output.write(buffer,0,n) }
            }
        }
        FileOutputStream(target,true).use { it.fd.sync() };sync(target.parentFile)
        if (digest(target)!=expected || digest(source)!=expected) throw GatewayStateException("gateway_recovery_source_changed")
    }
    private fun text(file: File, value: String) {
        GatewayRecoveryStorage.output(file).use { it.write(value.toByteArray(Charsets.UTF_8)) }
        FileOutputStream(file,true).use { it.fd.sync() };sync(file.parentFile)
        if (file.readText()!=value) refuse()
    }
    fun export(source: File, destination: File, cancelled: () -> Boolean = { false }): GatewayRecoveryArchive {
        safeDirectory(source)
        if (destination.canonicalPath.startsWith(source.canonicalPath+File.separator)) refuse()
        fresh(destination);val objects=File(destination,"objects");fresh(objects)
        val manifest=File(destination,MANIFEST)
        var count=0L
        GatewayRecoveryStorage.output(manifest).use { stream ->
            fun line(value: JSONObject) { stream.write((value.toString()+"\n").toByteArray(Charsets.UTF_8)) }
            line(JSONObject().put("contract_version",1).put("archive_id",UUID.randomUUID().toString()).put("format","collect_gateway_ciphertext_v1")
                .put("storage_key_alias","collect.gateway.storage.v1").put("signing_key_included",false).put("activation_authority",false))
            count=inventory(source,cancelled) { page -> for(entry in page) {
                cancelled(cancelled);copyExact(File(source,entry.name),File(objects,entry.name),entry)
                line(JSONObject().put("name",entry.name).put("size",entry.size).put("sha256",entry.sha256))
            } }
        };GatewayRecoveryStorage.syncFile(manifest)
        // A second streaming source pass rejects changes/new/missing files.
        val checked=inventory(source,cancelled) { page -> for(entry in page) if(digest(File(objects,entry.name))!=entry) throw GatewayStateException("gateway_recovery_source_changed") }
        if (checked!=count) throw GatewayStateException("gateway_recovery_source_changed")
        val sha=digest(manifest,Long.MAX_VALUE).sha256
        text(File(destination,SEAL),JSONObject().put("contract_version",1).put("manifest_sha256",sha).put("files",count).put("complete",true).toString())
        return GatewayRecoveryArchive(destination,sha,count)
    }
    private fun line(input: InputStream): String? {
        val out=ByteArrayOutputStream();while(true) { val b=input.read();if(b<0) { if(out.size()!=0)refuse();return null };if(b==10)break
            if(out.size()>=1024 || b==0 || b==13)refuse();out.write(b) }
        val bytes=out.toByteArray();val value=String(bytes,Charsets.UTF_8);if(!value.toByteArray(Charsets.UTF_8).contentEquals(bytes))refuse();return value
    }
    private fun each(archive: File, expected: String, cancelled: () -> Boolean, visit: (GatewayRecoveryEntry) -> Unit): Long {
        safeDirectory(archive);safeDirectory(File(archive,"objects"))
        if(!expected.matches(Regex("[0-9a-f]{64}")) || digest(File(archive,MANIFEST),Long.MAX_VALUE).sha256!=expected)refuse()
        val sealFile=File(archive,SEAL);regular(sealFile);if(sealFile.length()>1024)refuse();val seal=JSONObject(sealFile.readText())
        requireKeys(seal,setOf("contract_version","manifest_sha256","files","complete"))
        if(strictInteger(seal,"contract_version")!=1L || strictString(seal,"manifest_sha256")!=expected || !strictBoolean(seal,"complete"))refuse()
        val wanted=strictInteger(seal,"files");if(wanted<0)refuse();var count=0L
        FileInputStream(File(archive,MANIFEST)).use { input ->
            val header=JSONObject(line(input)?:refuse());requireKeys(header,setOf("contract_version","archive_id","format","storage_key_alias","signing_key_included","activation_authority"))
            if(strictInteger(header,"contract_version")!=1L || strictString(header,"format")!="collect_gateway_ciphertext_v1" || strictString(header,"storage_key_alias")!="collect.gateway.storage.v1" || strictBoolean(header,"signing_key_included") || strictBoolean(header,"activation_authority"))refuse();requireUuid(header,"archive_id")
            while(true) { cancelled(cancelled);val row=line(input)?:break;val value=JSONObject(row);requireKeys(value,setOf("name","size","sha256"))
                val entry=GatewayRecoveryEntry(strictString(value,"name"),strictInteger(value,"size"),strictString(value,"sha256"))
                if(!names.matches(entry.name) || entry.size !in 0..MAX_FILE || !entry.sha256.matches(Regex("[0-9a-f]{64}")))refuse()
                if(digest(File(archive,"objects/${entry.name}"))!=entry)refuse();visit(entry);count++
            }
        }
        if(count!=wanted || inventory(File(archive,"objects"),cancelled) {}!=count)refuse();return count
    }
    /** Restore publication starts with a durable inactive marker. Historical
     * identity/enrollment stays only in original/view evidence. No key import,
     * default installation merge, resumption or network call exists here. */
    fun restore(archive: File, manifestSha256: String, destination: File, activeDirectory: File,
        cancelled: () -> Boolean = { false }, validate: (File,Long) -> Boolean): GatewayRecoveryResult {
        if(destination.canonicalFile==activeDirectory.canonicalFile || destination.canonicalPath.startsWith(activeDirectory.canonicalPath+File.separator) ||
            activeDirectory.canonicalPath.startsWith(destination.canonicalPath+File.separator) || destination.canonicalPath.startsWith(archive.canonicalPath+File.separator))refuse()
        fresh(destination)
        text(File(destination,INACTIVE),JSONObject().put("contract_version",1).put("inactive",true).put("manifest_sha256",manifestSha256).toString())
        val original=File(destination,"original");fresh(original);val view=File(destination,"view");fresh(view)
        text(File(view,INACTIVE),"inactive; historical evidence only\n")
        val count=each(archive,manifestSha256,cancelled) { entry ->
            copyExact(File(archive,"objects/${entry.name}"),File(original,entry.name),entry)
            copyExact(File(original,entry.name),File(view,entry.name),entry)
        }
        // Duplicate manifest names fail CREATE_NEW. Exact original readback is
        // independent of validation repairs, whose writes affect only view.
        each(archive,manifestSha256,cancelled) { if(digest(File(original,it.name))!=it)refuse() }
        cancelled(cancelled);val validated=validate(view,count)
        text(File(destination,"RESULT.json"),JSONObject().put("contract_version",1).put("manifest_sha256",manifestSha256).put("files",count)
            .put("key_validated",validated).put("inactive",true).put("requires_re_enrollment",true).toString())
        return GatewayRecoveryResult(destination,count,validated)
    }
}
