package rw.ikanisa.burimunsi.data
import org.json.JSONObject
class ApiFailure(val code:String,val status:Int=0,val uncertain:Boolean=false):Exception(code)
data class Request(val method:String,val path:String,val token:String?,val body:JSONObject?,val recoveryOrigin:String?=null)
class ApiClient(val installationId:String="installation-1"){
 val calls=mutableListOf<Request>()
 var handler:(Request)->String={error("No API fixture")}
 fun call(method:String,path:String,token:String?=null,body:JSONObject?=null,csv:Boolean=false,recoveryOrigin:String?=null,contractContext:Map<String,Any?> = emptyMap()):String{
  val req=Request(method,path,token,body,recoveryOrigin);synchronized(calls){calls.add(req)};return handler(req)
 }
 internal fun validateCached(path:String,payload:String,context:Map<String,Any?>)=validateCachedPayload(installationId,path,payload,context)
}
