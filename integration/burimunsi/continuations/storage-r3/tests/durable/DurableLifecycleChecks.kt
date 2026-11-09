package durablechecks

import rw.ikanisa.storagepolicy.*
import rw.ikanisa.storagepolicy.jvm.AppendOnlyLifecycleJournal
import java.io.*
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger

private val names = mutableListOf<String>()
private fun test(name: String, body: () -> Unit) { body(); check(name !in names); names += name }
private fun reject(code: String? = null, body: () -> Unit) {
    val e = runCatching(body).exceptionOrNull() ?: error("expected rejection $code")
    if (code != null) check(e is StoragePolicyFailure && e.code == code) { "expected $code, got $e" }
}
private val owner = Binding("burimunsi", "owner-1", "generation-1")
private val hash = "a".repeat(64)
private fun token(s: StorageState, id: String) = EffectToken(s.binding, s.revision, id)
private fun phases(): List<StorageState> {
    val a = StorageState(owner, evidence = setOf("ledger", "originals", "wrap"))
    val w = StorageLifecyclePolicy.beginWrite(a, "write", hash)
    val c = StorageLifecyclePolicy.confirmWrite(w, token(w, "write"), hash, "new-record")
    val d = StorageLifecyclePolicy.beginDeletion(c, "delete", true)
    val r = StorageLifecyclePolicy.acceptDeletionReceipt(d, token(d, "delete"), "receipt")
    var x = r
    val all = mutableListOf(a,w,c,d,r)
    while (StorageLifecyclePolicy.nextCleanup(x) != null) {
        x = StorageLifecyclePolicy.confirmArtifactAbsent(x, token(x, "delete"), StorageLifecyclePolicy.nextCleanup(x)!!); all += x
    }
    x = StorageLifecyclePolicy.finishCleanup(x, token(x, "delete")); all += x
    x = StorageLifecyclePolicy.beginReplacement(x, "replace", owner.copy(generation="generation-2"), true); all += x
    x = StorageLifecyclePolicy.confirmReplacement(x, token(x,"replace"), x.replacement!!.target, setOf("new-ledger")); all += x
    return all
}
private class MemoryJournal: LifecycleJournalPort {
    var bytes: ByteArray? = null
    var cut: String? = null
    var virgin = true
    var lockHeld = false
    var commits = 0
    override fun <T> exclusive(block: () -> T): T = synchronized(this) {
        check(!lockHeld); lockHeld = true
        try { block() } finally { lockHeld = false }
    }
    override fun read(): ByteArray? { check(lockHeld); return bytes?.copyOf() }
    override fun verifyVirginScope(binding: Binding) { check(lockHeld); if (!virgin) throw StoragePolicyFailure("journal_sibling_evidence") }
    override fun compareAndSet(expected: ByteArray?, replacement: ByteArray) {
        check(lockHeld)
        check(if (expected == null) bytes == null else bytes?.contentEquals(expected) == true)
        when(cut) {
            "before" -> throw IOException("before write")
            "silent" -> return
        }
        bytes = replacement.copyOf(); commits++
        when(cut) {
            "after" -> throw IOException("ack lost")
            "corrupt" -> bytes!![bytes!!.lastIndex] = (bytes!!.last().toInt() xor 1).toByte()
        }
    }
}
private class Artifacts(ids: Set<String>): CleanupArtifactPort {
    val present = ids.toMutableSet()
    var mode = "ok"
    var removes = 0
    override fun observe(binding: Binding, artifactId: String): ArtifactObservation = when (mode) {
        "unreadable" -> ArtifactObservation.UNREADABLE
        "unsafe" -> ArtifactObservation.UNSAFE
        else -> if (artifactId in present) ArtifactObservation.PRESENT else ArtifactObservation.ABSENT
    }
    override fun remove(binding: Binding, artifactId: String) {
        removes++
        if (mode == "fail-before") throw IOException("unlink failed")
        if (mode != "silent") present.remove(artifactId)
        if (mode == "fail-after") throw IOException("unlink acknowledgment lost")
    }
}
private fun seeded(port: LifecycleJournalPort): Pair<DurableStorageCoordinator, StoredLifecycle> {
    val c = DurableStorageCoordinator(port)
    var s = c.provision(owner, true)
    for (id in listOf("ledger","originals","wrap")) {
        s = c.apply(s, LifecycleCommand.BeginWrite("write-$id",hash))
        s = c.apply(s, LifecycleCommand.ConfirmWrite("write-$id",hash,id))
    }
    return c to s
}
private fun ready(c: DurableStorageCoordinator, s: StoredLifecycle): StoredLifecycle {
    val d = c.apply(s,LifecycleCommand.BeginDeletion("delete",true))
    return c.apply(d,LifecycleCommand.AcceptDeletionReceipt("delete","receipt"))
}
private fun rechecksum(b: ByteArray): ByteArray {
    val c = b.copyOf(); val h = MessageDigest.getInstance("SHA-256").digest(c.copyOfRange(12,c.size-32))
    h.copyInto(c,c.size-32); return c
}
private fun withTemp(body: (Path) -> Unit) {
    val p = Files.createTempDirectory("storage-durable-fixture-")
    try { body(p) } finally { p.toFile().deleteRecursively() } // only this synthetic test directory
}
private fun treeBytes(root: Path): Map<String,String> = Files.walk(root).use { stream ->
    stream.filter { Files.isRegularFile(it, java.nio.file.LinkOption.NOFOLLOW_LINKS) }
        .toList().associate { root.relativize(it).toString() to LifecycleSnapshotCodec.sha256(Files.readAllBytes(it)) }
}

