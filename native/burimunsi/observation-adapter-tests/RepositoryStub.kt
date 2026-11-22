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
  fun switch(owner:ObservationOwner?)=synchronized(lock){generation++;active=owner}
  fun observationOwner(context:Context):ObservationSessionOwner?=synchronized(lock){active?.let{ObservationSessionOwner(it,generation)}}
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
  reconciliationRequests.add(value);val action=afterReconcile;afterReconcile=null;action?.invoke()
  reconcileFailure?.let{throw it}
  val existing=retainedSources[value.sourceKey];val newest=retainedSources.values.lastOrNull()
  return reconcileOverride?:if(existing!=null)ObservationReconcileReply(value.sourceKey,"matched",existing,newest)
   else ObservationReconcileReply(value.sourceKey,"missing",null,newest)
 }
 fun reconcileObservations(values:List<ObservationReconcileRequest>):List<ObservationReconcileReply> {
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
  statusCalls++;statusFailure?.let{throw it};val count=retainedSources.size+cloudOnlySources.size
  val revision=statusRevisionOverride?:Values.sha256((retainedSources.toString()+cloudOnlySources.toString()+pendingReservation+unmatchedCanonical))
  val result=ObservationReconcileStatus(pendingReservation,count>0,count,revision,unmatchedCanonical)
  afterStatus?.invoke(statusCalls);return statusReplyOverride?.invoke(statusCalls,result)?:result
 }
 fun observationPage(q:String="",cursor:String?=null,limit:Int?=null):Page<ObservationListRow> {
  pageCalls++;pageCursors.add(cursor);val action=afterPage;afterPage=null;action?.invoke();pageFailure?.let{throw it}
  if(cursor!=null)cursorFailure?.let{throw it}
  val all=retainedSources.values.toList()+cloudOnlySources
  val count=pageCountOverride?:all.size;val offset=cursor?.toInt()?:0;val size=limit?:100
  val items=all.drop(offset).take(size).map{ObservationListRow(SmsSourceRef.Observation(it),"group-1","2026-11-17T00:00:00Z")}
  val next=if(offset+items.size<count&&items.isNotEmpty())(offset+items.size).toString() else null
  return Page(items,next,count,pageRevision,"2026-11-17T00:00:00Z")
 }
}
