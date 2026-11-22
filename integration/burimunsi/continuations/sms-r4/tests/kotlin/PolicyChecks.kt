package rw.ikanisa.sms.policy.tests

import rw.ikanisa.sms.policy.*
import rw.ikanisa.sms.adapters.burimunsi.BuriSmsClassifier
import rw.ikanisa.sms.adapters.mmoney.MmoneySmsClassifier
import rw.ikanisa.burimunsi.core.ReceiptProfile
import rw.ikanisa.burimunsi.core.ReceiptParser
import java.io.File
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.random.Random

private val buri = BuriSmsClassifier()
private val mm = MmoneySmsClassifier()
private const val GOOD = "You have received 1,000 RWF from Test Person (*****007) at 2026-11-09 09:30:00. Balance: 2,000 RWF. FT Id: 123456789."
private fun uuid(n: Int) = "10000000-0000-4000-8000-"+n.toString().padStart(12,'0')
private fun part(body: String? = GOOD,sender: String? = "M-Money") = SmsPart(1,1,null,null,sender,body,1000,7,0,null,true,"00")
private fun assembly(body: String? = GOOD,sender: String? = "M-Money",mode: InputMode = InputMode.LIVE): Assembly =
    MultipartPolicy.inspect(SmsInput(mode,if (mode == InputMode.LIVE) "3gpp" else null,listOf(part(body,sender))))
private fun original(contract: Contract = Contract.BURI_COLLECT_V2,n: Int = 1,body: String = GOOD,
    mode: InputMode = InputMode.LIVE,binding: SourceBinding = SourceBinding("binding",1,7),
    scope: OwnerScope = OwnerScope(contract,"owner","installation","generation"),source: String = "source"): Original {
    val a=assembly(body,mode=mode)
    return Original(scope,binding,uuid(n),source,a,(if (contract==Contract.BURI_COLLECT_V2) buri else mm).classify(a))
}
private fun batch(contract: Contract = Contract.BURI_COLLECT_V2,n: Int = 1): UploadBatch =
    UploadBatch(uuid(if (contract == Contract.BURI_COLLECT_V2) n else n+100),listOf(original(contract,n)))
