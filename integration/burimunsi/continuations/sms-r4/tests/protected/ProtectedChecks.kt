package rw.ikanisa.sms.protectedtests

import rw.ikanisa.sms.policy.*
import rw.ikanisa.sms.adapters.burimunsi.BuriSmsClassifier
import rw.ikanisa.sms.adapters.mmoney.MmoneySmsClassifier
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import java.nio.ByteBuffer

private const val BODY="You have received 1,000 RWF from Test Person (*****007) at 2026-11-09 09:30:00. Balance: 2,000 RWF. FT Id: 123456789."
private val buri=BuriSmsClassifier()
private val mm=MmoneySmsClassifier()
private fun uuid(n: Int)="20000000-0000-4000-8000-"+n.toString().padStart(12,'0')
private fun scope(c: Contract)=OwnerScope(c,"synthetic-owner","synthetic-installation","generation-1")
private val binding=SourceBinding("synthetic-binding",1,7)
private fun classifier(c: Contract)=if(c==Contract.BURI_COLLECT_V2) buri else mm
private fun batch(c: Contract=Contract.BURI_COLLECT_V2,n: Int=1,parts: List<SmsPart>?=null,
                  mode: InputMode=InputMode.LIVE,source: String="source-$n",owner: OwnerScope=scope(c),
                  bind: SourceBinding=binding): UploadBatch {
    val p=parts ?: listOf(SmsPart(1,1,null,null,"M-Money",BODY,1000,7,0,null,true,"aB00"))
    val a=MultipartPolicy.inspect(SmsInput(mode,if(mode==InputMode.LIVE) "3gpp" else null,p))
    val o=Original(owner,bind,uuid(n),source,a,classifier(c).classify(a))
    return UploadBatch(if(c==Contract.BURI_COLLECT_V2) o.captureId else uuid(n+100),listOf(o))
}
private fun auth(b: UploadBatch)=Authority(b.scope,b.binding,1,SimState(true,setOf(7,8)))
private fun machine(b: UploadBatch)=QueueMachine(classifier(b.scope.contract))
private fun initial(b: UploadBatch=batch())=QueueSnapshot.capture(b,1000)
private fun move(s: QueueSnapshot,a: QueueAction,now: Long=s.lastObservedAt)=machine(s.batch).transition(s,a,auth(s.batch),now).next
private fun ack(b: UploadBatch,canonical: String=uuid(900),rejected: Boolean=false): Map<String,Any?> =
    if(b.scope.contract==Contract.BURI_COLLECT_V2) mapOf("ok" to true,"receipt" to mapOf("contract_version" to 2,
        "stored" to true,"owner_user_id" to b.scope.ownerId,"client_envelope_id" to b.originals.single().captureId,
        "raw_sms_id" to canonical,"body_sha256" to b.originals.single().bodySha256))
    else mapOf("schemaVersion" to 1,"acknowledgements" to b.originals.map {
        if(rejected) mapOf("id" to it.captureId,"status" to "rejected","canonicalId" to null,"code" to "UNSUPPORTED")
        else mapOf("id" to it.captureId,"status" to "accepted","canonicalId" to canonical)
    })
