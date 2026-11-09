package rw.ikanisa.sms.persistence.tests

import rw.ikanisa.sms.policy.*
import rw.ikanisa.sms.host.*
import rw.ikanisa.sms.adapters.burimunsi.BuriSmsClassifier
import rw.ikanisa.sms.adapters.mmoney.MmoneySmsClassifier
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.PosixFilePermissions
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.random.Random

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
private fun stateCopy(s: QueueSnapshot, batch: UploadBatch=s.batch, revision: Long=s.revision,
    phase: Phase=s.phase,reason: String=s.reason,attempts: Int=s.attempts,first: Long?=s.firstAttemptAt,
    observed: Long=s.lastObservedAt,notBefore: Long?=s.notBefore,active: Attempt?=s.activeAttempt,
    uncertain: Boolean=s.outcomeUncertain,receipts: List<VerifiedReceipt> = s.receipts,
    conflicts: List<VerifiedReceipt> = s.conflictingReceipts) =
    QueueSnapshot(batch,revision,phase,reason,attempts,first,observed,notBefore,active,uncertain,receipts,conflicts)

private var assertions=0
private var malformedInputs=0
private var processRuns=0
private val results=mutableListOf<Pair<String,String>>()
private fun yes(value: Boolean) { assertions++; check(value) { "assertion-$assertions" } }
private fun test(name: String, body: ()->Unit) {
    try { body(); results+=name to "passed" }
    catch(e: Throwable) { results+=name to "failed"; System.err.println("FAILED $name: ${e.javaClass.simpleName}: ${e.message}"); e.printStackTrace(System.err) }
}
private fun rejected(bytes: ByteArray,code: DecodeCode?=null) {
    malformedInputs++
    try { SnapshotCodec.decode(bytes); error("accepted-malformed-input") }
    catch(e: SnapshotFormatException) { yes(code==null || e.code==code) }
}
private fun invalid(s: QueueSnapshot) {
    try { SnapshotCodec.encode(s); error("accepted-invalid-state") }
    catch(e: SnapshotFormatException) { yes(e.code==DecodeCode.INVARIANT) }
}
private fun reseal(bytes: ByteArray): ByteArray {
    val prefix=bytes.copyOfRange(0,bytes.size-32)
    return prefix+MessageDigest.getInstance("SHA-256").digest(prefix)
}
private fun replace(bytes: ByteArray,old: String,new: String): ByteArray {
    require(old.length==new.length)
    fun raw(s: String)=ByteBuffer.allocate(s.length*2).also { b -> s.forEach { b.putChar(it) } }.array()
    val from=raw(old); val to=raw(new); val out=bytes.copyOf()
    val at=(12..out.size-32-from.size).first { i -> from.indices.all { out[i+it]==from[it] } }
    to.copyInto(out,at); return reseal(out)
}
private enum class Fault { NONE, BEFORE, UNKNOWN_BEFORE, UNKNOWN_AFTER, THROW_BEFORE, THROW_AFTER, PARTIAL, CONFLICT }
private class MemoryJournal(initial: ByteArray): AppendJournalPort {
    var bytes=initial.copyOf()
    var fault=Fault.NONE
    var missing=false
    var unavailable=false
    @Synchronized override fun read(): JournalRead = when { missing -> JournalRead.Missing; unavailable -> JournalRead.Unavailable; else -> JournalRead.Bytes(bytes) }
    @Synchronized override fun append(expectedContentHash: String,record: ByteArray): StoreWrite {
        if(EvidenceHash.sha256(bytes)!=expectedContentHash) return StoreWrite.REVISION_CONFLICT
        val f=fault; fault=Fault.NONE
        when(f) {
            Fault.BEFORE -> return StoreWrite.NOT_COMMITTED
            Fault.UNKNOWN_BEFORE -> return StoreWrite.UNKNOWN
            Fault.THROW_BEFORE -> error("injected-before")
            Fault.CONFLICT -> return StoreWrite.REVISION_CONFLICT
            Fault.PARTIAL -> { bytes+=record.copyOfRange(0,record.size/2); return StoreWrite.UNKNOWN }
            else -> Unit
        }
        bytes+=record
        if(f==Fault.THROW_AFTER) error("injected-after")
        return if(f==Fault.UNKNOWN_AFTER) StoreWrite.UNKNOWN else StoreWrite.COMMITTED
    }
}
private class Setup(val b: UploadBatch=batch()) {
    val port=MemoryJournal(JournalFormat.empty(b.scope))
    val store=JournalQueueStore(port,b.scope)
    val driver=CommitDriver(store,machine(b))
    fun capture()=driver.capture(b,1000)
    fun get()=(store.read(b.key) as StoreRead.Present).snapshot
    fun step(a: QueueAction,now: Long=1000)=driver.advance(b.key,a,auth(b),now)
}
private fun chain(states: List<QueueSnapshot>): ByteArray {
    var bytes=JournalFormat.empty(states.first().batch.scope)
    for(s in states) bytes+=JournalFormat.record(JournalFormat.replay(bytes,s.batch.scope),s)
    return bytes
}
private fun readyAndSent(b: UploadBatch=batch()): Pair<QueueSnapshot,QueueSnapshot> {
    val r=initial(b); return r to move(r,QueueAction.SendOriginal)
}
private fun child(args: Array<String>) {
    val command=args[0]; val dir=Path.of(args[1]); val b=batch(); val port=HostFileJournal(dir)
    val store=JournalQueueStore(port,b.scope); val driver=CommitDriver(store,machine(b))
    when(command) {
        "child-capture" -> { check(driver.capture(b,1000).status=="CAPTURE_COMMITTED"); println("captured") }
        "child-send" -> { val r=driver.advance(b.key,QueueAction.SendOriginal,auth(b),1000); check(r.effect is QueueEffect.UploadOriginal); println("reserved") }
        "child-restore" -> { val r=driver.advance(b.key,QueueAction.Restore,auth(b),1100); check(r.snapshot?.phase==Phase.RETRY_WAIT && r.effect==QueueEffect.None); println("restored") }
        "child-inspect" -> { val s=(store.read(b.key) as StoreRead.Present).snapshot; println("${s.phase}:${s.attempts}:${s.batch.payloadHash}") }
        "child-stage-ack" -> {
            val s=(store.read(b.key) as StoreRead.Present).snapshot
            val r=driver.advance(b.key,QueueAction.Response(s.activeAttempt!!,ack(b)),auth(b),2200)
            check(r.snapshot?.phase==Phase.ACK_PENDING); println("staged")
        }
        "child-finalize" -> { val r=driver.advance(b.key,QueueAction.FinalizeAcknowledgement,auth(b),2300); check(r.snapshot?.phase==Phase.ACKNOWLEDGED); println("finalized") }
        "child-race" -> {
            val start=args[2].toLong(); while(System.currentTimeMillis()<start) Thread.sleep(5)
            val r=driver.advance(b.key,QueueAction.SendOriginal,auth(b),1000)
            println(if(r.effect is QueueEffect.UploadOriginal) "send" else "no-send")
        }
        "child-halt-partial" -> {
            val interrupted=HostFileJournal(dir,HostWriteFault { if(it==HostWriteStage.AFTER_PARTIAL_APPEND) Runtime.getRuntime().halt(71) })
            CommitDriver(JournalQueueStore(interrupted,b.scope),machine(b)).advance(b.key,QueueAction.SendOriginal,auth(b),1000)
            error("halt-not-triggered")
        }
        "child-halt-forced" -> {
            val interrupted=HostFileJournal(dir,HostWriteFault { if(it==HostWriteStage.AFTER_FORCE) Runtime.getRuntime().halt(72) })
            CommitDriver(JournalQueueStore(interrupted,b.scope),machine(b)).advance(b.key,QueueAction.SendOriginal,auth(b),1000)
            error("halt-not-triggered")
        }
        else -> error("unknown-child-command")
    }
}
private fun startChild(command: String,dir: Path,extra: String?=null): Process {
    processRuns++
    val args=mutableListOf(Path.of(System.getProperty("java.home"),"bin","java").toString(),"-cp",System.getProperty("java.class.path"),
        "rw.ikanisa.sms.persistence.tests.PersistenceChecksKt",command,dir.toString())
    if(extra!=null) args+=extra
    return ProcessBuilder(args).redirectErrorStream(true).start()
}
private fun finish(p: Process,expected: Int=0): String {
    check(p.waitFor(20,java.util.concurrent.TimeUnit.SECONDS)) { "child-timeout" }
    val out=p.inputStream.bufferedReader().readText().trim()
    check(p.exitValue()==expected) { "child-exit-${p.exitValue()}:$out" }
    return out
}
private fun runChild(command: String,dir: Path,expected: Int=0)=finish(startChild(command,dir),expected)

