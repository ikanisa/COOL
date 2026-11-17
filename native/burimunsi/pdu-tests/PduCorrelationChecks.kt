package app.cool.mobile.receiver_sms

import android.content.Context
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.SecureStore
import java.util.UUID

private fun pdu(body:ByteArray,sequence:Int=1,total:Int=2,reference:Int=7):ByteArray {
    val header=byteArrayOf(5,0,3,reference.toByte(),total.toByte(),sequence.toByte());val data=header+body
    return byteArrayOf(0,64,2,0x91.toByte(),0x21,0,4,0,0,0,0,0,0,0,data.size.toByte())+data
}
fun main(){
    var checks=0;fun test(name:String,action:()->Unit){action();checks++;println("PASS $name")}
    val now=System.currentTimeMillis();val owner=ObservationOwner("group-1","admin-1")
    val installation="50000000-0000-4000-8000-000000000001"
    val profile=ObservationProfile(ReceiptProfile("approved-v1",setOf("M-Money"),120,setOf("You have received"),setOf("RWF"),setOf("FT Id:")),now,now+86_400_000)
    val body="You have received 1000 RWF from EXAMPLE (*****001) at 2026-10-08 15:15:20. Balance: 2000 RWF. FT Id: 123456789."
    val left=body.substring(0,55);val right=body.substring(55);val centre=now-1_000
    fun complete(id:String=UUID.randomUUID().toString())=PduInboxCorrelation.capture(id,owner,installation,profile,now,3,"3gpp",
        listOf("M-Money","M-Money"),listOf(centre,centre),listOf(right,left),listOf(pdu(right.toByteArray(),2),pdu(left.toByteArray(),1)))!!
    fun row(id:Long,request:String=UUID.randomUUID().toString(),message:String=body)=PduInboxCorrelation.inbox(request,owner,installation,profile,now,id,
        "M-Money",message,centre,now,3)!!
    fun fresh():PduCorrelationStore{SecureStore.reset();return PduCorrelationStore(Context())}
    test("complete reordered multipart data is correlated only as unverified") {
        val store=fresh();val p=complete();check(p.structurallyComplete&&store.record(p)==CorrelationWrite.STORED)
        check(store.record(row(101))==CorrelationWrite.STORED)
        check(PduInboxCorrelation.status(PduCorrelationStore(Context()).read(),p.witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
    }
    test("missing and duplicate segments stay incomplete") {
        val incomplete=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,now,3,"3gpp",
            listOf("M-Money"),listOf(centre),listOf(body),listOf(pdu(body.toByteArray(),1)))!!
        check(!incomplete.structurallyComplete&&PduInboxCorrelation.status(CorrelationState(listOf(incomplete),listOf(row(102))),incomplete.witnessId)==CorrelationStatus.INCOMPLETE)
        val duplicate=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,now,3,"3gpp",
            listOf("M-Money","M-Money"),listOf(centre,centre),listOf(body,body),listOf(pdu(body.toByteArray(),1),pdu(body.toByteArray(),1)))!!
        check(!duplicate.structurallyComplete)
    }
    test("sender, timestamp, subscription and body mismatches never correlate") {
        val p=complete();val r=row(103)
        check(PduInboxCorrelation.status(CorrelationState(listOf(p),listOf(r.copy(sender="Other"))),p.witnessId)==CorrelationStatus.WAITING)
        check(PduInboxCorrelation.status(CorrelationState(listOf(p),listOf(r.copy(serviceCentreMs=centre+1))),p.witnessId)==CorrelationStatus.WAITING)
        check(PduInboxCorrelation.status(CorrelationState(listOf(p),listOf(r.copy(subscriptionId=4))),p.witnessId)==CorrelationStatus.WAITING)
        check(PduInboxCorrelation.status(CorrelationState(listOf(p),listOf(r.copy(bodySha256="0".repeat(64)))),p.witnessId)==CorrelationStatus.WAITING)
    }
    test("multipart sender and timestamp disagreement cannot claim completeness") {
        val senderMismatch=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,now,3,"3gpp",
            listOf("M-Money","Other"),listOf(centre,centre),listOf(left,right),listOf(pdu(left.toByteArray(),1),pdu(right.toByteArray(),2)))!!
        val timeMismatch=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,now,3,"3gpp",
            listOf("M-Money","M-Money"),listOf(centre,centre+1),listOf(left,right),listOf(pdu(left.toByteArray(),1),pdu(right.toByteArray(),2)))!!
        check(!senderMismatch.structurallyComplete&&!timeMismatch.structurallyComplete)
    }
    test("identical distinct inbox rows remain distinct and ambiguous") {
        val store=fresh();val p=complete();val a=row(104);val b=row(105)
        check(a.sourceKey!=b.sourceKey&&store.record(p)==CorrelationWrite.STORED&&store.record(a)==CorrelationWrite.STORED&&store.record(b)==CorrelationWrite.STORED)
        val state=store.read();check(state.inbox.size==2&&PduInboxCorrelation.status(state,p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("a later identical broadcast or concatenation collision reverses correlation to ambiguous") {
        val store=fresh();val p=complete();check(store.record(p)==CorrelationWrite.STORED);check(store.record(row(106))==CorrelationWrite.STORED)
        check(PduInboxCorrelation.status(store.read(),p.witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
        check(store.record(complete())==CorrelationWrite.STORED)
        check(PduInboxCorrelation.status(store.read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("a late incomplete segment sharing the concatenation reference holds the earlier match") {
        val store=fresh();val p=complete();check(store.record(p)==CorrelationWrite.STORED);check(store.record(row(110))==CorrelationWrite.STORED)
        check(PduInboxCorrelation.status(store.read(),p.witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
        val late=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,now,3,"3gpp",
            listOf("M-Money"),listOf(centre),listOf(body),listOf(pdu(body.toByteArray(),1)))!!
        check(!late.structurallyComplete&&store.record(late)==CorrelationWrite.STORED)
        check(PduInboxCorrelation.status(store.read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("idempotent replay preserves exact evidence and changed source is held") {
        val store=fresh();val p=complete();val r=row(107)
        check(store.record(p)==CorrelationWrite.STORED&&store.record(p)==CorrelationWrite.DUPLICATE)
        check(store.record(r)==CorrelationWrite.STORED&&store.record(r)==CorrelationWrite.DUPLICATE)
        check(store.record(r.copy(bodySha256="f".repeat(64)))==CorrelationWrite.CONFLICT)
        check(PduInboxCorrelation.status(store.read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("changed evidence under the same witness ID permanently holds its match") {
        val store=fresh();val p=complete();check(store.record(p)==CorrelationWrite.STORED);check(store.record(row(111))==CorrelationWrite.STORED)
        check(store.record(p.copy(capturedAtMs=p.capturedAtMs+1))==CorrelationWrite.CONFLICT)
        check(PduInboxCorrelation.status(PduCorrelationStore(Context()).read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("unknown transport and missing subscription stay incomplete") {
        val p=complete();check(PduInboxCorrelation.status(CorrelationState(listOf(p.copy(subscriptionId=null)),listOf(row(108))),p.witnessId)==CorrelationStatus.INCOMPLETE)
        val unknown=PduInboxCorrelation.capture(UUID.randomUUID().toString(),owner,installation,profile,now,3,"3gpp2",
            listOf("M-Money"),listOf(centre),listOf(body),listOf(pdu(body.toByteArray(),1)))!!
        check(!unknown.structurallyComplete)
        check(PduInboxCorrelation.inbox(UUID.randomUUID().toString(),owner,installation,profile,now,109,"M-Money","Transfer sent 1234",centre,now,3)!=null)
    }
    test("changed PDU bytes cannot preserve a completeness witness") {
        val p=complete();val corrupt=p.copy(segments=p.segments.mapIndexed{i,s->if(i==0)s.copy(pduHex=s.pduHex.dropLast(2)+"00")else s})
        check(!PduInboxCorrelation.valid(corrupt));check(runCatching{fresh().record(corrupt)}.isFailure)
    }
    test("damaged protected evidence fails closed without deleting the original") {
        fresh();SecureStore.values["pdu-correlation"]="synthetic-damaged-evidence"
        check(runCatching{PduCorrelationStore(Context()).read()}.isFailure)
        check(SecureStore.values["pdu-correlation"]=="synthetic-damaged-evidence")
    }
    test("count saturation persists a hold for a later colliding witness") {
        SecureStore.reset();val store=PduCorrelationStore(Context(),pduLimit=1);val p=complete()
        check(store.record(p)==CorrelationWrite.STORED&&store.record(row(112))==CorrelationWrite.STORED)
        check(PduInboxCorrelation.status(store.read(),p.witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
        check(store.record(complete())==CorrelationWrite.FULL)
        check(PduInboxCorrelation.status(PduCorrelationStore(Context()).read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("inbox saturation persists a hold for a later identical row") {
        SecureStore.reset();val store=PduCorrelationStore(Context(),rowLimit=1);val p=complete()
        check(store.record(p)==CorrelationWrite.STORED&&store.record(row(113))==CorrelationWrite.STORED)
        check(store.record(row(114))==CorrelationWrite.FULL)
        check(PduInboxCorrelation.status(PduCorrelationStore(Context()).read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("byte-budget saturation persists a hold before refusing new evidence") {
        val store=fresh();val p=complete();check(store.record(p)==CorrelationWrite.STORED&&store.record(row(115))==CorrelationWrite.STORED)
        val size=SecureStore.values.getValue("pdu-correlation").toByteArray().size
        val bounded=PduCorrelationStore(Context(),byteLimit=size+8)
        check(bounded.record(complete())==CorrelationWrite.FULL)
        check(PduInboxCorrelation.status(PduCorrelationStore(Context()).read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    test("failed second write retains the durable uncertainty fence") {
        val store=fresh();val p=complete();check(store.record(p)==CorrelationWrite.STORED&&store.record(row(116))==CorrelationWrite.STORED)
        SecureStore.failAt=SecureStore.writes+2
        check(runCatching{store.record(complete())}.isFailure);SecureStore.failAt=null
        check(PduInboxCorrelation.status(PduCorrelationStore(Context()).read(),p.witnessId)==CorrelationStatus.AMBIGUOUS)
    }
    println("RESULT: $checks PDU/inbox correlation checks using the pinned multipart policy and in-memory store; no carrier, wallet, Android keystore or posting proof.")
}
