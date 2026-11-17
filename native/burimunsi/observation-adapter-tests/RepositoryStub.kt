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
 val requests=mutableListOf<SmsObservation>()
 fun observationConsent():ObservationConsentRevision{consentFailure?.let{throw it};val value=consent;val action=afterConsentRead;afterConsentRead=null;action?.invoke();return value}
 fun setObservationConsent(value:ObservationConsentRevision):ObservationConsentRevision{val action=duringConsentSet;duringConsentSet=null;action?.invoke();consent=value;return value}
 fun observationProfile():JSONObject {profileFailure?.let{throw it};val action=afterProfileRead;afterProfileRead=null;action?.invoke();return profile}
 fun submitObservation(value:SmsObservation):ObservationAck {
  requests.add(value);val action=switchDuringSubmit;switchDuringSubmit=null;action?.invoke()
  submitFailure?.let{throw it}
  if(value.requestId in unresolvedIds)throw ObservationUploadUnresolved(unresolvedReportedId?:value.requestId)
  if(failSubmit)throw ApiFailure("observation_unavailable",503,true)
  return ObservationAck(value.requestId,"source-1",if(invalidAck)"0".repeat(64)else Values.sha256(value.rawBody),"source_unresolved",0)
 }
}
