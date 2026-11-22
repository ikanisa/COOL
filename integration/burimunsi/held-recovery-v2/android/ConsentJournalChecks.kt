package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.storage.SecureStore
import java.time.Instant
import java.util.concurrent.CountDownLatch

/** Synthetic host checks for the real journal with an in-memory store double.
 * These do not establish Android Keystore, server or device behavior. */
fun main(){
    var checks=0
    fun test(name:String,body:()->Unit){SecureStore.reset();body();checks++;println("PASS $name")}
    val owner=ObservationOwner("test-collection","test-admin")
    val install="50000000-0000-4000-8000-000000000001"
    val device=Values.sha256("synthetic-device")
    val key=Values.sha256("synthetic-source")
    val body="Synthetic mobile-money message 100 RWF"
    val now=1_800_000_000_000L
    val received=Instant.ofEpochMilli(now).toString()
    fun consent(generation:Long=7,enabled:Boolean=true,confirmed:Boolean=true)=
        ObservationConsentState(ObservationConsentRevision(enabled,generation),confirmed)
    fun journal()=HeldRecoveryJournal(Context(),owner,install,device)
    fun prepare(j:HeldRecoveryJournal,c:ObservationConsentState=consent())=
        j.prepare(12,key,"M-Money",body,received,null,3,now,c)
    fun ack(e:HeldRecoveryJournal.Entry)=HeldObservationAck(
        ObservationAck(e.requestId,"synthetic-source-1",Values.sha256(body),"source_unresolved",0),"held")
    fun resolution(e:HeldRecoveryJournal.Entry)=HeldRecoveryResolution(e.requestId,key,Values.sha256(body),
        "acknowledged","synthetic-source-1","held",0,false)
    fun storedName()=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")}
    fun makeLegacy(j:HeldRecoveryJournal,phase:String):Pair<String,String>{
        val prepared=prepare(j)!!;val name=storedName()
        val legacy=JSONObject(SecureStore.data[name]!!).put("version",1).put("phase",phase)
        legacy.remove("consentGeneration")
        if(phase=="CONFIRMED"||phase=="MATCHED_EXISTING")legacy.put("terminalSourceId","synthetic-source-1")
        val encoded=legacy.toString();SecureStore.data[name]=encoded
        check(prepared.observation!=null)
        return name to encoded
    }
    test("new preparation requires an enabled confirmed bounded consent"){
        val j=journal()
        for(c in listOf(consent(enabled=false),consent(confirmed=false),consent(0),consent(9_007_199_254_740_992L)))
            check(prepare(j,c)==null)
        check(SecureStore.data.isEmpty())
    }
    test("consent is stored with the immutable request before attempting"){
        val j=journal();val prepared=prepare(j)!!;val saved=JSONObject(SecureStore.data[storedName()]!!)
        check(saved.getInt("version")==3&&saved.getLong("consentGeneration")==7L)
        check(prepared.consentGeneration==7L&&!prepared.toString().contains(body))
        val restarted=journal();check(restarted.pending(key)==prepared)
        check(prepare(restarted)==prepared&&prepare(restarted,consent(8))==null)
        check(restarted.prepare(12,key,"M-Money",body+" changed",received,null,3,now,consent())==null)
        val attempted=restarted.begin(prepared,consent())!!
        check(attempted.phase==HeldRecoveryJournal.Phase.ATTEMPTING&&attempted.observation==prepared.observation)
        check(journal().pending(key)==attempted&&journal().begin(attempted,consent())==null)
        check(journal().consentMatches(attempted,consent())&&!journal().consentMatches(attempted,consent(8)))
        check(journal().matches(attempted,12,"M-Money",body,received,null,3))
        check(!journal().matches(attempted,12,"M-Money",body+" changed",received,null,3))
    }
    test("revocation or regrant prevents begin and leaves the original bytes intact"){
        val j=journal();val prepared=prepare(j)!!;val name=storedName();val before=SecureStore.data[name]
        check(j.begin(prepared,consent(enabled=false))==null)
        check(j.begin(prepared,consent(8))==null&&j.begin(prepared,consent(confirmed=false))==null)
        check(SecureStore.data[name]==before&&j.pending(key)==prepared)
    }
    test("same-call never-dispatched restoration keeps the exact request and consent witness"){
        val j=journal();val prepared=prepare(j)!!;val attempted=j.begin(prepared,consent())!!
        check(j.restoreNeverDispatched(attempted,consent(8))==null)
        check(j.restoreNeverDispatched(attempted.copy(requestId="00000000-0000-4000-8000-000000000099"),consent())==null)
        check(j.pending(key)==attempted)
        check(j.restoreNeverDispatched(attempted,consent())==prepared&&journal().pending(key)==prepared)
        check(journal().begin(prepared,consent())==attempted)
    }
    test("failed never-dispatched restoration leaves the attempted entry intact"){
        val j=journal();val attempted=j.begin(prepare(j)!!,consent())!!;val name=storedName();val before=SecureStore.data[name]
        SecureStore.unwritable.add(name)
        check(runCatching{j.restoreNeverDispatched(attempted,consent())}.isFailure&&SecureStore.data[name]==before)
        SecureStore.unwritable.remove(name);check(j.pending(key)==attempted)
    }
    test("competing local restorations change one exact attempt at most once"){
        val j=journal();val prepared=prepare(j)!!;val attempted=j.begin(prepared,consent())!!
        val start=CountDownLatch(1);val done=CountDownLatch(2)
        val results=java.util.Collections.synchronizedList(mutableListOf<HeldRecoveryJournal.Entry?>())
        repeat(2){Thread{start.await();try{results.add(journal().restoreNeverDispatched(attempted,consent()))}finally{done.countDown()}}.start()}
        start.countDown();done.await();check(results.count{it==prepared}==1&&j.pending(key)==prepared)
    }
    test("confirmation requires matching consent and produces a redacted tombstone"){
        val j=journal();val attempted=j.begin(prepare(j)!!,consent())!!;val name=storedName();val before=SecureStore.data[name]
        check(j.confirm(attempted,ack(attempted),consent(8))==null)
        check(j.confirm(attempted,ack(attempted).copy(autoProcessing="unknown"),consent())==null)
        check(SecureStore.data[name]==before)
        val done=j.confirm(attempted,ack(attempted),consent())!!;val encoded=SecureStore.data[name]!!
        check(done.phase==HeldRecoveryJournal.Phase.CONFIRMED&&done.consentGeneration==null&&done.observation==null)
        check(JSONObject(encoded).keys().asSequence().toSet()==setOf("version","phase","requestId","sourceId","rowDigest"))
        check(!encoded.contains(body)&&!encoded.contains("M-Money"))
    }
    test("read-only ACK for a witnessed request rejects changed consent and invalid proof"){
        val j=journal();val attempted=j.begin(prepare(j)!!,consent())!!;val proof=resolution(attempted)
        check(j.confirmReadOnly(attempted,proof,consent(8))==null)
        check(j.confirmReadOnly(attempted,proof.copy(retryAllowed=true),consent())==null)
        check(j.confirmReadOnly(attempted,proof.copy(financialEffects=1),consent())==null)
        check(j.confirmReadOnly(attempted,proof,consent())?.phase==HeldRecoveryJournal.Phase.CONFIRMED)
    }
    test("legacy attempting stays byte-exact and cannot acquire a replay witness"){
        val j=journal();val (name,original)=makeLegacy(j,"ATTEMPTING");val pending=journal().pending(key)!!
        check(pending.consentGeneration==null&&pending.phase==HeldRecoveryJournal.Phase.ATTEMPTING)
        check(journal().begin(pending,consent())==null&&!journal().consentMatches(pending,consent()))
        check(prepare(journal(),consent())==null&&!journal().clear(pending))
        check(journal().matches(pending,12,"M-Money",body,received,null,3))
        check(SecureStore.data[name]==original)
    }
    test("legacy read-only acknowledgement stays unresolved without authenticated provenance"){
        val j=journal();val (name,original)=makeLegacy(j,"ATTEMPTING");val pending=j.pending(key)!!;val proof=resolution(pending)
        check(j.confirmReadOnly(pending,proof,consent(enabled=false))==null)
        check(j.confirmReadOnly(pending,proof.copy(state="unconfirmed",sourceId=null,autoProcessing="unknown"),consent())==null)
        check(j.confirmReadOnly(pending,proof.copy(bodySha256=Values.sha256("different")),consent())==null)
        // A valid-shaped value can be locally constructed. Its shape does not
        // establish that the authenticated server admitted the original request.
        check(j.confirmReadOnly(pending,proof,consent())==null&&SecureStore.data[name]==original)
    }
    test("legacy prepared can be cleared locally but never upgraded in place"){
        val j=journal();val (_,original)=makeLegacy(j,"PREPARED");val old=j.pending(key)!!
        check(old.consentGeneration==null&&j.begin(old,consent())==null&&prepare(j,consent())==null)
        check(j.clear(old));val replacement=prepare(j,consent())!!
        check(replacement.requestId!=old.requestId&&replacement.consentGeneration==7L&&original.contains(body))
    }
    test("legacy terminal migration still redacts without a consent witness"){
        val j=journal();val (name,_)=makeLegacy(j,"CONFIRMED");val done=j.pending(key)!!
        check(done.phase==HeldRecoveryJournal.Phase.CONFIRMED&&done.consentGeneration==null)
        check(JSONObject(SecureStore.data[name]!!).getInt("version")==2&&!SecureStore.data[name]!!.contains(body))
    }
    test("invalid or missing stored witnesses fail closed without replacement"){
        for(value in listOf<Any>(0L,-1L,9_007_199_254_740_992L,"7",1.5)){
            SecureStore.reset();val j=journal();prepare(j)!!;val name=storedName()
            val bad=JSONObject(SecureStore.data[name]!!).put("consentGeneration",value).toString();SecureStore.data[name]=bad
            check(runCatching{j.pending(key)}.isFailure&&SecureStore.data[name]==bad)
        }
    }
    test("failed writes preserve the exact previous protected state"){
        val j=journal();val prepared=prepare(j)!!;val name=storedName();val before=SecureStore.data[name]
        SecureStore.unwritable.add(name)
        check(runCatching{j.begin(prepared,consent())}.isFailure&&SecureStore.data[name]==before)
        SecureStore.unwritable.remove(name);check(j.begin(prepared,consent())!=null)
    }
    test("concurrent begin admits at most one transition"){
        val j=journal();val prepared=prepare(j)!!;val start=CountDownLatch(1);val done=CountDownLatch(2)
        val results=java.util.Collections.synchronizedList(mutableListOf<HeldRecoveryJournal.Entry?>())
        repeat(2){Thread{start.await();try{results.add(journal().begin(prepared,consent()))}finally{done.countDown()}}.start()}
        start.countDown();done.await();check(results.count{it!=null}==1)
        check(j.pending(key)?.phase==HeldRecoveryJournal.Phase.ATTEMPTING)
    }
    println("PASS $checks held-consent journal checks (synthetic storage)")
}
