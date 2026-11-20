package rw.ikanisa.burimunsi.data
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArrayList
class ApiFailure(val code:String,val status:Int=400,val uncertain:Boolean=false):RuntimeException(code)
class ManagedRequestAccess(val token:String,val collectionId:String)
fun interface ManagedSessionTokenProvider { fun currentAccessToken():String?;fun currentAccessContext():ManagedRequestAccess?=null;fun currentCollectionId():String?=null }
object ManagedScopeFixture { var collectionId:String?="synthetic-group" }
interface ManagedSessionHost { val managedSessionTokenProvider:ManagedSessionTokenProvider;fun signOutManagedSession(){} }
data class Request(val method:String,val path:String,val token:String?,val body:JSONObject?,val recoveryOrigin:String?)
/** Only the transport is synthetic: the repository, journal, DTO and controller are real. */
object Transport {
 val calls=CopyOnWriteArrayList<Request>()
 var handler:(Request)->String={error("No transport fixture")}
}
class ApiClient(origin:String,val installationId:String,token:()->String?,val installationProfile:String?=null) {
 val resolvesLoginScope get()=installationProfile!=null
 companion object{fun phonePin(origin:String,id:String,profile:String,prefix:String,publicKey:String="",token:()->String)=ApiClient(origin,id,token,profile)}
 constructor(origin:String,id:String,provider:ManagedSessionTokenProvider,token:()->String?):this(origin,id,token)
 constructor(origin:String,id:String,prefix:String,token:()->String?):this(origin,id,token)
 constructor(origin:String,id:String,provider:ManagedSessionTokenProvider,prefix:String,token:()->String?):this(origin,id,provider,token)
 fun call(method:String,path:String,token:String?=null,body:JSONObject?=null,csv:Boolean=false,recoveryOrigin:String?=null,contractContext:Map<String,Any?> = emptyMap()):String {
  val request=Request(method,path,token,body,recoveryOrigin);Transport.calls.add(request);return Transport.handler(request)
 }
 internal fun validateCached(path:String,payload:String,context:Map<String,Any?>)=validateCachedPayload(installationId,path,payload,context)
}
