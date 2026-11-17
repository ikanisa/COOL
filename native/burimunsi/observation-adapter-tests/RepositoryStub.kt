package rw.ikanisa.burimunsi.data
import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
/** In-memory authenticated session/network double; no socket or backend access. */
class NativeRepository() {
 constructor(context:Context,api:ApiClient):this()
 fun restore():Any?=Unit
 companion object {
  private val lock=Any();private var generation=0L;private var active:ObservationOwner?=null
  var sessionDeadline=Long.MAX_VALUE
  fun custodyHeld()=Thread.holdsLock(lock)
  fun switch(owner:ObservationOwner?)=synchronized(lock){generation++;active=owner}
  fun observationOwner(context:Context):ObservationSessionOwner?=synchronized(lock){active?.let{ObservationSessionOwner(it,generation)}}
  fun observationDeadline(context:Context,expected:ObservationSessionOwner):Long?=synchronized(lock){
   sessionDeadline.takeIf{observationOwner(context)==expected&&it>System.currentTimeMillis()}
  }
  fun <T> withObservationOwner(context:Context,expected:ObservationSessionOwner?=null,action:(String,String)->T):T?=synchronized(lock){
   val owner=active?:return@synchronized null
   if(expected!=null&&expected!=ObservationSessionOwner(owner,generation))return@synchronized null
   action(owner.collectionId,owner.accountId)
  }
 }
 var consent=ObservationConsentRevision(true,1);lateinit var profile:JSONObject
 var failSubmit=false;var switchDuringSubmit:(()->Unit)?=null;var invalidAck=false
 var unresolvedIds:Set<String> = emptySet();var unresolvedReportedId:String?=null
 var afterConsentRead:(()->Unit)?=null;var duringConsentSet:(()->Unit)?=null
 var afterProfileRead:(()->Unit)?=null
 var consentFailure:Exception?=null;var profileFailure:Exception?=null;var submitFailure:Exception?=null
 var reconcileFailure:Exception?=null;var reconcileOverride:ObservationReconcileReply?=null;var afterReconcile:(()->Unit)?=null
 var batchFailure:Exception?=null;var poisonSourceKeys:Set<String> = emptySet();var afterBatch:(()->Unit)?=null
 var batchReplyOverride:((List<ObservationReconcileRequest>)->List<ObservationReconcileReply>)?=null
 val reconciliationBatches=mutableListOf<List<ObservationReconcileRequest>>()
 var pageFailure:Exception?=null;var pageCountOverride:Int?=null;var afterPage:(()->Unit)?=null;var pageCalls=0
 var cursorFailure:Exception?=null;val pageCursors=mutableListOf<String?>()
 val reconciliationRequests=mutableListOf<ObservationReconcileRequest>()
 val retainedSourceKeys=mutableSetOf<String>()
 val retainedSources=linkedMapOf<String,String>();var distinctSourceIds=true
 val cloudOnlySources=mutableListOf<String>();var pageRevision="fixture"
 var pendingReservation=false;var unmatchedCanonical=false;var statusFailure:Exception?=null;var statusRevisionOverride:String?=null;var statusCalls=0
 var afterStatus:((Int)->Unit)?=null
 var statusReplyOverride:((Int,ObservationReconcileStatus)->ObservationReconcileStatus)?=null
 val requests=mutableListOf<SmsObservation>()
 var verifiedScope="verified_collection";var verifiedFailure:Exception?=null;var verifiedPending:Boolean?=null
 var verifiedUnmatched:Boolean?=null;var verifiedRevisionOverride:String?=null;var verifiedCalls=0
 var afterVerified:((Int)->Unit)?=null
 var recoveryFailureBeforeCommit:Exception?=null;var recoveryFailureAfterCommit:Exception?=null
 var strictLegacyHeldServer=false
 // Synthetic unknown old server: discards the new field rather than rejecting it.
 var permissiveLegacyHeldServer=false
 var capabilityFailure:Exception?=null;var capabilitySource="a".repeat(64);var capabilityMigration="b".repeat(64)
 var capabilityGroup="group-1";var capabilityGeneration:Long?=null;var capabilityNoStore=true
 var afterCapability:(()->Unit)?=null;var afterBeforePost:(()->Unit)?=null;val capabilityRequests=mutableListOf<Long>()
 var afterRecovery:(()->Unit)?=null;var recoveryAckOverride:((HeldObservationAck)->HeldObservationAck)?=null
 val recoveryRequests=mutableListOf<SmsObservation>();val recoveryCommitted=mutableMapOf<String,Pair<SmsObservation,String>>()
 val recoveryGenerations=mutableListOf<Long>();val recoveryCommittedGenerations=mutableMapOf<String,Long>()
 val heldAckRequests=mutableListOf<SmsObservation>();var heldAckFailure:Exception?=null
 val heldAckGenerations=mutableListOf<Long>()
 var heldAckAcknowledged=false;var afterHeldAck:(()->Unit)?=null
 var heldAckOverride:((HeldRecoveryResolution)->HeldRecoveryResolution)?=null
 var beforeNetwork:((String)->Unit)?=null
 fun observationConsent():ObservationConsentRevision{consentFailure?.let{throw it};val value=consent;val action=afterConsentRead;afterConsentRead=null;action?.invoke();return value}
 fun setObservationConsent(value:ObservationConsentRevision):ObservationConsentRevision{val action=duringConsentSet;duringConsentSet=null;action?.invoke();consent=value;return value}
 fun observationProfile():JSONObject {profileFailure?.let{throw it};val action=afterProfileRead;afterProfileRead=null;action?.invoke();return profile}
 fun submitObservation(value:SmsObservation):ObservationAck {
  requests.add(value);val action=switchDuringSubmit;switchDuringSubmit=null;action?.invoke()
  submitFailure?.let{throw it}
  if(value.requestId in unresolvedIds)throw ObservationUploadUnresolved(unresolvedReportedId?:value.requestId)
  if(failSubmit)throw ApiFailure("observation_unavailable",503,true)
  val source=if(!invalidAck&&value.sourceKey!=null){
   retainedSourceKeys.add(value.sourceKey);retainedSources.getOrPut(value.sourceKey){if(distinctSourceIds)"source-${retainedSources.size+1}" else "source-1"}
  }else "source-1"
  return ObservationAck(value.requestId,source,if(invalidAck)"0".repeat(64)else Values.sha256(value.rawBody),"source_unresolved",0)
 }
 fun reconcileObservation(value:ObservationReconcileRequest):ObservationReconcileReply {
  beforeNetwork?.invoke("reconcile")
  reconciliationRequests.add(value);val action=afterReconcile;afterReconcile=null;action?.invoke()
  reconcileFailure?.let{throw it}
  val existing=retainedSources[value.sourceKey];val newest=retainedSources.values.lastOrNull()
  return reconcileOverride?:if(existing!=null)ObservationReconcileReply(value.sourceKey,"matched",existing,newest)
   else ObservationReconcileReply(value.sourceKey,"missing",null,newest)
 }
 fun reconcileObservations(values:List<ObservationReconcileRequest>):List<ObservationReconcileReply> {
  beforeNetwork?.invoke("batch")
  reconciliationBatches.add(values.toList());val action=afterBatch;afterBatch=null;action?.invoke()
  batchFailure?.let{throw it}
  if(values.any{it.sourceKey in poisonSourceKeys})throw ApiFailure("observation_item_conflict",409)
  batchReplyOverride?.let{return it(values)}
  return values.map{value->
   val source=retainedSources[value.sourceKey]
   ObservationReconcileReply(value.sourceKey,if(source==null)"missing" else "matched",source,null)
  }
 }
 fun observationReconcileStatus():ObservationReconcileStatus {
  beforeNetwork?.invoke("status")
  statusCalls++;statusFailure?.let{throw it};val count=retainedSources.size+cloudOnlySources.size
  val revision=statusRevisionOverride?:Values.sha256((retainedSources.toString()+cloudOnlySources.toString()+pendingReservation+unmatchedCanonical))
  val result=ObservationReconcileStatus(pendingReservation,count>0,count,revision,unmatchedCanonical)
  afterStatus?.invoke(statusCalls);return statusReplyOverride?.invoke(statusCalls,result)?:result
 }
 fun observationReconcileVerifiedStatus():ObservationVerifiedStatus {
  beforeNetwork?.invoke("verified")
  verifiedCalls++;verifiedFailure?.let{throw it};val count=retainedSources.size+cloudOnlySources.size
  val pending=verifiedPending?:pendingReservation;val unmatched=verifiedUnmatched?:unmatchedCanonical
  val revision=verifiedRevisionOverride?:Values.sha256(retainedSources.toString()+cloudOnlySources.toString()+pending+unmatched)
  val result=ObservationVerifiedStatus(verifiedScope,ObservationReconcileStatus(pending,count>0,count,revision,unmatched))
  afterVerified?.invoke(verifiedCalls);return result
 }
 private fun capability(expectedConsentGeneration:Long){
  beforeNetwork?.invoke("capability");capabilityRequests.add(expectedConsentGeneration)
  if(strictLegacyHeldServer)throw ApiFailure("invalid_api_request",400)
  // A permissive v1-shaped 200 lacks the strictly required v2 capability data.
  if(permissiveLegacyHeldServer)throw ApiFailure("contract_missing_field",200)
  capabilityFailure?.let{throw it}
  if(capabilitySource!="a".repeat(64)||capabilityMigration!="b".repeat(64)||capabilityGroup!="group-1"||
   (capabilityGeneration?:expectedConsentGeneration)!=expectedConsentGeneration||!capabilityNoStore)
   throw ApiFailure("held_recovery_unapproved",403)
  val action=afterCapability;afterCapability=null;action?.invoke()
 }
 fun recoverHeldObservation(value:SmsObservation,expectedConsentGeneration:Long,
  onNeverDispatched:()->Unit={},beforePost:()->Boolean):HeldObservationAck {
  val started=android.os.SystemClock.elapsedRealtime()
  capability(expectedConsentGeneration)
  var enteredPost=false
  try{
   if(android.os.SystemClock.elapsedRealtime()-started !in 0..30_000L)throw ApiFailure("held_recovery_unapproved",403)
   val permitted=beforePost();val action=afterBeforePost;afterBeforePost=null;action?.invoke()
   if(!permitted||android.os.SystemClock.elapsedRealtime()-started !in 0..30_000L)throw ApiFailure("held_recovery_unapproved",403)
   enteredPost=true
   beforeNetwork?.invoke("recover")
   recoveryRequests.add(value);recoveryGenerations.add(expectedConsentGeneration)
   if(strictLegacyHeldServer)throw ApiFailure("invalid_api_request",400)
   recoveryFailureBeforeCommit?.let{throw it}
   val prior=recoveryCommitted[value.requestId]
   if(prior!=null&&(prior.first!=value||(!permissiveLegacyHeldServer&&recoveryCommittedGenerations[value.requestId]!=expectedConsentGeneration)))throw ApiFailure("observation_item_conflict",409)
   val key=value.sourceKey?:throw ApiFailure("invalid_source",400)
   if(prior==null&&retainedSources.containsKey(key))throw ApiFailure("observation_item_conflict",409)
   val source=prior?.second?:"source-${retainedSources.size+1}".also{
    retainedSources[key]=it;retainedSourceKeys.add(key);recoveryCommitted[value.requestId]=value to it
    if(!permissiveLegacyHeldServer)recoveryCommittedGenerations[value.requestId]=expectedConsentGeneration
   }
   val completed=afterRecovery;afterRecovery=null;completed?.invoke();recoveryFailureAfterCommit?.let{throw it}
   val ack=HeldObservationAck(ObservationAck(value.requestId,source,Values.sha256(value.rawBody),"source_unresolved",0),"held")
   return recoveryAckOverride?.invoke(ack)?:ack
  }finally{
   if(!enteredPost)runCatching{onNeverDispatched()}
  }
 }
 fun heldRecoveryAcknowledgement(value:SmsObservation,expectedConsentGeneration:Long,beforePost:()->Boolean):HeldRecoveryResolution {
  capability(expectedConsentGeneration)
  if(!beforePost())throw ApiFailure("held_recovery_unapproved",403)
  beforeNetwork?.invoke("ack")
  heldAckRequests.add(value);heldAckGenerations.add(expectedConsentGeneration)
  if(strictLegacyHeldServer)throw ApiFailure("invalid_api_request",400)
  heldAckFailure?.let{throw it}
  val committed=recoveryCommitted[value.requestId]?.takeIf{it.first==value}
  val acknowledged=heldAckAcknowledged&&committed!=null&&
   (permissiveLegacyHeldServer||recoveryCommittedGenerations[value.requestId]==expectedConsentGeneration)
  val result=HeldRecoveryResolution(value.requestId,value.sourceKey!!,Values.sha256(value.rawBody),
   if(acknowledged)"acknowledged" else "unconfirmed",if(acknowledged)committed!!.second else null,
   if(acknowledged)"held" else "unknown",0,false)
  val action=afterHeldAck;afterHeldAck=null;action?.invoke()
  return heldAckOverride?.invoke(result)?:result
 }
 fun observationPage(q:String="",cursor:String?=null,limit:Int?=null):Page<ObservationListRow> {
  beforeNetwork?.invoke("page")
  pageCalls++;pageCursors.add(cursor);val action=afterPage;afterPage=null;action?.invoke();pageFailure?.let{throw it}
  if(cursor!=null)cursorFailure?.let{throw it}
  val all=retainedSources.values.toList()+cloudOnlySources
  val count=pageCountOverride?:all.size;val offset=cursor?.toInt()?:0;val size=limit?:100
  val items=all.drop(offset).take(size).map{ObservationListRow(SmsSourceRef.Observation(it),"group-1","2026-11-17T00:00:00Z")}
  val next=if(offset+items.size<count&&items.isNotEmpty())(offset+items.size).toString() else null
  return Page(items,next,count,pageRevision,"2026-11-17T00:00:00Z")
 }
}
