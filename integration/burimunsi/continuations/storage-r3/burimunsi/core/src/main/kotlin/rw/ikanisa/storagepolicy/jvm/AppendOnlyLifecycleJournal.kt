package rw.ikanisa.storagepolicy.jvm

import rw.ikanisa.storagepolicy.*
import java.io.*
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.*
import java.nio.file.attribute.BasicFileAttributes
import java.util.concurrent.ConcurrentHashMap

/** Append-only NIO storage engine for a private, pre-created directory. Host-qualified;
 * Android filesystem/Keystore qualification remains separate. Default protection is
 * explicitly unprotected host compatibility; Android callers MUST supply AES-GCM.
 * Append-only completed snapshots and an immutable genesis anchor retain evidence. A
 * leftover pending entry blocks all ordinary reads/writes until explicitly inspected and
 * promoted. No fallback, overwrite, cleanup, auto-repair or history compaction exists.
 *
 * Uses JVM + cooperative OS locks and force(true). This does not certify filesystem/flash
 * power-loss durability, protect against privileged mutation or detect removal of a whole
 * valid history suffix; those require independent trusted anchors/platform qualification.
 * All participating writers must use this port; the private directory must not be exposed.
 * afterStep is fault-injection instrumentation, not an asynchronous callback contract. */
class AppendOnlyLifecycleJournal(
    private val directory: Path,
    private val virginEvidenceCheck: (Binding) -> Boolean,
    private val afterStep: (String) -> Unit = {},
    private val protection: JournalRecordProtection = UnprotectedHostRecords,
): LifecycleJournalPort {
    companion object {
        private val locks = ConcurrentHashMap<String, Any>()
        const val MAX_ENTRIES = 4096
        private val committedPattern = Regex("[0-9]{19}\\.snapshot")
        private val pendingPattern = Regex("[0-9]{19}\\.pending")
        private const val MAGIC = 0x4a524e31
    }
    init { require(protection.maxOverhead in 0..4096) { "Invalid protection size bound" } }
    private val root = directory.toAbsolutePath().normalize()
    private val lock = locks.computeIfAbsent(root.toString()) { Any() }
    private val held = ThreadLocal.withInitial { false }
    private fun need(ok: Boolean, code: String) { if (!ok) throw StoragePolicyFailure(code) }
    private fun assertHeld() = need(held.get(), "journal_lock_required")
    private fun attrs(p: Path): BasicFileAttributes? = try {
        Files.readAttributes(p, BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
    } catch (_: NoSuchFileException) { null }
    private fun checkRoot() {
        var p: Path? = root
        while (p != null) {
            val a = attrs(p); need(a != null && a.isDirectory && !a.isSymbolicLink, "journal_unsafe_directory")
            p = p.parent
        }
    }
    override fun <T> exclusive(block: () -> T): T = synchronized(lock) {
        need(!held.get(), "journal_reentrant_access")
        checkRoot()
        val path = root.resolve(".lock")
        val a = attrs(path); need(a == null || (a.isRegularFile && !a.isSymbolicLink), "journal_unsafe_lock")
        FileChannel.open(path, StandardOpenOption.CREATE, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS).use { channel ->
            channel.lock().use {
                held.set(true)
                try { block() } finally { held.set(false) }
            }
        }
    }
    private fun boundedRead(p: Path, max: Int): ByteArray {
        val a = attrs(p); need(a != null && a.isRegularFile && !a.isSymbolicLink, "journal_unsafe_record")
        need(a!!.size() in 1..max.toLong(), "journal_record_size")
        FileChannel.open(p, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS).use { c ->
            val out = ByteArrayOutputStream(); val b = ByteBuffer.allocate(8192)
            while (true) { b.clear(); val n = c.read(b); if (n == -1) break
                need(out.size() + n <= max, "journal_record_size"); out.write(b.array(), 0, n) }
            return out.toByteArray()
        }
    }
    private fun readProtected(path: Path, id: String, max: Int): ByteArray {
        val raw = boundedRead(path, max + protection.maxOverhead)
        val bytes = protection.open(id, raw)
        need(bytes.size in 1..max, "journal_plaintext_size")
        return bytes
    }
    private fun createProtected(path: Path, id: String, bytes: ByteArray, point: String) {
        val sealed = protection.seal(id, bytes)
        need(sealed.size <= bytes.size + protection.maxOverhead, "journal_ciphertext_size")
        createExact(path, sealed, point)
        need(readProtected(path, id, bytes.size).contentEquals(bytes), "journal_crypto_readback_failed")
    }
    private fun names(): List<String> {
        assertHeld(); checkRoot()
        val n = Files.newDirectoryStream(root).use { it.map { p -> p.fileName.toString() }.toList().sorted() }
        need(n.size <= MAX_ENTRIES + 4, "journal_history_limit")
        need(n.all { it == ".lock" || it == "genesis.anchor" || it == "migration.anchor" || committedPattern.matches(it) || pendingPattern.matches(it) }, "journal_unknown_evidence")
        n.forEach { val a = attrs(root.resolve(it)); need(a != null && a.isRegularFile && !a.isSymbolicLink, "journal_unsafe_record") }
        return n
    }
    private fun revisionName(revision: Long, suffix: String) = "%019d.%s".format(java.util.Locale.ROOT, revision, suffix)
    private fun frame(snapshot: ByteArray, previous: ByteArray?): ByteArray {
        val b = ByteArrayOutputStream()
        DataOutputStream(b).use {
            it.writeInt(MAGIC)
            it.write((previous?.let(LifecycleSnapshotCodec::sha256) ?: "0".repeat(64)).toByteArray(Charsets.US_ASCII))
            it.writeInt(snapshot.size); it.write(snapshot)
        }
        val raw = b.toByteArray()
        return raw + LifecycleSnapshotCodec.sha256(raw).toByteArray(Charsets.US_ASCII)
    }
    private fun unframe(p: Path, previous: ByteArray?, expectedRevision: Long): ByteArray {
        val bytes = readProtected(p, "snapshot:$expectedRevision", LifecycleSnapshotCodec.MAX_BYTES + 136)
        need(bytes.size >= 136, "journal_truncated")
        val body = bytes.copyOfRange(0, bytes.size - 64)
        need(bytes.copyOfRange(bytes.size - 64, bytes.size).contentEquals(LifecycleSnapshotCodec.sha256(body).toByteArray(Charsets.US_ASCII)), "journal_checksum_mismatch")
        val input = DataInputStream(ByteArrayInputStream(body))
        need(input.readInt() == MAGIC, "journal_bad_magic")
        val parent = ByteArray(64); input.readFully(parent)
        need(parent.contentEquals((previous?.let(LifecycleSnapshotCodec::sha256) ?: "0".repeat(64)).toByteArray(Charsets.US_ASCII)), "journal_parent_mismatch")
        val size = input.readInt(); need(size == input.available() && size in 44..LifecycleSnapshotCodec.MAX_BYTES, "journal_length_mismatch")
        val snapshot = ByteArray(size); input.readFully(snapshot)
        val state = LifecycleSnapshotCodec.decode(snapshot)
        protection.validateBinding(state.binding)
        need(state.revision == expectedRevision, "journal_revision_gap")
        if (previous != null) {
            val prior = LifecycleSnapshotCodec.decode(previous)
            need(state.binding.product == prior.binding.product && state.binding.owner == prior.binding.owner, "journal_scope_changed")
        }
        return snapshot
    }
    private fun verifyAnchor(snapshot: ByteArray, names: List<String>) {
        val anchor = readProtected(root.resolve("genesis.anchor"), "genesis", 129)
        val digest = LifecycleSnapshotCodec.sha256(snapshot)
        val expected = if ("migration.anchor" in names) {
            val marker = readProtected(root.resolve("migration.anchor"), "migration", LifecycleSnapshotCodec.MAX_BYTES)
            digest + ":" + LifecycleSnapshotCodec.sha256(marker)
        } else digest
        need(anchor.contentEquals(expected.toByteArray(Charsets.US_ASCII)), "journal_anchor_mismatch")
    }
    private fun history(n: List<String>): ByteArray? {
        val files = n.filter { committedPattern.matches(it) }
        if (files.isEmpty()) return null
        need("genesis.anchor" in n, "journal_anchor_missing")
        var previous: ByteArray? = null
        for ((index, name) in files.withIndex()) {
            need(name == revisionName(index.toLong(), "snapshot"), "journal_revision_gap")
            val state = unframe(root.resolve(name), previous, index.toLong())
            if (index == 0) verifyAnchor(state, n)
            previous = state
        }
        return previous
    }
    override fun read(): ByteArray? {
        val n = names()
        need(n.none { pendingPattern.matches(it) }, "journal_pending_requires_recovery")
        val last = history(n)
        if ("migration.anchor" in n) {
            readProtected(root.resolve("migration.anchor"), "migration", LifecycleSnapshotCodec.MAX_BYTES)
            need(last != null, "migration_bootstrap_incomplete")
        }
        need(last != null || "genesis.anchor" !in n, "journal_history_missing")
        return last
    }
    override fun verifyVirginScope(binding: Binding) {
        need(names().all { it == ".lock" }, "journal_not_virgin")
        need(virginEvidenceCheck(binding), "journal_sibling_evidence")
    }
    private fun syncDirectory() { FileChannel.open(root, StandardOpenOption.READ).use { it.force(true) } }
    private fun createExact(p: Path, bytes: ByteArray, point: String) {
        FileChannel.open(p, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS).use { c ->
            afterStep("${point}_created")
            val buf = ByteBuffer.wrap(bytes); while (buf.hasRemaining()) c.write(buf)
            afterStep("${point}_written"); c.force(true); afterStep("${point}_forced")
        }
        need(boundedRead(p, bytes.size).contentEquals(bytes), "journal_write_unverified")
    }
    override fun compareAndSet(expected: ByteArray?, replacement: ByteArray) {
        assertHeld(); val actual = read()
        need(if (expected == null) actual == null else actual != null && actual.contentEquals(expected), "journal_cas_conflict")
        val state = LifecycleSnapshotCodec.decode(replacement)
        protection.validateBinding(state.binding)
        val revision = actual?.let { LifecycleSnapshotCodec.decode(it).revision + 1 } ?: 0
        need(state.revision == revision && revision < MAX_ENTRIES, "journal_revision_or_capacity")
        if (actual == null) {
            verifyVirginScope(state.binding)
            protection.validateBinding(state.binding)
            createProtected(root.resolve("genesis.anchor"), "genesis", LifecycleSnapshotCodec.sha256(replacement).toByteArray(Charsets.US_ASCII), "anchor")
            syncDirectory(); afterStep("anchor_directory_forced")
        }
        val pending = root.resolve(revisionName(revision, "pending"))
        createProtected(pending, "snapshot:$revision", frame(replacement, actual), "pending")
        syncDirectory(); afterStep("pending_directory_forced")
        val target = root.resolve(revisionName(revision, "snapshot"))
        need(attrs(target) == null, "journal_destination_exists")
        Files.move(pending, target, StandardCopyOption.ATOMIC_MOVE)
        afterStep("published"); syncDirectory(); afterStep("published_directory_forced")
        need(read()!!.contentEquals(replacement), "journal_commit_unverified")
    }
    /** Validates and exposes the complete candidate without changing any file. A partial,
     * malformed or conflicting candidate remains untouched and continues to block access. */
    fun inspectPending(): StoredLifecycle = exclusive { pendingCandidate().let { StoredLifecycle(LifecycleSnapshotCodec.decode(it), LifecycleSnapshotCodec.sha256(it)) } }
    private fun pendingCandidate(): ByteArray {
        val n = names(); val list = n.filter { pendingPattern.matches(it) }
        need(list.size == 1, "journal_expected_one_pending")
        val last = history(n); val revision = last?.let { LifecycleSnapshotCodec.decode(it).revision + 1 } ?: 0
        need(list.single() == revisionName(revision, "pending"), "journal_pending_revision_mismatch")
        val candidate = unframe(root.resolve(list.single()), last, revision)
        need("genesis.anchor" in n, "journal_anchor_missing")
        if (last == null) verifyAnchor(candidate, n)
        return candidate
    }
    /** Promotes ONLY an explicitly approved, exact, validated pending candidate. Its bytes
     * survive in the new committed entry. Does not discard a pending record or roll back. */
    fun promotePending(expected: StoredLifecycle, explicit: Boolean): StoredLifecycle = exclusive {
        need(explicit, "explicit_pending_recovery_required")
        val n = names()
        if (n.none { pendingPattern.matches(it) }) {
            val last = read() ?: throw StoragePolicyFailure("journal_pending_missing")
            val current = StoredLifecycle(LifecycleSnapshotCodec.decode(last), LifecycleSnapshotCodec.sha256(last))
            need(current == expected, "journal_pending_identity_mismatch"); return@exclusive current
        }
        val candidate = pendingCandidate()
        need(StoredLifecycle(LifecycleSnapshotCodec.decode(candidate), LifecycleSnapshotCodec.sha256(candidate)) == expected, "journal_pending_identity_mismatch")
        val revision = expected.state.revision
        val target = root.resolve(revisionName(revision, "snapshot"))
        need(attrs(target) == null, "journal_destination_exists")
        Files.move(root.resolve(revisionName(revision, "pending")), target, StandardCopyOption.ATOMIC_MOVE)
        syncDirectory()
        need(read()!!.contentEquals(candidate), "journal_commit_unverified")
        expected
    }
    /** Source lock -> journal lock, always in that order. Caller must quiesce all old writers
     * and retain that handover fence after success. This method NEVER deletes legacy bytes.
     * Repeated exact bootstrap is idempotent; an advanced journal is not rewound. */
    fun adoptLegacy(plan: LegacyLifecycleMigration, source: LegacyLifecycleReadPort, explicit: Boolean): StoredLifecycle {
        need(explicit, "explicit_migration_required")
        need(protection.authenticated, "migration_authenticated_journal_required")
        return source.frozen { exclusive {
            protection.validateBinding(plan.binding)
            val marker = plan.marker()
            val initial = plan.initialBytes()
            val n = names()
            need(n.all { it in setOf(".lock", "migration.anchor", "genesis.anchor", revisionName(0, "pending"), revisionName(0, "snapshot")) }, "migration_destination_not_empty")
            val migration = root.resolve("migration.anchor")
            if ("migration.anchor" in n) {
                need(readProtected(migration, "migration", LifecycleSnapshotCodec.MAX_BYTES).contentEquals(marker), "migration_plan_conflict")
            } else {
                need(n.all { it == ".lock" }, "migration_unmarked_destination")
            }
            // Every retry re-reads original state + ciphertext identities, including
            // retries after a committed bootstrap. A changed source is never guessed.
            plan.verifyCurrent(source.capture(plan.binding))
            if ("migration.anchor" !in n) {
                createProtected(migration, "migration", marker, "migration")
                syncDirectory(); afterStep("migration_directory_forced")
            }
            val anchor = root.resolve("genesis.anchor")
            val digest = (LifecycleSnapshotCodec.sha256(initial) + ":" + LifecycleSnapshotCodec.sha256(marker)).toByteArray(Charsets.US_ASCII)
            if (attrs(anchor) == null) {
                createProtected(anchor, "genesis", digest, "anchor")
                syncDirectory(); afterStep("anchor_directory_forced")
            } else need(readProtected(anchor, "genesis", 129).contentEquals(digest), "migration_anchor_conflict")
            val pending = root.resolve(revisionName(0, "pending"))
            val committed = root.resolve(revisionName(0, "snapshot"))
            if (attrs(committed) == null) {
                if (attrs(pending) == null) {
                    createProtected(pending, "snapshot:0", frame(initial, null), "pending")
                    syncDirectory(); afterStep("pending_directory_forced")
                }
                // Partial pending evidence blocks migration. It is not overwritten.
                need(unframe(pending, null, 0).contentEquals(initial), "migration_pending_conflict")
                plan.verifyCurrent(source.capture(plan.binding))
                Files.move(pending, committed, StandardCopyOption.ATOMIC_MOVE)
                afterStep("published"); syncDirectory(); afterStep("published_directory_forced")
            }
            val current = read() ?: throw StoragePolicyFailure("migration_commit_unverified")
            need(current.contentEquals(initial), "migration_commit_unverified")
            plan.verifyCurrent(source.capture(plan.binding))
            StoredLifecycle(LifecycleSnapshotCodec.decode(current), LifecycleSnapshotCodec.sha256(current))
        } }
    }

}