private var assertions=0
private var malformedInputs=0
private val results=mutableListOf<Pair<String,String>>()
private fun yes(ok: Boolean) { assertions++; check(ok) { "assertion-$assertions" } }
private fun test(name: String,body: ()->Unit) {
    try { body(); results+=name to "passed" }
    catch(e: Throwable) { results+=name to "failed"; System.err.println("FAILED $name: ${e.javaClass.simpleName}: ${e.message}"); e.printStackTrace(System.err) }
}
private fun key(): SecretKey=KeyGenerator.getInstance("AES").also { it.init(256) }.generateKey()
private enum class Fault { NONE, BEFORE, UNKNOWN_BEFORE, UNKNOWN_AFTER, THROW_BEFORE, THROW_AFTER, PARTIAL }
private class Keys(var value: SecretKey?=key()): ExistingAesKey {
    var unavailable=false
    val requested=mutableListOf<String>()
    override fun resolve(alias: String): SecretKey? { requested+=alias; if(unavailable) error("synthetic-key-unavailable"); return value }
}
private class Blob(initial: ByteArray): CiphertextBlobPort {
    var bytes=initial.copyOf()
    var fault=Fault.NONE
    var reads=0; var writes=0
    var missing=false; var unavailable=false
    var onRead: (() -> Unit)?=null
    @Synchronized override fun read(): JournalRead {
        reads++; onRead?.also { onRead=null; it() }
        return when { missing -> JournalRead.Missing; unavailable -> JournalRead.Unavailable; else -> JournalRead.Bytes(bytes) }
    }
    @Synchronized override fun replace(expectedCiphertextHash: String,replacement: ByteArray): StoreWrite {
        writes++
        if(missing || unavailable) return StoreWrite.NOT_COMMITTED
        if(EvidenceHash.sha256(bytes)!=expectedCiphertextHash) return StoreWrite.REVISION_CONFLICT
        val f=fault; fault=Fault.NONE
        when(f) {
            Fault.BEFORE -> return StoreWrite.NOT_COMMITTED
            Fault.UNKNOWN_BEFORE -> return StoreWrite.UNKNOWN
            Fault.THROW_BEFORE -> error("synthetic-write-before")
            Fault.PARTIAL -> { bytes=replacement.copyOfRange(0,replacement.size/2); return StoreWrite.UNKNOWN }
            else -> Unit
        }
        bytes=replacement.copyOf()
        if(f==Fault.THROW_AFTER) error("synthetic-write-after")
        return if(f==Fault.UNKNOWN_AFTER) StoreWrite.UNKNOWN else StoreWrite.COMMITTED
    }
}
private class Checkpoints(initial: Checkpoint): TrustedCheckpointPort {
    var value=initial
    var calls=0; var reads=0
    var faultAt=0; var fault=Fault.NONE
    @Synchronized override fun read(contextHash: String): Checkpoint { reads++; return value }
    @Synchronized override fun compareAndSet(expected: Checkpoint,next: Checkpoint): StoreWrite {
        calls++
        if(value!=expected) return StoreWrite.REVISION_CONFLICT
        if(!CheckpointRules.follows(expected,next)) return StoreWrite.NOT_COMMITTED
        val f=if(calls==faultAt) fault else Fault.NONE
        when(f) {
            Fault.BEFORE -> return StoreWrite.NOT_COMMITTED
            Fault.UNKNOWN_BEFORE -> return StoreWrite.UNKNOWN
            Fault.THROW_BEFORE -> error("synthetic-checkpoint-before")
            else -> Unit
        }
        value=next
        if(f==Fault.THROW_AFTER) error("synthetic-checkpoint-after")
        return if(f==Fault.UNKNOWN_AFTER) StoreWrite.UNKNOWN else StoreWrite.COMMITTED
    }
}
private class Setup(val b: UploadBatch=batch()) {
    val identity=StorageBinding(b.scope,"synthetic-store-1","synthetic-alias-1")
    val keys=Keys()
    val cipher=AesGcmJournalCipher(keys)
    val empty=JournalFormat.empty(b.scope)
    val blob=Blob(cipher.seal(empty,identity,0))
    val cp=Checkpoints(Checkpoint.Committed(JournalAnchor(identity.contextHash,0,EvidenceHash.sha256(blob.bytes),EvidenceHash.sha256(empty))))
    fun port()=ProtectedJournalPort(identity,cipher,blob,cp)
    val port=port()
    val store=JournalQueueStore(port,b.scope)
    val driver=CommitDriver(store,machine(b))
    fun capture()=driver.capture(b,1000)
    fun get()=(store.read(b.key) as StoreRead.Present).snapshot
    fun step(a: QueueAction,now: Long=1000)=driver.advance(b.key,a,auth(b),now)
}
private fun reject(code: SecureCode?=null,body: ()->Unit) {
    malformedInputs++
    try { body(); error("accepted-invalid-envelope") }
    catch(e: SecureStorageException) { yes(code==null || code==e.code) }
}
private fun contains(bytes: ByteArray,pattern: ByteArray): Boolean =
    bytes.size>=pattern.size && (0..bytes.size-pattern.size).any { i -> pattern.indices.all { bytes[i+it]==pattern[it] } }