private fun authority(b: UploadBatch) = Authority(b.scope,b.binding,1,SimState(true,setOf(7,8)))
private fun machine(contract: Contract,limits: RetryLimits = RetryLimits()) = QueueMachine(if(contract==Contract.BURI_COLLECT_V2) buri else mm,limits)
private fun ack(b: UploadBatch,canonical: String = uuid(800)): Map<String,Any?> = when(b.scope.contract) {
    Contract.BURI_COLLECT_V2 -> mapOf("ok" to true,"receipt" to mapOf("contract_version" to 2,"stored" to true,
        "owner_user_id" to b.scope.ownerId,"client_envelope_id" to b.originals.single().captureId,
        "raw_sms_id" to canonical,"body_sha256" to b.originals.single().bodySha256))
    Contract.MMONEY_LEDGER_V1 -> mapOf("schemaVersion" to 1,"acknowledgements" to b.originals.map {
        mapOf("id" to it.captureId,"status" to "accepted","canonicalId" to canonical)
    })
}
private fun changeReceipt(raw: Map<String,Any?>,field: String,value: Any?,remove: Boolean = false): Map<String,Any?> {
    @Suppress("UNCHECKED_CAST") val receipt=(raw["receipt"] as Map<String,Any?>).toMutableMap()
    if(remove) receipt.remove(field) else receipt[field]=value
    return raw+mapOf("receipt" to receipt)
}
private fun changeMm(raw: Map<String,Any?>,field: String,value: Any?,remove: Boolean=false): Map<String,Any?> {
    @Suppress("UNCHECKED_CAST") val rows=(raw["acknowledgements"] as List<Map<String,Any?>>).map { it.toMutableMap() }
    if(remove) rows.first().remove(field) else rows.first()[field]=value
    return raw+mapOf("acknowledgements" to rows)
}
private enum class Fault { NONE, BEFORE_FAIL, BEFORE_UNKNOWN, AFTER_UNKNOWN, THROW_BEFORE, THROW_AFTER, CAS_CONFLICT }
/** Synthetic persistence oracle. No Android, disk or database claims are made by this class. */
private class MemoryStore: QueueStorePort {
    private val entries=mutableMapOf<String,QueueSnapshot>()
    var fault=Fault.NONE
    var corrupt=false
    var unavailable=false
    var throwRead=false
    @Synchronized override fun read(key: String): StoreRead {
        if(throwRead) throw IllegalStateException("synthetic-read-fault")
        return when { corrupt -> StoreRead.Corrupt; unavailable -> StoreRead.Unavailable
            else -> entries[key]?.let(StoreRead::Present) ?: StoreRead.Missing }
    }
    private fun persist(block: () -> Unit): StoreWrite {
        val f=fault;fault=Fault.NONE
        when(f) {
            Fault.BEFORE_FAIL -> return StoreWrite.NOT_COMMITTED
            Fault.BEFORE_UNKNOWN -> return StoreWrite.UNKNOWN
            Fault.THROW_BEFORE -> throw IllegalStateException("synthetic-write-fault")
            Fault.CAS_CONFLICT -> return StoreWrite.REVISION_CONFLICT
            else -> Unit
        }
        block()
        if(f==Fault.THROW_AFTER) throw IllegalStateException("synthetic-commit-result-lost")
        return if(f==Fault.AFTER_UNKNOWN) StoreWrite.UNKNOWN else StoreWrite.COMMITTED
    }
    @Synchronized override fun createIfUnbound(initial: QueueSnapshot): StoreWrite {
        when(BatchAdmissionPolicy.decide(initial.batch,entries.values.toList())) {
            BatchAdmission.NEW -> Unit
            BatchAdmission.ORIGINAL_ALREADY_BOUND -> return StoreWrite.ORIGINAL_ALREADY_BOUND
            else -> return StoreWrite.REVISION_CONFLICT
        }
        return persist { entries[initial.batch.key]=initial }
    }
    @Synchronized override fun compareAndSet(key: String,expectedRevision: Long,next: QueueSnapshot): StoreWrite {
        val old=entries[key] ?: return StoreWrite.REVISION_CONFLICT
        if(old.revision != expectedRevision || next.revision != expectedRevision+1 || next.batch.payloadHash != old.batch.payloadHash || !next.valid())
            return StoreWrite.REVISION_CONFLICT
        return persist { entries[key]=next }
    }
    fun snapshot(b: UploadBatch)=(read(b.key) as StoreRead.Present).snapshot
}
private data class Setup(val batch: UploadBatch,val auth: Authority,val store: MemoryStore,val driver: CommitDriver) {
    fun advance(action: QueueAction,time: Long=1000)=driver.advance(batch.key,action,auth,time)
    fun snapshot()=store.snapshot(batch)
}
private fun setup(contract: Contract=Contract.BURI_COLLECT_V2,limits: RetryLimits=RetryLimits()): Setup {
    val b=batch(contract);val store=MemoryStore();val driver=CommitDriver(store,machine(contract,limits))
    check(driver.capture(b,1000).status=="CAPTURE_COMMITTED")
    return Setup(b,authority(b),store,driver)
}
private fun Setup.send(time: Long=1000): QueueEffect.UploadOriginal = advance(QueueAction.SendOriginal,time).effect as QueueEffect.UploadOriginal
private var assertions=0
private fun yes(value: Boolean) { assertions++; check(value) { "Assertion $assertions failed" } }
private val results=mutableListOf<Pair<String,Boolean>>()
private fun test(name: String,block: () -> Unit) {
    require(results.none { it.first==name })
    try { block();results+=name to true }
    catch(e: Throwable) { results+=name to false; System.err.println("FAIL $name (${e::class.simpleName}): ${e.message}"); e.printStackTrace(System.err) }
}
fun main(args: Array<String>) {
    val root=File(args.single())
    // Original JSON corpus is transported as bounded Base64 TSV, never normalized.
    for(line in File(root,"fixtures/classification.tsv").readLines().drop(1)) {
        val f=line.split('\t')
        test("fixture/${f[0]}") {
            val sender=if(f[2]=="-") null else String(Base64.getDecoder().decode(f[2]),Charsets.UTF_8)
            val body=String(Base64.getDecoder().decode(f[3]),Charsets.UTF_8)
            val a=assembly(body,sender)
            val c=(if(f[1]=="BURI_COLLECT_V2") buri else mm).classify(a)
            yes(c.kind.name==f[4]);yes(a.input.parts.single().body==body)
            if(c.eligible) { yes(a.body==body);yes(a.sender==sender) }
        }
    }
    test("evidence/defensive-copy") {
        val parts=mutableListOf(part());val input=SmsInput(InputMode.LIVE,"3gpp",parts); val hash=input.fingerprint
        parts.clear();yes(input.parts.size==1);yes(input.fingerprint==hash)
        yes(runCatching { (input.parts as MutableList).clear() }.isFailure)
        val list=mutableListOf(original());val b=UploadBatch(uuid(1),list);list.clear();yes(b.originals.size==1)
    }
    test("evidence/redacted-toString") {
        yes(!part().toString().contains("Test Person"));yes(!assembly().toString().contains(GOOD))
        yes(!original().toString().contains(GOOD));yes(!batch().toString().contains(GOOD))
    }
    test("evidence/framing-and-invalid-unicode") {
        yes(EvidenceHash.framed(listOf("a","bc"))!=EvidenceHash.framed(listOf("ab","c")))
        yes(EvidenceHash.framed(listOf(null))!=EvidenceHash.framed(listOf("")))
        yes(EvidenceHash.framed(listOf("\ud800"))!=EvidenceHash.framed(listOf("?")))
        yes(EvidenceHash.utf8("\ud800")==null);yes(EvidenceHash.utf8("\udc00")==null)
        yes(EvidenceHash.utf8("\u0000")==null);yes(EvidenceHash.utf8("\ud83d\ude00")!=null)
    }
    val p1=part("You have ").copy(total=2,reference=3,referenceBits=8)
    val p2=part("received 100 RWF.").copy(sequence=2,total=2,reference=3,referenceBits=8)
    fun inspect(parts: List<SmsPart>,format: String?="3gpp")=MultipartPolicy.inspect(SmsInput(InputMode.LIVE,format,parts))
    test("multipart/ordered-copy-preserves-observation-order") {
        val a=inspect(listOf(p2,p1));yes(a.completeness==Completeness.PDU_SET);yes(a.body=="You have received 100 RWF.")
        yes(a.input.parts==listOf(p2,p1))
    }
    val mutations=listOf(
        "empty" to emptyList(),"missing" to listOf(p1),"duplicate" to listOf(p1,p1),
        "sender" to listOf(p1,p2.copy(sender="Other")),"timestamp" to listOf(p1,p2.copy(serviceCentreMillis=2000)),
        "sim" to listOf(p1,p2.copy(subscriptionId=8)),"coding" to listOf(p1,p2.copy(dcs=8)),
        "reference" to listOf(p1,p2.copy(reference=4)),"width" to listOf(p1,p2.copy(referenceBits=16)),
        "total" to listOf(p1,p2.copy(total=3)),"zero-sequence" to listOf(p1,p2.copy(sequence=0)),
        "reference-range" to listOf(p1.copy(reference=256),p2.copy(reference=256)),
        "missing-reference" to listOf(p1.copy(reference=null),p2.copy(reference=null)),
        "body-null" to listOf(p1,p2.copy(body=null)),"timestamp-null" to listOf(p1,p2.copy(serviceCentreMillis=null)),
        "timestamp-zero" to listOf(part().copy(serviceCentreMillis=0)),"invalid-pdu" to listOf(part().copy(pduHex="0Z")),
        "missing-pdu" to listOf(part().copy(pduHex=null)),"binary" to listOf(part().copy(dcs=4)),
        "compressed" to listOf(part().copy(dcs=32)),"port" to listOf(part().copy(applicationPort="80")),
        "unvalidated" to listOf(part().copy(envelopeValidated=false)),"split-surrogate" to listOf(p1.copy(body="\ud800"),p2.copy(body="\udc00")),
        "oversized" to listOf(part("x".repeat(65537))),"utf8-oversized" to listOf(part("é".repeat(32769)))
    )
    for((name,parts) in mutations) test("multipart/reject-$name") {
        val a=inspect(parts);yes(a.completeness!=Completeness.PDU_SET);yes(a.body==null);yes(a.input.parts==parts)
    }
    test("multipart/unsupported-format") { yes(inspect(listOf(part()),"3gpp2").completeness==Completeness.UNSUPPORTED) }
    test("multipart/ucs2-and-wide-reference") {
        yes(inspect(listOf(part().copy(dcs=8))).completeness==Completeness.PDU_SET)
        yes(inspect(listOf(p1.copy(reference=300,referenceBits=16),p2.copy(reference=300,referenceBits=16))).completeness==Completeness.PDU_SET)
    }
    test("multipart/provider-not-pdu-proof") {
        val a=assembly(mode=InputMode.PROVIDER);yes(a.completeness==Completeness.PROVIDER_BODY_ONLY)
        yes(!buri.classify(a).eligible);yes(mm.classify(a).eligible)
    }
    test("classification/profile-refusal") {
        yes(!BuriSmsClassifier(ReceiptProfile("future",setOf("M-Money"),120)).classify(assembly()).eligible)
        yes(!BuriSmsClassifier(ReceiptProfile(ReceiptParser.VERSION,setOf("MTN"),120)).classify(assembly()).eligible)
        yes(!BuriSmsClassifier(ReceiptProfile(ReceiptParser.VERSION,setOf("M-Money"),841)).classify(assembly()).eligible)
    }
    test("classification/forged-positive-blocked") {
        val a=assembly("Your OTP is 1234")
        val o=Original(original().scope,original().binding,uuid(1),"source",a,
            Classification(Contract.BURI_COLLECT_V2,ClassificationKind.SUPPORTED_RECEIPT,"fake","fake",a.input.fingerprint))
        yes(!QueueMachine(buri).admits(UploadBatch(uuid(1),listOf(o))))
    }
    for(observed in listOf(null,-1,Int.MAX_VALUE,9)) test("sim/invalid-observed-$observed") {
        yes(SimPolicy.route(original().binding,observed,SimState(true,setOf(7,8)))==Route.HOLD_UNKNOWN)
    }
    for(bound in listOf(null,-1,Int.MAX_VALUE,9)) test("sim/invalid-binding-$bound") {
        yes(SimPolicy.route(SourceBinding("binding",1,bound),7,SimState(true,setOf(7,8)))==Route.HOLD_BINDING)
    }
    test("sim/permission-empty-and-other-sim") {
        val b=original().binding
        yes(SimPolicy.route(b,7,SimState(false,setOf(7)))==Route.HOLD_PERMISSION)
        yes(SimPolicy.route(b,7,SimState(true,null))==Route.HOLD_UNKNOWN)
        yes(SimPolicy.route(b,7,SimState(true,emptySet()))==Route.HOLD_BINDING)
        yes(SimPolicy.route(b,8,SimState(true,setOf(7,8)))==Route.OTHER_SIM)
        yes(SimPolicy.route(b,7,SimState(true,setOf(7,8)))==Route.ACCEPT)
        yes(SimPolicy.route(b,7,SimState(true,setOf(7)),false)==Route.HOLD_PROFILE)
    }
    test("duplicate/replay-even-when-full") {
        val o=original();val a=DuplicatePolicy.admit(o,listOf(o),1000)
        yes(a.kind==AdmissionKind.DUPLICATE);yes(a.retained===o)
    }
    test("duplicate/conflict-retains-both") {
        val old=original();val new=original(body=GOOD.replace("1,000","3,000"))
        val a=DuplicatePolicy.admit(new,listOf(old),1)
        yes(a.kind==AdmissionKind.CONFLICT);yes(a.retained===old);yes(a.incoming===new)
    }
    test("duplicate/mmoney-source-body-not-global") {
        val o=original(Contract.MMONEY_LEDGER_V1)
        yes(DuplicatePolicy.admit(original(Contract.MMONEY_LEDGER_V1,2),listOf(o),1).kind==AdmissionKind.DUPLICATE)
        yes(DuplicatePolicy.admit(original(Contract.MMONEY_LEDGER_V1,2,source="other"),listOf(o),1).kind==AdmissionKind.NEW)
        val changed=o.scope.copy(generation="new")
        yes(DuplicatePolicy.admit(original(Contract.MMONEY_LEDGER_V1,scope=changed),listOf(o),1).kind==AdmissionKind.NEW)
        val b=o.binding.copy(version=2)
        yes(DuplicatePolicy.admit(original(Contract.MMONEY_LEDGER_V1,2,binding=b),listOf(o),1).kind==AdmissionKind.CONFLICT)
    }
    test("duplicate/buri-does-not-use-body-as-payment-dedup") {
        yes(DuplicatePolicy.admit(original(n=2),listOf(original()),1).kind==AdmissionKind.NEW)
    }
    test("queue/capacity-reserve-and-corrupt-index") {
        val o=original();val p=original(Contract.MMONEY_LEDGER_V1,mode=InputMode.PROVIDER)
        yes(DuplicatePolicy.admit(o,emptyList(),999).kind==AdmissionKind.NEW)
        yes(DuplicatePolicy.admit(o,emptyList(),1000).kind==AdmissionKind.FULL)
        yes(DuplicatePolicy.admit(p,emptyList(),900).kind==AdmissionKind.RESERVED)
        yes(DuplicatePolicy.admit(p,emptyList(),1000).kind==AdmissionKind.FULL)
        yes(DuplicatePolicy.admit(o,listOf(o,o),2).kind==AdmissionKind.HOLD)
        yes(runCatching { DuplicatePolicy.admit(o,emptyList(),-1) }.isFailure)
    }
    test("batch/identity-and-size-rules") {
        yes(!UploadBatch(uuid(2),listOf(original())).valid())
        yes(!UploadBatch(uuid(1),emptyList()).valid())
        yes(!UploadBatch(uuid(101),listOf(original(Contract.MMONEY_LEDGER_V1),original())).valid())
        yes(!UploadBatch(uuid(101),List(21) { original(Contract.MMONEY_LEDGER_V1,it+1) }).valid())
        yes(UploadBatch(uuid(101),List(20) { original(Contract.MMONEY_LEDGER_V1,it+1) }).valid())
    }
    test("batch/new-operation-cannot-rebind-original") {
        val x=setup(Contract.MMONEY_LEDGER_V1);val new=UploadBatch(uuid(102),x.batch.originals)
        yes(x.driver.capture(new,1001).status=="ORIGINAL_ALREADY_BOUND")
        yes(x.snapshot().batch.operationId==x.batch.operationId)
    }
    test("batch/same-operation-changed-payload-conflict") {
        val x=setup();val changed=UploadBatch(uuid(1),listOf(original(body=GOOD.replace("1,000","3,000"))))
        yes(x.driver.capture(changed,1001).status=="OPERATION_CONFLICT");yes(x.snapshot().batch===x.batch)
    }
    for(c in Contract.values()) test("ack/${c.name}-valid") { yes(AckPolicy.validate(ack(batch(c)),batch(c)) is AckDecision.Valid) }
    val b=batch();val goodAck=ack(b)
    val invalidFields=listOf("contract_version" to "2","contract_version" to 2.0,"contract_version" to 2L,
        "contract_version" to 3,"stored" to "true","stored" to 1,"stored" to false,
        "owner_user_id" to "other","client_envelope_id" to uuid(2),"raw_sms_id" to "",
        "body_sha256" to "0".repeat(64),"body_sha256" to b.originals.single().bodySha256!!.uppercase())
    for((i,pair) in invalidFields.withIndex()) test("ack/collect-invalid-$i") {
        yes(AckPolicy.validate(changeReceipt(goodAck,pair.first,pair.second),b) is AckDecision.Invalid)
    }
    for(field in listOf("contract_version","stored","owner_user_id","client_envelope_id","raw_sms_id","body_sha256")) test("ack/collect-missing-$field") {
        yes(AckPolicy.validate(changeReceipt(goodAck,field,null,true),b) is AckDecision.Invalid)
    }
    test("ack/collect-root-and-cross-contract") {
        yes(AckPolicy.validate(goodAck+mapOf("ok" to "true"),b) is AckDecision.Invalid)
        yes(AckPolicy.validate(mapOf("ok" to true),b) is AckDecision.Invalid)
        yes(AckPolicy.validate(ack(batch(Contract.MMONEY_LEDGER_V1)),b) is AckDecision.Invalid)
    }
    val mb=batch(Contract.MMONEY_LEDGER_V1);val ma=ack(mb)
    val mmInvalid=listOf("status" to "pending","status" to true,"canonicalId" to "not-uuid","canonicalId" to null,
        "id" to uuid(99),"id" to 1,"code" to "REJECTED")
    for((i,pair) in mmInvalid.withIndex()) test("ack/mmoney-invalid-$i") { yes(AckPolicy.validate(changeMm(ma,pair.first,pair.second),mb) is AckDecision.Invalid) }
    test("ack/mmoney-missing-fields-and-strict-version") {
        for(v in listOf("1",1L,1.0,2,null)) yes(AckPolicy.validate(ma+mapOf("schemaVersion" to v),mb) is AckDecision.Invalid)
        yes(AckPolicy.validate(changeMm(ma,"canonicalId",null,true),mb) is AckDecision.Invalid)
        yes(AckPolicy.validate(ma+mapOf("acknowledgements" to emptyList<Any>()),mb) is AckDecision.Invalid)
    }
    test("ack/mmoney-rejection-requires-code-and-null") {
        val rejected=changeMm(changeMm(changeMm(ma,"status","rejected"),"canonicalId",null),"code","UNSUPPORTED")
        yes(AckPolicy.validate(rejected,mb) is AckDecision.Valid)
        yes(AckPolicy.validate(changeMm(rejected,"code",null,true),mb) is AckDecision.Invalid)
        yes(AckPolicy.validate(changeMm(rejected,"canonicalId",uuid(800)),mb) is AckDecision.Invalid)
        yes(AckPolicy.validate(changeMm(rejected,"code","private diagnostic text"),mb) is AckDecision.Invalid)
    }
    test("ack/mmoney-batch-coverage-is-atomic") {
        val two=UploadBatch(uuid(101),listOf(original(Contract.MMONEY_LEDGER_V1,1),original(Contract.MMONEY_LEDGER_V1,2)))
        val raw=ack(two)
        @Suppress("UNCHECKED_CAST") val rows=raw["acknowledgements"] as List<Map<String,Any?>>
        yes(AckPolicy.validate(raw,two) is AckDecision.Valid)
        yes(AckPolicy.validate(raw+mapOf("acknowledgements" to rows.reversed()),two) is AckDecision.Valid)
        yes(AckPolicy.validate(raw+mapOf("acknowledgements" to listOf(rows[0],rows[0])),two) is AckDecision.Invalid)
        yes(AckPolicy.validate(raw+mapOf("acknowledgements" to rows.dropLast(1)),two) is AckDecision.Invalid)
        yes(AckPolicy.validate(raw+mapOf("acknowledgements" to (rows+rows[0])),two) is AckDecision.Invalid)
    }
    for(c in Contract.values()) test("lifecycle/${c.name}-ack-two-phase-and-replay") {
        val x=setup(c);val e=x.send()
        yes(x.snapshot().phase==Phase.IN_FLIGHT);yes(e.batch===x.batch)
        yes(x.advance(QueueAction.Response(e.attempt,ack(x.batch)),1001).status=="ACK_VALIDATED")
        yes(x.snapshot().phase==Phase.ACK_PENDING);yes(x.snapshot().batch===x.batch)
        yes(x.advance(QueueAction.Restore,1002).status=="FINALIZE_ACK_REQUIRED")
        yes(x.advance(QueueAction.FinalizeAcknowledgement,1003).status=="ACK_COMMITTED")
        yes(x.snapshot().phase==Phase.ACKNOWLEDGED)
        yes(x.advance(QueueAction.Response(e.attempt,ack(x.batch)),1004).status=="ACK_REPLAY")
        yes(x.advance(QueueAction.SendOriginal,1005).effect==QueueEffect.None)
        yes(x.driver.capture(x.batch,1006).status=="CAPTURE_ALREADY_RETAINED")
    }
    test("lifecycle/rejected-batch-retains-original") {
        val x=setup(Contract.MMONEY_LEDGER_V1);val e=x.send()
        val raw=changeMm(changeMm(changeMm(ack(x.batch),"status","rejected"),"canonicalId",null),"code","UNSUPPORTED")
        x.advance(QueueAction.Response(e.attempt,raw),1001);x.advance(QueueAction.FinalizeAcknowledgement,1002)
        yes(x.snapshot().phase==Phase.REJECTED);yes(x.snapshot().batch===x.batch)
        yes(x.advance(QueueAction.SendOriginal,1003).effect==QueueEffect.None)
    }
    test("lifecycle/conflicting-acks-preserve-both") {
        val x=setup();val e=x.send();x.advance(QueueAction.Response(e.attempt,ack(x.batch)),1001)
        x.advance(QueueAction.FinalizeAcknowledgement,1002)
        yes(x.advance(QueueAction.Response(e.attempt,ack(x.batch,uuid(801))),1003).status=="CONFLICTING_ACK")
        yes(x.snapshot().phase==Phase.CONFLICT);yes(x.snapshot().receipts.size==1);yes(x.snapshot().conflictingReceipts.size==1)
        yes(x.advance(QueueAction.SendOriginal,1004).effect==QueueEffect.None)
    }
    test("lifecycle/lost-ack-original-id-and-payload") {
        val x=setup();val first=x.send();x.advance(QueueAction.Failure(first.attempt,null),1001)
        yes(x.snapshot().outcomeUncertain);yes(x.advance(QueueAction.SendOriginal,1002).status=="BACKOFF")
        val second=x.send(x.snapshot().notBefore!!)
        yes(second.attempt.operationId==first.attempt.operationId);yes(second.attempt.payloadHash==first.attempt.payloadHash)
        yes(second.attempt.ordinal==2);yes(x.advance(QueueAction.Response(first.attempt,ack(x.batch)),2002).status=="STALE_RESPONSE")
    }
    test("lifecycle/timeout-lease-and-restart") {
        val x=setup();x.send()
        yes(x.advance(QueueAction.Timeout,1001).status=="LEASE_ACTIVE")
        yes(x.advance(QueueAction.Timeout,61000).status=="TIMEOUT_UNCERTAIN")
        val y=setup();y.send();yes(y.advance(QueueAction.Restore,1001).status=="INTERRUPTED_UNCERTAIN")
        yes(y.snapshot().attempts==1);yes(y.snapshot().outcomeUncertain)
    }
    for(status in listOf(401,403,409,400,404,422,301,200,0)) test("lifecycle/http-hold-$status") {
        val x=setup();val e=x.send();x.advance(QueueAction.Failure(e.attempt,status),1001)
        yes(x.snapshot().phase==if(status==409) Phase.CONFLICT else Phase.HELD)
        yes(x.snapshot().batch===x.batch);yes(x.advance(QueueAction.SendOriginal,1002).effect==QueueEffect.None)
    }
    for(status in listOf<Int?>(null,408,429,500,503,599)) test("lifecycle/http-retry-$status") {
        val x=setup();val e=x.send();x.advance(QueueAction.Failure(e.attempt,status),1001)
        yes(x.snapshot().phase==Phase.RETRY_WAIT);yes(x.snapshot().outcomeUncertain)
    }
    test("lifecycle/reauth-does-not-reset-identity-or-attempts") {
        val x=setup();val e=x.send();x.advance(QueueAction.Failure(e.attempt,401),1001)
        yes(x.advance(QueueAction.ResumeAfterAuthorization,1002).status=="NEW_SESSION_REQUIRED")
        val new=x.auth.copy(sessionEpoch=2)
        yes(x.driver.advance(x.batch.key,QueueAction.Response(e.attempt,ack(x.batch)),new,1002).status=="STALE_RESPONSE")
        yes(x.driver.advance(x.batch.key,QueueAction.ResumeAfterAuthorization,new,1002).status=="REAUTHORIZED_ORIGINAL_ONLY")
        val r=x.driver.advance(x.batch.key,QueueAction.SendOriginal,new,x.snapshot().notBefore!!)
        val next=r.effect as QueueEffect.UploadOriginal
        yes(next.attempt.ordinal==2);yes(next.batch===x.batch);yes(next.attempt.sessionEpoch==2L)
    }
    test("lifecycle/changed-owner-generation-binding-session") {
        val x=setup();val e=x.send()
        val authorities=listOf(x.auth.copy(scope=x.auth.scope.copy(ownerId="other")),x.auth.copy(scope=x.auth.scope.copy(generation="new")),
            x.auth.copy(scope=x.auth.scope.copy(installationId="new")),x.auth.copy(binding=x.auth.binding.copy(version=2)),
            x.auth.copy(binding=x.auth.binding.copy(subscriptionId=8)),x.auth.copy(sessionEpoch=2))
        for(a in authorities) {
            val rev=x.snapshot().revision
            yes(x.driver.advance(x.batch.key,QueueAction.Response(e.attempt,ack(x.batch)),a,1001).effect==QueueEffect.None)
            yes(x.snapshot().revision==rev);yes(!DispatchPolicy.permitted(e,x.snapshot(),a,1001))
        }
    }
    test("lifecycle/offline-paused-and-invalid-sim-do-not-spend-attempt") {
        val x=setup()
        for(a in listOf(x.auth.copy(online=false),x.auth.copy(enabled=false),x.auth.copy(sim=SimState(false,null)),x.auth.copy(sim=SimState(true,setOf(8))))) {
            yes(x.driver.advance(x.batch.key,QueueAction.SendOriginal,a,1001).effect==QueueEffect.None)
            yes(x.snapshot().attempts==0)
        }
    }
    test("lifecycle/malformed-ack-does-not-retire") {
        val x=setup();val e=x.send();x.advance(QueueAction.Response(e.attempt,mapOf("ok" to true)),1001)
        yes(x.snapshot().phase==Phase.RETRY_WAIT);yes(x.snapshot().receipts.isEmpty());yes(x.snapshot().outcomeUncertain)
    }
    test("retry/default-budget-and-late-final-receipt") {
        val x=setup();var now=1000L;var last: QueueEffect.UploadOriginal?=null
        repeat(5) {
            last=x.send(now);x.advance(QueueAction.Failure(last!!.attempt,null),now+1)
            now=x.snapshot().notBefore ?: (now+2)
        }
        yes(x.snapshot().phase==Phase.HELD);yes(x.snapshot().reason=="RETRY_LIMIT");yes(x.snapshot().attempts==5)
        yes(x.advance(QueueAction.Restore,now).status=="RESTORED_WITHOUT_RESET")
        yes(x.advance(QueueAction.SendOriginal,now).effect==QueueEffect.None)
        yes(x.advance(QueueAction.Response(last!!.attempt,ack(x.batch)),now).status=="ACK_VALIDATED")
    }
    test("retry/backoff-bounds-age-overflow-and-retry-after") {
        val limits=RetryLimits(maxAttempts=10,baseDelayMs=1000,maxDelayMs=4000,maxElapsedMs=100000)
        yes(RetryPolicy.schedule(1,1000,1000,limits)==RetryDecision.Wait(2000))
        yes(RetryPolicy.schedule(2,1000,1000,limits)==RetryDecision.Wait(3000))
        yes(RetryPolicy.schedule(9,1000,1000,limits)==RetryDecision.Wait(5000))
        yes(RetryPolicy.schedule(1,1000,1000,limits,5000)==RetryDecision.Wait(6000))
        yes(RetryPolicy.schedule(1,1000,1000,limits,-1) is RetryDecision.Hold)
        yes(RetryPolicy.schedule(1,101000,1000,limits) is RetryDecision.Hold)
        yes(RetryPolicy.schedule(1,Long.MAX_VALUE-1,Long.MAX_VALUE-1,limits) is RetryDecision.Hold)
        yes(RetryPolicy.schedule(1,999,1000,limits) is RetryDecision.Hold)
        yes(RetryPolicy.deltaSeconds("5")==5000L);yes(RetryPolicy.deltaSeconds("05")==null)
        yes(RetryPolicy.deltaSeconds("Wed, 21 Oct")==null);yes(RetryPolicy.deltaSeconds("-1")==null)
        yes(runCatching { RetryLimits(maxAttempts=0) }.isFailure)
    }
    test("lifecycle/clock-rollback-no-send") {
        val x=setup();yes(x.advance(QueueAction.SendOriginal,999).status=="CLOCK_ROLLBACK");yes(x.snapshot().attempts==0)
    }
    for(c in Contract.values()) for(fault in Fault.values().filter { it!=Fault.NONE }) for(stage in listOf("capture","reserve","ack-stage","finalize")) test("fault/${c.name}/$stage/$fault") {
        val b=batch(c);val s=MemoryStore();val d=CommitDriver(s,machine(c));val a=authority(b)
        var effect: QueueEffect.UploadOriginal?=null
        if(stage!="capture") yes(d.capture(b,1000).status=="CAPTURE_COMMITTED")
        if(stage in listOf("ack-stage","finalize")) effect=d.advance(b.key,QueueAction.SendOriginal,a,1000).effect as QueueEffect.UploadOriginal
        if(stage=="finalize") yes(d.advance(b.key,QueueAction.Response(effect!!.attempt,ack(b)),a,1001).status=="ACK_VALIDATED")
        s.fault=fault
        val result=when(stage) {
            "capture" -> d.capture(b,1000)
            "reserve" -> d.advance(b.key,QueueAction.SendOriginal,a,1000)
            "ack-stage" -> d.advance(b.key,QueueAction.Response(effect!!.attempt,ack(b)),a,1001)
            else -> d.advance(b.key,QueueAction.FinalizeAcknowledgement,a,1002)
        }
        yes(result.effect==QueueEffect.None)
        val stored=s.read(b.key)
        if(stored is StoreRead.Present) {
            yes(stored.snapshot.valid());yes(stored.snapshot.batch===b)
            val before=stored.snapshot.batch.payloadHash
            val recovery=d.advance(b.key,QueueAction.Restore,a,1003)
            yes(recovery.effect==QueueEffect.None);yes(s.snapshot(b).batch.payloadHash==before)
            if(s.snapshot(b).phase==Phase.ACK_PENDING) d.advance(b.key,QueueAction.FinalizeAcknowledgement,a,1004)
            yes(s.snapshot(b).batch.originals.map { it.evidenceHash }==b.originals.map { it.evidenceHash })
        } else yes(stage=="capture")
    }
    test("storage/no-recreation-on-missing-corrupt-unavailable") {
        val b=batch();val s=MemoryStore();val d=CommitDriver(s,machine(b.scope.contract));val a=authority(b)
        yes(d.advance(b.key,QueueAction.Restore,a,1000).status=="MISSING_EVIDENCE")
        s.corrupt=true;yes(d.capture(b,1000).status=="STORAGE_BLOCKED");yes(d.advance(b.key,QueueAction.Restore,a,1000).status=="CORRUPT_STORAGE")
        s.corrupt=false;s.unavailable=true;yes(d.capture(b,1000).status=="STORAGE_BLOCKED")
        s.unavailable=false;s.throwRead=true;yes(d.capture(b,1000).status=="STORAGE_BLOCKED")
        s.throwRead=false;yes(s.read(b.key)==StoreRead.Missing)
    }
    test("storage/concurrent-reservation-emits-once") {
        val x=setup();val ready=CountDownLatch(20);val go=CountDownLatch(1);val all=CopyOnWriteArrayList<DriverResult>()
        val threads=List(20) { Thread { ready.countDown();go.await();all+=x.advance(QueueAction.SendOriginal) }.apply { start() } }
        ready.await();go.countDown();threads.forEach { it.join() }
        yes(all.size==20);yes(all.count { it.effect is QueueEffect.UploadOriginal }==1);yes(x.snapshot().attempts==1)
    }
    test("dispatch/recheck-and-cas-stale-commit") {
        val x=setup();val before=x.snapshot();val e=x.send()
        yes(DispatchPolicy.permitted(e,x.snapshot(),x.auth,1000));yes(!DispatchPolicy.permitted(e,before,x.auth,1000))
        yes(!DispatchPolicy.permitted(e,x.snapshot(),x.auth.copy(enabled=false),1000))
        yes(x.store.compareAndSet(x.batch.key,0,before)==StoreWrite.REVISION_CONFLICT)
    }
    test("model/2000-deterministic-events-retain-evidence-and-budget") {
        val rng=Random(42)
        for(c in Contract.values()) repeat(10) {
            val x=setup(c);var now=1000L
            repeat(100) {
                now+=rng.nextLong(1,90000)
                val current=x.snapshot();val active=current.activeAttempt
                val action=when(rng.nextInt(7)) {
                    0 -> QueueAction.SendOriginal
                    1 -> QueueAction.Restore
                    2 -> QueueAction.Timeout
                    3 -> QueueAction.FinalizeAcknowledgement
                    4 -> if(active!=null) QueueAction.Response(active,ack(x.batch)) else QueueAction.SendOriginal
                    5 -> if(active!=null) QueueAction.Response(active,mapOf("ok" to "true")) else QueueAction.SendOriginal
                    else -> if(active!=null) QueueAction.Failure(active,503) else QueueAction.SendOriginal
                }
                val r=x.advance(action,now);val s=x.snapshot()
                yes(s.valid());yes(s.attempts<=5);yes(s.batch===x.batch)
                if(r.effect is QueueEffect.UploadOriginal) { yes(r.effect.batch===x.batch);yes(r.effect.attempt.operationId==x.batch.operationId) }
            }
        }
    }
    test("lifecycle/mmoney-full-batch-mixed-outcomes-atomic") {
        val originals=(1..20).map { original(Contract.MMONEY_LEDGER_V1,it,GOOD.replace("1,000",(1000+it).toString())) }
        val b=UploadBatch(uuid(500),originals);val s=MemoryStore();val d=CommitDriver(s,machine(b.scope.contract));val a=authority(b)
        yes(d.capture(b,1000).status=="CAPTURE_COMMITTED")
        val e=d.advance(b.key,QueueAction.SendOriginal,a,1000).effect as QueueEffect.UploadOriginal
        val rows=originals.mapIndexed { i,o -> if(i%3==0) mapOf("id" to o.captureId,"canonicalId" to null,"status" to "rejected","code" to "UNSUPPORTED")
            else mapOf("id" to o.captureId,"canonicalId" to uuid(800+i),"status" to "accepted") }
        val raw=mapOf("schemaVersion" to 1,"acknowledgements" to rows.reversed())
        yes(d.advance(b.key,QueueAction.Response(e.attempt,raw),a,1001).status=="ACK_VALIDATED")
        yes(s.snapshot(b).phase==Phase.ACK_PENDING);yes(s.snapshot(b).receipts.size==20)
        yes(d.advance(b.key,QueueAction.FinalizeAcknowledgement,a,1002).status=="ACK_COMMITTED")
        val done=s.snapshot(b);yes(done.phase==Phase.REJECTED);yes(done.receipts.count { it.outcome==ReceiptOutcome.RETAINED }==13)
        yes(done.batch.originals===b.originals);yes(d.advance(b.key,QueueAction.Response(e.attempt,raw),a,1003).status=="ACK_REPLAY")
    }
    test("lifecycle/policy-drift-stops-without-reset-or-send") {
        val x=setup();val b=x.batch
        val drift=MessageClassifier { a -> buri.classify(a).copy(policyVersion="changed") }
        val d=CommitDriver(x.store,QueueMachine(drift))
        yes(d.advance(b.key,QueueAction.SendOriginal,x.auth,1000).status=="CLASSIFICATION_CHANGED_OR_UNSUPPORTED")
        yes(x.snapshot().attempts==0);yes(x.snapshot().batch===b)
    }
    test("storage/malformed-restored-receipt-rejected") {
        val x=setup(Contract.MMONEY_LEDGER_V1);val e=x.send()
        x.advance(QueueAction.Response(e.attempt,ack(x.batch)),1001)
        val valid=x.snapshot()
        val bad=valid.evolve(receipts=listOf(valid.receipts.single().copy(canonicalId="not-a-uuid")))
        yes(!bad.valid())
        val invented=valid.evolve(receipts=listOf(valid.receipts.single().copy(bodySha256="0".repeat(64))))
        yes(!invented.valid())
    }
    val failed=results.count { !it.second }
    val names=results.joinToString(",") { "{\"name\":\"${it.first}\",\"status\":\"${if(it.second) "passed" else "failed"}\"}" }
    println("{\"status\":\"${if(failed==0) "passed" else "failed"}\",\"tests\":${results.size},\"failed\":$failed,\"assertions\":$assertions,\"model_events\":2000,\"cases\":[$names]}")
    if(failed!=0) throw IllegalStateException("$failed policy test cases failed")
}
