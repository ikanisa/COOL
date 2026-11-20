package authenticatedchecks

import rw.ikanisa.storagepolicy.*
import rw.ikanisa.storagepolicy.jvm.*
import rw.ikanisa.storagepolicy.android.*
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import javax.crypto.spec.SecretKeySpec

private val checks = mutableListOf<String>()
private fun test(name: String, block: () -> Unit) { block(); check(name !in checks); checks += name }
private fun reject(code: String? = null, block: () -> Unit) {
    val e = runCatching(block).exceptionOrNull() ?: error("expected rejection $code")
    if (code != null) check(e is StoragePolicyFailure && e.code == code) { "expected $code got $e" }
}
// Disposable synthetic fixture key, NEVER a deployable secret or configuration value.
private val key = SecretKeySpec(ByteArray(32) { (it + 17).toByte() }, "AES")
private val binding = Binding("burimunsi", "synthetic-owner", "old-generation")
private val scope = JournalScope(binding.product, binding.owner, "synthetic-lifecycle")
private val digest = "a".repeat(64)
private fun protect(s: JournalScope = scope) = AesGcmJournalRecords(s, ExistingJournalKey { key })
private fun journal(root: Path, cut: ((String) -> Unit) = {}) =
    AppendOnlyLifecycleJournal(root, { false }, cut, protect())