fun main(args: Array<String>) {
    if(args.isNotEmpty() && args[0].startsWith("child-")) { child(args); return }
    for(c in Contract.values()) {
        val b=batch(c); val (r,s)=readyAndSent(b)
        val pending=move(s,QueueAction.Response(s.activeAttempt!!,ack(b)),1100)
        val acknowledged=move(pending,QueueAction.FinalizeAcknowledgement,1200)
        val conflict=move(acknowledged,QueueAction.Response(s.activeAttempt,ack(b,uuid(901))),1300)
        val wait=move(s,QueueAction.Failure(s.activeAttempt,503),1100)
        val held=move(s,QueueAction.Failure(s.activeAttempt,401),1100)
        val states=mutableListOf(r,s,pending,acknowledged,conflict,wait,held)
        if(c==Contract.MMONEY_LEDGER_V1) {
            val reject=move(s,QueueAction.Response(s.activeAttempt,ack(b,rejected=true)),1100)
            states+=move(reject,QueueAction.FinalizeAcknowledgement,1200)
        }
        for(st in states) test("codec/$c/${st.phase}") {
            val bytes=SnapshotCodec.encode(st); val restored=SnapshotCodec.decode(bytes)
            yes(bytes.contentEquals(SnapshotCodec.encode(restored)))
            yes(restored.batch.originals.single().assembly.input.parts==st.batch.originals.single().assembly.input.parts)
            yes(restored.batch.payloadHash==st.batch.payloadHash && restored.activeAttempt==st.activeAttempt)
            yes(restored.receipts==st.receipts && restored.conflictingReceipts==st.conflictingReceipts)
            yes(restored.phase==st.phase && restored.reason==st.reason && restored.revision==st.revision)
        }
        test("journal/$c/full-acknowledgement-history") {
            val bytes=chain(listOf(r,s,pending,acknowledged,conflict))
            val restored=JournalFormat.replay(bytes,b.scope)
            yes(restored.recordCount==5 && restored.snapshots.size==1)
            yes(restored.snapshots[b.key]!!.phase==Phase.CONFLICT)
        }
    }
    test("codec/multipart-observation-order-and-PDU-case") {
        val first=SmsPart(1,2,55,8,"M-Money",BODY.take(30),1000,7,0,null,true,"aAbB")
        val last=first.copy(sequence=2,body=BODY.drop(30),pduHex="bBcC")
        val s=initial(batch(parts=listOf(last,first)))
        val out=SnapshotCodec.decode(SnapshotCodec.encode(s))
        yes(out.batch.originals.single().assembly.input.parts==listOf(last,first))
        yes(out.batch.originals.single().body==BODY)
    }
    test("codec/provider-body-never-gains-PDU-completeness") {
        val p=SmsPart(null,null,null,null,"M-Money",BODY,1000,7,null,null,false,null)
        val s=initial(batch(Contract.MMONEY_LEDGER_V1,parts=listOf(p),mode=InputMode.PROVIDER))
        val o=SnapshotCodec.decode(SnapshotCodec.encode(s)).batch.originals.single()
        yes(o.assembly.completeness==Completeness.PROVIDER_BODY_ONLY)
        yes(o.assembly.input.parts.single()==p)
    }
    test("codec/raw-null-empty-and-invalid-code-unit-metadata") {
        // Provider metadata is retained as evidence, not interpreted as live-PDU proof.
        val p=SmsPart(null,null,0,null,"M-Money",BODY,null,7,null,"\ud800",false,"")
        val s=initial(batch(Contract.MMONEY_LEDGER_V1,parts=listOf(p),mode=InputMode.PROVIDER))
        val restored=SnapshotCodec.decode(SnapshotCodec.encode(s))
        yes(restored.batch.originals.single().assembly.input.parts.single()==p)
        yes(restored.batch.originals.single().evidenceHash==s.batch.originals.single().evidenceHash)
    }
    val valid=SnapshotCodec.encode(initial())
    test("codec/every-truncation-offset") { for(i in valid.indices) rejected(valid.copyOf(i)) }
    test("codec/every-single-byte-corruption") {
        for(i in valid.indices) { val copy=valid.copyOf(); copy[i]=(copy[i].toInt() xor 1).toByte(); rejected(copy) }
    }
    test("codec/unsupported-version") { val copy=valid.copyOf(); ByteBuffer.wrap(copy).putInt(4,99); rejected(copy,DecodeCode.VERSION) }
    test("codec/trailing-bytes") { rejected(valid+byteArrayOf(1,2),DecodeCode.SIZE) }
    test("codec/negative-and-overflow-lengths") {
        for(n in listOf(-1,Int.MIN_VALUE,Int.MAX_VALUE,SnapshotCodec.MAX_BYTES)) {
            val copy=valid.copyOf(); ByteBuffer.wrap(copy).putInt(8,n); rejected(copy,DecodeCode.SIZE)
        }
    }
    test("codec/resealed-invalid-string-count") {
        val copy=valid.copyOf(); ByteBuffer.wrap(copy).putInt(12,Int.MAX_VALUE); rejected(reseal(copy),DecodeCode.SIZE)
    }
    test("codec/resealed-unknown-enum") { rejected(replace(valid,"READY","XXXXX"),DecodeCode.STRUCTURE) }
    test("codec/resealed-derived-evidence-hash") {
        rejected(replace(valid,initial().batch.originals.single().evidenceHash,"f".repeat(64)),DecodeCode.INVARIANT)
    }
    test("codec/resealed-derived-classification-fingerprint") {
        rejected(replace(valid,initial().batch.originals.single().classification.evidenceFingerprint,"e".repeat(64)),DecodeCode.INVARIANT)
    }
    test("codec/deterministic-random-malformed-inputs") {
        val random=Random(309)
        repeat(1000) { rejected(random.nextBytes(random.nextInt(0,3000))) }
    }
    test("codec/unknown-boolean-tag") {
        val r=BinaryReader(byteArrayOf(2)); try { r.bool(); error("bad-boolean") } catch(e: SnapshotFormatException) { yes(e.code==DecodeCode.STRUCTURE) }
    }
    val (ready,sent)=readyAndSent()
    val pending=move(sent,QueueAction.Response(sent.activeAttempt!!,ack(sent.batch)),1100)
    val acknowledged=move(pending,QueueAction.FinalizeAcknowledgement,1200)
    for((name,s) in listOf(
        "negative-revision" to stateCopy(ready,revision=-1),
        "ready-with-attempt" to stateCopy(sent,phase=Phase.READY),
        "held-without-attempt" to stateCopy(ready,phase=Phase.HELD),
        "unsafe-diagnostic" to stateCopy(ready,reason=BODY),
        "ack-with-no-receipt" to stateCopy(sent,phase=Phase.ACKNOWLEDGED),
        "invalid-conflict-coverage" to stateCopy(acknowledged,phase=Phase.CONFLICT,conflicts=listOf(VerifiedReceipt("wrong",ReceiptOutcome.RETAINED,"x","bad",null))),
        "identical-conflict-receipts" to stateCopy(acknowledged,phase=Phase.CONFLICT,conflicts=acknowledged.receipts),
        "attempt-identity" to stateCopy(sent,active=sent.activeAttempt.copy(operationId="wrong")),
        "clock-order" to stateCopy(sent,observed=0),
        "counter-reset" to stateCopy(sent,attempts=0)
    )) test("codec/invariant-$name") { invalid(s) }

    test("journal/missing-is-not-empty-and-never-auto-provisioned") {
        val x=Setup(); x.port.missing=true; val before=x.port.bytes.copyOf()
        yes(x.capture().status=="STORAGE_BLOCKED")
        yes(x.port.bytes.contentEquals(before))
        yes(x.store.inspect()==JournalInspection.Blocked("JOURNAL_MISSING"))
    }
    test("journal/unavailable-read-never-captures") { val x=Setup(); x.port.unavailable=true; yes(x.capture().status=="STORAGE_BLOCKED") }
    test("journal/wrong-owner-generation-installation-contract") {
        val bytes=chain(listOf(ready))
        for(s in listOf(ready.batch.scope.copy(ownerId="other"),ready.batch.scope.copy(generation="other"),
            ready.batch.scope.copy(installationId="other"),ready.batch.scope.copy(contract=Contract.MMONEY_LEDGER_V1))) {
            val store=JournalQueueStore(MemoryJournal(bytes),s)
            yes(store.read(ready.batch.key)==StoreRead.Corrupt)
            yes((store.inspect() as JournalInspection.Blocked).reason=="JOURNAL_SCOPE")
        }
    }
    test("journal/replay-stable-original-and-ack-tombstone") {
        val x=Setup(); yes(x.capture().status=="CAPTURE_COMMITTED"); yes(x.capture().status=="CAPTURE_ALREADY_RETAINED")
        val send=x.step(QueueAction.SendOriginal); val effect=send.effect as QueueEffect.UploadOriginal
        yes(x.step(QueueAction.Response(effect.attempt,ack(x.b)),1100).snapshot?.phase==Phase.ACK_PENDING)
        yes(x.step(QueueAction.FinalizeAcknowledgement,1200).snapshot?.phase==Phase.ACKNOWLEDGED)
        val rebuilt=JournalQueueStore(x.port,x.b.scope)
        yes((rebuilt.read(x.b.key) as StoreRead.Present).snapshot.batch.payloadHash==x.b.payloadHash)
        yes(x.capture().status=="CAPTURE_ALREADY_RETAINED")
        yes(x.step(QueueAction.SendOriginal,1300).effect==QueueEffect.None)
    }
    test("journal/mmoney-source-body-duplicate-atomic-admission") {
        val x=Setup(batch(Contract.MMONEY_LEDGER_V1)); x.capture()
        val duplicate=batch(Contract.MMONEY_LEDGER_V1,2,source="source-1")
        val before=x.port.bytes.copyOf(); yes(x.driver.capture(duplicate,1000).status=="ORIGINAL_ALREADY_BOUND")
        yes(before.contentEquals(x.port.bytes))
        val rebatch=UploadBatch(uuid(888),x.b.originals)
        yes(x.driver.capture(rebatch,1000).status=="ORIGINAL_ALREADY_BOUND")
    }
    test("journal/mmoney-duplicates-within-new-batch") {
        val one=batch(Contract.MMONEY_LEDGER_V1,1,source="same").originals.single()
        val two=batch(Contract.MMONEY_LEDGER_V1,2,source="same").originals.single()
        val x=Setup(UploadBatch(uuid(950),listOf(one,two)))
        yes(x.capture().status=="ORIGINAL_ALREADY_BOUND")
        yes(JournalFormat.replay(x.port.bytes,x.b.scope).snapshots.isEmpty())
    }
    test("journal/immutable-classification-cannot-change-on-CAS") {
        val x=Setup(); x.capture(); val s=x.get(); val o=x.b.originals.single()
        val changed=Original(o.scope,o.binding,o.captureId,o.sourceId,o.assembly,o.classification.copy(policyVersion="other"))
        val changedBatch=UploadBatch(x.b.operationId,listOf(changed))
        val next=move(s,QueueAction.SendOriginal)
        yes(x.store.compareAndSet(x.b.key,0,stateCopy(next,batch=changedBatch))==StoreWrite.REVISION_CONFLICT)
        yes(x.get().revision==0L)
    }
    test("journal/CAS-refuses-clock-revision-attempt-and-receipt-rollback") {
        yes(!JournalHistory.follows(ready,stateCopy(sent,revision=2)))
        yes(!JournalHistory.follows(sent,stateCopy(sent,revision=2)))
        yes(!JournalHistory.follows(acknowledged,stateCopy(ready,revision=4)))
        yes(!JournalHistory.follows(pending,stateCopy(acknowledged,receipts=listOf(VerifiedReceipt(ready.batch.originals.single().captureId,ReceiptOutcome.RETAINED,"other",ready.batch.originals.single().bodySha256,null)))))
    }
    test("journal/complete-record-reordering-rejected") {
        val header=JournalFormat.empty(ready.batch.scope)
        val f1=JournalFormat.record(JournalFormat.replay(header,ready.batch.scope),ready)
        val f2=JournalFormat.record(JournalFormat.replay(header+f1,ready.batch.scope),sent)
        val port=MemoryJournal(header+f2+f1); yes(JournalQueueStore(port,ready.batch.scope).read(ready.batch.key)==StoreRead.Corrupt)
    }
    test("journal/every-partial-tail-offset-blocks-without-mutation") {
        val prefix=chain(listOf(ready)); val frame=JournalFormat.record(JournalFormat.replay(prefix,ready.batch.scope),sent)
        for(i in 1 until frame.size) {
            val bytes=prefix+frame.copyOf(i); val p=MemoryJournal(bytes); val store=JournalQueueStore(p,ready.batch.scope)
            yes(store.read(ready.batch.key)==StoreRead.Corrupt)
            yes(store.compareAndSet(ready.batch.key,0,sent)==StoreWrite.NOT_COMMITTED)
            yes(p.bytes.contentEquals(bytes))
        }
    }
    test("journal/damaged-committed-record-is-not-skipped") {
        val bytes=chain(listOf(ready,sent,pending,acknowledged)); bytes[100]=(bytes[100].toInt() xor 1).toByte()
        val p=MemoryJournal(bytes); val store=JournalQueueStore(p,ready.batch.scope)
        yes(store.read(ready.batch.key)==StoreRead.Corrupt); yes(p.bytes.contentEquals(bytes))
    }
    test("journal/schema-version-is-not-guessed-or-upgraded") {
        val bytes=chain(listOf(ready)); ByteBuffer.wrap(bytes).putInt(4,99)
        val p=MemoryJournal(bytes); yes((JournalQueueStore(p,ready.batch.scope).inspect() as JournalInspection.Blocked).reason=="JOURNAL_VERSION")
        yes(bytes.contentEquals(p.bytes))
    }
    for(f in Fault.values().filter { it!=Fault.NONE }) for(stage in listOf("capture","reserve","stage-ack","finalize")) {
        test("fault/$stage/$f") {
            val x=Setup()
            if(stage!="capture") x.capture()
            if(stage in listOf("stage-ack","finalize")) x.step(QueueAction.SendOriginal)
            if(stage=="finalize") x.step(QueueAction.Response(x.get().activeAttempt!!,ack(x.b)),1100)
            val before=x.port.bytes.copyOf()
            val action=when(stage) {
                "reserve" -> QueueAction.SendOriginal
                "stage-ack" -> QueueAction.Response(x.get().activeAttempt!!,ack(x.b))
                "finalize" -> QueueAction.FinalizeAcknowledgement
                else -> null
            }
            x.port.fault=f
            val result=if(action==null) x.capture() else x.step(action,1200)
            yes(result.effect==QueueEffect.None)
            yes(result.status !in setOf("CAPTURE_COMMITTED","ORIGINAL_RESERVED","ACK_VALIDATED","ACK_COMMITTED"))
            yes(x.port.bytes.take(before.size)==before.toList())
            if(f==Fault.PARTIAL) yes(x.store.read(x.b.key)==StoreRead.Corrupt)
            if(f in setOf(Fault.UNKNOWN_AFTER,Fault.THROW_AFTER)) {
                val restored=x.get(); yes(restored.batch.payloadHash==x.b.payloadHash)
                if(stage=="reserve") { val recovery=x.step(QueueAction.Restore,1300); yes(recovery.effect==QueueEffect.None && recovery.snapshot?.outcomeUncertain==true) }
                if(stage=="stage-ack") yes(restored.phase==Phase.ACK_PENDING)
                if(stage=="finalize") yes(restored.phase==Phase.ACKNOWLEDGED)
            }
        }
    }
    test("journal/two-concurrent-reservations-emit-at-most-one-send") {
        val x=Setup(); x.capture(); val start=CountDownLatch(1); val out=CopyOnWriteArrayList<DriverResult>()
        val threads=List(2) { Thread { start.await(); val driver=CommitDriver(JournalQueueStore(x.port,x.b.scope),machine(x.b)); out+=driver.advance(x.b.key,QueueAction.SendOriginal,auth(x.b),1000) } }
        threads.forEach { it.start() }; start.countDown(); threads.forEach { it.join() }
        yes(out.count { it.effect is QueueEffect.UploadOriginal }==1); yes(x.get().attempts==1)
    }
    test("dispatch/lease-and-current-authority-gate") {
        val b=sent.batch; val machine=machine(b); val effect=QueueEffect.UploadOriginal(sent.activeAttempt!!,b)
        yes(ReservationGate.permitted(effect,sent,auth(b),1000,machine))
        yes(!ReservationGate.permitted(effect,sent,auth(b),999,machine))
        yes(!ReservationGate.permitted(effect,sent,auth(b),1000+machine.limits.leaseMs,machine))
        yes(!ReservationGate.permitted(effect,sent,auth(b).copy(sessionEpoch=2),1000,machine))
        yes(!ReservationGate.permitted(effect,sent,auth(b).copy(enabled=false),1000,machine))
        yes(!ReservationGate.permitted(effect,sent,auth(b).copy(sim=SimState(true,setOf(8))),1000,machine))
        yes(!ReservationGate.permitted(effect,pending,auth(b),1100,machine))
    }
    test("privacy/diagnostics-do-not-print-raw-evidence") {
        yes(!SnapshotFormatException(DecodeCode.INVARIANT).toString().contains(BODY))
        yes(!JournalRead.Bytes(valid).toString().contains(BODY))
        yes(!JournalFormat.replay(chain(listOf(ready)),ready.batch.scope).toString().contains(BODY))
    }
    val parent=Files.createTempDirectory("sms-r3-host-")
    fun dir(name: String): Path=parent.resolve(name)
    test("host/explicit-fresh-provisioning-and-permissions") {
        val d=dir("provision"); HostFileJournal.initializeFresh(d,ready.batch.scope)
        yes(Files.getPosixFilePermissions(d)==PosixFilePermissions.fromString("rwx------"))
        yes(Files.getPosixFilePermissions(d.resolve("queue.journal"))==PosixFilePermissions.fromString("rw-------"))
        val before=Files.readAllBytes(d.resolve("queue.journal"))
        yes(runCatching { HostFileJournal.initializeFresh(d,ready.batch.scope) }.isFailure)
        yes(before.contentEquals(Files.readAllBytes(d.resolve("queue.journal"))))
    }
    test("host/missing-file-is-not-recreated") {
        val d=dir("missing"); Files.createDirectory(d)
        val store=JournalQueueStore(HostFileJournal(d),ready.batch.scope)
        yes(store.read(ready.batch.key)==StoreRead.Unavailable)
        yes(store.createIfUnbound(ready)==StoreWrite.NOT_COMMITTED)
        yes(!Files.exists(d.resolve("queue.journal")))
        yes(runCatching { HostFileJournal.initializeFresh(d,ready.batch.scope) }.isFailure)
    }
    test("host/symlink-refusal") {
        val real=dir("real"); HostFileJournal.initializeFresh(real,ready.batch.scope)
        val link=dir("link"); Files.createSymbolicLink(link,real)
        yes(HostFileJournal(link).read()==JournalRead.Unavailable)
        yes(runCatching { HostFileJournal.initializeFresh(link,ready.batch.scope) }.isFailure)
        val d=dir("link-file"); Files.createDirectory(d); Files.createSymbolicLink(d.resolve("queue.journal"),real.resolve("queue.journal"))
        yes(HostFileJournal(d).read()==JournalRead.Unavailable)
    }
    for(stage in HostWriteStage.values()) test("host/write-fault-$stage") {
        val d=dir("fault-$stage"); HostFileJournal.initializeFresh(d,ready.batch.scope)
        val clean=JournalQueueStore(HostFileJournal(d),ready.batch.scope)
        yes(clean.createIfUnbound(ready)==StoreWrite.COMMITTED)
        val before=Files.readAllBytes(d.resolve("queue.journal"))
        val faulty=HostFileJournal(d,HostWriteFault { if(it==stage) error("injected") })
        val result=CommitDriver(JournalQueueStore(faulty,ready.batch.scope),machine(ready.batch)).advance(ready.batch.key,QueueAction.SendOriginal,auth(ready.batch),1000)
        yes(result.effect==QueueEffect.None)
        val after=Files.readAllBytes(d.resolve("queue.journal")); yes(after.take(before.size)==before.toList())
        if(stage==HostWriteStage.AFTER_PARTIAL_APPEND) yes(clean.read(ready.batch.key)==StoreRead.Corrupt)
        if(stage in setOf(HostWriteStage.AFTER_APPEND,HostWriteStage.AFTER_FORCE)) yes((clean.read(ready.batch.key) as StoreRead.Present).snapshot.phase==Phase.IN_FLIGHT)
    }
    test("host/separate-process-capture-reservation-restore-and-ack-finalization") {
        val d=dir("restart"); HostFileJournal.initializeFresh(d,ready.batch.scope)
        yes(runChild("child-capture",d)=="captured")
        yes(runChild("child-send",d)=="reserved")
        yes(runChild("child-inspect",d)=="IN_FLIGHT:1:${ready.batch.payloadHash}")
        yes(runChild("child-restore",d)=="restored")
        yes(runChild("child-inspect",d)=="RETRY_WAIT:1:${ready.batch.payloadHash}")
        yes(runChild("child-stage-ack",d)=="staged")
        yes(runChild("child-finalize",d)=="finalized")
        yes(runChild("child-inspect",d)=="ACKNOWLEDGED:1:${ready.batch.payloadHash}")
    }
    test("host/separate-process-write-contention") {
        val d=dir("process-race"); HostFileJournal.initializeFresh(d,ready.batch.scope); runChild("child-capture",d)
        val start=(System.currentTimeMillis()+900).toString()
        val one=startChild("child-race",d,start); val two=startChild("child-race",d,start)
        val outcomes=listOf(finish(one),finish(two)); yes(outcomes.count { it=="send" }==1)
        yes(runChild("child-inspect",d).startsWith("IN_FLIGHT:1:"))
    }
    test("host/abrupt-process-death-during-partial-append") {
        val d=dir("halt-partial"); HostFileJournal.initializeFresh(d,ready.batch.scope); runChild("child-capture",d)
        runChild("child-halt-partial",d,71)
        val before=Files.readAllBytes(d.resolve("queue.journal")); val store=JournalQueueStore(HostFileJournal(d),ready.batch.scope)
        yes(store.read(ready.batch.key)==StoreRead.Corrupt)
        yes(store.compareAndSet(ready.batch.key,0,sent)==StoreWrite.NOT_COMMITTED)
        yes(before.contentEquals(Files.readAllBytes(d.resolve("queue.journal"))))
    }
    test("host/abrupt-process-death-after-force-before-result") {
        val d=dir("halt-forced"); HostFileJournal.initializeFresh(d,ready.batch.scope); runChild("child-capture",d)
        runChild("child-halt-forced",d,72)
        yes(runChild("child-inspect",d).startsWith("IN_FLIGHT:1:"))
        yes(runChild("child-restore",d)=="restored")
        yes(runChild("child-inspect",d).startsWith("RETRY_WAIT:1:"))
    }
    // Temporary synthetic fixture cleanup only. Production storage exposes NO deletion operation.
    Files.walk(parent).use { paths -> paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) } }
    val failed=results.count { it.second=="failed" }
    val items=results.joinToString(",") { "{\"name\":\"${it.first}\",\"status\":\"${it.second}\"}" }
    println("{\"status\":\"${if(failed==0) "passed" else "failed"}\",\"tests\":${results.size},\"assertions\":$assertions,\"failed\":$failed,\"malformed_inputs\":$malformedInputs,\"child_processes\":$processRuns,\"cases\":[$items]}")
    if(failed>0) kotlin.system.exitProcess(1)
}
