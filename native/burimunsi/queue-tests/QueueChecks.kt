package app.cool.mobile.receiver_sms
import android.Manifest
import android.content.Context
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.NativeRepository
import java.time.Instant

/** Real local queue projection with synthetic session, permission and storage doubles. */
fun main(){
 var checks=0
 fun test(name:String,action:()->Unit){action();checks++;println("PASS $name")}
 val context=Context();val a=ObservationOwner("group-1","admin-a");val b=ObservationOwner("group-1","admin-b")
 val installation="50000000-0000-4000-8000-000000000001";val now=System.currentTimeMillis();val time=Instant.ofEpochMilli(now).toString()
 val profile=ObservationProfile(ReceiptProfile("test-v1",setOf("SyntheticSender"),120,setOf("you have received"),setOf("RWF"),setOf("FT Id:")),now-1000,now+60_000)
 val body="You have received 1000 RWF from EXAMPLE (*********123) at 2026-10-08 15:15:20. Balance: 2000 RWF. FT Id: 90001."
 val journal=ObservationJournal(ObservationStateStore(context))
 fun put(owner:ObservationOwner,row:Long):SmsObservation{
  val item=SmsObservation(java.util.UUID.randomUUID().toString(),"SyntheticSender",body,"catch_up",false,time,null,time,null)
  check(journal.append(owner,ObservationSourceIdentity.inbox(installation,owner,row),row,item,profile,now)==ObservationAppend.STORED);return item
 }
 NativeRepository.switch(a);val first=put(a,1)
 test("queue preview and body search are local and owner scoped"){
  val view=ObservationGateway.queued(context,"")!!;check(view.items==listOf(QueuedObservationRow(first.requestId,"SyntheticSender",time,body)))
  check(!view.toString().contains(body)&&!view.items.single().toString().contains("EXAMPLE"))
  check(ObservationGateway.queued(context,"Synthetic")!!.items.size==1&&ObservationGateway.queued(context,"example")!!.items.size==1&&ObservationGateway.queued(context,"other")!!.items.isEmpty())
  check(ObservationGateway.queued(context,"${first.requestId} SyntheticSender")!!.items.size==1)
  check(ObservationGateway.queued(context,"SyntheticSender You have")!!.items.size==1)
  NativeRepository.switch(b);check(ObservationGateway.queued(context,"")!!.items.isEmpty());NativeRepository.switch(a)
 }
 test("preview bounds preserve Unicode code points"){
  val emoji="\uD83D\uDE00"
  check(QueuedObservationPreview.from("short $emoji")=="short $emoji")
  check(QueuedObservationPreview.from("A".repeat(199)+emoji+"B")=="A".repeat(199)+emoji+"…")
  check(QueuedObservationPreview.from("A".repeat(200)+emoji)=="A".repeat(200)+"…")
 }
 test("logout and same-account re-login invalidate an in-flight snapshot"){
  val view=ObservationGateway.queued(context,"")!!;var shown=false
  NativeRepository.switch(null);check(!ObservationGateway.publishQueued(context,view){shown=true}&&!shown)
  NativeRepository.switch(a);check(!ObservationGateway.publishQueued(context,view){shown=true}&&!shown)
  check(journal.pending(a).size==1)
 }
 test("permission revocation blocks both reads and in-flight publication"){
  val view=ObservationGateway.queued(context,"")!!;var shown=false
  context.denied=setOf(Manifest.permission.READ_SMS)
  check(ObservationGateway.queued(context,"")==null&&!ObservationGateway.publishQueued(context,view){shown=true}&&!shown)
  context.denied=emptySet()
 }
 test("append and acknowledgement invalidate stale queue snapshots"){
  val old=ObservationGateway.queued(context,"")!!;val second=put(a,2);var shown=false
  check(!ObservationGateway.publishQueued(context,old){shown=true}&&!shown)
  val updated=ObservationGateway.queued(context,"")!!;check(updated.items.size==2)
  val ack=ObservationAck(first.requestId,"source-1",Values.sha256(first.rawBody),"source_unresolved",0)
  check(journal.acknowledge(a,first.requestId,ack))
  check(!ObservationGateway.publishQueued(context,updated){shown=true}&&!shown)
  val remaining=ObservationGateway.queued(context,"")!!;check(remaining.items.single().id==second.requestId)
  check(ObservationGateway.publishQueued(context,remaining){shown=true}&&shown)
 }
 test("unreadable local queue fails closed"){
  ObservationStateStore.fail=true;check(runCatching{ObservationGateway.queued(context,"")}.isFailure);ObservationStateStore.fail=false
 }
 println("$checks queue adapter checks passed")
}