private fun files(root: Path): Map<String,String> = Files.list(root).use { stream ->
    stream.toArray().map { it as Path }.associate { it.fileName.toString() to LifecycleSnapshotCodec.sha256(Files.readAllBytes(it)) }
}
private fun states(): List<StorageState> {
    val a = StorageState(binding, evidence=setOf("ciphertext"))
    val w = StorageLifecyclePolicy.beginWrite(a, "original-write", digest)
    val f = StorageLifecyclePolicy.recordFailure(w, StorageFault.NO_SPACE)
    val d = StorageLifecyclePolicy.beginDeletion(a, "original-delete", true)
    val c = StorageLifecyclePolicy.acceptDeletionReceipt(d, EffectToken(binding,d.revision,"original-delete"),"server-receipt")
    val r = StorageLifecyclePolicy.confirmArtifactAbsent(c,EffectToken(binding,c.revision,"original-delete"),"ciphertext")
    val t = StorageLifecyclePolicy.finishCleanup(r,EffectToken(binding,r.revision,"original-delete"))
    val p = StorageLifecyclePolicy.beginReplacement(t,"original-replace",binding.copy(generation="new-generation"),true)
    return listOf(a,w,f,d,c,r,t,p)
}
private class Legacy(var state: StorageState = states()[2], val file: Path? = null): LegacyLifecycleReadPort {
    var held = false
    var captures = 0
    var fail = false
    var mutateAfter = Int.MAX_VALUE
    var changedDigest = false
    override fun <T> frozen(block: () -> T): T = synchronized(this) {
        check(!held); held = true; try { block() } finally { held = false }
    }
    override fun capture(binding: Binding): LegacyLifecycleCapture {
        check(held); captures++
        if (fail) throw IOException("synthetic unreadable legacy")
        val hash = file?.let { LifecycleSnapshotCodec.sha256(Files.readAllBytes(it)) } ?: digest
        val length = file?.let { Files.size(it) } ?: 23
        val entries = state.evidence.sorted().map { ArchivedArtifact(it,length,if(changedDigest || captures>=mutateAfter) "b".repeat(64) else hash) }
        return LegacyLifecycleCapture(state,entries)
    }
    fun plan() = frozen { LegacyLifecycleMigration.prepare(binding,"explicit-migration-1",capture(binding)) }
}
private fun fixture(block: (Path, Legacy, LegacyLifecycleMigration) -> Unit) {
    val root=Files.createTempDirectory("auth-migration-")
    try { val source=Legacy(); block(root,source,source.plan()) }
    finally { root.toFile().deleteRecursively() } // disposable synthetic test fixture only
}
private fun process(args: Array<String>) {
    val root=Path.of(args[1]); val source=Legacy(file=root.resolveSibling("legacy.bin")); val plan=source.plan()
    when(args[0]) {
        "crash" -> journal(root) { if(it==args[2]) Runtime.getRuntime().halt(73) }.adoptLegacy(plan,source,true)
        "resume" -> { check(journal(root).adoptLegacy(plan,source,true).state == plan.initialState()); println("RESUMED") }
        "blocked" -> {
            val j=journal(root); val before=files(root)
            reject { j.adoptLegacy(plan,source,true) }
            check(files(root)==before); println("BLOCKED_RETAINED")
        }
    }
}
fun main(args: Array<String>) {
    if(args.isNotEmpty()) { process(args); return }
    val crypto=protect(); val bytes="synthetic-owner original-write retained evidence".toByteArray()
    test("aead-roundtrip-and-no-visible-plaintext") {
        val sealed=crypto.seal("snapshot:0",bytes)
        check(crypto.open("snapshot:0",sealed).contentEquals(bytes))
        check(!sealed.toString(Charsets.ISO_8859_1).contains("synthetic-owner"))
    }
    test("aead-randomized-provider-nonces-128-samples") {
        val seen=(0 until 128).map { crypto.seal("snapshot:0",bytes).sliceArray(8..19).toList() }
        check(seen.distinct().size==128)
    }
    for((name, other) in listOf("product" to scope.copy(product="mmoney"), "owner" to scope.copy(owner="other"), "namespace" to scope.copy(journalId="other")))
        test("aead-rejects-cross-$name") { reject("journal_authentication_failed") { protect(other).open("snapshot:0",crypto.seal("snapshot:0",bytes)) } }
    for(id in listOf("snapshot:1","genesis","migration")) test("aead-rejects-record-substitution-$id") {
        reject("journal_authentication_failed") { crypto.open(id,crypto.seal("snapshot:0",bytes)) }
    }
    test("aead-rejects-every-single-byte-mutation") {
        val sealed=crypto.seal("snapshot:0",bytes)
        for(i in sealed.indices) { val mutated=sealed.copyOf(); mutated[i]=(mutated[i].toInt() xor 1).toByte(); reject { crypto.open("snapshot:0",mutated) } }
    }
    test("aead-rejects-every-truncated-prefix") {
        val sealed=crypto.seal("snapshot:0",bytes)
        for(i in sealed.indices) reject { crypto.open("snapshot:0",sealed.copyOf(i)) }
    }
    test("aead-rejects-trailing-bytes") { reject { crypto.open("snapshot:0",crypto.seal("snapshot:0",bytes)+byteArrayOf(0)) } }
    test("aead-rejects-wrong-key") {
        val wrong=AesGcmJournalRecords(scope,ExistingJournalKey { SecretKeySpec(ByteArray(32){42},"AES") })
        reject("journal_authentication_failed") { wrong.open("snapshot:0",crypto.seal("snapshot:0",bytes)) }
    }
    test("aead-missing-key-never-falls-back") {
        val missing=AesGcmJournalRecords(scope,ExistingJournalKey { throw StoragePolicyFailure("missing") })
        reject("missing") { missing.open("snapshot:0",crypto.seal("snapshot:0",bytes)) }
        reject("missing") { missing.seal("snapshot:0",bytes) }
    }
    test("aead-rejects-128bit-key") {
        reject("journal_key_size") { AesGcmJournalRecords(scope,ExistingJournalKey { SecretKeySpec(ByteArray(16),"AES") }).seal("genesis",bytes) }
    }
    test("aead-rejects-empty-and-oversized-plaintext") {
        reject { crypto.seal("genesis",byteArrayOf()) }; reject { crypto.seal("genesis",ByteArray(LifecycleSnapshotCodec.MAX_BYTES+137)) }
    }
    test("aead-rejects-plaintext-downgrade") { reject { crypto.open("snapshot:0",LifecycleSnapshotCodec.encode(StorageState(binding))) } }
    test("aead-rejects-version-change") {
        val sealed=crypto.seal("genesis",bytes); ByteBuffer.wrap(sealed).putInt(4,2)
        reject("journal_envelope_version") { crypto.open("genesis",sealed) }
    }
    test("encrypted-provision-and-pending-recovery") {
        val root=Files.createTempDirectory("auth-fresh-")
        try {
            val j=AppendOnlyLifecycleJournal(root,{true},protection=crypto); val c=DurableStorageCoordinator(j)
            val start=c.provision(binding,true)
            val crash=AppendOnlyLifecycleJournal(root,{true},{ if(it=="pending_directory_forced") throw IOException("cut") },crypto)
            reject { DurableStorageCoordinator(crash).apply(start,LifecycleCommand.BeginWrite("write",digest)) }
            val before=files(root); reject("journal_pending_requires_recovery") { c.load(binding) }; check(before==files(root))
            val pending=j.inspectPending(); check(pending.state.write!!.operationId=="write")
            check(j.promotePending(pending,true)==pending); check(c.load(binding)==pending)
        } finally { root.toFile().deleteRecursively() }
    }
    test("encrypted-scope-rejects-wrong-binding-before-anchor") {
        val root=Files.createTempDirectory("auth-scope-")
        try {
            val c=DurableStorageCoordinator(AppendOnlyLifecycleJournal(root,{true},protection=crypto))
            reject("journal_crypto_scope_mismatch") { c.provision(binding.copy(product="mmoney"),true) }
            check(files(root).keys==setOf(".lock"))
        } finally { root.toFile().deleteRecursively() }
    }
    for((i,state) in states().withIndex()) test("migration-preserves-entire-state-$i-${state.phase}") {
        fixture { root,_,_ ->
            val src=Legacy(state); val plan=src.plan(); val result=journal(root).adoptLegacy(plan,src,true)
            check(result.state.copy(revision=state.revision,usedOperations=state.usedOperations)==state)
            check(result.state.usedOperations == state.usedOperations + plan.operationId)
            val prior=files(root); check(journal(root).adoptLegacy(plan,src,true)==result); check(files(root)==prior)
        }
    }
    test("migration-refuses-nonexplicit-and-plaintext-destinations") { fixture { root,src,plan ->
        reject("explicit_migration_required") { journal(root).adoptLegacy(plan,src,false) }; check(files(root).isEmpty())
        reject("migration_authenticated_journal_required") { AppendOnlyLifecycleJournal(root,{true}).adoptLegacy(plan,src,true) }
    } }
    test("migration-retains-original-file-byte-for-byte") {
        val outer=Files.createTempDirectory("migration-evidence-")
        try {
            val old=outer.resolve("legacy.bin"); val data="synthetic original ciphertext".toByteArray(); Files.write(old,data)
            val root=Files.createDirectory(outer.resolve("journal")); val src=Legacy(file=old); val p=src.plan()
            journal(root).adoptLegacy(p,src,true); check(Files.readAllBytes(old).contentEquals(data))
        } finally { outer.toFile().deleteRecursively() }
    }
    test("migration-rejects-changed-legacy-content-before-effects") { fixture { root,src,plan ->
        src.changedDigest=true; reject("migration_source_changed") { journal(root).adoptLegacy(plan,src,true) }
        check(files(root).keys==setOf(".lock"))
    } }
    test("migration-rejects-changed-legacy-state") { fixture { root,src,plan ->
        src.state=src.state.copy(fault=StorageFault.PERMISSION_DENIED)
        reject("migration_source_changed") { journal(root).adoptLegacy(plan,src,true) }
    } }
    test("migration-rejects-unreadable-source-without-bootstrap") { fixture { root,src,plan ->
        src.fail=true; reject { journal(root).adoptLegacy(plan,src,true) }; check(files(root).keys==setOf(".lock"))
    } }
    test("migration-detects-noncooperative-source-mutation-before-publish") { fixture { root,src,plan ->
        src.mutateAfter=3; reject("migration_source_changed") { journal(root).adoptLegacy(plan,src,true) }
        check(files(root).keys.any { it.endsWith("pending") }); check(files(root).keys.none { it.endsWith("snapshot") })
    } }
    test("migration-rejects-wrong-product") { fixture { root,src,_ ->
        val changed=src.state.copy(binding=binding.copy(product="mmoney"),write=src.state.write)
        val foreign=Legacy(changed); val plan=foreign.frozen { LegacyLifecycleMigration.prepare(changed.binding,"migration",foreign.capture(changed.binding)) }
        reject("journal_crypto_scope_mismatch") { journal(root).adoptLegacy(plan,foreign,true) }
    } }
    for(kind in listOf("duplicate","missing","extra","malformed","negative")) test("migration-rejects-inventory-$kind") {
        val s=states()[0]; val e=ArchivedArtifact("ciphertext",23,digest)
        val entries=when(kind){ "duplicate"->listOf(e,e); "missing"->emptyList(); "extra"->listOf(e,e.copy(id="unknown")); "malformed"->listOf(e.copy(sha256="x")); else->listOf(e.copy(bytes=-1)) }
        reject { LegacyLifecycleMigration.prepare(binding,"migration",LegacyLifecycleCapture(s,entries)) }
    }
    test("migration-refuses-operation-reuse") {
        val src=Legacy(); val cap=src.frozen { src.capture(binding) }
        reject("migration_operation_reused") { LegacyLifecycleMigration.prepare(binding,"original-write",cap) }
    }
    test("migration-refuses-unmarked-existing-journal") { fixture { root,src,p ->
        DurableStorageCoordinator(AppendOnlyLifecycleJournal(root,{true},protection=crypto)).provision(binding,true)
        val before=files(root); reject("migration_unmarked_destination") { journal(root).adoptLegacy(p,src,true) }; check(files(root)==before)
    } }
    val cuts=listOf("migration_created","migration_written","migration_forced","migration_directory_forced",
        "anchor_created","anchor_written","anchor_forced","anchor_directory_forced",
        "pending_created","pending_written","pending_forced","pending_directory_forced","published","published_directory_forced")
    for(cut in cuts) test("migration-cut-$cut-retains-evidence") { fixture { root,src,plan ->
        reject { journal(root) { if(it==cut) throw IOException("injected $cut") }.adoptLegacy(plan,src,true) }
        val before=files(root)
        if(cut.endsWith("_created")) {
            reject { journal(root).adoptLegacy(plan,src,true) }; check(files(root)==before)
        } else {
            val r=journal(root).adoptLegacy(plan,src,true); check(r.state==plan.initialState())
            val after=files(root)
            before.filterKeys { !it.endsWith("pending") }.forEach { (name,hash)->check(after[name]==hash) }
        }
    } }
    for(name in listOf("migration.anchor","genesis.anchor","0000000000000000000.snapshot")) {
        test("migration-corrupt-$name-is-retained") { fixture { root,src,p ->
            journal(root).adoptLegacy(p,src,true)
            val path=root.resolve(name); val b=Files.readAllBytes(path); b[b.lastIndex]=(b.last().toInt() xor 1).toByte(); Files.write(path,b)
            val before=files(root); reject { DurableStorageCoordinator(journal(root)).load(binding) }; reject { journal(root).adoptLegacy(p,src,true) }; check(files(root)==before)
        } }
    }
    test("migration-missing-marker-does-not-lose-provenance-silently") { fixture { root,src,p ->
        journal(root).adoptLegacy(p,src,true); Files.delete(root.resolve("migration.anchor"))
        reject("journal_anchor_mismatch") { DurableStorageCoordinator(journal(root)).load(binding) }
    } }
    test("migration-never-rewinds-advanced-state") { fixture { root,src,p ->
        val j=journal(root); val s=j.adoptLegacy(p,src,true)
        DurableStorageCoordinator(j).apply(s,LifecycleCommand.Failure(StorageFault.IO_UNAVAILABLE))
        val before=files(root); reject("migration_destination_not_empty") { j.adoptLegacy(p,src,true) }; check(files(root)==before)
    } }
    test("migration-conflicting-plan-retains-all-records") { fixture { root,src,p ->
        journal(root).adoptLegacy(p,src,true)
        val q=src.frozen { LegacyLifecycleMigration.prepare(binding,"different-migration",src.capture(binding)) }
        val before=files(root); reject("migration_plan_conflict") { journal(root).adoptLegacy(q,src,true) }; check(files(root)==before)
    } }
    test("android-provider-unavailable-blocks-not-emulated") {
        reject("journal_existing_key_unavailable") { AndroidExistingLifecycleKey("synthetic-test-alias").requireKey() }
    }
    println("{\"status\":\"passed\",\"checks\":${checks.size},\"names\":["+checks.joinToString(","){"\"$it\""}+"]}")
}
