package rw.ikanisa.burimunsi.receiverretirementtests

import rw.ikanisa.burimunsi.core.*
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

/** Actual journal state machine; storage is an explicit in-memory double. */
fun main(){
 var count=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");count++}
 fun denied(action:()->Unit)=runCatching(action).exceptionOrNull() is ContractFailure
 class Store:ReceiverRetirementStore{var value:ReceiverRetirementRecord?=null;var archived:ReceiverRetirementRecord?=null;var drop=false;override fun load()=value;override fun save(value:ReceiverRetirementRecord){if(!drop)this.value=value};override fun archive(value:ReceiverRetirementRecord){archived=value;if(!drop)this.value=null}}
 val request="30000000-0000-4000-8000-000000000001";val install="30000000-0000-4000-8000-000000000002";val handoff="30000000-0000-4000-8000-000000000003"
 val token="a".repeat(64);val code="b".repeat(64)
 fun prepare(store:Store)=ReceiverRetirementJournal(store){request}.prepare("group-1","operator-1",install,"3",token,code)
 val store=Store();val record=prepare(store);val journal=ReceiverRetirementJournal(store)
 ck("retirement is durable before dispatch and stores code digest only",record.state==ReceiverRetirementState.PREPARED&&store.value==record&&record.fingerprint==Values.sha256("burimunsi.gateway.retire.v1:"+Values.sha256(code)+":"+request)&&!record.toString().contains(token)&&!record.toString().contains(code))
 ck("prepared retirement cannot be replaced",denied{prepare(store)})
 journal.beginDispatch(record)
 ck("dispatch first persists SENT",store.value?.state==ReceiverRetirementState.SENT)
 ck("second dispatch is refused",denied{journal.beginDispatch(record)})
 val recreated=ReceiverRetirementJournal(store)
 ck("process recreation never treats SENT as unsent",denied{recreated.beginDispatch(record)})
 recreated.uncertain(record);ck("uncertain command retains original raw proof",store.value?.state==ReceiverRetirementState.UNKNOWN&&store.value?.token==token)
 ck("unknown command cannot be replayed",denied{recreated.beginDispatch(record)})
 for(bad in listOf(record.copy(actorId="other"),record.copy(groupId="other"),record.copy(installationId=handoff),record.copy(generation="4"),record.copy(fingerprint="e".repeat(64))))
  ck("substituted retirement identity cannot consume receipt",denied{recreated.acknowledge(bad,ReceiverRetirementAck(handoff,request))})
 ck("another request ACK cannot settle original",denied{recreated.acknowledge(record,ReceiverRetirementAck(handoff,install))})
 recreated.acknowledge(record,ReceiverRetirementAck(handoff,request))
 ck("positive ACK erases raw bearer and retains terminal history",store.value?.state==ReceiverRetirementState.RETIRED&&store.value?.token==null&&store.value?.ack?.handoffId==handoff)
 recreated.uncertain(record);ck("late transport failure cannot downgrade retired receipt",store.value?.state==ReceiverRetirementState.RETIRED)
 ck("conflicting ACK is refused",denied{recreated.acknowledge(record,ReceiverRetirementAck(install,request))})
 recreated.acknowledge(record,ReceiverRetirementAck(handoff,request));ck("same ACK is idempotent",store.value?.ack?.handoffId==handoff)
 journal.archiveAfterPair();ck("verified later Pair archives terminal receipt before releasing the next retirement slot",store.value==null&&store.archived?.ack?.handoffId==handoff)
 prepare(store);ck("reused handset may retain a new retirement after pairing",store.value?.state==ReceiverRetirementState.PREPARED)
 ck("pending receipt can never be archived to bypass recovery",denied{journal.archiveAfterPair()}&&store.value!=null)
 val broken=Store();broken.drop=true;ck("failed durable preparation cannot produce dispatch witness",denied{prepare(broken)}&&broken.value==null)
 val brokenSend=Store();val pending=prepare(brokenSend);brokenSend.drop=true
 ck("failed SENT readback blocks HTTP witness",denied{ReceiverRetirementJournal(brokenSend).beginDispatch(pending)}&&brokenSend.value?.state==ReceiverRetirementState.PREPARED)
 val corrupted=Store();corrupted.value=record.copy(token="e".repeat(64))
 ck("corrupt original proof fails closed without deletion",denied{ReceiverRetirementJournal(corrupted).retained()}&&corrupted.value!=null)
 val concurrent=Store();val original=prepare(concurrent);val readA=ReceiverRetirementJournal(concurrent);val readB=ReceiverRetirementJournal(concurrent)
 val entered=CountDownLatch(1);val release=CountDownLatch(1)
 val reader=thread{readA.withOutcomeRead(original){entered.countDown();release.await()}}
 entered.await();ck("one retained outcome has one concurrent GET lease",denied{readB.withOutcomeRead(original){error("Must not run")}})
 release.countDown();reader.join();readB.withOutcomeRead(original){}
 ck("outcome lease releases without altering journal",concurrent.value==original)
 println("RESULT: $count retirement journal checks passed; no Android, SQL or HTTP qualification.")
}