private fun blocked(s: Setup,reason: String?=null) {
    val result=s.port.inspect()
    yes(result is ProtectedInspection.Blocked)
    if(reason!=null) yes((result as ProtectedInspection.Blocked).reason==reason)
    yes(s.port.read()==JournalRead.Unavailable)
    yes(s.step(QueueAction.SendOriginal).effect==QueueEffect.None)
}
fun main() {
    for(c in Contract.values()) {
        test("encrypted/$c/complete-queue-history-and-reopen") {
            val s=Setup(batch(c)); yes(s.capture().status=="CAPTURE_COMMITTED")
            val sent=s.step(QueueAction.SendOriginal); yes(sent.effect is QueueEffect.UploadOriginal)
            val pending=s.step(QueueAction.Response(s.get().activeAttempt!!,ack(s.b)),1100)
            yes(pending.snapshot!!.phase==Phase.ACK_PENDING)
            yes(s.step(QueueAction.FinalizeAcknowledgement,1200).snapshot!!.phase==Phase.ACKNOWLEDGED)
            val restored=JournalQueueStore(s.port(),s.b.scope)
            val st=(restored.read(s.b.key) as StoreRead.Present).snapshot
            yes(st.batch.payloadHash==s.b.payloadHash && st.batch.operationId==s.b.operationId)
            yes(st.batch.originals.single().assembly.input.parts==s.b.originals.single().assembly.input.parts)
            yes(st.receipts.isNotEmpty() && st.attempts==1 && st.phase==Phase.ACKNOWLEDGED)
            yes(!contains(s.blob.bytes,BODY.toByteArray()))
            yes(!contains(s.blob.bytes,BODY.toByteArray(Charsets.UTF_16BE)))
            yes((s.cp.value as Checkpoint.Committed).anchor.sequence==4L)
        }
        test("rollback/$c/old-complete-valid-ciphertext-rejected") {
            val s=Setup(batch(c)); s.capture(); val old=s.blob.bytes.copyOf()
            s.step(QueueAction.SendOriginal); val current=s.cp.value
            s.blob.bytes=old
            blocked(s,"CIPHERTEXT_CHECKPOINT_MISMATCH")
            yes(s.port.recoverPrepared()=="RECOVERY_BLOCKED")
            yes(s.blob.bytes.contentEquals(old) && s.cp.value==current)
        }
    }
    test("crypto/provider-generated-nonce-and-randomization") {
        val s=Setup(); val envelopes=(1..100).map { s.cipher.seal(s.empty,s.identity,0) }
        yes(envelopes.map { EvidenceHash.sha256(it) }.distinct().size==100)
        yes(envelopes.map { it.sliceArray(52..63).toList() }.distinct().size==100)
        envelopes.forEach { yes(s.cipher.open(it,s.identity,0).contentEquals(s.empty)) }
    }
    test("crypto/every-envelope-byte-authenticated-or-structurally-rejected") {
        val s=Setup(); val original=s.blob.bytes.copyOf()
        for(i in original.indices) {
            val modified=original.copyOf(); modified[i]=(modified[i].toInt() xor 1).toByte()
            reject { s.cipher.open(modified,s.identity,0) }
        }
    }
    test("crypto/all-truncations-and-trailing-data-rejected") {
        val s=Setup()
        for(n in 0 until s.blob.bytes.size) reject { s.cipher.open(s.blob.bytes.copyOf(n),s.identity,0) }
        reject { s.cipher.open(s.blob.bytes+byteArrayOf(1),s.identity,0) }
    }
    for(kind in listOf("owner","installation","generation","contract","store","alias")) test("crypto/context/$kind") {
        val s=Setup()
        val other=when(kind) {
            "owner" -> s.identity.copy(scope=s.b.scope.copy(ownerId="other-owner"))
            "installation" -> s.identity.copy(scope=s.b.scope.copy(installationId="other-install"))
            "generation" -> s.identity.copy(scope=s.b.scope.copy(generation="other-generation"))
            "contract" -> s.identity.copy(scope=s.b.scope.copy(contract=Contract.MMONEY_LEDGER_V1))
            "store" -> s.identity.copy(storeId="other-store")
            else -> s.identity.copy(keyAlias="other-alias")
        }
        val before=s.keys.requested.size
        reject(SecureCode.CONTEXT) { s.cipher.open(s.blob.bytes,other,0) }
        yes(s.keys.requested.size==before)
    }
    test("crypto/wrong-key-no-fallback") {
        val s=Setup(); s.keys.value=key()
        reject(SecureCode.AUTHENTICATION) { s.cipher.open(s.blob.bytes,s.identity,0) }
        blocked(s,"AUTHENTICATION")
    }
    for(mode in listOf("missing","unavailable")) test("key/$mode-preserves-all-storage") {
        val s=Setup(); s.capture(); val bytes=s.blob.bytes.copyOf(); val cp=s.cp.value
        if(mode=="missing") s.keys.value=null else s.keys.unavailable=true
        blocked(s,"KEY_UNAVAILABLE")
        yes(s.blob.bytes.contentEquals(bytes) && s.cp.value==cp)
        yes(s.port.recoverPrepared()=="RECOVERY_BLOCKED")
    }
    test("crypto/version-sequence-size-strict") {
        val s=Setup(); val bad=s.blob.bytes.copyOf(); ByteBuffer.wrap(bad).putInt(4,2)
        reject(SecureCode.VERSION) { s.cipher.open(bad,s.identity,0) }
        reject(SecureCode.SEQUENCE) { s.cipher.open(s.blob.bytes,s.identity,1) }
        reject(SecureCode.SEQUENCE) { s.cipher.seal(s.empty,s.identity,-1) }
        reject(SecureCode.SIZE) { s.cipher.seal(byteArrayOf(),s.identity,0) }
        reject(SecureCode.CONTEXT) { s.cipher.seal(s.empty,s.identity.copy(storeId=""),0) }
        reject(SecureCode.SIZE) { s.cipher.open(ByteArray(AesGcmJournalCipher.MAX_BYTES+1),s.identity,0) }
    }
    test("checkpoint/transition-table-no-decrement-cancel-or-bootstrap") {
        val s=Setup(); val a=(s.cp.value as Checkpoint.Committed).anchor
        val b=a.copy(sequence=1,ciphertextHash="a".repeat(64),plaintextHash="b".repeat(64))
        val pending=Checkpoint.Prepared(a,b)
        val states=listOf(Checkpoint.Missing,Checkpoint.Unavailable,s.cp.value,pending,Checkpoint.Committed(b))
        for(x in states) for(y in states) yes(CheckpointRules.follows(x,y)==
            ((x==s.cp.value && y==pending) || (x==pending && y==Checkpoint.Committed(b))))
        yes(!CheckpointRules.prepared(pending.copy(after=b.copy(sequence=3))))
        yes(!CheckpointRules.prepared(pending.copy(after=b.copy(contextHash="f".repeat(64)))))
        yes(!CheckpointRules.prepared(pending.copy(after=b.copy(ciphertextHash=a.ciphertextHash))))
    }
    for(mode in listOf("missing","unavailable","foreign","negative","bad-hash","bad-pending")) test("checkpoint/$mode-blocks-without-write") {
        val s=Setup(); val old=s.cp.value as Checkpoint.Committed
        s.cp.value=when(mode) {
            "missing" -> Checkpoint.Missing
            "unavailable" -> Checkpoint.Unavailable
            "foreign" -> old.copy(anchor=old.anchor.copy(contextHash="f".repeat(64)))
            "negative" -> old.copy(anchor=old.anchor.copy(sequence=-1))
            "bad-hash" -> old.copy(anchor=old.anchor.copy(ciphertextHash="bad"))
            else -> Checkpoint.Prepared(old.anchor,old.anchor)
        }
        val bytes=s.blob.bytes.copyOf(); blocked(s)
        yes(s.capture().effect==QueueEffect.None)
        yes(s.blob.bytes.contentEquals(bytes) && s.blob.writes==0 && s.cp.calls==0)
    }
    test("checkpoint/changes-during-read-rejected") {
        val s=Setup(); s.blob.onRead={ s.cp.value=Checkpoint.Unavailable }
        val r=s.port.inspect(); yes(r is ProtectedInspection.Blocked && r.reason=="CHECKPOINT_CHANGED")
    }
    test("checkpoint/authentic-ciphertext-with-wrong-plaintext-hash-rejected") {
        val s=Setup(); val cp=s.cp.value as Checkpoint.Committed
        s.cp.value=cp.copy(anchor=cp.anchor.copy(plaintextHash="f".repeat(64)))
        blocked(s,"PLAINTEXT_CHECKPOINT_MISMATCH")
    }
    test("checkpoint/record-count-cannot-be-forged") {
        val s=Setup(); s.blob.bytes=s.cipher.seal(s.empty,s.identity,1)
        s.cp.value=Checkpoint.Committed(JournalAnchor(s.identity.contextHash,1,EvidenceHash.sha256(s.blob.bytes),EvidenceHash.sha256(s.empty)))
        blocked(s,"RECORD_COUNT_MISMATCH")
    }
    test("ciphertext/authentic-but-invalid-journal-blocks") {
        val s=Setup(); val bad=s.empty.copyOf(); bad[0]=0
        s.blob.bytes=s.cipher.seal(bad,s.identity,0)
        s.cp.value=Checkpoint.Committed(JournalAnchor(s.identity.contextHash,0,EvidenceHash.sha256(s.blob.bytes),EvidenceHash.sha256(bad)))
        blocked(s,"JOURNAL_MAGIC")
    }
    for(mode in listOf("missing","unavailable","truncated","modified")) test("ciphertext/$mode-no-recreation") {
        val s=Setup()
        when(mode) {
            "missing" -> s.blob.missing=true
            "unavailable" -> s.blob.unavailable=true
            "truncated" -> s.blob.bytes=s.blob.bytes.copyOf(3)
            else -> s.blob.bytes[60]=(s.blob.bytes[60].toInt() xor 1).toByte()
        }
        val old=s.blob.bytes.copyOf(); blocked(s); yes(s.capture().effect==QueueEffect.None)
        yes(s.blob.bytes.contentEquals(old) && s.blob.writes==0)
    }
    test("append/stale-hash-empty-garbage-and-two-records-rejected") {
        val s=Setup(); val state=JournalFormat.replay(s.empty,s.b.scope)
        val first=JournalFormat.record(state,initial(s.b))
        yes(s.port.append("0".repeat(64),first)==StoreWrite.REVISION_CONFLICT)
        yes(s.port.append(state.contentHash,byteArrayOf())==StoreWrite.NOT_COMMITTED)
        yes(s.port.append(state.contentHash,byteArrayOf(1,2))==StoreWrite.NOT_COMMITTED)
        val after=JournalFormat.replay(s.empty+first,s.b.scope)
        val second=JournalFormat.record(after,move(initial(s.b),QueueAction.SendOriginal))
        yes(s.port.append(state.contentHash,first+second)==StoreWrite.NOT_COMMITTED)
        yes(s.cp.calls==0 && s.blob.writes==0)
    }
    // Interrupt every durable boundary during capture, reservation, ACK staging and ACK finalization.
    for(operation in listOf("capture","send","ack","finalize"))
      for(stage in listOf("prepare","ciphertext","finalize"))
        for(f in Fault.values().filter { it!=Fault.NONE && (stage=="ciphertext" || it!=Fault.PARTIAL) }) {
        test("fault/$operation/$stage/$f") {
            val s=Setup()
            if(operation!="capture") s.capture()
            if(operation in listOf("ack","finalize")) s.step(QueueAction.SendOriginal)
            if(operation=="finalize") s.step(QueueAction.Response(s.get().activeAttempt!!,ack(s.b)),1100)
            val priorBytes=s.blob.bytes.copyOf(); val priorCp=s.cp.value
            if(stage=="ciphertext") s.blob.fault=f
            else { s.cp.faultAt=s.cp.calls+if(stage=="prepare") 1 else 2; s.cp.fault=f }
            val result=when(operation) {
                "capture" -> s.capture()
                "send" -> s.step(QueueAction.SendOriginal)
                "ack" -> s.step(QueueAction.Response(s.get().activeAttempt!!,ack(s.b)),1100)
                else -> s.step(QueueAction.FinalizeAcknowledgement,1200)
            }
            yes(result.effect==QueueEffect.None)
            val changed=s.cp.value!=priorCp
            if(!changed) yes(s.blob.bytes.contentEquals(priorBytes))
            if(s.cp.value is Checkpoint.Prepared) {
                yes(s.port.inspect() is ProtectedInspection.Blocked)
                val prepared=s.cp.value as Checkpoint.Prepared
                val complete=EvidenceHash.sha256(s.blob.bytes)==prepared.after.ciphertextHash
                val recovery=s.port().recoverPrepared()
                yes(recovery==if(complete) "RECOVERED" else "RECOVERY_BLOCKED")
                if(complete) {
                    yes(s.port.inspect() is ProtectedInspection.Ready)
                    yes(s.port.recoverPrepared()=="ALREADY_COMMITTED")
                    val restored=s.get()
                    yes(restored.batch.operationId==s.b.operationId && restored.batch.payloadHash==s.b.payloadHash)
                    if(operation=="send") { yes(restored.phase==Phase.IN_FLIGHT); yes(s.step(QueueAction.SendOriginal).effect==QueueEffect.None) }
                } else {
                    val bytes=s.blob.bytes.copyOf(); val checkpoint=s.cp.value
                    yes(s.port.recoverPrepared()=="RECOVERY_BLOCKED")
                    yes(s.cp.value==checkpoint && s.blob.bytes.contentEquals(bytes))
                }
            } else yes(s.port.inspect() is ProtectedInspection.Ready)
        }
    }
    test("recovery/unknown-reservation-never-mints-a-new-operation") {
        val s=Setup(); s.capture(); s.cp.faultAt=s.cp.calls+2; s.cp.fault=Fault.UNKNOWN_BEFORE
        yes(s.step(QueueAction.SendOriginal).effect==QueueEffect.None)
        yes(s.port().recoverPrepared()=="RECOVERED")
        val restored=s.step(QueueAction.Restore,1100)
        yes(restored.effect==QueueEffect.None && restored.snapshot!!.outcomeUncertain)
        val st=s.get(); yes(st.batch.operationId==s.b.operationId && st.attempts==1 && st.phase==Phase.RETRY_WAIT)
    }
    test("recovery/finalize-checkpoint-unknown-is-not-promoted") {
        val s=Setup(); s.blob.fault=Fault.UNKNOWN_AFTER; s.capture()
        s.cp.faultAt=s.cp.calls+1; s.cp.fault=Fault.UNKNOWN_AFTER
        yes(s.port.recoverPrepared()=="RECOVERY_OUTCOME_UNKNOWN")
        yes(s.port.recoverPrepared()=="ALREADY_COMMITTED")
    }
    test("recovery/lost-key-during-pending-preserves-both-stores") {
        val s=Setup(); s.blob.fault=Fault.UNKNOWN_AFTER; s.capture()
        val before=s.blob.bytes.copyOf(); val checkpoint=s.cp.value; s.keys.value=null
        yes(s.port.recoverPrepared()=="RECOVERY_BLOCKED")
        yes(s.blob.bytes.contentEquals(before) && s.cp.value==checkpoint)
    }
    test("concurrency/two-independent-port-instances-one-reservation") {
        repeat(20) {
            val s=Setup(); s.capture()
            val start=CountDownLatch(1); val done=CountDownLatch(2)
            val observed=CopyOnWriteArrayList<DriverResult>(); val errors=CopyOnWriteArrayList<Throwable>()
            repeat(2) { Thread {
                try { start.await(); observed+=CommitDriver(JournalQueueStore(s.port(),s.b.scope),machine(s.b)).advance(s.b.key,QueueAction.SendOriginal,auth(s.b),1000) }
                catch(e: Throwable) { errors+=e }
                finally { done.countDown() }
            }.start() }
            start.countDown(); yes(done.await(10,TimeUnit.SECONDS)); yes(errors.isEmpty())
            yes(observed.count { it.effect is QueueEffect.UploadOriginal }==1)
            yes(s.get().attempts==1)
        }
    }
    test("documented-boundary/checkpoint-and-ciphertext-joint-rollback-not-detectable") {
        val s=Setup(); s.capture(); val oldBytes=s.blob.bytes.copyOf(); val oldCp=s.cp.value
        s.step(QueueAction.SendOriginal); s.blob.bytes=oldBytes; s.cp.value=oldCp
        // Demonstrates why the real checkpoint MUST live outside the restorable local data set.
        yes(s.port.inspect() is ProtectedInspection.Ready)
        yes(s.get().attempts==0)
    }
    val failed=results.count { it.second=="failed" }
    println("""{"schema_version":1,"status":"${if(failed==0) "passed" else "failed"}","tests":${results.size},"failed":$failed,"assertions":$assertions,"malformed_inputs":$malformedInputs,"cases":[${results.joinToString(",") { "{\"name\":\"${it.first}\",\"status\":\"${it.second}\"}" }}]}""")
    if(failed>0) kotlin.system.exitProcess(1)
}