fun main(args: Array<String>) {
    if (args.firstOrNull() in setOf("seed", "status", "inspect", "promote", "race")) {
        val journal = AppendOnlyLifecycleJournal(Path.of(args[1]), { true })
        val c = DurableStorageCoordinator(journal)
        try {
            val value = when(args[0]) {
                "seed" -> seeded(journal).second
                "status" -> c.load(owner)
                "inspect" -> journal.inspectPending()
                "promote" -> {
                    val pending = journal.inspectPending()
                    check(pending.snapshotSha256 == args[2]); journal.promotePending(pending, true)
                }
                else -> {
                    val current = c.load(owner)
                    if(current.snapshotSha256 != args[3]) throw StoragePolicyFailure("lifecycle_stale_checkpoint")
                    c.apply(current, LifecycleCommand.BeginWrite(args[2], hash))
                }
            }
            println("{\"status\":\"ok\",\"revision\":${value.state.revision},\"phase\":\"${value.state.phase}\",\"sha256\":\"${value.snapshotSha256}\"}")
        } catch(e: StoragePolicyFailure) {
            println("{\"status\":\"rejected\",\"code\":\"${e.code}\"}")
            kotlin.system.exitProcess(3)
        }
        return
    }
    // The Python harness starts a separate JVM and deliberately halts at one persistence boundary.
    if (args.firstOrNull() == "child") {
        val root = Path.of(args[1]); val cut = args[2]
        val journal = AppendOnlyLifecycleJournal(root, { true }, { if(it == cut) Runtime.getRuntime().halt(73) })
        val c = DurableStorageCoordinator(journal)
        val s = c.load(owner); c.apply(s, LifecycleCommand.BeginWrite("process-write",hash))
        error("halt point not reached")
    }
    for ((index,s) in phases().withIndex()) {
        test("codec-roundtrip-phase-$index-${s.phase}") { check(LifecycleSnapshotCodec.decode(LifecycleSnapshotCodec.encode(s)) == s) }
    }
    test("codec-deterministic-set-order-and-unicode") {
        val a = StorageState(owner.copy(owner="é-munyamuryango"), evidence=linkedSetOf("z","é","a"))
        val b = a.copy(evidence=linkedSetOf("a","z","é"))
        check(LifecycleSnapshotCodec.encode(a).contentEquals(LifecycleSnapshotCodec.encode(b)))
    }
    val bytes = LifecycleSnapshotCodec.encode(phases()[1])
    test("codec-every-truncated-prefix-rejected") { for (n in 0 until bytes.size) reject { LifecycleSnapshotCodec.decode(bytes.copyOf(n)) } }
    test("codec-every-single-byte-change-rejected") { for (i in bytes.indices) {
        val b = bytes.copyOf(); b[i] = (b[i].toInt() xor 1).toByte(); reject { LifecycleSnapshotCodec.decode(b) }
    } }
    test("codec-unsupported-version") { val b = bytes.copyOf(); ByteBuffer.wrap(b).putInt(4,9)
        reject("snapshot_unsupported_version") { LifecycleSnapshotCodec.decode(b) } }
    test("codec-rejects-extra-envelope-bytes") { reject("snapshot_length_mismatch") { LifecycleSnapshotCodec.decode(bytes+byteArrayOf(0)) } }
    test("codec-checksum-not-authentication-semantic-validation") {
        val b = bytes.copyOf(); val offset = 12 + listOf(owner.product,owner.owner,owner.generation).sumOf { 4+it.toByteArray().size }
        ByteBuffer.wrap(b).putLong(offset,-1)
        reject("invalid_revision") { LifecycleSnapshotCodec.decode(rechecksum(b)) }
    }
    test("codec-unknown-enum") {
        val b = bytes.copyOf(); val i = b.toString(Charsets.ISO_8859_1).indexOf("WRITE_PENDING"); b[i] = 'X'.code.toByte()
        reject("snapshot_unknown_enum") { LifecycleSnapshotCodec.decode(rechecksum(b)) }
    }
    test("codec-invalid-utf8") { val b = bytes.copyOf(); b[16] = 0xff.toByte()
        reject("snapshot_invalid_utf8") { LifecycleSnapshotCodec.decode(rechecksum(b)) } }
    test("codec-bounded-string-read") { val b = bytes.copyOf(); ByteBuffer.wrap(b).putInt(12,Int.MAX_VALUE)
        reject("snapshot_string_limit") { LifecycleSnapshotCodec.decode(rechecksum(b)) } }
    test("codec-unpaired-surrogate-write") {
        reject("snapshot_invalid_utf8") { LifecycleSnapshotCodec.encode(StorageState(owner.copy(owner="x\ud800"))) }
    }
    test("codec-global-item-budget") { reject("snapshot_item_limit") {
        LifecycleSnapshotCodec.encode(StorageState(owner, evidence=(1..4097).map { "a$it" }.toSet())) } }
    test("codec-max-envelope-budget") { reject("snapshot_size_limit") { LifecycleSnapshotCodec.decode(ByteArray(LifecycleSnapshotCodec.MAX_BYTES+1)) } }
    test("codec-last-write-must-be-registered") { reject("invalid_last_write") {
        LifecycleSnapshotCodec.encode(StorageState(owner,lastWrite=WriteIntent("not-used",hash))) } }
    test("codec-rejects-cross-owner-retirement-proof") { reject("invalid_tombstone_scope") {
        LifecycleSnapshotCodec.encode(StorageState(owner,tombstones=listOf(Tombstone(owner.copy(owner="other"),"op","receipt")),usedOperations=setOf("op"))) } }
    test("codec-active-tombstone-forbidden") { reject("active_generation_tombstoned") {
        LifecycleSnapshotCodec.encode(StorageState(owner,tombstones=listOf(Tombstone(owner,"op","receipt")),usedOperations=setOf("op"))) } }
    test("load-missing-never-provisions") { val p=MemoryJournal(); reject("lifecycle_missing") { DurableStorageCoordinator(p).load(owner) }; check(p.bytes==null) }
    test("provision-is-explicit-and-virgin") {
        val p=MemoryJournal(); val c=DurableStorageCoordinator(p)
        reject("explicit_provisioning_required") { c.provision(owner,false) }
        p.virgin=false; reject("journal_sibling_evidence") { c.provision(owner,true) }; check(p.bytes==null)
    }
    test("provision-never-replaces-existing") { val p=MemoryJournal(); val (c,s)=seeded(p)
        reject("lifecycle_already_exists") { c.provision(owner,true) }; check(c.load(owner)==s) }
    for (kind in listOf("before","after","silent","corrupt")) test("failed-journal-write-$kind-blocks-progress") {
        val p=MemoryJournal(); val (c,s)=seeded(p); p.cut=kind
        reject { c.apply(s,LifecycleCommand.BeginDeletion("delete",true)) }
        check(p.commits >= 7)
        if(kind in listOf("before","silent")) check(c.load(owner)==s)
        if(kind=="after") check(c.load(owner).state.phase==Phase.DELETE_REQUESTED)
        if(kind=="corrupt") reject("snapshot_checksum_mismatch") { c.load(owner) }
    }
    test("cleanup-forbidden-before-receipt") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val d=c.apply(s,LifecycleCommand.BeginDeletion("delete",true)); val a=Artifacts(d.state.evidence)
        reject("cleanup_not_authorized") { c.cleanupOne(d,a) }; check(a.removes==0 && a.present==d.state.evidence)
    }
    for (kind in listOf("fail-before","fail-after","silent","unreadable","unsafe")) test("cleanup-$kind-retains-manifest-and-receipt") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val d=ready(c,s); val a=Artifacts(d.state.evidence); a.mode=kind
        reject { c.cleanupOne(d,a) }; check(c.load(owner)==d)
        a.mode="ok"; val recovered=c.cleanupOne(c.load(owner),a)
        check(recovered.state.removed.size==1 && recovered.state.deletion==d.state.deletion)
    }
    for (kind in listOf("before","after","silent")) test("cleanup-state-commit-$kind-recovers-same-artifact") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val d=ready(c,s); val a=Artifacts(d.state.evidence)
        p.cut=kind; reject { c.cleanupOne(d,a) }; check(a.removes==1)
        p.cut=null; val reopened=DurableStorageCoordinator(p); val loaded=reopened.load(owner)
        val next=reopened.cleanupOne(loaded,a)
        if(kind!="after") check(a.removes==1 && next.state.removed.size==1)
        else check(a.removes==2 && next.state.removed.size==2)
    }
    test("repeated-receipt-idempotent-conflicting-receipt-refused") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val d=ready(c,s); val n=p.commits
        check(c.apply(d,LifecycleCommand.AcceptDeletionReceipt("delete","receipt"))==d && p.commits==n)
        reject("deletion_receipt_conflict") { c.apply(d,LifecycleCommand.AcceptDeletionReceipt("delete","different")) }
    }
    test("full-cleanup-tombstone-survives-reopen-and-repetition") {
        val p=MemoryJournal(); val (c,s)=seeded(p); var d=ready(c,s); val a=Artifacts(d.state.evidence)
        repeat(4) { d=DurableStorageCoordinator(p).cleanupOne(d,a) }
        check(d.state.phase==Phase.TOMBSTONED && d.state.tombstones.size==1 && a.present.isEmpty())
        val n=p.commits; check(c.cleanupOne(d,a)==d && p.commits==n)
        reject("write_blocked") { c.apply(d,LifecycleCommand.BeginWrite("new",hash)) }
    }
    test("stale-checkpoint-after-concurrent-transition-has-no-effect") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val d=ready(c,s); val a=Artifacts(d.state.evidence)
        c.apply(d,LifecycleCommand.Failure(StorageFault.NO_SPACE))
        reject("lifecycle_stale_checkpoint") { c.cleanupOne(d,a) }; check(a.removes==0)
    }
    test("owner-product-and-generation-must-match-load") {
        val p=MemoryJournal(); val (c,_)=seeded(p)
        for(b in listOf(owner.copy(owner="other"),owner.copy(product="mmoney"),owner.copy(generation="old")))
            reject("lifecycle_binding_mismatch") { c.load(b) }
    }
    test("health-write-does-not-clear-unresolved-command") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val w=c.apply(s,LifecycleCommand.BeginWrite("pending",hash))
        val f=c.apply(w,LifecycleCommand.Failure(StorageFault.NO_SPACE))
        reject("outcome_unresolved") { c.apply(f,LifecycleCommand.ConfirmHealthWrite) }
    }
    test("health-write-clears-only-transient-error-after-readback") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val f=c.apply(s,LifecycleCommand.Failure(StorageFault.NO_SPACE))
        p.cut="silent"; reject("lifecycle_commit_unverified") { c.apply(f,LifecycleCommand.ConfirmHealthWrite) }
        check(c.load(owner)==f); p.cut=null; check(c.apply(f,LifecycleCommand.ConfirmHealthWrite).state.fault==null)
    }
    test("archive-verification-checks-content-not-only-ids") {
        val s=StorageState(owner,evidence=setOf("ledger"),fault=StorageFault.MALFORMED)
        val content=ArchivedArtifact("ledger",3,LifecycleSnapshotCodec.sha256(byteArrayOf(1,2,3)))
        val manifest=EvidenceArchiveManifest(owner,"archive-receipt",listOf(content))
        val good=object: EvidenceArchiveReadPort { override fun inspect(b:Binding,r:String,id:String)=content }
        check(VerifiedEvidenceArchive.verify(manifest,s,good).proof.artifactIds==s.evidence)
        val bad=object: EvidenceArchiveReadPort { override fun inspect(b:Binding,r:String,id:String)=content.copy(sha256=hash) }
        reject("archive_content_mismatch") { VerifiedEvidenceArchive.verify(manifest,s,bad) }
        reject("archive_duplicate_artifact") { VerifiedEvidenceArchive.verify(manifest.copy(artifacts=listOf(content,content)),s,good) }
        reject("archive_binding_mismatch") { VerifiedEvidenceArchive.verify(manifest.copy(binding=owner.copy(owner="other")),s,good) }
        reject("archive_inventory_mismatch") { VerifiedEvidenceArchive.verify(manifest.copy(artifacts=emptyList()),s,good) }
    }
    for (cut in listOf("effect-before","effect-after","state-before","state-after","silent-state","none")) test("replacement-$cut-preserves-intent-and-old-evidence") {
        val p=MemoryJournal(); val (c,s)=seeded(p); val f=c.apply(s,LifecycleCommand.Failure(StorageFault.MALFORMED))
        val manifest=EvidenceArchiveManifest(owner,"archive",f.state.evidence.map { ArchivedArtifact(it,3,hash) })
        val archive=VerifiedEvidenceArchive.verify(manifest,f.state,object: EvidenceArchiveReadPort {
            override fun inspect(b:Binding,r:String,id:String)=manifest.artifacts.single { it.id==id } })
        val pending=c.apply(f,LifecycleCommand.BeginReplacement("replace",owner.copy(generation="g2"),true,archive))
        var observed:ReplacementObservation?=null; var creates=0; var fail=cut
        val artifacts=object: ReplacementArtifactPort {
            override fun observe(i:ReplacementIntent)=observed
            override fun createOrResume(i:ReplacementIntent):ReplacementObservation {
                creates++; check(cut.isNotEmpty())
                if(fail=="effect-before") throw IOException("before create")
                observed=ReplacementObservation(i.operationId,i.target,setOf("new-ledger"))
                if(fail=="effect-after") throw IOException("after create")
                return observed!!
            }
        }
        p.cut=when(cut) { "state-before"->"before"; "state-after"->"after"; "silent-state"->"silent"; else->null }
        if(cut!="none") reject { c.resumeReplacement(pending,artifacts) } else c.resumeReplacement(pending,artifacts)
        fail="none"; p.cut=null
        val stored=LifecycleSnapshotCodec.decode(p.bytes!!)
        val done=if(stored.phase==Phase.REPLACEMENT_PENDING) c.resumeReplacement(c.load(owner),artifacts) else c.load(owner.copy(generation="g2"))
        check(done.state.phase==Phase.ACTIVE && done.state.archives.single()==archive.proof)
        check(creates==if(cut=="effect-before") 2 else 1)
        check(c.apply(done,LifecycleCommand.BeginReplacement("replace",owner.copy(generation="g2"),true,archive))==done)
        reject("lifecycle_binding_mismatch") { c.load(owner) }
    }
    test("replacement-rejects-unverified-create") {
        val p=MemoryJournal(); val (c,s)=seeded(p); var d=ready(c,s); val a=Artifacts(d.state.evidence)
        repeat(4){ d=c.cleanupOne(d,a) }
        val intent=c.apply(d,LifecycleCommand.BeginReplacement("replace",owner.copy(generation="g2"),true))
        val bad=object: ReplacementArtifactPort {
            override fun observe(i:ReplacementIntent):ReplacementObservation?=null
            override fun createOrResume(i:ReplacementIntent)=ReplacementObservation(i.operationId,i.target,setOf("new")) }
        reject("replacement_creation_unverified") { c.resumeReplacement(intent,bad) }; check(c.load(owner)==intent)
    }
    for (step in listOf("pending_created","pending_written","pending_forced","pending_directory_forced","published","published_directory_forced")) test("filesystem-interruption-$step-preserves-history") { withTemp { root ->
        var cut:String?=null
        val p=AppendOnlyLifecycleJournal(root,{true},{ if(it==cut) throw IOException("synthetic cut") })
        val (c,s)=seeded(p); val baseline=treeBytes(root); cut=step
        reject { c.apply(s,LifecycleCommand.BeginDeletion("delete",true)) }
        val after=treeBytes(root); for ((name,digest) in baseline) check(after[name]==digest)
        cut=null; val fresh=AppendOnlyLifecycleJournal(root,{true}); val reopened=DurableStorageCoordinator(fresh)
        if(step.startsWith("published")) check(reopened.load(owner).state.phase==Phase.DELETE_REQUESTED)
        else {
            reject("journal_pending_requires_recovery") { reopened.load(owner) }
            if(step=="pending_created") {
                val unchanged=treeBytes(root); reject { fresh.inspectPending() }; check(treeBytes(root)==unchanged)
                reject("journal_pending_requires_recovery") { reopened.provision(owner,true) }
            } else {
                val candidate=fresh.inspectPending()
                reject("explicit_pending_recovery_required") { fresh.promotePending(candidate,false) }
                reject("journal_pending_identity_mismatch") { fresh.promotePending(candidate.copy(snapshotSha256=hash),true) }
                fresh.promotePending(candidate,true); check(reopened.load(owner)==candidate)
                check(fresh.promotePending(candidate,true)==candidate)
            }
        }
    } }
    for (step in listOf("anchor_created","anchor_written","anchor_forced","anchor_directory_forced")) test("first-provision-interrupted-$step-never-recreated") { withTemp { root ->
        val p=AppendOnlyLifecycleJournal(root,{true},{ if(it==step) throw IOException("cut") })
        reject { DurableStorageCoordinator(p).provision(owner,true) }
        val before=treeBytes(root); val c=DurableStorageCoordinator(AppendOnlyLifecycleJournal(root,{true}))
        reject { c.load(owner) }; reject { c.provision(owner,true) }; check(treeBytes(root)==before)
    } }
    test("filesystem-unknown-evidence-blocks-without-delete") { withTemp { root ->
        Files.writeString(root.resolve("unknown.new"),"retain")
        val c=DurableStorageCoordinator(AppendOnlyLifecycleJournal(root,{true}))
        reject("journal_unknown_evidence") { c.provision(owner,true) }; check(Files.readString(root.resolve("unknown.new"))=="retain")
    } }
    test("filesystem-anchor-prevents-missing-history-reset") { withTemp { root ->
        val (c,_)=seeded(AppendOnlyLifecycleJournal(root,{true}))
        Files.newDirectoryStream(root,"*.snapshot").use { it.forEach(Files::delete) } // injected corruption in temp fixture
        reject("journal_history_missing") { c.load(owner) }; reject("journal_history_missing") { c.provision(owner,true) }
    } }
    test("filesystem-interior-history-gap-rejected") { withTemp { root ->
        val (c,_)=seeded(AppendOnlyLifecycleJournal(root,{true}))
        Files.delete(root.resolve("0000000000000000001.snapshot"))
        reject("journal_revision_gap") { c.load(owner) }
    } }
    test("filesystem-corruption-retained") { withTemp { root ->
        val (c,_)=seeded(AppendOnlyLifecycleJournal(root,{true}))
        val file=root.resolve("0000000000000000001.snapshot"); val b=Files.readAllBytes(file); b[90]=(b[90].toInt() xor 1).toByte(); Files.write(file,b)
        val before=treeBytes(root); reject("journal_checksum_mismatch") { c.load(owner) }; check(treeBytes(root)==before)
    } }
    test("filesystem-symlink-and-directory-records-refused") { withTemp { root ->
        val outside=Files.createTempFile("not-a-ledger", ".txt")
        try { Files.writeString(outside,"keep"); Files.createSymbolicLink(root.resolve("genesis.anchor"),outside)
            reject("journal_unsafe_record") { DurableStorageCoordinator(AppendOnlyLifecycleJournal(root,{true})).load(owner) }
            check(Files.readString(outside)=="keep")
        } finally { Files.deleteIfExists(outside) }
    } }
    test("filesystem-multiple-instances-one-winner-per-checkpoint") { withTemp { root ->
        val (c,s)=seeded(AppendOnlyLifecycleJournal(root,{true})); val start=CountDownLatch(1)
        val successes=AtomicInteger(); val refusals=AtomicInteger(); val errors=java.util.Collections.synchronizedList(mutableListOf<Throwable>())
        val threads=(1..8).map { n -> Thread {
            start.await()
            try { DurableStorageCoordinator(AppendOnlyLifecycleJournal(root,{true})).apply(s,LifecycleCommand.BeginWrite("race-$n",hash)); successes.incrementAndGet() }
            catch(e:StoragePolicyFailure) { if(e.code=="lifecycle_stale_checkpoint") refusals.incrementAndGet() else errors.add(e) }
            catch(e:Throwable) { errors.add(e) }
        }.apply { start() } }
        start.countDown(); threads.forEach { it.join(10000); check(!it.isAlive) }
        check(successes.get()==1 && refusals.get()==7 && errors.isEmpty()) { errors.toString() }
        check(c.load(owner).state.phase==Phase.WRITE_PENDING)
    } }
    val pStates = phases()
    val transitions = listOf(
        Triple("begin-write", pStates[0], LifecycleCommand.BeginWrite("next-write",hash)),
        Triple("confirm-write", pStates[1], LifecycleCommand.ConfirmWrite("write",hash,"new-record")),
        Triple("record-failure", pStates[0], LifecycleCommand.Failure(StorageFault.NO_SPACE)),
        Triple("health-write", pStates[0].copy(fault=StorageFault.NO_SPACE), LifecycleCommand.ConfirmHealthWrite),
        Triple("begin-deletion", pStates[2], LifecycleCommand.BeginDeletion("next-delete",true)),
        Triple("accept-receipt", pStates[3], LifecycleCommand.AcceptDeletionReceipt("delete","receipt")),
        Triple("begin-replacement", pStates.first { it.phase==Phase.TOMBSTONED },
            LifecycleCommand.BeginReplacement("next-replace",owner.copy(generation="next-generation"),true))
    )
    for ((label,state,command) in transitions) for(cut in listOf("before","after","silent")) test("transition-$label-commit-$cut") {
        val p=MemoryJournal(); val original=LifecycleSnapshotCodec.encode(state); p.bytes=original.copyOf()
        val c=DurableStorageCoordinator(p); val start=c.load(owner); val expected=c.apply(start,command)
        p.bytes=original.copyOf(); p.cut=cut
        reject { c.apply(start,command) }; p.cut=null
        val recovered=DurableStorageCoordinator(p).load(owner)
        check(recovered==if(cut=="after") expected else start)
        if(cut!="after") check(c.apply(recovered,command)==expected)
    }
    for(cut in listOf("before","after","silent")) test("finish-tombstone-commit-$cut") {
        val state=pStates.last { it.phase==Phase.CLEANUP_PENDING }
        val p=MemoryJournal(); p.bytes=LifecycleSnapshotCodec.encode(state)
        val c=DurableStorageCoordinator(p); val start=c.load(owner); val a=Artifacts(emptySet()); p.cut=cut
        reject { c.cleanupOne(start,a) }; p.cut=null
        val recovered=c.load(owner)
        check(recovered.state.phase==if(cut=="after") Phase.TOMBSTONED else Phase.CLEANUP_PENDING)
        check(c.cleanupOne(recovered,a).state.phase==Phase.TOMBSTONED && a.removes==0)
    }
    test("codec-rejects-duplicate-and-noncanonical-sets") {
        val b=LifecycleSnapshotCodec.encode(StorageState(owner,evidence=setOf("aaa","bbb")))
        val pos=b.toString(Charsets.ISO_8859_1).indexOf("bbb")
        "aaa".toByteArray().copyInto(b,pos)
        reject("snapshot_duplicate_item") { LifecycleSnapshotCodec.decode(rechecksum(b)) }
        "000".toByteArray().copyInto(b,pos)
        reject("snapshot_noncanonical_order") { LifecycleSnapshotCodec.decode(rechecksum(b)) }
    }
    test("codec-rejects-invalid-optional-tag") {
        val b=LifecycleSnapshotCodec.encode(StorageState(owner)); val usedOperationBytes=4
        // Optional tags are the seven zero bytes immediately preceding the used-operation count,
        // except the tombstone/archive counts between earlier optionals; use lastWrite tag.
        val offset=b.size-32-usedOperationBytes-2; b[offset]=2
        reject("snapshot_invalid_presence") { LifecycleSnapshotCodec.decode(rechecksum(b)) }
    }
    test("codec-rejects-extra-payload-fields-with-valid-checksum") {
        val b=LifecycleSnapshotCodec.encode(StorageState(owner))
        val extended=b.copyOfRange(0,b.size-32)+byteArrayOf(0)+ByteArray(32)
        ByteBuffer.wrap(extended).putInt(8,extended.size-44)
        reject("snapshot_trailing_fields") { LifecycleSnapshotCodec.decode(rechecksum(extended)) }
    }
    // Machine-readable, unique assertion names; loops remain one assertion family each.
    println("{\"status\":\"passed\",\"checks\":${names.size},\"names\":[" + names.joinToString(",") { "\"$it\"" } + "]}")
}
