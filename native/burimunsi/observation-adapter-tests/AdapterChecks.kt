package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID

/** Synthetic JVM-only integration checks for the real capture, scan and coordinator classes. */
fun main() {
 var checks=0
 fun test(name:String,block:()->Unit){block();checks++;println("PASS $name")}
 val adminA=ObservationOwner("group-1","admin-1");val adminB=ObservationOwner("group-1","admin-2")
 val installation="50000000-0000-4000-8000-000000000001"
 val body="You have received 1000 RWF from EXAMPLE (*****001) at 2026-10-08 15:15:20. Balance: 2000 RWF. FT Id: 123456789."
 val time=System.currentTimeMillis()
 fun profile():JSONObject {val now=System.currentTimeMillis();return JSONObject().put("profileVersion","approved-v1")
  .put("senders",JSONArray().put("M-Money")).put("incomingPrefixes",JSONArray().put("You have received"))
  .put("currencyAliases",JSONArray().put("RWF")).put("transactionIdPrefixes",JSONArray().put("FT Id:"))
  .put("offsetMinutes",120).put("issuedAt",now).put("expiresAt",now+86_400_000L).put("legacyHold",false)}
 fun row(id:Long,text:String=body):Map<String,Any?> = mapOf("_id" to id,"address" to "M-Money","body" to text,
  "date" to time,"date_sent" to null,"sub_id" to 3)
 fun pdu(text:String,sequence:Int,reference:Int=7):ByteArray {
  val data=byteArrayOf(5,0,3,reference.toByte(),2,sequence.toByte())+text.toByteArray()
  return byteArrayOf(0,64,2,0x91.toByte(),0x21,0,4,0,0,0,0,0,0,0,data.size.toByte())+data
 }
 data class Env(val context:Context,val repository:NativeRepository,val approved:JSONObject,val observerLease:Any)
 fun setup(owner:ObservationOwner=adminA):Env {
  android.os.SystemClock.fixed=null;android.os.SystemClock.afterRead=null;NativeRepository.sessionDeadline=Long.MAX_VALUE
  app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=false;app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=false
  ReceiverFixture.reset();ObservationStateStore.reset();SecureStore.reset();Settings.Secure.testId="1234567890abcdef";NativeRepository.switch(owner)
  val observerLease=ObservationInboxRevision.observerRegistered()
  val context=Context();val approved=profile();val config=ObservationConfigStore(context)
  config.saveProfile(owner,approved,System.currentTimeMillis())
  config.saveConsent(owner,ObservationConsentState(ObservationConsentRevision(true,1),true))
  val repo=NativeRepository();repo.profile=approved;repo.consent=ObservationConsentRevision(true,1)
  return Env(context,repo,approved,observerLease)
 }
 fun receiverProfileHttp(issued:Long,sender:String="M-Money",httpStatus:Int=200):MomoGatewayHttp {
  val response=JSONObject().put("contractVersion",1).put("collectionId","group-1").put("installationId",installation)
   .put("bindingId","binding-1").put("bindingVersion",1).put("receivingAccountId","wallet-1")
   .put("profileVersion","approved-v1").put("offsetMinutes",120).put("senders",JSONArray().put(sender))
   .put("incomingPrefixes",JSONArray().put("You have received")).put("currencyAliases",JSONArray().put("RWF"))
   .put("transactionIdPrefixes",JSONArray().put("FT Id:")).put("issuedAt",issued).put("expiresAt",issued+86_400_000L)
  return MomoGatewayHttp(openConnection={target->object:HttpURLConnection(URL(target)){
   override fun connect(){};override fun disconnect(){};override fun usingProxy()=false
   override fun getResponseCode()=httpStatus
   override fun getHeaderField(name:String)=if(name.equals("Content-Type",true))"application/json" else null
   override fun getInputStream()=response.toString().byteInputStream()
  }})
 }
 fun bindReceiver(e:Env,issued:Long=System.currentTimeMillis()-16*60_000L){
  val binding=JSONObject().put("id","binding-1").put("owner_user_id","owner-1")
   .put("collection_id","group-1").put("receiving_account_id","wallet-1").put("version",1).put("subscription_id",3)
   .put("created_at",Instant.ofEpochMilli(time-60_000).toString())
  ReceiverFixture.state=JSONObject().put("binding",binding).put("gateway_token","a".repeat(64))
   .put("capture_enabled",true).put("installation_id",installation)
  check(BuriReceiverProfile.refresh(e.context,receiverProfileHttp(issued)))
 }
 fun witness(e:Env,text:String=body,sent:Long=time-1_000,at:Long=System.currentTimeMillis(),reference:Int=7):PduEvidence {
  val left=text.substring(0,55);val right=text.substring(55)
  check(ObservationPduCapture.record(e.context,NativeRepository.observationOwner(e.context)!!,at,3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1,reference),pdu(right,2,reference))))
  return PduCorrelationStore(e.context).read().pdus.last()
 }
 fun pending(owner:ObservationOwner)=ObservationJournal(ObservationStateStore(Context())).pending(owner)
 fun cloudKey(owner:ObservationOwner,id:Long,received:Long=time)=ObservationSourceIdentity.reinstallStable(
  "1234567890abcdef",owner.collectionId,id,Instant.ofEpochMilli(received).toString())
 fun seedSeen(owner:ObservationOwner,ids:LongRange):List<ObservationSeen> = ids.map{id->
  val received=Instant.ofEpochMilli(time).toString()
  ObservationSeen(owner,ObservationSourceIdentity.inbox(installation,owner,id,received),id,UUID.randomUUID().toString(),Values.sha256(body),received)
 }
 fun cursor(context:Context)=SecureStore(context,"observation-bounded-rescan-"+
  Values.sha256(listOf(adminA.collectionId,adminA.accountId,false.toString()).joinToString(""){"${it.length}:$it"})).read()
 fun runUntilSettled(e:Env,maxCycles:Int=80):ObservationCycleResult {
  var result=ObservationCycleResult(false,true)
  repeat(maxCycles){if(!result.completed&&result.more)result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})}
  return result
 }
 fun heldFixture(rows:List<Map<String,Any?>> = listOf(row(12))):Env {
  val e=setup();app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=true;e.context.contentResolver.rows=rows
  ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty())
  return e
 }
 fun auditUntilSettled(e:Env,limit:Int=30):ObservationRecovery.Audit {
  val recovery=ObservationRecovery(e.context);var result=ObservationRecovery.Audit.MORE
  repeat(limit){if(result==ObservationRecovery.Audit.MORE||result==ObservationRecovery.Audit.RETRY)result=recovery.auditPage(e.repository)}
  return result
 }
 fun heldJournal(e:Env)=HeldRecoveryJournal(e.context,adminA,installation,Values.sha256("1234567890abcdef"))
 val consent1=ObservationConsentState(ObservationConsentRevision(true,1),true)
 fun pendingHeldFixture():Pair<Env,SmsObservation>{
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.recoveryFailureAfterCommit=IllegalStateException("synthetic lost reply")
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  e.repository.recoveryFailureAfterCommit=null
  return e to e.repository.recoveryRequests.single()
 }
 test("held recovery retains an exact request and marks an attempted call before dispatch") {
  val e=setup();val key=cloudKey(adminA,12);val deviceScope=Values.sha256("synthetic-device")
  val journal=HeldRecoveryJournal(e.context,adminA,installation,deviceScope)
  val received=Instant.ofEpochMilli(time).toString()
  val prepared=journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)!!
  check(prepared.phase==HeldRecoveryJournal.Phase.PREPARED&&!prepared.toString().contains(body))
  val restarted=HeldRecoveryJournal(e.context,adminA,installation,deviceScope)
  check(restarted.prepare(12,key,"M-Money",body,received,null,3,time+20_000,consent1)==prepared)
  check(restarted.prepare(12,key,"M-Money",body+" changed",received,null,3,time+20_000,consent1)==null)
  val attempted=restarted.begin(prepared,consent1)!!
  check(attempted.phase==HeldRecoveryJournal.Phase.ATTEMPTING&&attempted.observation==prepared.observation)
  check(journal.pending(key)==attempted&&journal.begin(attempted,consent1)==null&&!journal.clear(prepared))
  check(HeldRecoveryJournal(e.context,adminB,installation,deviceScope).pending(key)==null)
  check(HeldRecoveryJournal(e.context,adminA,installation,Values.sha256("another-device")).pending(key)==null)
  check(!journal.clear(attempted))
  val ack=HeldObservationAck(ObservationAck(attempted.observation!!.requestId,"source-1",Values.sha256(body),"source_unresolved",0),"held")
  val confirmed=journal.confirm(attempted,ack,consent1)!!
  check(confirmed.phase==HeldRecoveryJournal.Phase.CONFIRMED&&confirmed.sourceId=="source-1"&&confirmed.observation==null)
  val text=SecureStore.data.filterKeys{it.startsWith("observation-held-recovery-")}.values.single()
  check(!text.contains(body)&&!text.contains("M-Money"))
  check(JSONObject(text).keys().asSequence().toSet()==setOf("version","phase","requestId","sourceId","rowDigest"))
  check(journal.pending(key)==confirmed&&!journal.clear(confirmed)&&journal.begin(confirmed,consent1)==null)
  check(restarted.prepare(12,key,"M-Money",body,received,null,3,time+50_000,consent1)==confirmed)
  check(restarted.prepare(12,key,"M-Money",body+" changed",received,null,3,time+50_000,consent1)==null)
 }
 test("a corrupt held recovery journal is not silently replaced") {
  val e=setup();val key=cloudKey(adminA,12);val journal=HeldRecoveryJournal(e.context,adminA,installation,Values.sha256("device"))
  val received=Instant.ofEpochMilli(time).toString()
  check(journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)!=null)
  val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")}
  SecureStore.data[name]="{}"
  check(runCatching{journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)}.isFailure)
 }
 test("v1 terminal records migrate without session permission or an inbox row; pending records stay exact") {
  val e=setup();val received=Instant.ofEpochMilli(time).toString()
  fun legacy(owner:ObservationOwner,id:Long,phase:String):Pair<String,SmsObservation>{
   val before=SecureStore.data.keys.toSet();val key=cloudKey(owner,id)
   val journal=HeldRecoveryJournal(e.context,owner,installation,Values.sha256("1234567890abcdef"))
   val prepared=journal.prepare(id,key,"M-Money",body,received,null,3,time,consent1)!!
   val name=(SecureStore.data.keys-before).single()
   val old=JSONObject(SecureStore.data[name]!!).put("version",1).put("phase",phase);old.remove("consentGeneration")
   if(phase!="ATTEMPTING")old.put("terminalSourceId","source-$id")
   SecureStore.data[name]=old.toString()
   return name to prepared.observation!!
  }
  val (confirmedName,confirmedRequest)=legacy(adminA,12,"CONFIRMED")
  val (matchedName,matchedRequest)=legacy(adminB,13,"MATCHED_EXISTING")
  val (pendingName,pendingRequest)=legacy(adminA,14,"ATTEMPTING")
  val pendingBefore=SecureStore.data[pendingName]!!
  val foreignName="observation-held-recovery-"+"f".repeat(64);val foreign=SecureStore.data[confirmedName]!!
  SecureStore.data[foreignName]=foreign
  NativeRepository.switch(null);e.context.denied=setOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS)
  e.context.contentResolver.rows=emptyList()
  val names=listOf(confirmedName,matchedName,pendingName,foreignName).map{"buri-$it.v1"}
  HeldRecoveryJournal.migrateLegacyFiles(e.context,names+"buri-$confirmedName.v1.bak")
  for((name,request) in listOf(confirmedName to confirmedRequest,matchedName to matchedRequest)){
   val saved=JSONObject(SecureStore.data[name]!!)
   check(saved.getInt("version")==2&&saved.getString("requestId")==request.requestId)
   check(saved.keys().asSequence().toSet()==setOf("version","phase","requestId","sourceId","rowDigest"))
   check(!SecureStore.data[name]!!.contains(body)&&!SecureStore.data[name]!!.contains("M-Money"))
  }
  check(SecureStore.data[pendingName]==pendingBefore&&SecureStore.data[foreignName]==foreign)
  check(heldJournal(e).pending(cloudKey(adminA,14))?.observation==pendingRequest)
  val restarted=HeldRecoveryJournal(e.context,adminA,installation,Values.sha256("1234567890abcdef"))
  val saved=restarted.pending(cloudKey(adminA,12))!!
  check(saved.phase==HeldRecoveryJournal.Phase.CONFIRMED&&saved.requestId==confirmedRequest.requestId&&saved.observation==null)
  check(restarted.prepare(12,cloudKey(adminA,12),"M-Money",body,received,null,3,time,consent1)==saved)
  check(restarted.prepare(12,cloudKey(adminA,12),"M-Money",body+" altered",received,null,3,time,consent1)==null)
  check(restarted.prepare(12,cloudKey(adminA,12),"M-Money",body,received,null,4,time,consent1)==null)
 }
 test("failed legacy redaction preserves the old entry for a later safe retry") {
  val e=setup();val key=cloudKey(adminA,12);val journal=heldJournal(e);val received=Instant.ofEpochMilli(time).toString()
  check(journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)!=null)
  val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")}
  val legacyObject=JSONObject(SecureStore.data[name]!!).put("version",1).put("phase","CONFIRMED").put("terminalSourceId","source-1")
  legacyObject.remove("consentGeneration");val legacy=legacyObject.toString()
  SecureStore.data[name]=legacy;SecureStore.unwritable.add(name)
  HeldRecoveryJournal.migrateLegacyFiles(e.context,listOf("buri-$name.v1"));check(SecureStore.data[name]==legacy)
  check(runCatching{journal.pending(key)}.isFailure)
  SecureStore.unwritable.remove(name);HeldRecoveryJournal.migrateLegacyFiles(e.context,listOf("buri-$name.v1"))
  check(journal.pending(key)?.phase==HeldRecoveryJournal.Phase.CONFIRMED&&!SecureStore.data[name]!!.contains(body))
 }
 test("asynchronous privacy migration retries transient failures and can be retriggered after its bound") {
  val e=setup();val received=Instant.ofEpochMilli(time).toString();val journal=heldJournal(e)
  fun terminal(id:Long):String {
   val before=SecureStore.data.keys.toSet()
   check(journal.prepare(id,cloudKey(adminA,id),"M-Money",body,received,null,3,time,consent1)!=null)
   val name=(SecureStore.data.keys-before).single()
   val legacy=JSONObject(SecureStore.data[name]!!).put("version",1).put("phase","CONFIRMED").put("terminalSourceId","source-$id")
   legacy.remove("consentGeneration");SecureStore.data[name]=legacy.toString()
   return name
  }
  val transient=terminal(12);val persistent=terminal(13);val retained=SecureStore.data[persistent]
  val firstWrites=SecureStore.writeCounts.toMap();SecureStore.unwritable.addAll(listOf(transient,persistent))
  NativeRepository.switch(null);e.context.denied=setOf(Manifest.permission.READ_SMS,Manifest.permission.RECEIVE_SMS)
  val names=listOf("buri-$transient.v1","buri-$persistent.v1")
  val checks=java.util.concurrent.atomic.AtomicInteger();val pauses=java.util.concurrent.atomic.AtomicInteger()
  val finished=java.util.concurrent.CountDownLatch(1);val result=java.util.concurrent.atomic.AtomicReference<Boolean>()
  HeldRecoveryJournal.migrateLegacyAsync(e.context,listFiles={checks.incrementAndGet();names},
   wait={if(pauses.incrementAndGet()==1)SecureStore.unwritable.remove(transient)},finished={result.set(it);finished.countDown()})
  check(finished.await(5,java.util.concurrent.TimeUnit.SECONDS)&&result.get()==false&&checks.get()==3&&pauses.get()==2)
  check(JSONObject(SecureStore.data[transient]!!).getInt("version")==2&&!SecureStore.data[transient]!!.contains(body))
  check(SecureStore.data[persistent]==retained&&SecureStore.writeCounts[persistent]!!-firstWrites.getValue(persistent)==3)
  SecureStore.unwritable.remove(persistent)
  val again=java.util.concurrent.CountDownLatch(1);val retryResult=java.util.concurrent.atomic.AtomicReference<Boolean>()
  HeldRecoveryJournal.migrateLegacyAsync(e.context,listFiles={names},wait={error("Unexpected retry")},
   finished={retryResult.set(it);again.countDown()})
  check(again.await(5,java.util.concurrent.TimeUnit.SECONDS)&&retryResult.get()==true)
  check(JSONObject(SecureStore.data[persistent]!!).getInt("version")==2&&!SecureStore.data[persistent]!!.contains(body))
  check(e.repository.recoveryRequests.isEmpty()&&e.repository.heldAckRequests.isEmpty())
 }
 test("a corrupt terminal tombstone cannot be replaced with a new request") {
  val e=setup();val key=cloudKey(adminA,12);val journal=heldJournal(e);val received=Instant.ofEpochMilli(time).toString()
  val prepared=journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)!!
  val saved=journal.markExisting(prepared,"source-1",consent1)!!;check(saved.observation==null)
  val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")}
  val bad=JSONObject(SecureStore.data[name]!!).put("rowDigest","corrupt").toString();SecureStore.data[name]=bad
  check(runCatching{journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)}.isFailure&&SecureStore.data[name]==bad)
 }
 test("invalid recovery input cannot corrupt a fresh journal") {
  val e=setup();val key=cloudKey(adminA,12);val journal=heldJournal(e)
  check(journal.prepare(12,key,"M-Money","",Instant.ofEpochMilli(time).toString(),null,3,time,consent1)==null)
  check(journal.pending(key)==null)
 }
 test("held recovery is disabled in the normal build") {
  val e=heldFixture();check(!app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED)
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.recoveryRequests.isEmpty()&&e.repository.verifiedCalls==0&&pending(adminA).isEmpty())
 }
 test("default-off client treats the draft legacy pending status as unconfirmed") {
  val e=heldFixture();e.repository.statusReplyOverride={_,status->status.copy(hasPending=true)}
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&result.problem=="sync_unconfirmed")
  check(e.repository.recoveryRequests.isEmpty()&&e.repository.verifiedCalls==0&&ObservationRecovery(e.context).auditStartedAt()==null)
 }
 test("enabled recovery retains a missing held source without releasing it or queuing financial work") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  check(auditUntilSettled(e)==ObservationRecovery.Audit.COMPLETE)
  val request=e.repository.recoveryRequests.single();val saved=heldJournal(e).pending(cloudKey(adminA,12))!!
  check(request.sourceMode=="catch_up"&&!request.complete&&request.sourceKey==cloudKey(adminA,12))
  check(saved.phase==HeldRecoveryJournal.Phase.CONFIRMED&&saved.observation==null&&saved.requestId==request.requestId&&saved.sourceId!=null)
  check(e.repository.recoveryCommitted.size==1&&pending(adminA).isEmpty())
  ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty())
  check(auditUntilSettled(e)==ObservationRecovery.Audit.COMPLETE&&e.repository.recoveryRequests.size==1)
 }
 test("an already matched held source stays read-only") {
  val e=heldFixture();e.repository.retainedSources[cloudKey(adminA,12)]="source-1"
  app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true;e.repository.verifiedFailure=IllegalStateException("unavailable")
  check(auditUntilSettled(e)==ObservationRecovery.Audit.COMPLETE)
  check(e.repository.recoveryRequests.isEmpty()&&e.repository.verifiedCalls==0)
 }
 test("a confirmed recovery whose Cloud source disappears cannot mint a second request") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  check(auditUntilSettled(e)==ObservationRecovery.Audit.COMPLETE)
  val first=e.repository.recoveryRequests.single();e.repository.retainedSources.clear()
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.recoveryRequests==listOf(first)&&heldJournal(e).pending(cloudKey(adminA,12))?.phase==HeldRecoveryJournal.Phase.CONFIRMED)
 }
 test("an ambiguous server reconciliation never becomes a recovery request") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.poisonSourceKeys=setOf(cloudKey(adminA,12))
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.recoveryRequests.isEmpty()&&e.repository.verifiedCalls==0)
 }
 test("verified scope unavailable changed pending or stale never dispatches recovery") {
  for(kind in listOf("unavailable","scope","changed_scope","pending","unmatched","stale")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   when(kind){
    "unavailable"->e.repository.verifiedFailure=IllegalStateException("unavailable")
    "scope"->e.repository.verifiedScope="other"
    "changed_scope"->e.repository.afterVerified={if(it==1)e.repository.verifiedScope="other"}
    "pending"->e.repository.verifiedPending=true
    "unmatched"->e.repository.verifiedUnmatched=true
    "stale"->e.repository.afterVerified={if(it==1)e.repository.verifiedRevisionOverride="a".repeat(64)}
   }
   check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
   check(e.repository.recoveryRequests.isEmpty()&&heldJournal(e).pending(cloudKey(adminA,12))==null)
  }
 }
 test("unscoped legacy pending or canonical receipts allow held-only recovery but never full equality") {
  for(kind in listOf("pending","unmatched")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   e.repository.statusReplyOverride={_,status->if(kind=="pending")status.copy(hasPending=true)else status.copy(hasUnmatchedCanonical=true)}
   e.repository.verifiedPending=false;e.repository.verifiedUnmatched=false
   check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
   check(e.repository.recoveryRequests.size==1&&e.repository.recoveryCommitted.size==1)
   check(ObservationRecovery(e.context).auditStartedAt()==null&&pending(adminA).isEmpty())
  }
 }
 test("the real sync cycle runs scoped held recovery but remains unconfirmed for legacy pending") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.statusReplyOverride={_,status->status.copy(hasPending=true)};e.repository.verifiedPending=false
  val result=runUntilSettled(e)
  check(!result.completed&&result.problem=="sync_unconfirmed")
  check(e.repository.recoveryRequests.size==1&&e.repository.recoveryCommitted.size==1&&pending(adminA).isEmpty())
  check(ObservationRecovery(e.context).auditStartedAt()==null)
 }
 test("an unconfirmed legacy status advances past several independently recovered held rows") {
  val e=heldFixture(listOf(row(12),row(13)+("date" to (time+1))))
  app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.statusReplyOverride={_,status->status.copy(hasPending=true)};e.repository.verifiedPending=false
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.recoveryRequests.size==2&&e.repository.recoveryCommitted.size==2&&e.repository.statusCalls==1)
  check(ObservationRecovery(e.context).auditStartedAt()==null&&pending(adminA).isEmpty())
 }
 test("duplicate phone witnesses even after the selected row cannot be recovered") {
  val e=heldFixture(listOf(row(12),row(13)+("address" to "m-money")));app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  check(auditUntilSettled(e)==ObservationRecovery.Audit.BLOCKED)
  check(e.repository.recoveryRequests.isEmpty()&&e.repository.recoveryCommitted.isEmpty())
 }
 test("owner permission consent and inbox revision changes stop dispatch") {
  for(kind in listOf("owner","permission","consent","pause","revision")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   e.repository.afterVerified={if(it==1)when(kind){
    "owner"->NativeRepository.switch(adminB)
    "permission"->e.context.denied=setOf(Manifest.permission.READ_SMS)
    "consent"->{val c=ObservationConfigStore(e.context);c.saveConsent(adminA,c.consent(adminA)!!.copy(confirmed=false))}
    "pause"->ObservationConfigStore(e.context).setPaused(adminA,true)
    "revision"->ObservationInboxRevision.changed()
   }}
   check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
   check(e.repository.recoveryRequests.isEmpty())
  }
 }
 test("consent or permission changes at a journal write stop dispatch and retain the original generation") {
  for(phase in listOf("PREPARED","ATTEMPTING"))for(kind in listOf("consent","permission","owner")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true;var changed=false
   SecureStore.afterWrite={name,text->
    if(name.startsWith("observation-held-recovery-")&&JSONObject(text).optString("phase")==phase){
     SecureStore.afterWrite=null;changed=true
     when(kind){
      "consent"->ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(true,2),true))
      "permission"->e.context.denied=setOf(Manifest.permission.RECEIVE_SMS)
      else->NativeRepository.switch(adminB)
     }
    }
   }
   check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
   check(changed&&e.repository.recoveryRequests.isEmpty())
   val saved=heldJournal(e).pending(cloudKey(adminA,12))!!
   check(saved.phase.name==phase&&saved.consentGeneration==1L&&saved.observation!=null)
   if(kind=="consent"){
    e.repository.consent=ObservationConsentRevision(true,2)
    check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
    check(e.repository.recoveryRequests.isEmpty()&&heldJournal(e).pending(cloudKey(adminA,12))==saved)
   }
  }
 }
 test("revocation during a held audit read cannot reach a journal write") {
  for(stage in listOf("status","batch"))for(kind in listOf("consent","permission")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   val revoke={
    if(kind=="consent")ObservationConfigStore(e.context).saveConsent(adminA,
     ObservationConsentState(ObservationConsentRevision(true,2),true))
    else e.context.denied=setOf(Manifest.permission.READ_SMS)
    Unit
   }
   if(stage=="status")e.repository.afterStatus={calls->if(calls==1)revoke()}
   else e.repository.afterBatch=revoke
   check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
   check(e.repository.recoveryRequests.isEmpty()&&heldJournal(e).pending(cloudKey(adminA,12))==null)
  }
 }
 test("a revocation racing terminal redaction remains unconfirmed and cannot mint another request") {
  for(phase in listOf("MATCHED_EXISTING","CONFIRMED")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   val key=cloudKey(adminA,12);val journal=heldJournal(e)
   if(phase=="MATCHED_EXISTING"){
    check(journal.prepare(12,key,"M-Money",body,Instant.ofEpochMilli(time).toString(),null,3,time,consent1)!=null)
    e.repository.retainedSources[key]="source-1"
   }
   var changed=false
   SecureStore.afterWrite={name,text->
    if(name.startsWith("observation-held-recovery-")&&JSONObject(text).optString("phase")==phase){
     SecureStore.afterWrite=null;changed=true;e.context.denied=setOf(Manifest.permission.READ_SMS)
    }
   }
   check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
   val terminal=journal.pending(key)!!
   check(changed&&terminal.phase.name==phase&&terminal.observation==null)
   val before=e.repository.recoveryRequests.toList()
   check(before.size==if(phase=="CONFIRMED")1 else 0)
   e.context.denied=emptySet();val next=ObservationConsentRevision(true,2)
   ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(next,true));e.repository.consent=next
   auditUntilSettled(e)
   check(e.repository.recoveryRequests==before&&journal.pending(key)==terminal)
  }
 }
 test("lost response after server commit remains pending without a second upload") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.recoveryFailureAfterCommit=IllegalStateException("timeout")
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  val first=e.repository.recoveryRequests.single();val key=cloudKey(adminA,12)
  check(heldJournal(e).pending(key)?.phase==HeldRecoveryJournal.Phase.ATTEMPTING&&e.repository.recoveryCommitted.size==1)
  val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")};val stored=SecureStore.data[name]
  e.repository.recoveryFailureAfterCommit=null
  for(isPending in listOf(true,false)){
   e.repository.verifiedPending=isPending
   e.repository.statusReplyOverride={_,status->status.copy(hasPending=isPending)}
   check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
   check(e.repository.recoveryRequests==listOf(first)&&heldJournal(e).pending(key)?.observation==first&&SecureStore.data[name]==stored)
  }
  check(e.repository.recoveryCommitted.size==1)
 }
 test("lost response before server commit preserves the exact request without replay") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.recoveryFailureBeforeCommit=IllegalStateException("timeout")
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  val first=e.repository.recoveryRequests.single();check(e.repository.recoveryCommitted.isEmpty())
  e.repository.recoveryFailureBeforeCommit=null
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.recoveryRequests==listOf(first)&&e.repository.recoveryCommitted.isEmpty())
  check(heldJournal(e).pending(cloudKey(adminA,12))?.observation==first)
 }
 test("a crash after the local attempt marker but before dispatch never invents a retry") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  val key=cloudKey(adminA,12);val received=Instant.ofEpochMilli(time).toString();val journal=heldJournal(e)
  val prepared=journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)!!
  val attempted=journal.begin(prepared,consent1)!!;val original=attempted.observation!!
  val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")};val originalBytes=SecureStore.data[name]
  // A restarted process cannot infer from an empty server whether a delayed
  // copy of the original POST is still in flight.
  repeat(3){check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)}
  check(e.repository.heldAckRequests==listOf(original,original,original)&&e.repository.recoveryRequests.isEmpty())
  check(heldJournal(e).pending(key)==attempted&&SecureStore.data[name]==originalBytes)
 }
 test("legacy uncertain journals without a consent witness cannot be acknowledged or resent") {
  for(phase in listOf("PREPARED","ATTEMPTING")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   val key=cloudKey(adminA,12);val received=Instant.ofEpochMilli(time).toString();val journal=heldJournal(e)
   val prepared=journal.prepare(12,key,"M-Money",body,received,null,3,time,consent1)!!
   if(phase=="ATTEMPTING")check(journal.begin(prepared,consent1)!=null)
   val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")}
   val legacy=JSONObject(SecureStore.data[name]!!).put("version",1);legacy.remove("consentGeneration")
   val original=legacy.toString();SecureStore.data[name]=original;e.repository.heldAckAcknowledged=true
   repeat(2){check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))}
   check(SecureStore.data[name]==original&&journal.pending(key)?.consentGeneration==null&&
    e.repository.heldAckRequests.isEmpty()&&e.repository.recoveryRequests.isEmpty())
  }
 }
 test("concurrent unconfirmed ACK checks never generate a recovery POST") {
  val (e,original)=pendingHeldFixture();val recovery=ObservationRecovery(e.context)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
  e.repository.afterHeldAck={entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS))}
  val first=java.util.concurrent.atomic.AtomicReference<ObservationRecovery.Audit>()
  val second=java.util.concurrent.atomic.AtomicReference<ObservationRecovery.Audit>()
  val one=Thread{first.set(recovery.auditPage(e.repository))};val two=Thread{second.set(recovery.auditPage(e.repository))}
  one.start();check(entered.await(5,java.util.concurrent.TimeUnit.SECONDS));two.start();release.countDown()
  one.join(5_000);two.join(5_000);check(!one.isAlive&&!two.isAlive)
  check(first.get()==ObservationRecovery.Audit.UNCONFIRMED&&second.get()==ObservationRecovery.Audit.MORE)
  check(e.repository.recoveryRequests==listOf(original)&&e.repository.heldAckRequests==listOf(original))
  check(heldJournal(e).pending(cloudKey(adminA,12))?.observation==original)
 }
 test("a newer consent generation cannot turn an unconfirmed ACK into a resend") {
  val (e,original)=pendingHeldFixture();val config=ObservationConfigStore(e.context)
  val renewed=ObservationConsentRevision(true,2);config.saveConsent(adminA,ObservationConsentState(renewed,true));e.repository.consent=renewed
  repeat(2){check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)}
  check(e.repository.recoveryRequests==listOf(original)&&e.repository.heldAckRequests.isEmpty())
  check(heldJournal(e).pending(cloudKey(adminA,12))?.observation==original)
 }
 test("exact read-only held ACK resolves a pending source before a poisoned batch") {
  val (e,original)=pendingHeldFixture();val key=cloudKey(adminA,12)
  e.repository.heldAckAcknowledged=true;e.repository.poisonSourceKeys=setOf(key)
  e.repository.statusReplyOverride={_,status->status.copy(hasPending=true)};e.repository.verifiedPending=true
  val batches=e.repository.reconciliationBatches.size;val recovery=ObservationRecovery(e.context)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.RETRY)
  val entry=heldJournal(e).pending(key)!!
  check(entry.phase==HeldRecoveryJournal.Phase.CONFIRMED&&entry.requestId==original.requestId&&entry.observation==null)
  check(e.repository.heldAckRequests==listOf(original)&&e.repository.recoveryRequests==listOf(original)&&
   e.repository.reconciliationBatches.size==batches)
  val saved=SecureStore.data.filterKeys{it.startsWith("observation-held-recovery-")}.values.single()
  check(!saved.contains(body)&&!saved.contains("M-Money"))
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED&&recovery.auditStartedAt()==null)
 }
 test("unconfirmed or unavailable ACK lookups keep exact bytes and can be polled without resending") {
  for(kind in listOf("unconfirmed","404","403","409","503","timeout")){
   val (e,original)=pendingHeldFixture();val key=cloudKey(adminA,12)
   val name=SecureStore.data.keys.single{it.startsWith("observation-held-recovery-")};val before=SecureStore.data[name]
   if(kind!="unconfirmed")e.repository.heldAckFailure=if(kind=="timeout")java.net.SocketTimeoutException() else
    rw.ikanisa.burimunsi.data.ApiFailure("synthetic",kind.toInt(),true)
   check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
   check(e.repository.heldAckRequests==listOf(original)&&e.repository.recoveryRequests==listOf(original)&&
    heldJournal(e).pending(key)?.observation==original&&SecureStore.data[name]==before)
   e.repository.heldAckFailure=null;e.repository.heldAckAcknowledged=true
   check(auditUntilSettled(e)==ObservationRecovery.Audit.COMPLETE)
   check(e.repository.heldAckRequests==listOf(original,original)&&e.repository.recoveryRequests==listOf(original)&&
    heldJournal(e).pending(key)?.phase==HeldRecoveryJournal.Phase.CONFIRMED)
  }
 }
 test("forged read-only ACK never changes a pending request") {
  for(kind in listOf("request","source_key","digest","source","state","processing","financial","retry")){
   val (e,original)=pendingHeldFixture();e.repository.heldAckAcknowledged=true
   e.repository.heldAckOverride={a->when(kind){
    "request"->a.copy(requestId="00000000-0000-4000-8000-000000000099")
    "source_key"->a.copy(sourceKey="b".repeat(64))
    "digest"->a.copy(bodySha256="b".repeat(64))
    "source"->a.copy(sourceId=null)
    "state"->a.copy(state="unconfirmed")
    "processing"->a.copy(autoProcessing="unknown")
    "financial"->a.copy(financialEffects=1)
    else->a.copy(retryAllowed=true)
   }}
   check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
   check(e.repository.recoveryRequests==listOf(original)&&e.repository.heldAckRequests==listOf(original)&&
    heldJournal(e).pending(cloudKey(adminA,12))?.observation==original)
  }
 }
 test("a changed source row cannot issue an ACK lookup or create a replacement ID") {
  val (e,original)=pendingHeldFixture();e.repository.heldAckAcknowledged=true
  e.context.contentResolver.rows=listOf(row(12,body+" modified"))
  check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
  check(e.repository.heldAckRequests.isEmpty()&&e.repository.recoveryRequests==listOf(original)&&
   heldJournal(e).pending(cloudKey(adminA,12))?.observation==original)
 }
 test("owner consent permission installation and inbox changes after ACK preserve the uncertain request") {
  for(kind in listOf("owner","consent","regrant","pause","permission","installation","inbox","duplicate","revision","device","profile")){
   val (e,original)=pendingHeldFixture();e.repository.heldAckAcknowledged=true
   e.repository.afterHeldAck={when(kind){
    "owner"->NativeRepository.switch(adminB)
    "consent"->{val c=ObservationConfigStore(e.context);c.saveConsent(adminA,c.consent(adminA)!!.copy(confirmed=false))}
    "regrant"->{val next=ObservationConsentRevision(true,2);ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(next,true));e.repository.consent=next}
    "pause"->ObservationConfigStore(e.context).setPaused(adminA,true)
    "permission"->e.context.denied=setOf(Manifest.permission.RECEIVE_SMS)
    "installation"->ReceiverFixture.installationId="50000000-0000-4000-8000-000000000002"
    "inbox"->e.context.contentResolver.rows=emptyList()
    "duplicate"->e.context.contentResolver.rows=listOf(row(12),row(13))
    "revision"->ObservationInboxRevision.changed()
    "device"->Settings.Secure.testId="1111111111111111"
    "profile"->{e.approved.put("profileVersion","other-v2");ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())}
   }}
   check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
   check(e.repository.heldAckRequests==listOf(original)&&e.repository.recoveryRequests==listOf(original)&&
    heldJournal(e).pending(cloudKey(adminA,12))?.observation==original)
  }
 }
 test("changed inbox content after an unknown outcome cannot replace its request") {
  val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
  e.repository.recoveryFailureBeforeCommit=IllegalStateException("timeout")
  check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
  val first=e.repository.recoveryRequests.single();e.repository.recoveryFailureBeforeCommit=null
  e.context.contentResolver.rows=listOf(row(12,body+" changed"))
  check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
  check(e.repository.recoveryRequests==listOf(first)&&e.repository.heldAckRequests.isEmpty()&&
   heldJournal(e).pending(cloudKey(adminA,12))?.observation==first)
 }
 test("post-dispatch permission change or invalid hold acknowledgement preserves uncertainty") {
  for(kind in listOf("permission","consent","ack","duplicate","missing","owner")){
   val e=heldFixture();app.cool.mobile.BuildConfig.HELD_RECOVERY_ENABLED=true
   when(kind){
    "permission"->e.repository.afterRecovery={e.context.denied=setOf(Manifest.permission.READ_SMS)}
    "consent"->e.repository.afterRecovery={val next=ObservationConsentRevision(true,2);ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(next,true));e.repository.consent=next}
    "ack"->e.repository.recoveryAckOverride={it.copy(autoProcessing="released")}
    "duplicate"->e.repository.afterRecovery={e.context.contentResolver.rows=listOf(row(12),row(13))}
    "missing"->e.repository.afterRecovery={e.context.contentResolver.rows=emptyList()}
    "owner"->e.repository.afterRecovery={NativeRepository.switch(adminB)}
   }
   check(auditUntilSettled(e) in setOf(ObservationRecovery.Audit.BLOCKED,ObservationRecovery.Audit.UNCONFIRMED))
   val first=e.repository.recoveryRequests.single();check(heldJournal(e).pending(cloudKey(adminA,12))?.phase==HeldRecoveryJournal.Phase.ATTEMPTING)
   e.context.denied=emptySet();e.context.contentResolver.rows=listOf(row(12));e.repository.recoveryAckOverride=null
   if(kind=="owner")NativeRepository.switch(adminA)
   check(auditUntilSettled(e)==ObservationRecovery.Audit.UNCONFIRMED)
   check(e.repository.recoveryRequests==listOf(first)&&e.repository.recoveryCommitted.size==1)
   check(heldJournal(e).pending(cloudKey(adminA,12))?.observation==first)
  }
 }
 test("missing device identity keeps the inbox row unacknowledged for later recovery") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1));Settings.Secure.testId=null
  ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty());check(cursor(e.context)==null)
  Settings.Secure.testId="1234567890abcdef";ObservationRecovery(e.context).scan()
  check(pending(adminA).single().observation.sourceKey!=null)
 }
 test("missing inbox identity is not uploaded or acknowledged") {
  val e=setup();val session=NativeRepository.observationOwner(e.context)!!
  val fingerprint=ObservationConfigStore(e.context).profile(adminA,System.currentTimeMillis())!!.fingerprint()
  check(ObservationCapture.retain(e.context,session,fingerprint,"inbox:0","M-Money",body,"catch_up",false,
   null,Instant.ofEpochMilli(time).toString(),3)==ObservationCapture.Result.UNAVAILABLE)
  check(pending(adminA).isEmpty())
 }
 test("same device and inbox row keep their source identity after reinstall or account switch") {
  val e=setup(adminA);e.context.contentResolver.rows=listOf(row(11),row(12));ObservationRecovery(e.context).scan()
  val first=pending(adminA).map{it.observation.sourceKey};check(first.size==2&&first.toSet().size==2)
  val replacement=setup(adminB);replacement.context.contentResolver.rows=listOf(row(11),row(12));ObservationRecovery(replacement.context).scan()
  check(pending(adminB).map{it.observation.sourceKey}==first)
 }
 test("legacy snapshot holds existing rows but syncs later lower IDs and older timestamps") {
  val e=setup();e.approved.put("legacyHold",true);ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(100));val recovery=ObservationRecovery(e.context)
  check(recovery.backfill()==ObservationRecovery.Backfill.COMPLETE);recovery.scan();check(pending(adminA).isEmpty())
  e.context.contentResolver.rows=listOf(row(100),row(150));ObservationRecovery(e.context).scan()
  check(pending(adminA).size==1)
  e.context.contentResolver.rows=listOf(row(50)+("date" to (time-86_400_000L)),row(100),row(150))
  ObservationRecovery(e.context).scan();check(pending(adminA).size==2)
  check(pending(adminA).map{it.observation.sourceKey}.toSet().size==2)
 }
 test("clean Cloud receiver holds existing inbox rows even when the server has no legacy records") {
  val e=setup();app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=true
  try {
   e.context.contentResolver.rows=listOf(row(100));val recovery=ObservationRecovery(e.context)
   check(recovery.backfill()==ObservationRecovery.Backfill.COMPLETE)
   recovery.scan();check(pending(adminA).isEmpty())
   e.context.contentResolver.rows=listOf(row(100),row(101));recovery.scan()
   check(pending(adminA).size==1)
   recovery.scan();check(pending(adminA).size==1)
  } finally { app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=false }
 }
 test("insertion during legacy snapshot is processed after the held snapshot commits") {
  val e=setup();e.approved.put("legacyHold",true);ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(10));e.context.contentResolver.afterDateRead={e.context.contentResolver.rows=listOf(row(10),row(11))}
  ObservationRecovery(e.context).scan();check(pending(adminA).size==1)
 }
 test("permission revocation during legacy snapshot holds all rows until recovery") {
  val e=setup();e.approved.put("legacyHold",true);ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(10));e.context.contentResolver.afterDateRead={e.context.denied=setOf(Manifest.permission.READ_SMS)}
  ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty())
  e.context.denied=emptySet();ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty())
  e.context.contentResolver.rows=listOf(row(10),row(11));ObservationRecovery(e.context).scan();check(pending(adminA).size==1)
 }
 test("legacy held identities survive process restart while offline new rows remain queued") {
  val e=setup();e.approved.put("legacyHold",true);ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(100));ObservationRecovery(e.context).scan()
  e.context.contentResolver.rows=listOf(row(100),row(101));ObservationRecovery(e.context).scan()
  val queued=pending(adminA).single().observation;e.repository.failSubmit=true
  check(!ObservationCoordinator(e.context,e.repository).cycle());check(pending(adminA).single().observation==queued)
  ObservationRecovery(e.context).scan();check(pending(adminA).single().observation==queued)
  e.repository.failSubmit=false;check(ObservationCoordinator(e.context,e.repository).cycle());check(pending(adminA).isEmpty())
  ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty())
 }
 test("a reused row ID with a later received time is a distinct unheld message") {
  val e=setup();e.approved.put("legacyHold",true);ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(100));ObservationRecovery(e.context).scan();check(pending(adminA).isEmpty())
  e.context.contentResolver.rows=listOf(row(100)+("date" to (time+1)));ObservationRecovery(e.context).scan()
  check(pending(adminA).size==1)
 }
 test("a lower-ID restored message arriving mid-sweep is picked up on the next bounded sweep") {
  val e=setup();e.approved.put("legacyHold",true);ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  val old=(1L..201L).map{row(it*2)};e.context.contentResolver.rows=old
  check(ObservationRecovery(e.context).scan());check(pending(adminA).isEmpty())
  e.context.contentResolver.rows=old+listOf(row(101)+("date" to (time-86_400_000L)))
  repeat(5){ObservationRecovery(e.context).scan()}
  check(pending(adminA).size==1)
 }
 test("a collection without legacy requests catches restored lower IDs after a restart") {
  val e=setup();e.context.contentResolver.rows=listOf(row(100),row(150));ObservationRecovery(e.context).scan()
  val original=pending(adminA).map{it.observation.requestId};check(original.size==2)
  e.context.contentResolver.rows=listOf(row(50)+("date" to (time-86_400_000L)),row(100),row(150))
  ObservationRecovery(e.context).scan()
  val recovered=pending(adminA).map{it.observation.requestId}
  check(recovered.size==3&&recovered.take(2)==original&&recovered.toSet().size==3)
 }
 test("a collection without legacy requests captures a reused row ID with a new received time") {
  val e=setup();e.context.contentResolver.rows=listOf(row(100));ObservationRecovery(e.context).scan()
  e.context.contentResolver.rows=listOf(row(100)+("date" to (time+1)));ObservationRecovery(e.context).scan()
  check(pending(adminA).size==2&&pending(adminA).map{it.observation.sourceKey}.toSet().size==2)
 }
 test("unidentified old local rows are held without blocking newer no-legacy captures") {
  val e=setup();val request=UUID.randomUUID().toString()
  val old=ObservationSeen(adminA,ObservationSourceIdentity.inbox(installation,adminA,1000),1000,request,Values.sha256(body))
  ObservationStateStore.value=ObservationJournalState(emptyList(),listOf(old))
  e.context.contentResolver.rows=listOf(row(1000),row(1001));ObservationRecovery(e.context).scan()
  check(pending(adminA).size==1&&pending(adminA).single().observation.sourceKey==
   ObservationSourceIdentity.reinstallStable("1234567890abcdef",adminA.collectionId,1001,Instant.ofEpochMilli(time).toString()))
 }
 test("a lower-ID insertion during a no-legacy sweep is found on the following sweep") {
  val e=setup();val rows=(1L..201L).map{row(it*2)};e.context.contentResolver.rows=rows
  check(ObservationRecovery(e.context).scan());check(pending(adminA).size==100)
  e.context.contentResolver.rows=rows+listOf(row(101)+("date" to (time-86_400_000L)))
  repeat(4){ObservationRecovery(e.context).scan()}
  check(pending(adminA).size==202&&pending(adminA).map{it.observation.sourceKey}.toSet().size==202)
 }
 test("scanner uses dynamic sender selection to reach candidates after unrelated inbox rows") {
  val e=setup();e.context.contentResolver.rows=(1L..3000L).map{row(it)+("address" to "Other")} +
   listOf(row(3001),row(3002))
  ObservationRecovery(e.context).scan();ObservationRecovery(e.context).scan()
  check(pending(adminA).size==2)
  check(e.context.contentResolver.querySelection?.contains("address COLLATE NOCASE")==true)
  check(e.context.contentResolver.querySelection?.contains("M-Money")==false)
 }
 test("provider selection refusal falls back to the complete inbox scan") {
  val e=setup();e.context.contentResolver.rejectFilteredSelection=true;e.context.contentResolver.rows=listOf(row(5))
  ObservationRecovery(e.context).scan()
  check(pending(adminA).size==1&&e.context.contentResolver.querySelection=="_id > ?")
 }
 test("sender selection retains non-ASCII case equivalents for final matching") {
  val e=setup();e.approved.put("senders",JSONArray().put("Kiosk"));ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(6)+("address" to "Kiosk"))
  ObservationRecovery(e.context).scan()
  check(pending(adminA).size==1&&e.context.contentResolver.querySelection?.contains("GLOB")==true)
 }
 test("non-ASCII configured senders use the complete inbox scan") {
  val e=setup();e.approved.put("senders",JSONArray().put("Kiosk"));ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(7)+("address" to "Kiosk"))
  ObservationRecovery(e.context).scan()
  check(pending(adminA).size==1&&e.context.contentResolver.querySelection=="_id > ?")
 }
 test("scanner accepts sender-scoped messages regardless of incoming markers") {
  val e=setup();val outgoing="Transfer completed to another account.\r\nRef:\t5678"
  e.context.contentResolver.rows=listOf(row(9,outgoing),row(10,"Your OTP is 1234"),row(11),
   row(12,"Other sender message")+("address" to "Other"),row(13,"Invalid\u0000body"))
  ObservationRecovery(e.context).scan()
  val retained=pending(adminA).map{it.observation}
  check(retained.map{it.rawBody}==listOf(outgoing,"Your OTP is 1234",body))
  check(retained.all{it.sourceMode=="catch_up"&&!it.complete&&it.inboxReceivedAt!=null})
  check(cursor(e.context)!=null)
 }
 test("upgrade backfills previously filtered messages without replaying old accepted receipts") {
  val e=setup();val fingerprint=ObservationConfigStore(e.context).profile(adminA,System.currentTimeMillis())!!.fingerprint()
  val prior=JSONArray().put(JSONObject().put("collectionId",adminA.collectionId).put("accountId",adminA.accountId)
   .put("profileFingerprint",fingerprint).put("lastId",3000L))
  SecureStore(e.context,"observation-cursors").write(JSONObject().put("items",prior).toString())
  e.context.contentResolver.rows=listOf(row(100,body),row(1100,"Transfer sent 100 RWF"),row(2000,body),
   row(2500,"Provider notice"),row(3001,"Transfer sent 500 RWF"))
  check(ObservationRecovery(e.context).backfill()==ObservationRecovery.Backfill.COMPLETE)
  check(pending(adminA).map{it.observation.rawBody}==listOf("Transfer sent 100 RWF","Provider notice"))
  check(ObservationRecovery(e.context).backfill()==ObservationRecovery.Backfill.COMPLETE)
  ObservationRecovery(e.context).scan()
  check(pending(adminA).map{it.observation.rawBody}==listOf("Transfer sent 100 RWF","Provider notice","Transfer sent 500 RWF"))
 }
 test("backfill permission loss does not advance its protected cursor") {
  val e=setup();val fingerprint=ObservationConfigStore(e.context).profile(adminA,System.currentTimeMillis())!!.fingerprint()
  val prior=JSONArray().put(JSONObject().put("collectionId",adminA.collectionId).put("accountId",adminA.accountId)
   .put("profileFingerprint",fingerprint).put("lastId",100L))
  SecureStore(e.context,"observation-cursors").write(JSONObject().put("items",prior).toString())
  e.context.contentResolver.rows=listOf(row(40,"Transfer sent 100 RWF"))
  e.context.contentResolver.afterBodyRead={e.context.denied=setOf(Manifest.permission.READ_SMS)}
  check(ObservationRecovery(e.context).backfill()==ObservationRecovery.Backfill.BLOCKED&&pending(adminA).isEmpty())
  e.context.denied=emptySet()
  check(ObservationRecovery(e.context).backfill()==ObservationRecovery.Backfill.COMPLETE&&pending(adminA).size==1)
 }
 test("fresh installation initializes an empty backfill and scans normally") {
  val e=setup();e.context.contentResolver.rows=listOf(row(5,"Transfer sent 100 RWF"))
  check(ObservationRecovery(e.context).backfill()==ObservationRecovery.Backfill.COMPLETE)
  ObservationRecovery(e.context).scan();check(pending(adminA).size==1)
  check(ObservationRecovery(e.context).backfill()==ObservationRecovery.Backfill.COMPLETE&&pending(adminA).size==1)
 }
 test("catch-up preserves the provider timestamp without asserting completeness") {
  val e=setup();val sent=time-5_000;e.context.contentResolver.rows=listOf(row(12)+("date_sent" to sent))
  ObservationRecovery(e.context).scan()
  val value=pending(adminA).single().observation
  check(value.serviceCentreAt==Instant.ofEpochMilli(sent).toString()&&value.inboxReceivedAt==Instant.ofEpochMilli(time).toString())
  check(value.sourceMode=="catch_up"&&!value.complete)
 }
 test("candidate broadcast and its durable inbox request correlate locally without creating a second observation") {
  val e=setup();val session=NativeRepository.observationOwner(e.context)!!;val sent=time-1_000
  val left=body.substring(0,55);val right=body.substring(55)
  check(ObservationPduCapture.record(e.context,session,System.currentTimeMillis(),3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(right,left),listOf(pdu(right,2),pdu(left,1))))
  e.context.contentResolver.rows=listOf(row(13)+("date_sent" to sent));ObservationRecovery(e.context).scan()
  val state=PduCorrelationStore(e.context).read();val witness=state.pdus.single();val item=pending(adminA).single().observation
  check(state.inbox.single().requestId==item.requestId&&PduInboxCorrelation.status(state,witness.witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
  check(witness.structurallyComplete&&item.sourceMode=="catch_up"&&!item.complete&&e.repository.requests.isEmpty())
  ObservationRecovery(e.context).scan();check(pending(adminA).size==1&&PduCorrelationStore(e.context).read().inbox.size==1)
 }
 test("inbox-first capture is correlated using the original retained request identity") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(14)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val original=pending(adminA).single().observation
  val session=NativeRepository.observationOwner(e.context)!!;val left=body.substring(0,55);val right=body.substring(55)
  check(ObservationPduCapture.record(e.context,session,System.currentTimeMillis(),3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1),pdu(right,2))))
  ObservationRecovery(e.context).correlateRecent()
  val state=PduCorrelationStore(e.context).read();check(state.inbox.single().requestId==original.requestId)
  check(PduInboxCorrelation.status(state,state.pdus.single().witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
  check(pending(adminA).single().observation==original&&e.repository.requests.isEmpty())
 }
 test("inbox-first identical rows remain separate and make PDU correlation ambiguous") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(15)+("date_sent" to sent),row(16)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();check(pending(adminA).size==2)
  val session=NativeRepository.observationOwner(e.context)!!;val left=body.substring(0,55);val right=body.substring(55)
  check(ObservationPduCapture.record(e.context,session,System.currentTimeMillis(),3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1),pdu(right,2))))
  ObservationRecovery(e.context).correlateRecent()
  val state=PduCorrelationStore(e.context).read()
  check(state.inbox.size==2&&state.inbox.map{it.requestId}.toSet().size==2)
  check(PduInboxCorrelation.status(state,state.pdus.single().witnessId)==CorrelationStatus.AMBIGUOUS)
 }
 test("permission revocation during inbox-first correlation cannot attach PDU evidence") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(17)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val session=NativeRepository.observationOwner(e.context)!!
  val left=body.substring(0,55);val right=body.substring(55)
  check(ObservationPduCapture.record(e.context,session,System.currentTimeMillis(),3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1),pdu(right,2))))
  e.context.contentResolver.afterBodyRead={e.context.denied=setOf(Manifest.permission.READ_SMS)}
  ObservationRecovery(e.context).correlateRecent();check(PduCorrelationStore(e.context).read().inbox.isEmpty())
  check(pending(adminA).size==1)
 }
 test("500 irrelevant provider rows avoid per-row protected configuration and correlation reads") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(500,"Provider seed"))
  ObservationRecovery(e.context).scan();val original=pending(adminA);val pdu=witness(e,sent=sent)
  e.context.contentResolver.rows=(1L..500L).map{row(it,"Provider notice $it")+("date_sent" to sent)}
  SecureStore.readCounts.clear();e.context.contentResolver.cursorRowsRead=0;e.context.contentResolver.bodyReads=0
  ObservationRecovery(e.context).correlateRecent()
  val profileReads=SecureStore.readCounts["observation-profile"]?:0
  val consentReads=SecureStore.readCounts["observation-consent"]?:0
  val correlationReads=SecureStore.readCounts["pdu-correlation"]?:0
  println("correlation_prefilter_probe rows=${e.context.contentResolver.bodyReads} profile_reads=$profileReads consent_reads=$consentReads pdu_reads=$correlationReads")
  check(e.context.contentResolver.cursorRowsRead==500&&e.context.contentResolver.bodyReads==500)
  check(profileReads==1&&consentReads==1&&correlationReads==1)
  val state=PduCorrelationStore(e.context).read()
  check(state.inbox.isEmpty()&&PduInboxCorrelation.status(state,pdu.witnessId)==CorrelationStatus.WAITING)
  check(pending(adminA)==original&&e.repository.requests.isEmpty())
 }
 test("rejected rows still honor the existing stop callback within the bounded scan") {
  val e=setup();e.context.contentResolver.rows=listOf(row(500,"Provider seed"));ObservationRecovery(e.context).scan();witness(e)
  e.context.contentResolver.rows=(1L..500L).map{row(it,"Provider notice $it")+("date_sent" to (time-1_000))}
  e.context.contentResolver.bodyReads=0;var stops=0
  ObservationRecovery(e.context).correlateRecent{++stops>=16}
  check(stops==16&&e.context.contentResolver.bodyReads in 1..15&&PduCorrelationStore(e.context).read().inbox.isEmpty())
 }
 test("a matching row among 499 rejections retains the original request with live guards") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(500)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val original=pending(adminA).single();val pdu=witness(e,sent=sent)
  e.context.contentResolver.rows=(1L..500L).map{row(it,if(it==500L)body else "Provider notice $it")+("date_sent" to sent)}
  SecureStore.readCounts.clear();ObservationRecovery(e.context).correlateRecent()
  check((SecureStore.readCounts["observation-profile"]?:0) in 2..8)
  val state=PduCorrelationStore(e.context).read()
  check(state.inbox.single().requestId==original.observation.requestId)
  check(PduInboxCorrelation.status(state,pdu.witnessId)==CorrelationStatus.CORRELATED_UNVERIFIED)
  check(pending(adminA)==listOf(original)&&e.repository.requests.isEmpty())
 }
 test("late PDU with a new digest waits for the next snapshot and then retains both ambiguous rows") {
  val e=setup();val sent=time-1_000;val changed=body.replace("1000 RWF","1001 RWF")
  e.context.contentResolver.rows=listOf(row(31,changed)+("date_sent" to sent),row(32,changed)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val original=pending(adminA);witness(e,sent=sent)
  var late:PduEvidence?=null;e.context.contentResolver.afterBodyRead={late=witness(e,changed,sent,reference=8)}
  ObservationRecovery(e.context).correlateRecent()
  val first=PduCorrelationStore(e.context).read();check(first.pdus.size==2&&first.inbox.isEmpty())
  check(PduInboxCorrelation.status(first,late!!.witnessId)==CorrelationStatus.WAITING)
  ObservationRecovery(e.context).correlateRecent();val next=PduCorrelationStore(e.context).read()
  check(next.inbox.map{it.requestId}.toSet()==original.map{it.observation.requestId}.toSet())
  check(PduInboxCorrelation.status(next,late!!.witnessId)==CorrelationStatus.AMBIGUOUS&&pending(adminA)==original)
 }
 test("snapshot keeps out-of-window rows potential for a later PDU with the same exact digest key") {
  val e=setup();val sent=time-1_000
  e.context.contentResolver.rows=listOf(row(33)+("date_sent" to sent)+("date" to time-600_001),row(34)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val original=pending(adminA);val first=witness(e,sent=sent,at=time)
  var late:PduEvidence?=null;e.context.contentResolver.afterBodyRead={late=witness(e,sent=sent,at=time-1,reference=8)}
  ObservationRecovery(e.context).correlateRecent();val state=PduCorrelationStore(e.context).read()
  check(state.inbox.size==2&&state.inbox.map{it.requestId}.toSet()==original.map{it.observation.requestId}.toSet())
  check(state.inbox.count{PduInboxCorrelation.matches(first,it)}==1)
  check(state.inbox.count{PduInboxCorrelation.matches(late!!,it)}==2)
  check(PduInboxCorrelation.status(state,late!!.witnessId)==CorrelationStatus.AMBIGUOUS&&pending(adminA)==original)
 }
 test("an unretained matching duplicate still holds a retained row correlation ambiguous") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(42)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val original=pending(adminA);val pdu=witness(e,sent=sent)
  e.context.contentResolver.rows=listOf(row(41)+("date_sent" to sent),row(42)+("date_sent" to sent))
  ObservationRecovery(e.context).correlateRecent();val state=PduCorrelationStore(e.context).read()
  check(state.inbox.single().requestId==original.single().observation.requestId&&pdu.witnessId in state.conflictedWitnesses)
  check(PduInboxCorrelation.status(state,pdu.witnessId)==CorrelationStatus.AMBIGUOUS&&pending(adminA)==original)
 }
 test("changed retained row content cannot bypass the existing journal conflict hold") {
  val e=setup();val sent=time-1_000;val changed=body.replace("1000 RWF","1001 RWF")
  e.context.contentResolver.rows=listOf(row(43,changed)+("date_sent" to sent));ObservationRecovery(e.context).scan()
  val original=pending(adminA);val pdu=witness(e,sent=sent)
  e.context.contentResolver.rows=listOf(row(43)+("date_sent" to sent));ObservationRecovery(e.context).correlateRecent()
  val state=PduCorrelationStore(e.context).read();check(state.inbox.isEmpty()&&pdu.witnessId in state.conflictedWitnesses)
  check(PduInboxCorrelation.status(state,pdu.witnessId)==CorrelationStatus.AMBIGUOUS&&pending(adminA)==original)
 }
 test("incomplete matching PDU evidence remains eligible for guarded retention without completeness promotion") {
  val e=setup();val sent=time-1_000;val partial=body.substring(0,55)
  e.context.contentResolver.rows=listOf(row(44,partial)+("date_sent" to sent));ObservationRecovery(e.context).scan()
  val original=pending(adminA).single();val session=NativeRepository.observationOwner(e.context)!!
  check(ObservationPduCapture.record(e.context,session,time,3,"3gpp",listOf("M-Money"),listOf(sent),listOf(partial),listOf(pdu(partial,1))))
  ObservationRecovery(e.context).correlateRecent();val state=PduCorrelationStore(e.context).read()
  check(state.inbox.single().requestId==original.observation.requestId&&!state.pdus.single().structurallyComplete)
  check(PduInboxCorrelation.status(state,state.pdus.single().witnessId)==CorrelationStatus.INCOMPLETE&&!original.observation.complete)
 }
 for(fence in listOf("owner","session generation","profile","pause","consent","READ_SMS","RECEIVE_SMS","legacy transition","legacy binding"))
 test("potential correlation still fences a changed $fence") {
  val e=setup();val sent=time-1_000;e.context.contentResolver.rows=listOf(row(45)+("date_sent" to sent))
  ObservationRecovery(e.context).scan();val original=pending(adminA);witness(e,sent=sent)
  e.context.contentResolver.afterBodyRead={
   val config=ObservationConfigStore(e.context)
   when(fence){
    "owner"->NativeRepository.switch(adminB)
    "session generation"->{NativeRepository.switch(null);NativeRepository.switch(adminA)}
    "profile"->config.saveProfile(adminA,profile().put("profileVersion","approved-v2"),System.currentTimeMillis())
    "pause"->config.setPaused(adminA,true)
    "consent"->config.saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(false,2),true))
    "READ_SMS"->e.context.denied=setOf(Manifest.permission.READ_SMS)
    "RECEIVE_SMS"->e.context.denied=setOf(Manifest.permission.RECEIVE_SMS)
    "legacy transition"->ReceiverFixture.state=JSONObject().put("control_transition",JSONObject())
    "legacy binding"->ReceiverFixture.state=JSONObject().put("binding",JSONObject())
   }
  }
  ObservationRecovery(e.context).correlateRecent()
  check(PduCorrelationStore(e.context).read().inbox.isEmpty()&&pending(adminA)==original&&pending(adminB).isEmpty())
  check(e.repository.requests.isEmpty())
 }
 test("full or unreadable PDU evidence cannot block the original inbox queue") {
  val e=setup();val sent=time-1_000;val session=NativeRepository.observationOwner(e.context)!!
  val left=body.substring(0,55);val right=body.substring(55)
  check(ObservationPduCapture.record(e.context,session,System.currentTimeMillis(),3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1),pdu(right,2))))
  val witness=PduCorrelationStore(e.context).read().pdus.single()
  check(PduCorrelationStore(e.context,pduLimit=1).record(witness.copy(witnessId=UUID.randomUUID().toString()))==CorrelationWrite.FULL)
  e.context.contentResolver.rows=listOf(row(18)+("date_sent" to sent));ObservationRecovery(e.context).scan()
  check(pending(adminA).single().observation.sourceMode=="catch_up"&&cursor(e.context)!=null)
  SecureStore.unreadable.add("pdu-correlation")
  e.context.contentResolver.rows=listOf(row(19)+("date_sent" to sent));ObservationRecovery(e.context).scan()
  check(pending(adminA).size==2&&pending(adminA).all{!it.observation.complete})
 }
 test("system broadcast captures multipart evidence and schedules inbox recovery without a network request") {
  val e=setup();android.content.BroadcastFixture.reset();ObservationBackground.signals=0;val sent=time-1_000
  val left=body.substring(0,55);val right=body.substring(55)
  val messages=arrayOf(android.provider.SmsMessage("M-Money",sent,right),android.provider.SmsMessage("M-Money",sent,left))
  val intent=android.content.Intent(android.provider.Telephony.Sms.Intents.SMS_RECEIVED_ACTION,
   mapOf("messages" to messages,"pdus" to arrayOf(pdu(right,2),pdu(left,1)),"format" to "3gpp","subscription" to 3))
  ObservationSmsReceiver().onReceive(e.context,intent)
  check(android.content.BroadcastFixture.finished.await(5,java.util.concurrent.TimeUnit.SECONDS))
  val state=PduCorrelationStore(e.context).read()
  check(state.pdus.single().structurallyComplete&&state.inbox.isEmpty()&&pending(adminA).isEmpty())
  check(ObservationBackground.signals>=1&&e.repository.requests.isEmpty())
 }
 test("PDU evidence respects account generation, permission, consent and existing receiver ownership") {
  val e=setup();val session=NativeRepository.observationOwner(e.context)!!;val sent=time-1_000
  val left=body.substring(0,55);val right=body.substring(55)
  fun record()=ObservationPduCapture.record(e.context,session,System.currentTimeMillis(),3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1),pdu(right,2)))
  e.context.denied=setOf(Manifest.permission.READ_SMS);check(!record());e.context.denied=emptySet()
  val cfg=ObservationConfigStore(e.context);cfg.setPaused(adminA,true);check(!record());cfg.setPaused(adminA,false)
  cfg.saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(true,3),true))
  ReceiverFixture.state=JSONObject().put("binding",JSONObject());check(!record());ReceiverFixture.state=null
  NativeRepository.switch(null);NativeRepository.switch(adminA);check(!record())
  check(PduCorrelationStore(e.context).read().pdus.isEmpty())
 }
 test("scanner does not transfer an in-flight row from account A to B") {
  val e=setup();e.context.contentResolver.rows=listOf(row(20))
  e.context.contentResolver.afterBodyRead={NativeRepository.switch(adminB)}
  ObservationRecovery(e.context).scan()
  check(pending(adminA).isEmpty()&&pending(adminB).isEmpty()&&cursor(e.context)==null)
 }
 test("scanner fences logout followed by a new session for the same account") {
  val e=setup();e.context.contentResolver.rows=listOf(row(21))
  e.context.contentResolver.afterBodyRead={NativeRepository.switch(null);NativeRepository.switch(adminA)}
  ObservationRecovery(e.context).scan()
  check(pending(adminA).isEmpty()&&cursor(e.context)==null)
 }
 test("scanner stops before storing when permission is revoked during selection") {
  val e=setup();e.context.contentResolver.rows=listOf(row(22))
  e.context.contentResolver.afterBodyRead={e.context.denied=setOf(Manifest.permission.RECEIVE_SMS)}
  ObservationRecovery(e.context).scan()
  check(pending(adminA).isEmpty()&&cursor(e.context)==null)
 }
 test("an account-scoped pause stops a selected row and reconciles disabled consent") {
  val e=setup();val config=ObservationConfigStore(e.context);e.context.contentResolver.rows=listOf(row(23))
  e.context.contentResolver.afterBodyRead={config.setPaused(adminA,true)}
  ObservationRecovery(e.context).scan()
  check(pending(adminA).isEmpty()&&cursor(e.context)==null&&config.paused(adminA)&&!config.paused(adminB))
  check(!ObservationCoordinator(e.context,e.repository).cycle())
  check(!e.repository.consent.enabled&&e.repository.consent.generation==2L)
  config.setPaused(adminA,false)
  check(ObservationCoordinator(e.context,e.repository).cycle())
  check(e.repository.consent.enabled&&e.repository.consent.generation==3L)
  ObservationRecovery(e.context).scan();check(pending(adminA).size==1)
 }
 test("pause and resume during consent read cannot overwrite a newer generation") {
  val e=setup();val config=ObservationConfigStore(e.context)
  e.repository.afterConsentRead={config.setPaused(adminA,true);config.setPaused(adminA,false)}
  check(!ObservationCoordinator(e.context,e.repository).cycle())
  check(config.controlState(adminA).revision==2L&&config.consent(adminA)?.revision==ObservationConsentRevision(true,3))
  check(config.consent(adminA)?.confirmed==false)
  check(ObservationCoordinator(e.context,e.repository).cycle()&&e.repository.consent==ObservationConsentRevision(true,3))
 }
 test("a pause racing an in-flight enable is followed by the newer disabled revision") {
  val e=setup();val config=ObservationConfigStore(e.context)
  config.saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(true,1),false))
  e.repository.consent=ObservationConsentRevision(false,0)
  e.repository.duringConsentSet={config.setPaused(adminA,true)}
  check(!ObservationCoordinator(e.context,e.repository).cycle())
  check(e.repository.consent==ObservationConsentRevision(true,1)&&config.consent(adminA)?.revision==ObservationConsentRevision(false,2))
  check(!ObservationCoordinator(e.context,e.repository).cycle())
  check(e.repository.consent==ObservationConsentRevision(false,2)&&config.consent(adminA)?.confirmed==true)
 }
 test("canonical inbox candidate holds until exact legacy retention is proven") {
  val e=setup();val binding=JSONObject().put("id","binding-1").put("owner_user_id","owner-1")
   .put("collection_id","group-1").put("receiving_account_id","wallet-1").put("version",1).put("subscription_id",3)
   .put("created_at",Instant.ofEpochMilli(time-60_000).toString())
  ReceiverFixture.state=JSONObject().put("binding",binding).put("gateway_token","a".repeat(64))
   .put("capture_enabled",true).put("installation_id",installation)
  val issued=System.currentTimeMillis()
  val response=JSONObject().put("contractVersion",1).put("collectionId","group-1").put("installationId",installation)
   .put("bindingId","binding-1").put("bindingVersion",1).put("receivingAccountId","wallet-1")
   .put("profileVersion","approved-v1").put("offsetMinutes",120).put("senders",JSONArray().put("M-Money"))
   .put("incomingPrefixes",JSONArray().put("You have received")).put("currencyAliases",JSONArray().put("RWF"))
   .put("transactionIdPrefixes",JSONArray().put("FT Id:")).put("issuedAt",issued).put("expiresAt",issued+86_400_000L)
  val fakeHttp=MomoGatewayHttp(openConnection={target->object:HttpURLConnection(URL(target)){
   override fun connect(){};override fun disconnect(){};override fun usingProxy()=false
   override fun getResponseCode()=200
   override fun getHeaderField(name:String)=if(name.equals("Content-Type",true)) "application/json" else null
   override fun getInputStream()=response.toString().byteInputStream()
  }})
  check(BuriReceiverProfile.refresh(e.context,fakeHttp))
  e.context.contentResolver.rows=listOf(row(30));ObservationRecovery(e.context).scan()
  check(pending(adminA).isEmpty()&&JSONObject(cursor(e.context)!!).getLong("lastId")==0L)
  val before=cursor(e.context)
  ReceiverFixture.retainedCaptureId=MomoGatewayPolicy.captureId(installation,"binding-1","M-Money",body,time,3)
  ReceiverFixture.retainedBodyHash=Values.sha256(body)
  ReceiverFixture.afterSourceLookup={ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(false,2),true))}
  ObservationRecovery(e.context).scan()
  check(cursor(e.context)==before) // Consent changed after classification/lookup.
  ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(true,3),true))
  ObservationRecovery(e.context).scan()
  check(pending(adminA).isEmpty()&&cursor(e.context)!=null)
 }
 test("returning provider profile rescans only the protected overlap") {
  val e=setup();val config=ObservationConfigStore(e.context);val current=config.profile(adminA,System.currentTimeMillis())!!
  val item=SmsObservation(UUID.randomUUID().toString(),"M-Money",body,"catch_up",false,
   Instant.ofEpochMilli(time).toString(),null,Instant.ofEpochMilli(time).toString(),3)
  val journal=ObservationJournal(ObservationStateStore(e.context));val key=ObservationSourceIdentity.inbox(installation,adminA,1600,Instant.ofEpochMilli(time).toString())
  check(journal.append(adminA,key,1600,item,current,System.currentTimeMillis())==ObservationAppend.STORED)
  check(journal.acknowledge(adminA,item.requestId,ObservationAck(item.requestId,"source-1",Values.sha256(body),"source_unresolved",0)))
  val fingerprint=current.fingerprint();val other=if(fingerprint=="f".repeat(64))"e".repeat(64)else "f".repeat(64)
  val rows=JSONArray().put(JSONObject().put("collectionId",adminA.collectionId).put("accountId",adminA.accountId)
   .put("profileFingerprint",fingerprint).put("lastId",100L))
   .put(JSONObject().put("collectionId",adminA.collectionId).put("accountId",adminA.accountId)
    .put("profileFingerprint",other).put("lastId",2000L))
  SecureStore(e.context,"observation-cursors").write(JSONObject().put("items",rows).toString())
  e.context.contentResolver.rows=listOf(row(1200),row(1600),row(1800));ObservationRecovery(e.context).scan()
  check(e.context.contentResolver.queryAfter==0L)
  val kept=pending(adminA);check(kept.size==1&&kept.single().sourceKey==ObservationSourceIdentity.inbox(installation,adminA,1800,Instant.ofEpochMilli(time).toString()))
 }
 test("a sparse inbox ID resumes on the next pass without duplicate or lost requests") {
  val e=setup();e.context.contentResolver.rows=listOf(row(10),row(10_000),row(10_001))
  ObservationRecovery(e.context).scan()
  val first=pending(adminA).map{it.observation.requestId};check(first.size==3)
  ObservationRecovery(e.context).scan()
  val resumed=pending(adminA).map{it.observation.requestId}
  check(e.context.contentResolver.queryAfter==0L&&resumed==first&&resumed.toSet().size==3)
 }
 test("unknown upload outcome preserves the exact request until a later acknowledgement") {
  val e=setup();e.context.contentResolver.rows=listOf(row(40));ObservationRecovery(e.context).scan()
  val original=pending(adminA).single().observation;e.repository.failSubmit=true
  check(!ObservationCoordinator(e.context,e.repository).cycle()&&pending(adminA).single().observation==original)
  e.repository.failSubmit=false;check(ObservationCoordinator(e.context,e.repository).cycle())
  check(pending(adminA).isEmpty()&&e.repository.requests.size==2&&e.repository.requests.all{it==original})
 }
 test("a proven unresolved source stays queued while two later entries can advance") {
  val e=setup();e.context.contentResolver.rows=(100L..103L).map{row(it)};ObservationRecovery(e.context).scan()
  val original=pending(adminA).map{it.observation};e.repository.unresolvedIds=setOf(original.first().requestId)
  check(!ObservationCoordinator(e.context,e.repository).cycle())
  check(e.repository.requests.map{it.requestId}==original.take(3).map{it.requestId})
  check(pending(adminA).map{it.observation}==listOf(original.first(),original.last()))
  e.repository.unresolvedIds=emptySet();check(ObservationCoordinator(e.context,e.repository).cycle())
  check(pending(adminA).isEmpty()&&e.repository.requests[3]==original.first())
 }
 test("generic or mismatched unresolved failures stop without advancing") {
  for(mismatch in listOf(false,true)){
   val e=setup();e.context.contentResolver.rows=listOf(row(110),row(111));ObservationRecovery(e.context).scan()
   val original=pending(adminA).map{it.observation}
   if(mismatch){e.repository.unresolvedIds=setOf(original.first().requestId);e.repository.unresolvedReportedId=original.last().requestId}else e.repository.failSubmit=true
   check(!ObservationCoordinator(e.context,e.repository).cycle()&&pending(adminA).map{it.observation}==original&&e.repository.requests.size==1)
  }
 }
 test("authority, permission, consent, pause or stop after unresolved proof stops the next dispatch") {
  for(change in listOf("owner","permission","consent","pause","stop")){
   val e=setup();e.context.contentResolver.rows=listOf(row(120),row(121));ObservationRecovery(e.context).scan()
   val original=pending(adminA).map{it.observation};e.repository.unresolvedIds=setOf(original.first().requestId)
   var stopped=false
   e.repository.switchDuringSubmit={when(change){
    "owner"->NativeRepository.switch(adminB)
    "permission"->e.context.denied=setOf(Manifest.permission.READ_SMS)
    "consent"->{val config=ObservationConfigStore(e.context);config.saveConsent(adminA,config.consent(adminA)!!.copy(confirmed=false))}
    "stop"->stopped=true
    else->ObservationConfigStore(e.context).setPaused(adminA,true)
   }}
   check(!ObservationCoordinator(e.context,e.repository).cycle{stopped}&&pending(adminA).map{it.observation}==original&&e.repository.requests.size==1)
  }
 }
 test("unresolved continuation is bounded to sixteen skipped and two later successes") {
  val e=setup();e.context.contentResolver.rows=(200L..219L).map{row(it)};ObservationRecovery(e.context).scan()
  val original=pending(adminA).map{it.observation};e.repository.unresolvedIds=original.take(16).map{it.requestId}.toSet()
  check(!ObservationCoordinator(e.context,e.repository).cycle()&&e.repository.requests.size==18)
  check(pending(adminA).map{it.observation}==original.take(16)+original.drop(18))
  val second=setup();second.context.contentResolver.rows=(300L..317L).map{row(it)};ObservationRecovery(second.context).scan()
  val stuck=pending(adminA).map{it.observation};second.repository.unresolvedIds=stuck.take(17).map{it.requestId}.toSet()
  check(!ObservationCoordinator(second.context,second.repository).cycle()&&second.repository.requests.size==17&&pending(adminA).map{it.observation}==stuck)
 }
 test("in-flight account change cannot acknowledge another owner's retained item") {
  val e=setup();e.context.contentResolver.rows=listOf(row(41));ObservationRecovery(e.context).scan()
  val original=pending(adminA).single().observation;e.repository.switchDuringSubmit={NativeRepository.switch(adminB)}
  check(!ObservationCoordinator(e.context,e.repository).cycle())
  check(pending(adminA).single().observation==original&&pending(adminB).isEmpty())
  NativeRepository.switch(adminA);check(ObservationCoordinator(e.context,e.repository).cycle())
  check(pending(adminA).isEmpty()&&e.repository.requests.all{it==original})
 }
 test("continuous online API outage retains cached-authorized local inbox evidence before restore") {
  val e=setup();e.context.contentResolver.rows=listOf(row(601));var restores=0
  val result=ObservationSyncCycle.run(e.context,true,restore={
   restores++;check(pending(adminA).size==1);throw rw.ikanisa.burimunsi.data.ApiFailure("service_unavailable",503,true)
  },stopped={false})
  check(restores==1&&!result.completed&&result.more&&result.problem=="connection_waiting")
  val original=pending(adminA).single().observation;check(e.repository.requests.isEmpty())
  val recovered=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(recovered.completed&&pending(adminA).isEmpty()&&e.repository.requests==listOf(original))
 }
 test("continuous cached local pass does not bypass missing owner permission or explicit pause") {
  for(kind in listOf("owner","permission","pause")){
   val e=setup();e.context.contentResolver.rows=listOf(row(602))
   when(kind){"owner"->NativeRepository.switch(null);"permission"->e.context.denied=setOf(Manifest.permission.READ_SMS);else->ObservationConfigStore(e.context).setPaused(adminA,true)}
   ObservationSyncCycle.run(e.context,true,restore={throw rw.ikanisa.burimunsi.data.ApiFailure("service_unavailable",503,true)},stopped={false})
   check(pending(adminA).isEmpty()&&e.repository.requests.isEmpty())
  }
 }
 test("continuous stop after dispatch keeps exact observation pending and suppresses acknowledgement") {
  val e=setup();e.context.contentResolver.rows=listOf(row(603));var stop=false
  e.repository.switchDuringSubmit={stop=true}
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={stop})
  check(!result.completed&&e.repository.requests.size==1)
  check(pending(adminA).single().observation==e.repository.requests.single())
 }
 test("continuous execution lease excludes reentry and a second caller until actual owner exit") {
  val gate=ContinuousSyncWorkGate();val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
  val thread=Thread{gate.runIfIdle{entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS));true}}
  thread.start();check(entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
  check(gate.runIfIdle{error("Concurrent job or restarted service entered") }==null)
  release.countDown();thread.join(5000);check(!thread.isAlive)
  check(gate.runIfIdle{gate.runIfIdle{error("Recursive cycle entered") }==null}==true)
  runCatching{gate.runIfIdle<Unit>{error("Synthetic worker failure")}};check(gate.runIfIdle{true}==true)
 }
 test("continuous work budget bounds elapsed work cancellation and clock reversal") {
  var now=1000L;var stop=false;val budget=ContinuousSyncBudget({now},{stop},2000)
  check(!budget.stopped());now=2999;check(!budget.stopped());now=3000;check(budget.stopped())
  now=1000;val cancelled=ContinuousSyncBudget({now},{stop});stop=true;check(cancelled.stopped())
  stop=false;val reversed=ContinuousSyncBudget({now},{stop});now=999;check(reversed.stopped())
 }
 test("continuous failures back off finitely and successful pending work resets the delay") {
  val retry=ContinuousSyncRetry();check(retry.next(false,true)==15000L);check(retry.next(false,true)==30000L)
  repeat(8){check(retry.next(false,true)==60000L)}
  check(retry.next(true,true)==2000L&&retry.next(true,false)==30000L&&retry.next(false,true)==15000L)
  check(retry.next(false,true,progress=true)==2000L&&retry.next(false,true)==15000L)
 }
 test("sync health expires on its original monotonic proof and cannot resurrect after clock reversal") {
  val health=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,proofStartedAtElapsed=1_000L,
   proofInboxRevision=7L,proofAuthorityRevision=11L,proofSessionDigest="a".repeat(64),proofScope="b".repeat(64),
   proofSessionExpiresAtWall=Long.MAX_VALUE,proofObservationIssuedAtWall=1L,proofObservationExpiresAtWall=Long.MAX_VALUE)
  val state=ContinuousSyncHealthState(health)
  fun checked(s:ContinuousSyncHealthState,now:Long,observer:Boolean=true)=s.health(now,observer,7,11,"a".repeat(64),true,"b".repeat(64),true)
  check(checked(state,300_999L)==health)
  val expired=checked(state,301_000L)
  check(expired.problem=="sync_unconfirmed"&&expired.proofStartedAtElapsed==null)
  check(checked(state,2_000L)==expired)
  check(checked(ContinuousSyncHealthState(health),999L).problem=="sync_unconfirmed")
  check(checked(ContinuousSyncHealthState(health),2_000L,false).problem=="sync_unconfirmed")
  val restarted=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true)
  check(checked(ContinuousSyncHealthState(restarted),2_000L).problem=="sync_unconfirmed")
  val paused=health.copy(problem="paused",proofStartedAtElapsed=null)
  check(checked(ContinuousSyncHealthState(paused),301_000L,false)==paused)
 }
 test("inbox or authority changes after cycle completion cannot publish its old success") {
  for(kind in listOf("inbox","owner","consent","permission","pause","profile","scope")){
   val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(802))
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(result.completed&&result.proofInboxRevision!=null&&result.proofAuthorityRevision!=null&&
    result.proofSessionDigest!=null&&result.proofScope!=null)
   val old=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,
    proofStartedAtElapsed=result.proofStartedAtElapsed,proofInboxRevision=result.proofInboxRevision,
    proofAuthorityRevision=result.proofAuthorityRevision,proofSessionDigest=result.proofSessionDigest,proofScope=result.proofScope,
    proofSessionExpiresAtWall=result.proofSessionExpiresAtWall,proofObservationIssuedAtWall=result.proofObservationIssuedAtWall,
    proofObservationExpiresAtWall=result.proofObservationExpiresAtWall)
   when(kind){
    "inbox"->ObservationInboxRevision.changed()
    "owner"->NativeRepository.switch(adminB)
    "consent"->{val c=ObservationConfigStore(e.context);c.saveConsent(adminA,c.consent(adminA)!!.copy(confirmed=false))}
    "permission"->e.context.denied=setOf(Manifest.permission.READ_SMS)
    "pause"->ObservationConfigStore(e.context).setPaused(adminA,true)
    "profile"->{e.approved.put("profileVersion","changed-v2");ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())}
    "scope"->Settings.Secure.testId="1111111111111111"
   }
   // Model the main-thread callback arriving after the worker's final check.
   val state=ContinuousSyncHealthState();state.set(old)
   val session=NativeRepository.observationOwner(e.context)
   val permission=e.context.denied.isEmpty();val scope=ObservationRecovery(e.context).healthScope()
   val checked=state.health(1_000L,ObservationInboxRevision.observerActive(),ObservationInboxRevision.snapshot(),
    ObservationAuthorityRevision.stable(),session?.let(ObservationAuthorityRevision::sessionDigest),permission,scope,true)
   check(checked.problem=="sync_unconfirmed"&&checked.proofStartedAtElapsed==null)
  }
 }
 test("a changed or rejected bound receiver profile invalidates success before wake and cannot reuse its audit") {
  for(kind in listOf("change","remove")){
   val e=setup();android.os.SystemClock.fixed=1_000L;bindReceiver(e)
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(result.completed&&result.proofLegacyIssuedAtWall!=null&&result.proofLegacyExpiresAtWall!=null)
   val old=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,
    proofStartedAtElapsed=result.proofStartedAtElapsed,proofInboxRevision=result.proofInboxRevision,
    proofAuthorityRevision=result.proofAuthorityRevision,proofSessionDigest=result.proofSessionDigest,proofScope=result.proofScope,
    proofSessionExpiresAtWall=result.proofSessionExpiresAtWall,proofObservationIssuedAtWall=result.proofObservationIssuedAtWall,
    proofObservationExpiresAtWall=result.proofObservationExpiresAtWall,
    proofLegacyIssuedAtWall=result.proofLegacyIssuedAtWall,proofLegacyExpiresAtWall=result.proofLegacyExpiresAtWall,
    proofLegacySubscriptionsDigest=result.proofLegacySubscriptionsDigest)
   val state=ContinuousSyncHealthState(old);var wakes=0
   val stop=ObservationAuthorityRevision.observe{wake->state.invalidate();if(wake){check(state.get().problem=="sync_unconfirmed");wakes++}}
   val now=System.currentTimeMillis()
   if(kind=="change")check(BuriReceiverProfile.refresh(e.context,receiverProfileHttp(now,"ALT-SENDER"),now))
   else check(!BuriReceiverProfile.refresh(e.context,receiverProfileHttp(now,httpStatus=403),now))
   stop();check(wakes==1&&state.get().problem=="sync_unconfirmed")
   val session=NativeRepository.observationOwner(e.context)
   val rechecked=ContinuousSyncHealthState(old).health(1_000L,true,ObservationInboxRevision.snapshot(),
    ObservationAuthorityRevision.stable(),session?.let(ObservationAuthorityRevision::sessionDigest),true,
    ObservationRecovery(e.context).healthScope(),true,System.currentTimeMillis(),ObservationLegacyOwnership.subscriptionScope(e.context))
   check(rechecked.problem=="sync_unconfirmed")
   val statusCalls=e.repository.statusCalls;e.repository.statusFailure=rw.ikanisa.burimunsi.data.ApiFailure("unavailable",503,true)
   val next=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!next.completed)
   if(kind=="change")check(e.repository.statusCalls>statusCalls) // old cached equality was not reused
  }
 }
 test("a bound receiver profile change during an audit page rejects that page") {
  for(kind in listOf("change","remove")){
   val e=setup();bindReceiver(e);val recovery=ObservationRecovery(e.context)
   e.repository.afterStatus={calls->if(calls==1){
    val now=System.currentTimeMillis()
    BuriReceiverProfile.refresh(e.context,receiverProfileHttp(now,if(kind=="change")"ALT-SENDER" else "M-Money",
     if(kind=="change")200 else 403),now)
   }}
   check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.BLOCKED)
   check(recovery.auditStartedAt()==null&&e.repository.reconciliationBatches.isEmpty())
  }
 }
 test("a 401 receiver park invalidates success before wake and interrupts an in-flight audit") {
  val e=setup();android.os.SystemClock.fixed=1_000L;bindReceiver(e)
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false});check(result.completed)
  val health=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,
   proofStartedAtElapsed=result.proofStartedAtElapsed,proofInboxRevision=result.proofInboxRevision,
   proofAuthorityRevision=result.proofAuthorityRevision,proofSessionDigest=result.proofSessionDigest,proofScope=result.proofScope,
   proofSessionExpiresAtWall=result.proofSessionExpiresAtWall,proofObservationIssuedAtWall=result.proofObservationIssuedAtWall,
   proofObservationExpiresAtWall=result.proofObservationExpiresAtWall,proofLegacyIssuedAtWall=result.proofLegacyIssuedAtWall,
   proofLegacyExpiresAtWall=result.proofLegacyExpiresAtWall,proofLegacySubscriptionsDigest=result.proofLegacySubscriptionsDigest)
  val state=ContinuousSyncHealthState(health);var wakes=0
  val stop=ObservationAuthorityRevision.observe{wake->state.invalidate();if(wake){check(state.get().problem=="sync_unconfirmed");wakes++}}
  MomoGatewayStore(e.context).park("authorization_required")
  check(wakes==1&&state.get().problem=="sync_unconfirmed"&&ObservationRecovery(e.context).healthScope()==null)
  MomoGatewayStore(e.context).park("authorization_required");stop();check(wakes==1)
  check(!ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  val race=setup();bindReceiver(race);val recovery=ObservationRecovery(race.context)
  race.repository.afterStatus={calls->if(calls==1)MomoGatewayStore(race.context).park("authorization_required")}
  check(recovery.auditPage(race.repository)==ObservationRecovery.Audit.BLOCKED&&recovery.auditStartedAt()==null)
 }
 test("a profile change restarts a partially completed receiver scan") {
  val e=setup();bindReceiver(e);e.context.contentResolver.rows=(1L..101L).map{row(it)}
  val recovery=ObservationRecovery(e.context)
  check(recovery.scanStatus()==ObservationRecovery.Scan.MORE)
  check(JSONObject(cursor(e.context)!!).getLong("lastId")==100L)
  val now=System.currentTimeMillis()
  check(BuriReceiverProfile.refresh(e.context,receiverProfileHttp(now,"ALT-SENDER"),now))
  e.context.contentResolver.queryAfter=null
  check(recovery.scanStatus()==ObservationRecovery.Scan.MORE)
  check(e.context.contentResolver.queryAfter==0L&&pending(adminA).isNotEmpty())
 }
 test("observation profile and session deadlines expire published health") {
  val e=setup();android.os.SystemClock.fixed=1_000L;val now=System.currentTimeMillis()
  val issued=now-86_400_000L+30_000L;val expiry=now+30_000L
  e.approved.put("issuedAt",issued).put("expiresAt",expiry)
  ObservationConfigStore(e.context).saveProfile(adminA,e.approved,now)
  NativeRepository.sessionDeadline=now+60_000L
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false});check(result.completed)
  val health=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,
   proofStartedAtElapsed=result.proofStartedAtElapsed,proofInboxRevision=result.proofInboxRevision,
   proofAuthorityRevision=result.proofAuthorityRevision,proofSessionDigest=result.proofSessionDigest,proofScope=result.proofScope,
   proofSessionExpiresAtWall=result.proofSessionExpiresAtWall,proofObservationIssuedAtWall=result.proofObservationIssuedAtWall,
   proofObservationExpiresAtWall=result.proofObservationExpiresAtWall)
  fun checked(value:rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth,wall:Long)=
   ContinuousSyncHealthState(value).health(1_000L,true,result.proofInboxRevision,result.proofAuthorityRevision,
    result.proofSessionDigest,true,result.proofScope,true,wall)
  check(checked(health,expiry-1).problem==null&&checked(health,expiry).problem=="sync_unconfirmed")
  val longer=health.copy(proofObservationExpiresAtWall=now+120_000L)
  check(checked(longer,now+59_999L).problem==null&&checked(longer,now+60_000L).problem=="sync_unconfirmed")
 }
 test("bound receiver profile expiry invalidates scope and health without a mutation callback") {
  val e=setup();android.os.SystemClock.fixed=1_000L
  val issued=System.currentTimeMillis()-86_400_000L+30_000L;bindReceiver(e,issued)
  val legacy=ObservationLegacyOwnership.scope(e.context)!!;val expiry=legacy.expiresAt!!
  check(ObservationLegacyOwnership.scope(e.context,expiry-1)==legacy)
  check(ObservationLegacyOwnership.scope(e.context,expiry)==null)
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false});check(result.completed)
  check(result.proofLegacyIssuedAtWall==issued&&result.proofLegacyExpiresAtWall==expiry)
  val health=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,
   proofStartedAtElapsed=result.proofStartedAtElapsed,proofInboxRevision=result.proofInboxRevision,
   proofAuthorityRevision=result.proofAuthorityRevision,proofSessionDigest=result.proofSessionDigest,proofScope=result.proofScope,
   proofSessionExpiresAtWall=result.proofSessionExpiresAtWall,proofObservationIssuedAtWall=result.proofObservationIssuedAtWall,
   proofObservationExpiresAtWall=result.proofObservationExpiresAtWall,
   proofLegacyIssuedAtWall=issued,proofLegacyExpiresAtWall=expiry,proofLegacySubscriptionsDigest=result.proofLegacySubscriptionsDigest)
  fun read(now:Long)=ContinuousSyncHealthState(health).health(1_000L,true,result.proofInboxRevision,
   result.proofAuthorityRevision,result.proofSessionDigest,true,result.proofScope,true,now,result.proofLegacySubscriptionsDigest)
  check(read(expiry-1).problem==null&&read(expiry).problem=="sync_unconfirmed")
  check(read(issued-120_001L).problem=="sync_unconfirmed")
  val expired=ContinuousSyncHealthState(health)
  check(expired.health(1_000L,true,result.proofInboxRevision,result.proofAuthorityRevision,result.proofSessionDigest,
   true,result.proofScope,true,expiry,result.proofLegacySubscriptionsDigest).problem=="sync_unconfirmed")
  check(expired.health(1_000L,true,result.proofInboxRevision,result.proofAuthorityRevision,result.proofSessionDigest,
   true,result.proofScope,true,expiry-1,result.proofLegacySubscriptionsDigest).problem=="sync_unconfirmed")
 }
 test("bound receiver scope changes with SIM routing and fails closed when the route is unavailable") {
  val e=setup();android.os.SystemClock.fixed=1_000L;bindReceiver(e)
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false});check(result.completed)
  val health=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,
   proofStartedAtElapsed=result.proofStartedAtElapsed,proofInboxRevision=result.proofInboxRevision,
   proofAuthorityRevision=result.proofAuthorityRevision,proofSessionDigest=result.proofSessionDigest,proofScope=result.proofScope,
   proofSessionExpiresAtWall=result.proofSessionExpiresAtWall,proofObservationIssuedAtWall=result.proofObservationIssuedAtWall,
   proofObservationExpiresAtWall=result.proofObservationExpiresAtWall,
   proofLegacyIssuedAtWall=result.proofLegacyIssuedAtWall,proofLegacyExpiresAtWall=result.proofLegacyExpiresAtWall,
   proofLegacySubscriptionsDigest=result.proofLegacySubscriptionsDigest)
  val original=ObservationRecovery(e.context).sweepScope()!!
  ReceiverFixture.subscriptions=setOf(3,4)
  check(ObservationRecovery(e.context).sweepScope()!=original)
  check(ContinuousSyncHealthState(health).health(1_000L,true,result.proofInboxRevision,result.proofAuthorityRevision,
   result.proofSessionDigest,true,result.proofScope,false,System.currentTimeMillis(),
   ObservationLegacyOwnership.subscriptionScope(e.context)).problem=="sync_unconfirmed")
  ReceiverFixture.subscriptions=setOf(4)
  check(ObservationRecovery(e.context).sweepScope()==null)
  ReceiverFixture.subscriptions=setOf(3);e.context.denied=setOf(Manifest.permission.READ_PHONE_STATE)
  check(ObservationRecovery(e.context).healthScope()==null)
 }
 test("an unchanged fetched receiver profile neither invalidates nor wakes") {
  val e=setup();val issued=System.currentTimeMillis()-16*60_000L;bindReceiver(e,issued)
  val before=ObservationAuthorityRevision.stable();var events=0
  val stop=ObservationAuthorityRevision.observe{events++}
  check(BuriReceiverProfile.refresh(e.context,receiverProfileHttp(issued)))
  stop();check(events==0&&ObservationAuthorityRevision.stable()==before)
 }
 test("authority transitions invalidate immediately without waiting for the wake callback") {
  val health=rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true,proofStartedAtElapsed=1_000L,
   proofInboxRevision=7L,proofAuthorityRevision=ObservationAuthorityRevision.stable(),proofSessionDigest="a".repeat(64),proofScope="b".repeat(64))
  val state=ContinuousSyncHealthState(health);var wakes=0
  val stop=ObservationAuthorityRevision.observe{wake->state.invalidate();if(wake)wakes++}
  ObservationAuthorityRevision.ownerChanged()
  check(state.get().problem=="sync_unconfirmed"&&wakes==1)
  state.set(health)
  ObservationAuthorityRevision.changing{
   check(ObservationAuthorityRevision.stable()==null&&state.get().problem=="sync_unconfirmed")
  }
  stop();check(ObservationAuthorityRevision.stable()!=null)
 }
 test("pending passcode holds the supervisor across ticks and rejection wakes retry") {
  val state=ContinuousSyncHealthState(rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth(supported=true,running=true))
  var wakes=0;val detach=ObservationAuthorityRevision.observe{wake->state.invalidate();if(wake)wakes++}
  ObservationAuthorityRevision.sessionMetadataChanged(false)
  repeat(3){check(ContinuousSyncPreflight.waiting("passcode_pending")&&state.get().running&&state.get().problem=="sync_unconfirmed")}
  check(wakes==0&&!ContinuousSyncPreflight.waiting("authorization_required"))
  ObservationAuthorityRevision.sessionMetadataChanged(true)
  check(wakes==1&&!ContinuousSyncPreflight.waiting(null));detach()
 }
 test("an empty phone requires an authoritative empty Cloud reservation status") {
  val e=setup()
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  val diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(result.completed&&e.repository.requests.isEmpty()&&e.repository.pageCalls==1)
  check(diagnostic.outcome==ObservationSyncDiagnostics.Outcome.COMPLETED&&diagnostic.coordinator==ObservationSyncDiagnostics.Outcome.COMPLETED)
  check(diagnostic.queueRead&&diagnostic.queued==0&&diagnostic.attempts==0&&diagnostic.acknowledged==0)
  check(diagnostic.fence==ObservationSyncDiagnostics.Fence.NONE&&diagnostic.stop==ObservationSyncDiagnostics.Stop.NONE)
  val blocked=setup();blocked.repository.pendingReservation=true
  check(!ObservationSyncCycle.run(blocked.context,true,restore={blocked.repository},stopped={false}).completed)
 }
 test("an unreadable encrypted queue cannot prove empty after the Cloud reply") {
  val e=setup();e.context.contentResolver.rows=listOf(row(800))
  e.repository.afterReconcile={
   e.context.contentResolver.rows=listOf(row(800),row(801))
   ObservationRecovery(e.context).scan()
   check(pending(adminA).size==1)
   e.context.contentResolver.rows=listOf(row(800))
   ObservationStateStore.unreadable=true
  }
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed)
  ObservationStateStore.unreadable=false
  check(pending(adminA).size==1)
 }
 test("the latest exact source is checked after the complete sweep and cached only briefly") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(801))
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(first.completed&&first.proofStartedAtElapsed==1_000L&&e.repository.requests.size==1&&e.repository.reconciliationRequests.size==1&&pending(adminA).isEmpty())
  android.os.SystemClock.fixed=300_999L
  val cached=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(cached.completed&&cached.proofStartedAtElapsed==first.proofStartedAtElapsed&&e.repository.reconciliationRequests.size==1)
  android.os.SystemClock.fixed=301_000L
  val renewed=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(renewed.completed&&renewed.proofStartedAtElapsed==301_000L&&e.repository.reconciliationRequests.size==2)
 }
 test("legacy pending takes effect on the first cycle after the five-minute proof expires") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(802))
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  val reads=e.repository.statusCalls
  e.repository.statusReplyOverride={_,status->status.copy(hasPending=true)}
  android.os.SystemClock.fixed=300_999L
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  check(e.repository.statusCalls==reads)
  android.os.SystemClock.fixed=301_000L
  val expired=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!expired.completed&&expired.problem=="sync_unconfirmed"&&e.repository.statusCalls>reads)
 }
 test("a newer SMS arriving during the Cloud check invalidates the match") {
  val e=setup();e.context.contentResolver.rows=listOf(row(810))
  e.repository.afterReconcile={e.context.contentResolver.rows=listOf(row(810),row(811)+("date" to (time+1)))}
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.RECONCILE_CHANGED)
  val next=runUntilSettled(e)
  check(next.completed&&e.repository.requests.size==2&&e.repository.reconciliationRequests.size==2)
 }
 test("an older insertion during the Cloud check invalidates the sweep and is uploaded on retry") {
  val e=setup();e.context.contentResolver.rows=listOf(row(820)+("date" to (time+1000)))
  e.repository.afterReconcile={e.context.contentResolver.rows=listOf(row(819)+("date" to (time-1000)),row(820)+("date" to (time+1000)));ObservationInboxRevision.changed()}
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&result.more&&result.progress&&ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.RECONCILE_CHANGED)
  val next=runUntilSettled(e)
  check(!next.completed&&e.repository.requests.size==2&&pending(adminA).isEmpty()&&
   ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.RECONCILE_ORDER_UNCERTAIN)
 }
 test("the phone latest uses received time and row identity even for identical messages") {
  val e=setup();e.context.contentResolver.rows=listOf(row(830)+("date" to (time+10)),row(831)+("date" to (time+10)),row(999)+("date" to (time-10)))
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  val expected=ObservationSourceIdentity.reinstallStable("1234567890abcdef",adminA.collectionId,831,Instant.ofEpochMilli(time+10).toString())
  val latest=ObservationRecovery(e.context).latest() as? ObservationRecovery.Latest.Ready
  check(!result.completed&&latest?.witness?.request?.sourceKey==expected&&e.repository.reconciliationRequests.isEmpty()&&
   e.repository.requests.size==3&&ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.AUDIT_UNCONFIRMED)
 }
 test("an inbox provider that ignores descending order cannot select an older message") {
  val e=setup();e.context.contentResolver.ignoreDescendingOrder=true
  e.context.contentResolver.rows=listOf(row(831)+("date" to (time-100)),row(830)+("date" to (time+100)))
  val result=runUntilSettled(e)
  val expected=ObservationSourceIdentity.reinstallStable("1234567890abcdef",adminA.collectionId,830,Instant.ofEpochMilli(time+100).toString())
  check(!result.completed&&e.repository.reconciliationRequests.single().sourceKey==expected)
 }
 test("latest lookup falls back to an unfiltered inbox without syncing unrelated senders") {
  val e=setup();e.context.contentResolver.rejectFilteredSelection=true
  e.context.contentResolver.rows=listOf(row(840)+("address" to "Other")+("date" to (time+100)),row(841))
  val result=runUntilSettled(e)
  check(result.completed&&e.repository.requests.size==1&&e.repository.reconciliationRequests.single().rawSender=="M-Money")
 }
 test("a held newest SMS is never skipped for an older unheld message") {
  val e=setup();app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=true
  try{
   e.context.contentResolver.rows=listOf(row(900)+("date" to (time+1000)));ObservationRecovery(e.context).scan()
   e.context.contentResolver.rows=listOf(row(900)+("date" to (time+1000)),row(901)+("date" to (time-1000)))
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!result.completed&&ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.AUDIT_UNCONFIRMED)
   check(e.repository.requests.size==1&&e.repository.reconciliationRequests.isEmpty())
  }finally{app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=false}
 }
 test("an earlier unseen phone SMS is uploaded before a matching newest can complete") {
  val e=setup();e.context.contentResolver.rows=listOf(row(910)+("date" to (time+1000)))
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  e.context.contentResolver.rows=listOf(row(909)+("date" to (time-1000)),row(910)+("date" to (time+1000)))
  ObservationInboxRevision.changed()
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.size==2&&e.repository.requests[1].inboxReceivedAt==Instant.ofEpochMilli(time-1000).toString())
  check(pending(adminA).isEmpty())
 }
 test("an earlier backfill is audited without assuming server retention order is phone chronology") {
  val e=setup();e.repository.distinctSourceIds=true;android.os.SystemClock.fixed=1_000L
  e.context.contentResolver.rows=listOf(row(915)+("date" to (time+1000)))
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  e.context.contentResolver.rows=listOf(row(914)+("date" to (time-1000)),row(915)+("date" to (time+1000)))
  ObservationInboxRevision.changed()
  val result=runUntilSettled(e)
  check(!result.completed&&pending(adminA).isEmpty()&&e.repository.requests.size==2&&e.repository.reconciliationRequests.size==2)
  check(ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.RECONCILE_ORDER_UNCERTAIN)
 }
 test("missing Cloud evidence never recreates an acknowledged SMS; order alone does not imply a gap") {
  for(kind in listOf("missing","order")){
   val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(920))
   check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
   val key=e.repository.requests.single().sourceKey!!
   e.repository.reconcileOverride=if(kind=="missing")ObservationReconcileReply(key,"missing",null,"source-other")
    else ObservationReconcileReply(key,"matched","source-1","source-other")
   android.os.SystemClock.fixed=301_001L
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!result.completed&&e.repository.requests.size==1&&pending(adminA).isEmpty())
   check(ObservationSyncDiagnostics.snapshot()!!.fence==if(kind=="missing")ObservationSyncDiagnostics.Fence.RECONCILE_MISSING else ObservationSyncDiagnostics.Fence.RECONCILE_ORDER_UNCERTAIN)
  }
 }
 test("a changed owner or revoked permission after the Cloud response cannot confirm sync") {
  for(kind in listOf("owner","permission")){
   val e=setup();e.context.contentResolver.rows=listOf(row(930))
   e.repository.afterReconcile={if(kind=="owner")NativeRepository.switch(adminB) else e.context.denied=setOf(Manifest.permission.READ_SMS)}
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!result.completed&&ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.RECONCILE_CHANGED)
  }
 }
 test("Cloud outages and permission loss invalidate a verified cache") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(935))
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  e.context.denied=setOf(Manifest.permission.READ_SMS)
  check(!ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  e.context.denied=emptySet();e.repository.reconcileFailure=rw.ikanisa.burimunsi.data.ApiFailure("unavailable",503,true)
  val outage=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!outage.completed&&outage.more&&!outage.progress&&outage.problem=="connection_waiting"&&e.repository.reconciliationRequests.size==2)
  e.repository.reconcileFailure=null
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  check(e.repository.reconciliationRequests.size==3)
 }
 test("a healthy bounded sweep continues quickly without claiming completion") {
  val e=setup();e.context.contentResolver.rows=(1L..210L).map{row(it,"$body $it")}
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!first.completed&&first.more&&first.progress&&ContinuousSyncRetry().next(first.completed,first.more,first.progress)==2_000L)
  var completed=first
  repeat(80){if(!completed.completed)completed=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})}
  check(completed.completed&&pending(adminA).isEmpty()&&e.repository.requests.size==210)
 }
 test("slow completed batches resume from the next fully verified page") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=(2101L..2112L).map{row(it,"$body $it")}
  e.repository.afterBatch={android.os.SystemClock.fixed=61_000L}
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!first.completed&&first.more&&first.progress&&e.repository.reconciliationBatches.size==1)
  check(e.repository.reconciliationBatches[0].map{it.sourceKey}==listOf(cloudKey(adminA,2101)))
  e.repository.afterBatch={android.os.SystemClock.fixed=121_000L}
  val second=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!second.completed&&second.more&&second.progress&&e.repository.reconciliationBatches.size==2)
  check(e.repository.reconciliationBatches[1].map{it.sourceKey}==listOf(cloudKey(adminA,2102)))
  var result=second;repeat(8){if(!result.completed)result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})}
  check(result.completed&&e.repository.requests.size==12&&pending(adminA).isEmpty()&&
   e.repository.reconciliationBatches.all{it.size==1}&&
   e.repository.reconciliationBatches.flatten().map{it.sourceKey}==(2101L..2112L).map{cloudKey(adminA,it)})
 }
 test("a temporary outage retries the failed singleton without repeating the verified checkpoint") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=(2161L..2163L).map{row(it,"$body $it")}
  e.repository.afterBatch={android.os.SystemClock.fixed=61_000L}
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!first.completed&&first.more&&first.progress&&e.repository.reconciliationBatches.single().single().sourceKey==cloudKey(adminA,2161))
  e.repository.batchFailure=rw.ikanisa.burimunsi.data.ApiFailure("observation_unavailable",503,true)
  val failed=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!failed.completed&&failed.more&&e.repository.reconciliationBatches.last().single().sourceKey==cloudKey(adminA,2162))
  e.repository.batchFailure=null
  val recovered=runUntilSettled(e)
  check(recovered.completed&&e.repository.requests.size==3&&pending(adminA).isEmpty()&&
   e.repository.reconciliationBatches.all{it.size==1}&&e.repository.reconciliationBatches.flatten().map{it.sourceKey}==
    listOf(2161L,2162L,2162L,2163L).map{cloudKey(adminA,it)})
 }
 test("an initial Cloud status completed after the deadline is checkpointed") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(2115))
  e.repository.afterStatus={calls->if(calls==1)android.os.SystemClock.fixed=61_000L}
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!first.completed&&first.more&&first.progress&&e.repository.statusCalls==1&&e.repository.reconciliationBatches.isEmpty())
  e.repository.afterStatus=null
  val second=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(second.completed&&e.repository.statusCalls==4&&e.repository.reconciliationBatches.size==1)
 }
 test("a last Cloud page completed after the deadline is not fetched twice") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(2120))
  e.repository.afterPage={android.os.SystemClock.fixed=61_000L}
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!first.completed&&first.more&&first.progress&&e.repository.pageCalls==1&&e.repository.statusCalls==1)
  val second=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(second.completed&&e.repository.pageCalls==1&&e.repository.statusCalls==4)
 }
 test("latest comparison resumes each successful late response without repeating it") {
  for(late in listOf("status","source","final")){
   val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(2130))
   if(late=="source")e.repository.afterReconcile={android.os.SystemClock.fixed=61_000L}
   else e.repository.afterStatus={calls->if(calls==if(late=="status")3 else 4)android.os.SystemClock.fixed=61_000L}
   val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!first.completed&&first.more&&first.progress)
   val priorSources=e.repository.reconciliationRequests.size;val priorStatus=e.repository.statusCalls
   e.repository.afterStatus=null
   val second=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(second.completed&&e.repository.reconciliationRequests.size==1)
   if(late=="source"||late=="final")check(priorSources==1&&e.repository.reconciliationRequests.size==priorSources)
   if(late=="final")check(e.repository.statusCalls==priorStatus)
  }
 }
 test("late contradictory Cloud evidence discards the comparison and the audit") {
  for(stage in listOf("status","source","final")){
   val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(2135))
   if(stage=="source")e.repository.afterReconcile={
    android.os.SystemClock.fixed=61_000L
    e.repository.reconcileOverride=rw.ikanisa.burimunsi.core.ObservationReconcileReply(cloudKey(adminA,2135),"missing",null,null)
   }else{
    val target=if(stage=="status")3 else 4
    e.repository.afterStatus={calls->if(calls==target)android.os.SystemClock.fixed=61_000L}
    e.repository.statusReplyOverride={calls,status->if(calls==target)status.copy(hasPending=true)else status}
   }
   val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!first.completed&&!first.progress&&e.repository.reconciliationBatches.size==1)
   e.repository.afterStatus=null;e.repository.statusReplyOverride=null;e.repository.reconcileOverride=null
   var next=ObservationCycleResult(false,false)
   repeat(4){if(!next.completed)next=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})}
   check(next.completed&&e.repository.reconciliationBatches.size==2)
  }
 }
 test("a late response cannot preserve a cancelled or changed authority") {
  for(change in listOf("cancel","observer","permission","inbox")){
   val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=(2141L..2145L).map{row(it,"$body $it")}
   var cancelled=false
   e.repository.afterBatch={
    android.os.SystemClock.fixed=61_000L
    when(change){"cancel"->cancelled=true;"observer"->ObservationInboxRevision.observerDetached(e.observerLease)
     "permission"->e.context.denied=setOf(Manifest.permission.READ_SMS)
     else->{e.context.contentResolver.rows=e.context.contentResolver.rows+row(2146,"$body 2146");ObservationInboxRevision.changed()}}
   }
   val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={cancelled})
   check(!first.completed&&!first.progress)
   cancelled=false
   if(change=="observer")ObservationInboxRevision.observerRegistered()
   if(change=="permission")e.context.denied=emptySet()
   val before=e.repository.reconciliationBatches.size
   var next=ObservationCycleResult(false,false)
   repeat(6){if(!next.completed)next=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})}
   check(e.repository.reconciliationBatches.size>before&&
    e.repository.reconciliationBatches[before].first().sourceKey==cloudKey(adminA,2141))
  }
 }
 test("an exact comparison cannot renew a five-minute-old witness") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(2150))
  e.repository.afterStatus={calls->if(calls==4)android.os.SystemClock.fixed=301_000L}
  val first=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!first.completed&&e.repository.reconciliationRequests.size==1)
  e.repository.afterStatus=null
  val second=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(second.completed&&e.repository.reconciliationRequests.size==2)
 }
 test("a completed large audit is reused until inbox revision changes") {
  val e=setup();e.context.contentResolver.rows=(1L..210L).map{row(it,"$body $it")}
  var result=runUntilSettled(e)
  check(result.completed&&e.repository.requests.size==210)
  val batches=e.repository.reconciliationBatches.size;val pages=e.repository.pageCalls
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  check(e.repository.reconciliationBatches.size==batches&&e.repository.pageCalls==pages)
  e.context.contentResolver.rows=e.context.contentResolver.rows+row(211,"$body 211");ObservationInboxRevision.changed()
  result=runUntilSettled(e)
  check(result.completed&&e.repository.requests.size==211&&e.repository.reconciliationBatches.size>batches)
 }
 test("a changed audit scope cannot reuse an earlier latest match") {
  val e=setup();android.os.SystemClock.fixed=1_000L;e.context.contentResolver.rows=listOf(row(2200),row(2201,"$body 2201"))
  check(runUntilSettled(e).completed)
  val oldKey=cloudKey(adminA,2200)
  val oldSource=e.repository.retainedSources.remove(oldKey)!!
  e.repository.retainedSources[oldKey]=oldSource
  val heldName="observation-prior-cursor-held-"+Values.sha256(listOf(adminA.collectionId,adminA.accountId)
   .joinToString(""){"${it.length}:$it"})
  val store=SecureStore(e.context,heldName);val held=JSONObject(store.read()!!)
  held.getJSONArray("keys").put(oldKey);store.write(held.toString())
  val result=runUntilSettled(e)
  check(!result.completed&&e.repository.reconciliationRequests.size==2&&
   ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.RECONCILE_ORDER_UNCERTAIN)
 }
 test("detached inbox monitoring invalidates a completed audit even if the newest SMS is unchanged") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1950),row(1951,"$body 1951"))
  check(runUntilSettled(e).completed)
  val batches=e.repository.reconciliationBatches.size
  ObservationInboxRevision.observerDetached(e.observerLease)
  e.context.contentResolver.rows=listOf(row(1951,"$body 1951")) // An old-row deletion emits no SMS_RECEIVED.
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&!result.progress&&e.repository.reconciliationBatches.size==batches&&
   ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.OBSERVER_UNAVAILABLE)
 }
 test("the job fallback captures new SMS but cannot confirm without a registered inbox observer") {
  val e=setup();ObservationInboxRevision.observerDetached(e.observerLease)
  e.context.contentResolver.rows=listOf(row(1952))
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.size==1&&pending(adminA).isEmpty()&&
   ObservationSyncDiagnostics.snapshot()!!.fence==ObservationSyncDiagnostics.Fence.OBSERVER_UNAVAILABLE)
 }
 test("a missing evicted identity is audited but never recreated") {
  val e=setup();ObservationRecovery(e.context).scan()
  ObservationStateStore.value=ObservationJournalState(emptyList(),seedSeen(adminA,2L..1025L))
  e.context.contentResolver.rows=listOf(row(1),row(1025));val latest=cloudKey(adminA,1025)
  e.repository.retainedSources[latest]="source-latest";e.repository.retainedSourceKeys.add(latest)
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.isEmpty()&&e.repository.reconciliationBatches.flatten().any{it.sourceKey==cloudKey(adminA,1)})
  check(pending(adminA).isEmpty())
 }
 test("an owner switch cannot recreate another owner's acknowledged missing source") {
  val e=setup();check(!ObservationReplayGuard.ambiguous(e.context,adminA,1))
  val config=ObservationConfigStore(e.context);config.saveProfile(adminB,e.approved,System.currentTimeMillis())
  config.saveConsent(adminB,ObservationConsentState(ObservationConsentRevision(true,1),true));NativeRepository.switch(adminB)
  e.context.contentResolver.rows=listOf(row(5000));ObservationRecovery(e.context).scan()
  check(ObservationCoordinator(e.context,e.repository).cycle()&&e.repository.requests.size==1)
  e.repository.retainedSources.clear();e.repository.retainedSourceKeys.clear()
  config.saveProfile(adminA,e.approved,System.currentTimeMillis())
  config.saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(true,1),true));NativeRepository.switch(adminA)
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.size==1&&pending(adminA).isEmpty())
 }
 test("an unknown lower row below the replay horizon remains visible and unconfirmed") {
  val e=setup();check(ObservationReplayGuard.protect(e.context,adminA,5000))
  e.context.contentResolver.rows=listOf(row(2))
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.isEmpty()&&e.repository.reconciliationBatches.flatten().any{it.sourceKey==cloudKey(adminA,2)})
 }
 test("a 1100-row seen journal scans in bounded pages without per-row store rereads") {
  val e=setup();ObservationRecovery(e.context).scan()
  ObservationStateStore.value=ObservationJournalState(emptyList(),seedSeen(adminA,1L..1100L))
  e.context.contentResolver.rows=(1L..1100L).map{row(it)}
  val before=ObservationStateStore.reads;val started=System.nanoTime();var state=ObservationRecovery.Scan.MORE
  repeat(12){if(state==ObservationRecovery.Scan.MORE)state=ObservationRecovery(e.context).scanStatus()}
  val elapsed=(System.nanoTime()-started)/1_000_000
  check(state==ObservationRecovery.Scan.COMPLETE&&pending(adminA).isEmpty()&&ObservationStateStore.reads-before<40)
  println("METRIC 1100-row synthetic bounded scan ${elapsed}ms")
 }
 test("a lower insertion between capture pages invalidates the sweep cursor") {
  val e=setup();e.context.contentResolver.rows=(1L..200L).map{row(it*2)}
  check(ObservationRecovery(e.context).scan())
  e.context.contentResolver.rows=e.context.contentResolver.rows+row(101);ObservationInboxRevision.changed()
  ObservationRecovery(e.context).scan()
  check(pending(adminA).any{it.observation.sourceKey==cloudKey(adminA,101)})
 }
 test("a held source is checked read-only and never released or uploaded") {
  val e=setup();app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=true
  try{
   e.context.contentResolver.rows=listOf(row(1200));ObservationRecovery(e.context).scan()
   val key=cloudKey(adminA,1200);e.repository.retainedSources[key]="source-held";e.repository.retainedSourceKeys.add(key)
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(result.completed&&e.repository.requests.isEmpty()&&e.repository.reconciliationBatches.flatten().any{it.sourceKey==key})
  }finally{app.cool.mobile.BuildConfig.CLOUD_HOLD_EXISTING_INBOX=false}
 }
 test("an unsupported newest approved-provider SMS prevents confirmation") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1300),row(1301,"x".repeat(3001))+("date" to (time+100)))
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.size==1&&e.repository.requests.single().rawBody==body)
 }
 test("a Cloud-only source prevents an otherwise matching latest witness") {
  val e=setup();android.os.SystemClock.fixed=1_000;e.context.contentResolver.rows=listOf(row(1400))
  check(ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false}).completed)
  e.repository.cloudOnlySources.add("source-other");android.os.SystemClock.fixed=301_001
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.requests.size==1)
 }
 test("pending reservations or unmatched canonical sources prevent completion") {
  for(kind in listOf("pending","canonical")){
   val e=setup();e.context.contentResolver.rows=listOf(row(1500))
   if(kind=="pending")e.repository.pendingReservation=true else e.repository.unmatchedCanonical=true
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   check(!result.completed)
  }
 }
 test("an item conflict holds its page while later pages are checked without replay") {
  val e=setup();e.context.contentResolver.rows=(1601L..1608L).map{row(it,"$body $it")}
  for(id in 1601L..1608L)e.repository.retainedSources[cloudKey(adminA,id)]="source-$id"
  e.repository.poisonSourceKeys=setOf(cloudKey(adminA,1602))
  val recovery=ObservationRecovery(e.context);recovery.resetAudit();var audit=ObservationRecovery.Audit.MORE
  repeat(12){if(audit==ObservationRecovery.Audit.MORE)audit=recovery.auditPage(e.repository)}
  check(audit==ObservationRecovery.Audit.UNCONFIRMED&&e.repository.reconciliationBatches.size==8&&
   e.repository.reconciliationBatches.all{it.size==1}&&
   e.repository.reconciliationBatches.last().first().sourceKey==cloudKey(adminA,1608)&&e.repository.requests.isEmpty())
 }
 test("duplicate or missing source IDs cannot confirm an audit") {
  for(kind in listOf("duplicate","missing")){
   val e=setup();e.context.contentResolver.rows=listOf(row(1605),row(1606,"$body 1606"))
   e.repository.retainedSources[cloudKey(adminA,1605)]="source-1605"
   e.repository.retainedSources[cloudKey(adminA,1606)]="source-1606"
   e.repository.batchReplyOverride={items->items.map{item->
    if(kind=="missing"&&item.sourceKey==cloudKey(adminA,1606))ObservationReconcileReply(item.sourceKey,"missing",null,null)
    else ObservationReconcileReply(item.sourceKey,"matched","source-same",null)
   }}
   ObservationRecovery(e.context).resetAudit()
   val recovery=ObservationRecovery(e.context)
   check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
   var audit=ObservationRecovery.Audit.MORE
   repeat(5){if(audit==ObservationRecovery.Audit.MORE)audit=recovery.auditPage(e.repository)}
   check(audit==ObservationRecovery.Audit.UNCONFIRMED&&e.repository.requests.isEmpty())
  }
 }
 test("identical phone witnesses cannot confirm two distinct sources") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1611),row(1612))
  for(id in 1611L..1612L)e.repository.retainedSources[cloudKey(adminA,id)]="source-$id"
  val recovery=ObservationRecovery(e.context);recovery.resetAudit()
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.reconciliationBatches.size==2&&e.repository.reconciliationBatches.all{it.size==1}&&e.repository.requests.isEmpty())
 }
 test("an identical phone witness on a later page remains unconfirmed") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1621),row(1622,"$body 2"),
   row(1623,"$body 3"),row(1624,"$body 4"),row(1625))
  for(id in 1621L..1625L)e.repository.retainedSources[cloudKey(adminA,id)]="source-$id"
  val recovery=ObservationRecovery(e.context);recovery.resetAudit()
  var audit=ObservationRecovery.Audit.MORE
  repeat(8){if(audit==ObservationRecovery.Audit.MORE)audit=recovery.auditPage(e.repository)}
  check(audit==ObservationRecovery.Audit.UNCONFIRMED&&e.repository.reconciliationBatches.size==5&&
   e.repository.reconciliationBatches.all{it.size==1}&&e.repository.requests.isEmpty())
 }
 test("sender aliases and optional metadata do not disambiguate identical phone witnesses") {
  val e=setup();e.approved.put("senders",JSONArray().put("M-Money").put("AnotherSender"))
  ObservationConfigStore(e.context).saveProfile(adminA,e.approved,System.currentTimeMillis())
  e.context.contentResolver.rows=listOf(row(1631),
   row(1632)+("address" to "AnotherSender")+("date_sent" to (time-1000))+("sub_id" to 4))
  for(id in 1631L..1632L)e.repository.retainedSources[cloudKey(adminA,id)]="source-$id"
  val recovery=ObservationRecovery(e.context);recovery.resetAudit()
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.UNCONFIRMED)
  check(e.repository.requests.isEmpty())
 }
 test("different phone received times remain distinct witnesses") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1633),row(1634)+("date" to (time+1)))
  e.repository.retainedSources[cloudKey(adminA,1633)]="source-1633"
  e.repository.retainedSources[cloudKey(adminA,1634,time+1)]="source-1634"
  val recovery=ObservationRecovery(e.context);recovery.resetAudit();var audit=ObservationRecovery.Audit.MORE
  repeat(8){if(audit==ObservationRecovery.Audit.MORE)audit=recovery.auditPage(e.repository)}
  check(audit==ObservationRecovery.Audit.COMPLETE&&e.repository.requests.isEmpty())
 }
 test("permission revoked between page read and batch dispatch sends no witness") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1700))
  val key=cloudKey(adminA,1700);e.repository.retainedSources[key]="source-1700"
  ObservationRecovery(e.context).scan()
  val recovery=ObservationRecovery(e.context);recovery.resetAudit()
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  e.context.contentResolver.afterBodyRead={e.context.denied=setOf(Manifest.permission.READ_SMS)}
  val audit=recovery.auditPage(e.repository)
  check(audit==ObservationRecovery.Audit.BLOCKED&&e.repository.reconciliationBatches.isEmpty())
 }
 test("permission revoked during status read prevents the latest-witness request") {
  val e=setup();e.context.contentResolver.rows=listOf(row(1701))
  e.repository.afterStatus={calls->if(calls==3)e.context.denied=setOf(Manifest.permission.READ_SMS)}
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  check(!result.completed&&e.repository.statusCalls==3&&e.repository.reconciliationRequests.isEmpty())
 }
 test("a changed Cloud pagination cursor restarts the audit") {
  val e=setup();e.context.contentResolver.rows=(1801L..1901L).map{row(it,"$body $it")}
  for(id in 1801L..1901L)e.repository.retainedSources[cloudKey(adminA,id)]="source-$id"
  val recovery=ObservationRecovery(e.context);recovery.resetAudit();repeat(104){check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)}
  e.repository.cursorFailure=rw.ikanisa.burimunsi.data.ApiFailure("cursor_scope_changed",409)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.RETRY)
  e.repository.cursorFailure=null;val batches=e.repository.reconciliationBatches.size
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE)
  check(recovery.auditPage(e.repository)==ObservationRecovery.Audit.MORE&&e.repository.reconciliationBatches.size>batches)
  check(e.repository.reconciliationBatches[batches].first().sourceKey==cloudKey(adminA,1801))
 }
 test("diagnostic identifies missing owner and owner loss during consent by their exact fence") {
  for(missing in listOf(true,false)){
   val e=setup()
   if(missing)NativeRepository.switch(null)else e.repository.afterConsentRead={NativeRepository.switch(adminB)}
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
   val diagnostic=ObservationSyncDiagnostics.snapshot()!!
   check(!result.completed&&result.problem=="sync_unconfirmed"&&e.repository.requests.isEmpty())
   check(diagnostic.fence==if(missing)ObservationSyncDiagnostics.Fence.OWNER_UNAVAILABLE else ObservationSyncDiagnostics.Fence.OWNER_CHANGED)
   check(diagnostic.fencePhase==if(missing)ObservationSyncDiagnostics.Phase.COORDINATOR_START else ObservationSyncDiagnostics.Phase.CONSENT_MERGE)
   check(diagnostic.coordinator==ObservationSyncDiagnostics.Outcome.UNCONFIRMED&&!diagnostic.queueRead)
  }
 }
 test("diagnostic distinguishes restore timeout from elapsed budget and cancellation") {
  val timed=setup()
  val timeout=ObservationSyncCycle.run(timed.context,true,restore={throw java.net.SocketTimeoutException("sensitive-timeout-detail")},stopped={false})
  var diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(!timeout.completed&&timeout.problem=="connection_waiting"&&diagnostic.error==ObservationSyncDiagnostics.ErrorKind.TIMEOUT)
  check(diagnostic.errorPhase==ObservationSyncDiagnostics.Phase.RESTORE&&diagnostic.stop==ObservationSyncDiagnostics.Stop.NONE)
  val budgeted=setup();android.os.SystemClock.fixed=1_000
  val expired=ObservationSyncCycle.run(budgeted.context,true,restore={android.os.SystemClock.fixed=61_000;budgeted.repository},stopped={false})
  diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(!expired.completed&&expired.problem=="sync_unconfirmed"&&budgeted.repository.requests.isEmpty())
  check(diagnostic.stop==ObservationSyncDiagnostics.Stop.ELAPSED_BUDGET&&diagnostic.stopPhase==ObservationSyncDiagnostics.Phase.RESTORE)
  check(diagnostic.error==ObservationSyncDiagnostics.ErrorKind.NONE&&diagnostic.coordinator==ObservationSyncDiagnostics.Outcome.NOT_RUN)
  val cancelled=setup();var restores=0
  val stopped=ObservationSyncCycle.run(cancelled.context,true,restore={restores++;cancelled.repository},stopped={true})
  diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(!stopped.completed&&stopped.problem=="sync_unconfirmed"&&restores==0)
  check(diagnostic.stop==ObservationSyncDiagnostics.Stop.CANCELLED&&diagnostic.stopPhase==ObservationSyncDiagnostics.Phase.IDLE)
 }
 test("diagnostic preserves coordinator success when the overall empty-queue cycle exhausts its budget") {
  val e=setup();android.os.SystemClock.fixed=1_000
  e.repository.afterProfileRead={
   var reads=0;android.os.SystemClock.afterRead={if(++reads==1)android.os.SystemClock.fixed=61_000}
  }
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  val diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(!result.completed&&result.problem=="sync_unconfirmed"&&e.repository.requests.isEmpty())
  check(diagnostic.coordinator==ObservationSyncDiagnostics.Outcome.COMPLETED&&diagnostic.queueRead&&diagnostic.queued==0)
  check(diagnostic.outcome==ObservationSyncDiagnostics.Outcome.UNCONFIRMED&&diagnostic.stop==ObservationSyncDiagnostics.Stop.ELAPSED_BUDGET)
  check(diagnostic.stopPhase==ObservationSyncDiagnostics.Phase.COORDINATOR_FINISHED)
 }
 test("diagnostic identifies a reversed monotonic clock and preserves unconfirmed status") {
  val e=setup();android.os.SystemClock.fixed=1_000
  val result=ObservationSyncCycle.run(e.context,true,restore={android.os.SystemClock.fixed=999;e.repository},stopped={false})
  val diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(!result.completed&&result.problem=="sync_unconfirmed"&&diagnostic.stop==ObservationSyncDiagnostics.Stop.CLOCK_REVERSED)
  check(diagnostic.stopPhase==ObservationSyncDiagnostics.Phase.RESTORE)
 }
 test("diagnostic retains permission consent and acknowledgement failure fences with exact queued requests") {
  for(kind in listOf("permission","consent","ack","owner","stop")){
   val e=setup();e.context.contentResolver.rows=listOf(row(701));var stop=false
   e.repository.invalidAck=kind=="ack"
   e.repository.switchDuringSubmit={when(kind){
    "permission"->e.context.denied=setOf(Manifest.permission.READ_SMS)
    "consent"->{val config=ObservationConfigStore(e.context);config.saveConsent(adminA,config.consent(adminA)!!.copy(confirmed=false))}
    "owner"->NativeRepository.switch(adminB)
    "stop"->stop=true
   }}
   val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={stop})
   val diagnostic=ObservationSyncDiagnostics.snapshot()!!
   val fence=when(kind){
    "permission"->ObservationSyncDiagnostics.Fence.PERMISSION_REQUIRED
    "consent"->ObservationSyncDiagnostics.Fence.CONSENT_NOT_CAPTURING
    "owner"->ObservationSyncDiagnostics.Fence.OWNER_CHANGED
    "stop"->ObservationSyncDiagnostics.Fence.STOPPED
    else->ObservationSyncDiagnostics.Fence.ACK_REJECTED
   }
   check(!result.completed&&diagnostic.fence==fence&&diagnostic.fencePhase==ObservationSyncDiagnostics.Phase.ACKNOWLEDGE)
   check(diagnostic.queued==1&&diagnostic.attempts==1&&diagnostic.acknowledged==0)
   check(pending(adminA).single().observation==e.repository.requests.single())
  }
 }
 test("busy reentry keeps the actual running cycle diagnostic and never calls a second restore") {
  val e=setup();e.context.contentResolver.rows=listOf(row(960))
  val result=ObservationSyncCycle.run(e.context,true,restore={
   val before=ObservationSyncDiagnostics.snapshot()!!
   val busy=ObservationSyncCycle.run(e.context,true,restore={error("second restore must not run")},stopped={false})
   check(busy.busy&&!busy.completed&&ObservationSyncDiagnostics.snapshot()!!.phase==before.phase)
   check(ObservationSyncDiagnostics.snapshot()!!.outcome==ObservationSyncDiagnostics.Outcome.RUNNING)
   e.repository
  },stopped={false})
  check(result.completed&&ObservationSyncDiagnostics.snapshot()!!.coordinator==ObservationSyncDiagnostics.Outcome.COMPLETED)
 }
 test("diagnostic dump is read-only and excludes unknown errors API codes identities and SMS content") {
  val secret="secret-detail-$installation-${adminA.collectionId}-${adminA.accountId}-$body"
  for(failure in listOf(IllegalStateException(secret),rw.ikanisa.burimunsi.data.ApiFailure(secret,422),rw.ikanisa.burimunsi.data.ApiFailure(secret,401))){
   val e=setup()
   val result=ObservationSyncCycle.run(e.context,true,restore={throw failure},stopped={false})
   check(!result.completed)
   check(result.problem==if(failure is rw.ikanisa.burimunsi.data.ApiFailure&&failure.status==401)"authorization_required"else "sync_unconfirmed")
   val before=ObservationSyncDiagnostics.snapshot()!!;val queries=e.context.contentResolver.queries
   val output=java.io.StringWriter();val writer=java.io.PrintWriter(output)
   repeat(3){ObservationSyncDiagnostics.dump(writer)};writer.flush()
   val text=output.toString()
   check(ObservationSyncDiagnostics.snapshot()==before&&e.context.contentResolver.queries==queries&&e.repository.requests.isEmpty())
   check(listOf(secret,installation,adminA.collectionId,adminA.accountId,body,"IllegalStateException","ApiFailure","approved-v1").none{text.contains(it)})
   check(text.length<12_288)
   val token=Regex("[a-z_]+=(?:[A-Z][A-Z_]*|true|false|[0-9]+)")
   check(text.lineSequence().filter{it.isNotEmpty()&&!it.startsWith("buri_sync_diagnostics ")}.all{line->line.split(' ').all{token.matches(it)}})
  }
 }
 test("diagnostic counters and durations remain bounded under concurrent updates and dumps") {
  var now=1_000L
  val diagnostic=ObservationSyncDiagnostics.begin(true){now}
  diagnostic.queued(Int.MAX_VALUE)
  val threads=(1..4).map{Thread{repeat(3_000){diagnostic.attempted();diagnostic.acknowledged();diagnostic.unresolved()}}.also{it.start()}}
  threads.forEach{it.join(5_000);check(!it.isAlive)}
  now=Long.MAX_VALUE
  check(diagnostic.snapshot().elapsedMs==ObservationSyncDiagnostics.MAX_DURATION_MS)
  val snapshot=diagnostic.snapshot()
  check(listOf(snapshot.queued,snapshot.attempts,snapshot.acknowledged,snapshot.unresolved).all{it==ObservationSyncDiagnostics.MAX_COUNT})
  diagnostic.finish(ObservationCycleResult(false,true,"unexpected-$installation"))
  diagnostic.finish(ObservationCycleResult(true,false))
  check(diagnostic.snapshot().outcome==ObservationSyncDiagnostics.Outcome.UNCONFIRMED&&diagnostic.snapshot().problem==ObservationSyncDiagnostics.Problem.UNKNOWN)
 }
 test("notification distinguishes connection waiting from unconfirmed starting and active states") {
  check(ObservationSyncDiagnostics.notificationState("connection_waiting")==ObservationSyncDiagnostics.NotificationState.WAITING)
  check(ObservationSyncDiagnostics.notificationState("sync_unconfirmed")==ObservationSyncDiagnostics.NotificationState.UNCONFIRMED)
  check(ObservationSyncDiagnostics.notificationState("starting")==ObservationSyncDiagnostics.NotificationState.STARTING)
  check(ObservationSyncDiagnostics.notificationState(null)==ObservationSyncDiagnostics.NotificationState.ACTIVE)
  check(ObservationSyncDiagnostics.notificationState("authorization_required")==ObservationSyncDiagnostics.NotificationState.UNCONFIRMED)
  check(ObservationSyncDiagnostics.notificationState("unknown-private-detail")==ObservationSyncDiagnostics.NotificationState.UNCONFIRMED)
 }
 println("PASS $checks actual-adapter host checks with synthetic doubles")
}
