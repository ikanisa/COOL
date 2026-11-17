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
 data class Env(val context:Context,val repository:NativeRepository,val approved:JSONObject)
 fun setup(owner:ObservationOwner=adminA):Env {
  android.os.SystemClock.fixed=null;android.os.SystemClock.afterRead=null
  ReceiverFixture.reset();ObservationStateStore.reset();SecureStore.reset();Settings.Secure.testId="1234567890abcdef";NativeRepository.switch(owner)
  val context=Context();val approved=profile();val config=ObservationConfigStore(context)
  config.saveProfile(owner,approved,System.currentTimeMillis())
  config.saveConsent(owner,ObservationConsentState(ObservationConsentRevision(true,1),true))
  val repo=NativeRepository();repo.profile=approved;repo.consent=ObservationConsentRevision(true,1)
  return Env(context,repo,approved)
 }
 fun witness(e:Env,text:String=body,sent:Long=time-1_000,at:Long=System.currentTimeMillis(),reference:Int=7):PduEvidence {
  val left=text.substring(0,55);val right=text.substring(55)
  check(ObservationPduCapture.record(e.context,NativeRepository.observationOwner(e.context)!!,at,3,"3gpp",
   listOf("M-Money","M-Money"),listOf(sent,sent),listOf(left,right),listOf(pdu(left,1,reference),pdu(right,2,reference))))
  return PduCorrelationStore(e.context).read().pdus.last()
 }
 fun pending(owner:ObservationOwner)=ObservationJournal(ObservationStateStore(Context())).pending(owner)
 fun cursor(context:Context)=SecureStore(context,"observation-bounded-rescan-"+
  Values.sha256(listOf(adminA.collectionId,adminA.accountId,false.toString()).joinToString(""){"${it.length}:$it"})).read()
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
  check(pending(adminA).isEmpty()&&cursor(e.context)==null)
  ReceiverFixture.retainedCaptureId=MomoGatewayPolicy.captureId(installation,"binding-1","M-Money",body,time,3)
  ReceiverFixture.retainedBodyHash=Values.sha256(body)
  ReceiverFixture.afterSourceLookup={ObservationConfigStore(e.context).saveConsent(adminA,ObservationConsentState(ObservationConsentRevision(false,2),true))}
  ObservationRecovery(e.context).scan()
  check(cursor(e.context)==null) // Consent changed after classification/lookup.
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
 }
 test("diagnostic confirms a same-owner empty journal without claiming an upload") {
  val e=setup()
  val result=ObservationSyncCycle.run(e.context,true,restore={e.repository},stopped={false})
  val diagnostic=ObservationSyncDiagnostics.snapshot()!!
  check(result.completed&&result.problem==null&&e.repository.requests.isEmpty())
  check(diagnostic.outcome==ObservationSyncDiagnostics.Outcome.COMPLETED&&diagnostic.coordinator==ObservationSyncDiagnostics.Outcome.COMPLETED)
  check(diagnostic.queueRead&&diagnostic.queued==0&&diagnostic.attempts==0&&diagnostic.acknowledged==0)
  check(diagnostic.fence==ObservationSyncDiagnostics.Fence.NONE&&diagnostic.stop==ObservationSyncDiagnostics.Stop.NONE)
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
  val e=setup()
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
