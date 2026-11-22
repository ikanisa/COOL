package rw.ikanisa.storagepolicy

import java.io.*
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

/** Versioned, deterministic, bounded snapshot framing. SHA-256 detects accidental changes;
 * it is NOT authentication, encryption or rollback protection. Production ports must supply
 * those controls. Decoding never defaults, migrates, deletes or creates any storage. */
object LifecycleSnapshotCodec {
    const val VERSION = 1
    const val MAX_BYTES = 1_048_576
    const val MAX_ITEMS = 4096
    private const val MAGIC = 0x53545032 // STP2, format version is separate
    private fun need(ok: Boolean, code: String) { if (!ok) throw StoragePolicyFailure(code) }
    private fun digest(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b)
    fun sha256(b: ByteArray): String = digest(b).joinToString("") { "%02x".format(it.toInt() and 255) }
    private class Writer(val out: DataOutputStream) {
        var items = 0
        fun text(s: String) {
            val enc = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            val buf = try { enc.encode(CharBuffer.wrap(s)) } catch (_: Exception) { throw StoragePolicyFailure("snapshot_invalid_utf8") }
            need(buf.remaining() in 1..1024, "snapshot_string_limit")
            val b = ByteArray(buf.remaining()); buf.get(b); out.writeInt(b.size); out.write(b)
        }
        fun count(n: Int) { items += n; need(n in 0..MAX_ITEMS && items <= MAX_ITEMS, "snapshot_item_limit"); out.writeInt(n) }
        fun strings(s: Set<String>) { count(s.size); s.sorted().forEach(::text) }
        fun binding(b: Binding) { text(b.product); text(b.owner); text(b.generation) }
        fun <T> optional(v: T?, write: (T) -> Unit) { out.writeByte(if (v == null) 0 else 1); if (v != null) write(v) }
        fun write(v: WriteIntent) { text(v.operationId); text(v.digest) }
        fun archive(v: ArchiveProof) { binding(v.binding); strings(v.artifactIds); text(v.receiptId) }
        fun replacement(v: ReplacementIntent) { text(v.operationId); binding(v.target); optional(v.archive, ::archive) }
    }
    private class Reader(val input: DataInputStream) {
        var items = 0
        fun text(): String {
            val n = input.readInt(); need(n in 1..1024 && n <= input.available(), "snapshot_string_limit")
            val b = ByteArray(n); input.readFully(b)
            return try { Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(b)).toString() }
            catch (_: Exception) { throw StoragePolicyFailure("snapshot_invalid_utf8") }
        }
        fun count(): Int { val n = input.readInt(); need(n in 0..MAX_ITEMS, "snapshot_item_limit"); items += n
            need(items <= MAX_ITEMS, "snapshot_item_limit"); return n }
        fun strings(): Set<String> {
            val a = List(count()) { text() }
            need(a.distinct().size == a.size, "snapshot_duplicate_item")
            need(a == a.sorted(), "snapshot_noncanonical_order"); return a.toSet()
        }
        fun binding() = Binding(text(), text(), text())
        fun <T> optional(read: () -> T): T? = when (input.readUnsignedByte()) {
            0 -> null; 1 -> read(); else -> throw StoragePolicyFailure("snapshot_invalid_presence")
        }
        fun write() = WriteIntent(text(), text())
        fun archive() = ArchiveProof(binding(), strings(), text())
        fun replacement() = ReplacementIntent(text(), binding(), optional(::archive))
        inline fun <reified T: Enum<T>> enum(): T { val v = text(); return enumValues<T>().find { it.name == v }
            ?: throw StoragePolicyFailure("snapshot_unknown_enum") }
    }
    fun encode(s: StorageState): ByteArray {
        s.validated()
        val stream = ByteArrayOutputStream()
        val w = Writer(DataOutputStream(stream))
        with(w) {
            binding(s.binding); out.writeLong(s.revision); text(s.phase.name); strings(s.evidence)
            optional(s.write, ::write)
            optional(s.deletion) { text(it.operationId); strings(it.artifacts); optional(it.receiptId, ::text) }
            strings(s.removed)
            count(s.tombstones.size); s.tombstones.forEach { binding(it.binding); text(it.operationId); text(it.receiptId) }
            count(s.archives.size); s.archives.forEach(::archive)
            optional(s.replacement, ::replacement); optional(s.fault) { text(it.name) }
            optional(s.lastWrite, ::write); optional(s.lastReplacement, ::replacement); strings(s.usedOperations)
        }
        val payload = stream.toByteArray(); need(payload.size <= MAX_BYTES - 44, "snapshot_size_limit")
        val framed = ByteArrayOutputStream()
        DataOutputStream(framed).use { it.writeInt(MAGIC); it.writeInt(VERSION); it.writeInt(payload.size); it.write(payload); it.write(digest(payload)) }
        return framed.toByteArray()
    }
    fun decode(bytes: ByteArray): StorageState {
        need(bytes.size in 44..MAX_BYTES, "snapshot_size_limit")
        try {
            val input = DataInputStream(ByteArrayInputStream(bytes))
            need(input.readInt() == MAGIC, "snapshot_bad_magic")
            need(input.readInt() == VERSION, "snapshot_unsupported_version")
            val n = input.readInt(); need(n >= 0 && n == bytes.size - 44, "snapshot_length_mismatch")
            val payload = ByteArray(n); input.readFully(payload)
            val hash = ByteArray(32); input.readFully(hash)
            need(MessageDigest.isEqual(hash, digest(payload)), "snapshot_checksum_mismatch")
            val r = Reader(DataInputStream(ByteArrayInputStream(payload)))
            val s = with(r) { StorageState(
                binding(), r.input.readLong(), enum<Phase>(), strings(), optional(::write),
                optional { DeleteIntent(text(), strings(), optional(::text)) }, strings(),
                List(count()) { Tombstone(binding(), text(), text()) }, List(count()) { archive() },
                optional(::replacement), optional { enum<StorageFault>() }, optional(::write),
                optional(::replacement), strings()) }
            need(r.input.available() == 0, "snapshot_trailing_fields")
            return s.validated()
        } catch (e: StoragePolicyFailure) { throw e }
          catch (_: EOFException) { throw StoragePolicyFailure("snapshot_truncated") }
          catch (_: IOException) { throw StoragePolicyFailure("snapshot_malformed") }
    }
}
