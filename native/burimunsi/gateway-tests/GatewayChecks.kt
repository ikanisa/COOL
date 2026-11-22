package rw.ikanisa.burimunsi.gatewaytests
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import app.cool.mobile.receiver_sms.ReceiverFixture as F
import rw.ikanisa.burimunsi.gateway.GatewayFactory
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.core.ContractFailure
import app.cool.mobile.BuildConfig
import app.cool.mobile.receiver_sms.BuriCapturePolicy
import app.cool.mobile.receiver_sms.BuriReceiverProfile
import app.cool.mobile.receiver_sms.MomoGatewayHttp
import app.cool.mobile.receiver_sms.ObservationLegacyOwnership
import app.cool.mobile.receiver_sms.ObservationAuthorityRevision
import app.cool.mobile.receiver_sms.ObservationHealthProof
import app.cool.mobile.receiver_sms.ContinuousSyncHealthState
import rw.ikanisa.burimunsi.gateway.ContinuousReceiverHealth
import rw.ikanisa.burimunsi.core.ObservationOwner
import java.time.Instant
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

fun main(){
 var count=0;fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");count++}
 fun <T> verifyHealthTransition(label:String,action:()->T):T {
  val state=ContinuousSyncHealthState()
  val old=ObservationHealthProof(100,4,checkNotNull(ObservationAuthorityRevision.stable()))
  val active=ContinuousReceiverHealth(supported=true,running=true)
  state.set(active,old)
  check(state.checked(101,ObservationAuthorityRevision.stable(),4,true).problem==null)
  var invalidatedDuringControl=false
  val stop=ObservationAuthorityRevision.observe{
   if(ObservationAuthorityRevision.stable()==null)
    invalidatedDuringControl=state.checked(101,null,4,true).problem=="sync_unconfirmed"
  }
  try {
   val result=action()
   ck("$label invalidates displayed success before the control completes",invalidatedDuringControl&&state.get().problem=="sync_unconfirmed")
   // The worker callback may already be queued on Android's main looper.
   state.set(active,old)
   ck("$label rejects a late successful worker publication",state.checked(101,ObservationAuthorityRevision.stable(),4,true).problem=="sync_unconfirmed")
   return result
  } finally {stop()}
 }
 val code="b".repeat(64);val handoff="50000000-0000-4000-8000-000000000002";val request="50000000-0000-4000-8000-000000000003"
 fun binding(id:String="old-binding")=JSONObject().put("id",id).put("owner_user_id","owner-1").put("collection_id","group-1")
  .put("receiving_account_id","wallet-1").put("version",1).put("subscription_id",3).put("created_at","2026-11-01T00:00:00Z")
 fun profileHttp(sender:String="M-Money",issued:Long=System.currentTimeMillis(),alter:(JSONObject)->Unit={}):MomoGatewayHttp {
  val b=F.state!!.getJSONObject("binding")
  val response=JSONObject().put("contractVersion",1).put("collectionId",b.getString("collection_id"))
   .put("installationId","50000000-0000-4000-8000-000000000001").put("bindingId",b.getString("id"))
   .put("bindingVersion",b.getInt("version")).put("receivingAccountId",b.getString("receiving_account_id"))
   .put("profileVersion","approved fixture / v1").put("offsetMinutes",120).put("senders",JSONArray().put(sender))
   .put("incomingPrefixes",JSONArray().put("You have received")).put("currencyAliases",JSONArray().put("RWF"))
   .put("transactionIdPrefixes",JSONArray().put("FT Id:")).put("issuedAt",issued).put("expiresAt",issued+24*60*60*1000L)
  alter(response)
  return MomoGatewayHttp(openConnection={target->object:HttpURLConnection(URL(target)){
   override fun connect()=Unit;override fun disconnect()=Unit;override fun usingProxy()=false
   override fun getResponseCode()=200
   override fun getHeaderField(name:String)=if(name.equals("Content-Type",true))"application/json" else null
   override fun getInputStream()=response.toString().byteInputStream()
  }})
 }
 fun reset(){F.reset();F.state=JSONObject().put("binding",binding()).put("gateway_token","a".repeat(64)).put("capture_enabled",true).put("inbox_checkpoint",91L)
  .put("installation_id","50000000-0000-4000-8000-000000000001");check(BuriReceiverProfile.refresh(Context(),profileHttp()))}
 fun ack(id:String=request)=JSONObject().put("retired",true).put("handoffId",handoff).put("requestId",id).put("reauthenticationRequired",true)
 F.reset()
 val sourceOwner=ObservationOwner("group-1","admin-1");val received=Instant.parse("2026-11-02T00:00:00Z").toEpochMilli()
 val candidate="You have received 1000 RWF from EXAMPLE (*****001) at 2026-11-01 12:00:00. Balance: 2000 RWF. FT Id: 123456789."
 fun source()=ObservationLegacyOwnership.classify(Context(),sourceOwner,101,received,"M-Money",candidate,3)
 ck("absent legacy binding leaves the observation unowned",source()==ObservationLegacyOwnership.Decision.UNOWNED)
 F.stateUnavailable=true;ck("unreadable legacy state fails closed",source()==ObservationLegacyOwnership.Decision.HOLD)
 reset();ck("active canonical gateway owns its matching inbox source",source()==ObservationLegacyOwnership.Decision.OWNED)
 F.state!!.put("capture_enabled",false);ck("paused legacy receiver never creates an observation",source()==ObservationLegacyOwnership.Decision.HOLD)
 reset();F.state!!.getJSONObject("binding").remove("receipt_profile")
 ck("missing legacy provider profile holds observation classification",source()==ObservationLegacyOwnership.Decision.HOLD)
 reset();val staleProfile=F.state!!.getJSONObject("binding").getJSONObject("receipt_profile")
 val oldIssued=System.currentTimeMillis()-25*60*60*1000L;staleProfile.put("issuedAt",oldIssued).put("expiresAt",oldIssued+24*60*60*1000L)
 ck("expired legacy provider profile holds observation classification",source()==ObservationLegacyOwnership.Decision.HOLD)
 reset();F.state!!.getJSONObject("binding").put("receipt_profile_revision","invalid")
 ck("invalid legacy provider profile holds observation classification",source()==ObservationLegacyOwnership.Decision.HOLD)
 reset();F.state!!.put("inbox_binding_baseline",110L)
 ck("pre-binding inbox evidence remains unowned",source()==ObservationLegacyOwnership.Decision.UNOWNED)
 reset();ck("routing alone does not prove canonical retention",!ObservationLegacyOwnership.retained(Context(),"M-Money",candidate,null,received,3))
 F.retainedCaptureId=app.cool.mobile.receiver_sms.MomoGatewayPolicy.captureId("50000000-0000-4000-8000-000000000001","old-binding","M-Money",candidate,received,3)
 F.retainedBodyHash=rw.ikanisa.burimunsi.core.Values.sha256(candidate)
 ck("matching canonical identity and body prove retention",ObservationLegacyOwnership.retained(Context(),"M-Money",candidate,null,received,3))
 F.retainedBodyHash="0".repeat(64)
 ck("mismatching canonical body never proves retention",!ObservationLegacyOwnership.retained(Context(),"M-Money",candidate,null,received,3))
 F.reset();F.state=JSONObject()
 val entered=CountDownLatch(1);val release=CountDownLatch(1);val attempted=CountDownLatch(1);val changedLatch=CountDownLatch(1);val held=AtomicBoolean(false)
 val scan=Thread{
  held.set(ObservationLegacyOwnership.withDecision(Context(),sourceOwner,101,received,"M-Money",candidate,3){decision->
   entered.countDown();release.await(3,TimeUnit.SECONDS)&&decision==ObservationLegacyOwnership.Decision.UNOWNED&&!F.state!!.has("binding")
  }==true)
 }
 scan.start();check(entered.await(3,TimeUnit.SECONDS))
 val writer=Thread{attempted.countDown();app.cool.mobile.receiver_sms.MomoGatewayStore(Context()).update{it.put("binding",binding())};changedLatch.countDown()}
 writer.start();check(attempted.await(3,TimeUnit.SECONDS));val mutationBlocked=!changedLatch.await(200,TimeUnit.MILLISECONDS)
 release.countDown();scan.join(3000);writer.join(3000)
 ck("legacy state cannot change between classification and protected callback",mutationBlocked&&held.get()&&changedLatch.count==0L)
 reset();var posts=0;var record=false;var reads=0;var result:JSONObject?=null
 val gateway=GatewayFactory.create(Context(),{"group-1"},{_,replace->check(replace);posts++;record=true;ack()},
  {record},{reads++;result},refreshProfile={true})
 ck("missing paired receiving code is not invented",gateway.status().pairedReceivingCode==null)
 F.state!!.getJSONObject("binding").put("public_code","route-101")
 ck("receiving code comes from the scoped pairing snapshot",gateway.status().pairedReceivingCode=="route-101")
 F.state!!.getJSONObject("binding").put("public_code","route-202")
 ck("a different paired code is reflected without a fixed value",gateway.status().pairedReceivingCode=="route-202")
 F.state!!.getJSONObject("binding").put("public_code","\u202eunsafe")
 ck("invalid paired code is not displayed",gateway.status().pairedReceivingCode==null)
 F.state!!.getJSONObject("binding").put("public_code","route-101")
 val otherScope=GatewayFactory.create(Context(),{"other-group"})
 ck("a different collection cannot reveal the paired route",otherScope.status().pairedReceivingCode==null)
 val active=F.state!!.getJSONObject("binding");val expired=active.getJSONObject("receipt_profile")
 val past=System.currentTimeMillis()-25*60*60*1000L
 expired.put("issuedAt",past).put("expiresAt",past+24*60*60*1000L)
 ck("expired profile blocks capture without moving the inbox cursor",BuriReceiverProfile.current(active)==null&&!BuriCapturePolicy.uploadsAdmitted(Context())&&F.state!!.getLong("inbox_checkpoint")==91L)
 ck("fresh approved profile restores admission without moving the cursor",BuriReceiverProfile.refresh(Context(),profileHttp())&&BuriCapturePolicy.uploadsAdmitted(Context())&&F.state!!.getLong("inbox_checkpoint")==91L)
 val priorSnapshot=active.getJSONObject("receipt_profile");val stale=System.currentTimeMillis()-16*60*1000L
 priorSnapshot.put("issuedAt",stale).put("expiresAt",stale+24*60*60*1000L)
 val oldBinding=JSONObject(active.toString())
 val refreshed=BuriReceiverProfile.refresh(Context(),profileHttp("ALT-SENDER",alter={it.put("incomingPrefixes",JSONArray().put("Payment received"));it.put("transactionIdPrefixes",JSONArray().put("Reference:"))}))
 val changed=F.state!!.getJSONObject("binding")
 ck("profile change invalidates in-flight scan binding without advancing cursor",refreshed&&!app.cool.mobile.receiver_sms.BuriReceiverReliability.bindingMatches(oldBinding::opt,changed::opt)&&F.state!!.getLong("inbox_checkpoint")==91L)
 val alternate="Payment received: RWF 1,500 from EXAMPLE. Reference: 123456789."
 ck("approved alternate sender and markers admit an alternate receipt candidate",BuriCapturePolicy.sourceAllowed(changed,"ALT-SENDER",alternate))
 ck("sender mismatch and secret-bearing messages remain excluded",!BuriCapturePolicy.sourceAllowed(changed,"M-Money",alternate)&&!BuriCapturePolicy.sourceAllowed(changed,"ALT-SENDER",alternate+" OTP 1234"))
 changed.remove("receipt_profile");changed.remove("receipt_profile_revision")
 val wrongScope=BuriReceiverProfile.refresh(Context(),profileHttp(alter={it.put("collectionId","other-group")}))
 ck("wrong-scope profile cannot authorize capture or advance cursor",!wrongScope&&!BuriCapturePolicy.uploadsAdmitted(Context())&&F.state!!.getLong("inbox_checkpoint")==91L)
 ck("correct scope refresh restores policy without advancing cursor",BuriReceiverProfile.refresh(Context(),profileHttp())&&BuriCapturePolicy.uploadsAdmitted(Context())&&F.state!!.getLong("inbox_checkpoint")==91L)
 changed.remove("receipt_profile");changed.remove("receipt_profile_revision")
 check(BuriReceiverProfile.refresh(Context(),profileHttp("i")))
 ck("sender case folding matches server Unicode semantics",BuriCapturePolicy.senderAllowed(changed,"I")&&!BuriCapturePolicy.senderAllowed(changed,"İ"))
 reset()
 F.queued=3;runCatching{gateway.replace(code)}
 ck("queued evidence refuses retirement before the API callback",posts==0&&F.queued==3&&!F.queueEnabled&&F.state!!.getBoolean("capture_enabled")==false&&!gateway.retirementPending())
 F.queued=0;F.unreadable=true;runCatching{gateway.replace(code)}
 ck("unreadable queue fails closed without discarding evidence",posts==0&&F.unreadable)
 F.unreadable=false;val originalBinding=F.state!!.getJSONObject("binding");val retired=verifyHealthTransition("Replace"){gateway.replace(code)}
 ck("old Replace returns typed ACK only",retired.requestId==request&&posts==1)
 ck("ACK parks capture and keeps original binding, credential and cursor",F.state!!.getJSONObject("binding")==originalBinding&&F.state!!.getString("gateway_token")=="a".repeat(64)&&F.state!!.getLong("inbox_checkpoint")==91L&&!F.state!!.getBoolean("capture_enabled")&&F.state!!.getBoolean("receiver_retired"))
 ck("retired handset cannot schedule capture, sync or resume",!gateway.bound()&&!gateway.retirementPending()&&runCatching{gateway.sync()}.isFailure&&runCatching{gateway.setPaused(false)}.isFailure)
 gateway.start();ck("retired start never schedules a worker",F.jobs==0)
 result=ack();val historicalAck=verifyHealthTransition("retirement readback"){gateway.recoverRetirement()}
 ck("already-applied historical ACK is not emitted again",historicalAck==null&&reads==1&&posts==1)
 // Cold process: SQL ACK was durably stored, local park never completed.
 reset();record=true;result=ack();val cold=GatewayFactory.create(Context(),{"group-1"},{_,_->error("No POST")},{record},{reads++;result})
 ck("terminal journal before local park remains discoverable",cold.retirementPending())
 cold.start();ck("unapplied ACK prevents startup upload scheduling",F.jobs==0)
 ck("foreground recovery applies terminal ACK once without operator or POST",cold.recoverRetirement()?.requestId==request&&!cold.bound()&&cold.recoverRetirement()==null)
 // Unknown SQL outcome: original Replace control checks without new code or permissions.
 reset();record=true;result=null;F.state!!.put("capture_enabled",false);F.queueEnabled=false
 val unknown=GatewayFactory.create(Context(),{"group-1"},{_,_->error("No replay")},{record},{reads++;result})
 val unknownBefore=reads;val lost=runCatching{unknown.replace("")}.exceptionOrNull()
 ck("pending Replace uses only GET recovery even with blank code",lost is ApiFailure&&lost.code=="gateway_retirement_unconfirmed"&&reads==unknownBefore+1&&posts==1)
 ck("unknown outcome preserves binding/token/cursor and does not enable capture",F.state!!.getString("gateway_token")=="a".repeat(64)&&F.state!!.getLong("inbox_checkpoint")==91L&&!F.state!!.getBoolean("capture_enabled")&&!F.queueEnabled)
 // No durable intent existed: a local preflight failure must not fabricate pending.
 reset();record=false
 val beforeIntent=GatewayFactory.create(Context(),{"group-1"},{_,_->throw ContractFailure("pending_operation_requires_resolution")},{record},{null})
 ck("failed pre-intent financial guard leaves paused capture without fictitious outcome",runCatching{beforeIntent.replace(code)}.exceptionOrNull() is ContractFailure&&!beforeIntent.retirementPending()&&!F.state!!.getBoolean("capture_enabled"))
 // A malformed/secret-bearing ACK cannot replace the receiving credential.
 reset();record=false
 val leaking=GatewayFactory.create(Context(),{"group-1"},{_,_->record=true;ack().put("gateway_token","c".repeat(64))},{record},{null})
 ck("unexpected credential field cannot count as a retirement ACK",runCatching{leaking.replace(code)}.exceptionOrNull() is ApiFailure&&leaking.retirementPending()&&F.state!!.getString("gateway_token")=="a".repeat(64))
 // A formerly retired handset can later be a genuine new target. Repository
 // archives terminal proof only after its authenticated Pair succeeds.
 reset();F.state!!.put("receiver_retired",true).put("capture_enabled",false).put("retirement_ack",ack());record=true
 var flags=mutableListOf<Boolean>();var next=false
 val reused=GatewayFactory.create(Context(),{"group-1"},{_,replace->flags.add(replace);if(!replace){record=false;JSONObject().put("binding",binding("new-binding")).put("gateway_token","c".repeat(64))}
  else{record=true;next=true;ack("50000000-0000-4000-8000-000000000004")}},{record},{null})
 reused.pair(code)
 ck("later Pair restores only the newly authorized binding and pauses capture",reused.bound()&&F.state!!.getJSONObject("binding").getString("id")=="new-binding"&&!F.state!!.getBoolean("capture_enabled")&&flags==listOf(false))
 check(BuriReceiverProfile.refresh(Context(),profileHttp()))
 val nextAck=reused.replace(code)
 ck("next retirement requires a new request ACK and never invokes pair replace flag",next&&flags==listOf(false,true)&&nextAck.requestId!=request&&!reused.bound())
 // The original Pair action starts receiving automatically when its permission,
 // approved profile, SIM and current Admin authority are already available.
 F.reset();F.state=JSONObject().put("installation_id","50000000-0000-4000-8000-000000000001");F.inboxLatest=91L
 val autoContext=Context();val auto=GatewayFactory.create(autoContext,{"group-1"},{_,replace->
  check(!replace);JSONObject().put("binding",binding("auto-binding")).put("gateway_token","d".repeat(64))
 },authorizeControl={true},refreshProfile={BuriReceiverProfile.refresh(autoContext,profileHttp())})
 auto.pair(code)
 ck("pair automatically resumes an approved receiving route",auto.bound()&&F.state!!.getBoolean("capture_enabled")&&F.queueEnabled&&F.jobs>0)
 ck("inbox boundary is taken before pairing",F.state!!.getLong("inbox_binding_baseline")==91L&&F.state!!.getLong("inbox_checkpoint")==91L)
 auto.setPaused(true);auto.start()
 ck("an explicit Pause cannot be silently resumed",!F.state!!.getBoolean("capture_enabled")&&!F.queueEnabled)
 F.reset();F.state=JSONObject().put("installation_id","50000000-0000-4000-8000-000000000001");F.inboxLatest=42L
 val deferredContext=Context();deferredContext.denied=setOf(android.Manifest.permission.READ_SMS)
 val deferred=GatewayFactory.create(deferredContext,{"group-1"},{_,_->JSONObject().put("binding",binding("deferred-binding")).put("gateway_token","e".repeat(64))},
  authorizeControl={true},refreshProfile={BuriReceiverProfile.refresh(deferredContext,profileHttp())})
 deferred.pair(code)
 ck("pair stays pending while SMS permission is unavailable",deferred.bound()&&!F.state!!.getBoolean("capture_enabled")&&F.state!!.getBoolean("auto_resume_pending"))
 deferredContext.denied=emptySet();deferred.start()
 ck("receiving resumes without skipping SMS that arrived before permission was granted",F.state!!.getBoolean("capture_enabled")&&!F.state!!.getBoolean("auto_resume_pending")&&!F.state!!.has("inbox_binding_baseline")&&F.jobs>0)
 ck("post-binding inbox row is reviewable without an unavailable baseline",app.cool.mobile.receiver_sms.BuriReceiverReliability.inboxAfterBinding(101,null,201,200))
 ck("pre-binding inbox rows cannot be associated",!app.cool.mobile.receiver_sms.BuriReceiverReliability.inboxAfterBinding(101,null,199,200))
 ck("known pairing boundary also excludes earlier IDs",!app.cool.mobile.receiver_sms.BuriReceiverReliability.inboxAfterBinding(100,100,201,200))
 ck("invalid binding time cannot authorize inbox rows",!app.cool.mobile.receiver_sms.BuriReceiverReliability.inboxAfterBinding(101,null,201,null))
 reset();F.state!!.put("capture_enabled",false).put("auto_resume_pending",true)
 lateinit var pausing:rw.ikanisa.burimunsi.gateway.GatewayPort
 pausing=GatewayFactory.create(Context(),{"group-1"},authorizeControl={true},refreshProfile={pausing.setPaused(true);true})
 pausing.start()
 ck("Pause during profile refresh prevents automatic resume",!F.state!!.getBoolean("capture_enabled")&&!F.state!!.getBoolean("auto_resume_pending")&&!F.queueEnabled)
 // Execute the real admission policy and generated HTTP boundary. Platform,
 // encrypted store and connection are explicit doubles; no network/SMS runs.
 reset();val context=Context()
 ck("valid persisted resumed receiver admits runtime transport",BuriCapturePolicy.uploadsAdmitted(context))
 for((label,mutate) in listOf<Pair<String,(JSONObject)->Unit>>(
  "paused" to {it.put("capture_enabled",false)},
  "retired" to {it.put("receiver_retired",true)},
  "retirement pending" to {it.put("retirement_pending",true)},
  "invalid credential" to {it.put("gateway_token","masked")},
  "different installation" to {it.put("installation_id","50000000-0000-4000-8000-000000000099")},
  "revoked authorization" to {it.put("reason","authorization_required")},
  "malformed pause flag" to {it.put("capture_enabled","true")},
  "malformed retirement flag" to {it.put("receiver_retired","false")},
  "invalid binding version" to {it.getJSONObject("binding").put("version",0)},
  "invalid SIM sentinel" to {it.getJSONObject("binding").put("subscription_id",Int.MAX_VALUE)},
  "invalid collection" to {it.getJSONObject("binding").put("collection_id","")}
 )){reset();mutate(F.state!!);ck("runtime denies $label",!BuriCapturePolicy.uploadsAdmitted(context))}
 reset();BuildConfig.IS_QUALIFICATION=true;ck("qualification cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));BuildConfig.IS_QUALIFICATION=false
 BuildConfig.IS_GATEWAY=false;BuildConfig.FLAVOR="staff";ck("staff-only build cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));BuildConfig.IS_GATEWAY=true;BuildConfig.FLAVOR="internal_receiver"
 val endpoint=BuildConfig.RECEIVER_API_BASE_URL;BuildConfig.RECEIVER_API_BASE_URL="http://gateway.example.invalid";ck("unconfigured endpoint cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));BuildConfig.RECEIVER_API_BASE_URL=endpoint
 F.state!!.getJSONObject("binding").remove("receipt_profile");ck("missing approved profile cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));check(BuriReceiverProfile.refresh(context,profileHttp()))
 context.denied=setOf(android.Manifest.permission.RECEIVE_SMS);ck("missing SMS permission cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));context.denied=emptySet()
 F.subscriptions=null;ck("unknown active SIM cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));F.subscriptions=setOf(9);ck("another SIM cannot transport",!BuriCapturePolicy.uploadsAdmitted(context));F.subscriptions=setOf(3)
 var controls=true;var scope:String?="group-1"
 val control=GatewayFactory.create(context,{scope},authorizeControl={controls})
 verifyHealthTransition("Pause"){control.setPaused(true)}
 ck("Pause holds capture and transport without erasing credential",!BuriCapturePolicy.uploadsAdmitted(context)&&F.state!!.getString("gateway_token")=="a".repeat(64))
 ck("Sync never silently resumes a paused receiver",runCatching{control.sync()}.isFailure&&!F.state!!.getBoolean("capture_enabled"))
 controls=false;ck("missing current operator authority cannot Resume",runCatching{control.setPaused(false)}.isFailure)
 controls=true;scope="other-group";ck("different current scope cannot Resume",runCatching{control.setPaused(false)}.isFailure)
 scope="group-1";F.state!!.put("reason","permission_required");control.setPaused(false)
 ck("original Resume admits valid receiver after permission recovery",BuriCapturePolicy.uploadsAdmitted(context)&&F.queueEnabled)
 // A control transition is durably held before either store changes. A later
 // authenticated status refresh recovers an interrupted transition to Pause.
 reset();val guarded=GatewayFactory.create(context,{"group-1"},authorizeControl={true});F.queued=1
 guarded.setPaused(true);F.failMarkerWrite=true
 ck("failed transition marker cannot resume either receiver",runCatching{guarded.setPaused(false)}.isFailure&&
  !F.state!!.has("control_transition")&&!F.queueEnabled&&F.observationPaused&&!BuriCapturePolicy.uploadsAdmitted(context))
 F.failMarkerWrite=false;F.failQueueEnable=true
 ck("failed queue enable retains a blocking transition",runCatching{guarded.setPaused(false)}.isFailure&&
  F.state!!.has("control_transition")&&!F.queueEnabled&&F.observationPaused&&!BuriCapturePolicy.uploadsAdmitted(context)&&F.queued==1)
 ck("held control blocks receiver replacement without changing its binding",runCatching{guarded.replace(code)}.isFailure&&
  F.state!!.getJSONObject("binding").getString("id")=="old-binding"&&F.queued==1)
 F.failQueueEnable=false;F.observationAccount="another-admin"
 val otherControl=guarded.status()
 ck("another account cannot clear the original transition",otherControl.problem=="control_unconfirmed"&&!otherControl.captureEnabled&&F.state!!.has("control_transition"))
 F.observationAccount="operator-1";val recovered=guarded.status()
 ck("interrupted resume recovers to pause without deleting evidence",!F.state!!.has("control_transition")&&!recovered.captureEnabled&&
  !F.queueEnabled&&F.observationPaused&&F.queued==1&&F.state!!.getString("gateway_token")=="a".repeat(64))
 F.failObservationAfterWrite=true
 ck("partial observation resume cannot admit legacy capture",runCatching{guarded.setPaused(false)}.isFailure&&
  F.state!!.has("control_transition")&&!F.observationPaused&&!BuriCapturePolicy.uploadsAdmitted(context)&&
  !ObservationLegacyOwnership.controlTransitionClear(context)&&F.queued==1)
 val blocked=guarded.status()
 ck("failed pause recovery remains visibly unresolved",blocked.problem=="control_unconfirmed"&&!blocked.captureEnabled&&F.state!!.has("control_transition"))
 F.failObservationAfterWrite=false;guarded.status()
 ck("recovery after protected write failure durably pauses both paths",!F.state!!.has("control_transition")&&
  !F.state!!.getBoolean("capture_enabled")&&!F.queueEnabled&&F.observationPaused&&F.queued==1)
 F.failMarkerClear=true
 ck("failed final transition write keeps capture held",runCatching{guarded.setPaused(false)}.isFailure&&
  F.state!!.has("control_transition")&&!BuriCapturePolicy.uploadsAdmitted(context)&&F.queued==1)
 F.failMarkerClear=false;guarded.status()
 ck("safe recovery clears the hold only after both pause writes",!F.state!!.has("control_transition")&&
  !F.state!!.getBoolean("capture_enabled")&&!F.queueEnabled&&F.observationPaused&&F.queued==1)
 guarded.setPaused(false);ck("explicit retry resumes after recovery",BuriCapturePolicy.uploadsAdmitted(context)&&F.queueEnabled&&!F.observationPaused)
 F.failQueueDisable=true
 ck("failed queue pause remains held and never clears retained sources",runCatching{guarded.setPaused(true)}.isFailure&&
  F.state!!.has("control_transition")&&!BuriCapturePolicy.uploadsAdmitted(context)&&F.queued==1)
 F.failQueueDisable=false;guarded.status()
 ck("pause retry clears its marker only after the queue is disabled",!F.state!!.has("control_transition")&&
  !F.queueEnabled&&F.observationPaused&&!F.state!!.getBoolean("capture_enabled"))
 val resumeEntered=CountDownLatch(1);val releaseResume=CountDownLatch(1);val pauseDone=CountDownLatch(1)
 F.afterObservationControl={value->if(!value){resumeEntered.countDown();check(releaseResume.await(5,TimeUnit.SECONDS))}}
 val resumeThread=Thread{guarded.setPaused(false)};resumeThread.start();check(resumeEntered.await(5,TimeUnit.SECONDS))
 val pauseThread=Thread{guarded.setPaused(true);pauseDone.countDown()};pauseThread.start()
 val pauseBlocked=!pauseDone.await(200,TimeUnit.MILLISECONDS);releaseResume.countDown();resumeThread.join(6000);pauseThread.join(6000)
 F.afterObservationControl=null
 ck("concurrent newer pause follows the complete resume without being overwritten",pauseBlocked&&pauseDone.count==0L&&
  !F.state!!.has("control_transition")&&!F.queueEnabled&&F.observationPaused&&!BuriCapturePolicy.uploadsAdmitted(context))
 reset();F.state!!.put("capture_enabled",false);F.state!!.put("control_transition",JSONObject().put("kind","resume")
  .put("collectionId","group-1").put("accountId","operator-1").put("bindingId","old-binding").put("bindingVersion",1))
 ck("transition blocks observation selection as well as legacy transport",source()==ObservationLegacyOwnership.Decision.HOLD&&
  !ObservationLegacyOwnership.controlTransitionClear(context)&&!BuriCapturePolicy.uploadsAdmitted(context))
 reset()
 control.sync();val started=F.jobs;controls=false;scope=null
 control.start();ck("ordinary operator logout preserves previously resumed background receiver",F.jobs>started&&BuriCapturePolicy.uploadsAdmitted(context))
 ck("signed-out operator cannot explicitly Sync",runCatching{control.sync()}.isFailure)
 var opens=0
 val opener:(String)->HttpURLConnection={target->opens++;object:HttpURLConnection(URL(target)){
  override fun connect()=Unit;override fun disconnect()=Unit;override fun usingProxy()=false
  override fun getResponseCode()=200
  override fun getHeaderField(name:String)=if(name.equals("Content-Type",true))"application/json" else null
  override fun getOutputStream()=java.io.ByteArrayOutputStream()
  override fun getInputStream()="{\"ok\":true}".byteInputStream()
 }}
 val body=JSONObject().put("gateway_binding_id","old-binding").put("gateway_binding_version",1).put("subscription_id",3)
  .put("source_mode","live").put("complete",true).put("raw_sender","M-Money")
  .put("raw_body","You have received 1000 RWF from EXAMPLE (*****001) at 2026-11-07 12:00:00. Balance: 2000 RWF. FT Id: 123456789.")
 val transport=MomoGatewayHttp(openConnection=opener,uploadAdmission={token,payload->BuriCapturePolicy.uploadRequestAdmitted(context,token,payload)})
 ck("real generated HTTP dispatches current admitted tuple",transport.request("ingest","a".repeat(64),body).getBoolean("ok")&&opens==1)
 val inbox=JSONObject().put("gateway_binding_id","old-binding").put("gateway_binding_version",1).put("subscription_id",3)
  .put("raw_sender",body.getString("raw_sender")).put("raw_body",body.getString("raw_body"))
  .put("source_mode","catch_up").put("complete",false).put("inbox_received_at","2026-11-02T00:00:00Z")
 ck("post-binding inbox observation is admitted without claiming PDU completeness",BuriCapturePolicy.uploadRequestAdmitted(context,"a".repeat(64),inbox))
 inbox.put("inbox_received_at","2026-10-31T00:00:00Z");ck("pre-binding inbox observation is not attributed",!BuriCapturePolicy.uploadRequestAdmitted(context,"a".repeat(64),inbox))
 inbox.put("inbox_received_at","2026-11-02T00:00:00Z").put("complete",true);ck("inbox cannot claim live PDU completeness",!BuriCapturePolicy.uploadRequestAdmitted(context,"a".repeat(64),inbox))
 ck("real HTTP denies a stale credential before opening a connection",runCatching{transport.request("ingest","b".repeat(64),body)}.isFailure&&opens==1)
 body.put("gateway_binding_version",2);ck("real HTTP denies stale binding before connection",runCatching{transport.request("ingest","a".repeat(64),body)}.isFailure&&opens==1);body.put("gateway_binding_version",1)
 F.state!!.put("capture_enabled",false);ck("real HTTP rechecks Pause at dispatch",runCatching{transport.request("ingest","a".repeat(64),body)}.isFailure&&opens==1)
 F.state!!.put("capture_enabled",true);ck("uninjected HTTP retains default closed admission",runCatching{MomoGatewayHttp(openConnection=opener).request("ingest","a".repeat(64),body)}.isFailure&&opens==1)
 println("RESULT: $count real receiver GatewayFactory checks passed with platform/queue doubles; no Android/SMS/SQL claims.")
}
