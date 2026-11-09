package rw.ikanisa.burimunsi.httptests
import java.net.*
import java.io.*
import org.json.JSONObject
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.wire.BuriMunsiSchemas

private data class Reply(val status:Int=200,val type:String="application/json",val body:String?=null,
    val breakWrite:Boolean=false,val bytes:ByteArray?=null,val headers:Map<String,List<String>> = emptyMap(),
    val streamFactory:(()->InputStream)?=null,val transform:(JSONObject)->Unit={})
private object Wire { var reply=Reply();var opened=0;var last:Connection?=null }
private class Connection(url:URL):HttpURLConnection(url){
 val written=ByteArrayOutputStream()
 init{Wire.last=this;Wire.opened++}
 override fun disconnect(){}
 override fun usingProxy()=false
 override fun connect(){}
 override fun getResponseCode()=Wire.reply.status
 override fun getHeaderFields():Map<String,List<String>> = mapOf("Content-Type" to listOf(Wire.reply.type)) + Wire.reply.headers
 override fun getHeaderField(name:String):String?=when(name.lowercase()){"content-type"->Wire.reply.type;"x-burimunsi-contract"->BuriMunsiSchemas.VERSION;else->null}
 private fun envelope():String {
   val binding=JSONObject().put("requestId",getRequestProperty("X-BuriMunsi-Request")).put("generation",getRequestProperty("X-BuriMunsi-Generation"))
       .put("installationId","installation-1").put("actorId","actor-1").put("groupId","group-1")
   val profile=JSONObject("""{"id":"actor-1","name":"Synthetic operator","phone":"+250780000001","role":"admin","capabilities":["records.read"]}""")
   val data=when {
    url.path.endsWith("/session/login")->JSONObject().put("token","a".repeat(64)).put("expiresAt",System.currentTimeMillis()+3600000).put("profile",profile)
    url.path.endsWith("/recovery")->JSONObject().put("protocol","burimunsi.operation-recovery.v1").put("requestId",url.path.substringBeforeLast('/').substringAfterLast('/'))
        .put("state","pending").put("originDigest",getRequestProperty("X-BuriMunsi-Operation-Origin")).put("groupId","group-1").put("actorId","actor-1").put("installationId","installation-1")
    url.path.contains("/operations/")->JSONObject().put("contractVersion",2).put("requestId",url.path.substringAfterLast('/'))
        .put("groupId","group-1").put("actorId","actor-1").put("state","committed")
        .put("operation","burimunsi.allocate").put("financialState","posted")
    url.path.endsWith("/allocate")->JSONObject("""{"transactionId":"payment-1","memberId":"member-1","amountRwf":1000,"currency":"RWF","ledgerEntryId":"ledger-1","memberBalanceRwf":1000,"groupBalanceRwf":1000}""")
    url.path.endsWith("/payments")->JSONObject().put("items",org.json.JSONArray()).put("totalCount",0)
        .put("nextCursor",JSONObject.NULL).put("revision","fixture-v1").put("asOf","2026-11-09T08:00:00Z")
    else->JSONObject("""{"groupBalanceRwf":17000,"todayRwf":1000,"memberCount":1,"unallocatedCount":0,"asOf":"2026-11-09T08:00:00Z","recentPayments":[]}""")
   }
   val value=JSONObject().put("contractVersion",BuriMunsiSchemas.VERSION).put("ok",true).put("binding",binding).put("data",data)
   Wire.reply.transform(value);return value.toString()
 }
 override fun getInputStream():InputStream=Wire.reply.streamFactory?.invoke() ?: ByteArrayInputStream(Wire.reply.bytes?:((Wire.reply.body?:envelope()).toByteArray()))
 override fun getErrorStream():InputStream=getInputStream()
 override fun getOutputStream():OutputStream {if(Wire.reply.breakWrite)throw IOException("synthetic lost write");return written}
}
fun main(){
 URL.setURLStreamHandlerFactory{p->if(p=="https")object:URLStreamHandler(){override fun openConnection(u:URL)=Connection(u)}else null}
 var count=0
 fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");count++}
 val scope=mapOf<String,Any?>("groupId" to "group-1","actorId" to "actor-1","generation" to "3")
 val api=ApiClient("https://test.invalid","installation-1"){"device-grant"}
 val id="00000000-0000-4000-8000-000000000004"
 fun command()=JSONObject().put("requestId",id).put("memberId","member-1").put("expectedVersion",1).put("note","Synthetic identification")
 fun request(post:Boolean=false)=api.call(if(post)"POST" else "GET",if(post)"/v1/burimunsi/payments/payment-1/allocate" else "/v1/burimunsi/home",token="a".repeat(64),body=if(post)command()else null,contractContext=scope)
 fun failure(post:Boolean=false)=runCatching{request(post)}.exceptionOrNull() as ApiFailure
 ck("valid strict JSON response decoded",JSONObject(request()).getLong("groupBalanceRwf")==17000L)
 ck("redirects disabled",Wire.last?.instanceFollowRedirects==false)
 ck("bounded timeouts",Wire.last?.connectTimeout==15000&&Wire.last?.readTimeout in 1..20000)
 ck("operator bearer attached",Wire.last?.getRequestProperty("Authorization")=="Bearer "+"a".repeat(64))
 ck("product version is explicit",Wire.last?.getRequestProperty("X-BuriMunsi-Contract")==BuriMunsiSchemas.VERSION)
 ck("generation sent",Wire.last?.getRequestProperty("X-BuriMunsi-Generation")=="3")
 ck("correlation has UUID shape",Regex("[0-9a-f-]{36}").matches(Wire.last!!.getRequestProperty("X-BuriMunsi-Request")))
 api.call("GET","/v1/burimunsi/home",contractContext=scope)
 ck("device credential only without bearer",Wire.last?.getRequestProperty("X-BuriMunsi-Device")=="device-grant"&&Wire.last?.getRequestProperty("Authorization")==null)
 val before=Wire.opened;runCatching{api.call("GET","https://foreign.invalid/v1/burimunsi/home",contractContext=scope)};ck("foreign URL cannot dispatch",Wire.opened==before)
 runCatching{api.call("GET","/v1/burimunsi/home")};ck("missing expected group cannot dispatch",Wire.opened==before)
 runCatching{api.call("POST","/v1/burimunsi/payments/payment-1/allocate",body=JSONObject(),contractContext=scope)};ck("missing command fields cannot dispatch",Wire.opened==before)
 val mutations=listOf<Pair<String,(JSONObject)->Unit>>(
  "contract_missing_field" to {v->v.remove("data");Unit},
  "contract_version" to {v->v.remove("contractVersion");Unit},
  "contract_version" to {v->v.put("contractVersion","mmoney.ledger.v1");Unit},
  "contract_type" to {v->v.put("data","{}");Unit},
  "contract_value" to {v->v.put("ok",false);Unit},
  "contract_unknown_field" to {v->v.put("extra",true);Unit},
  "contract_identity" to {v->v.put("binding",v.getJSONObject("binding").put("actorId","wrong-actor"));Unit},
  "contract_identity" to {v->v.put("binding",v.getJSONObject("binding").put("groupId","wrong-group"));Unit},
  "contract_identity" to {v->v.put("binding",v.getJSONObject("binding").put("installationId","wrong-installation"));Unit},
  "contract_generation" to {v->v.put("binding",v.getJSONObject("binding").put("generation","2"));Unit},
  "contract_identity" to {v->v.put("binding",v.getJSONObject("binding").put("requestId","00000000-0000-4000-8000-000000000099"));Unit}
 )
 for((index,pair)in mutations.withIndex()){
  Wire.reply=Reply(transform=pair.second)
  ck("protocol mutation $index rejected before display",failure().let{it.code==pair.first&&!it.uncertain})
  ck("protocol mutation $index cannot settle dispatched command",failure(true).let{it.code==pair.first&&it.uncertain})
 }
 Wire.reply=Reply(transform={v->v.put("data",v.getJSONObject("data").put("groupBalanceRwf","17000"))})
 ck("numeric string rejected",failure().code=="contract_amount")
 Wire.reply=Reply(body="{\"x\":1,\"x\":2}");ck("duplicate keys rejected",failure().code=="contract_duplicate_key")
 Wire.reply=Reply(body="{\"x\":1e3}");ck("exponent coercion rejected",failure().code=="contract_number")
 Wire.reply=Reply(body="not-json");ck("malformed JSON not offline",failure().code=="contract_json")
 Wire.reply=Reply(type="text/html",body="<html>fallback</html>");ck("HTML cannot pass as API",failure(true).let{it.code=="invalid_api_response"&&it.uncertain})
 Wire.reply=Reply(type="application/jsonp");ck("JSONP denied",failure().code=="invalid_api_response")
 for(status in listOf(201,202,204,302)){
  Wire.reply=Reply(status=status);ck("unexpected HTTP $status denied",failure(true).let{it.code=="contract_http_status"&&it.uncertain})
 }
 fun error(code:String)="""{"contractVersion":"burimunsi.native.v1","ok":false,"error":{"code":"$code"}}"""
 for(status in listOf(400,401,403,409)){
  Wire.reply=Reply(status=status,body=error("rejected"));ck("typed HTTP $status rejection",failure(true).let{it.code=="rejected"&&!it.uncertain})
 }
 for(status in listOf(408,425,429,500,503)){
  Wire.reply=Reply(status=status,body=error("retry_later"));ck("HTTP $status preserves uncertain command",failure(true).uncertain)
 }
 Wire.reply=Reply(status=409,body="""{"ok":false,"error":{"code":"rejected"}}""");ck("unversioned rejection cannot settle command",failure(true).uncertain)
 Wire.reply=Reply(status=400,body=error("unsafe payload value"));ck("unsafe error text not exposed",failure(true).let{it.code=="contract_string"&&it.uncertain})
 Wire.reply=Reply(bytes=byteArrayOf(0xc3.toByte(),0x28));ck("invalid UTF-8 preserves uncertainty",failure(true).let{it.code=="invalid_api_response"&&it.uncertain})
 Wire.reply=Reply(breakWrite=true);ck("write failure conservatively uncertain",failure(true).let{it.code=="connection_unavailable"&&it.uncertain})
 Wire.reply=Reply(body=" ".repeat(2_000_001));ck("response body bounded",failure().code=="response_too_large")
 Wire.reply=Reply(type="text/csv",body="id,amount\n1,1000\n")
 ck("CSV is an explicit separate route",api.call("GET","/v1/burimunsi/members/member-1/ledger.csv",csv=true,contractContext=scope).contains("1000"))
 Wire.reply=Reply();val recovery="/v1/burimunsi/operations/$id/recovery";val digest="b".repeat(64)
 api.call("GET",recovery,token="a".repeat(64),recoveryOrigin=digest,contractContext=scope)
 ck("recovery selector only in header",Wire.last?.getRequestProperty("X-BuriMunsi-Operation-Origin")==digest&&!Wire.last!!.url.toString().contains(digest))
 ck("recovery has no body",Wire.last?.written?.size()==0)
 for((method,path,token,origin)in listOf(listOf("POST",recovery,"a".repeat(64),digest),listOf("GET","/v1/burimunsi/home","a".repeat(64),digest),listOf("GET",recovery,"not-a-token",digest),listOf("GET",recovery,"a".repeat(64),"x"),listOf("GET",recovery+"?origin=x","a".repeat(64),digest))){
  val prior=Wire.opened;runCatching{api.call(method,path,token=token,recoveryOrigin=origin,contractContext=scope)};ck("invalid recovery cannot dispatch $method $path",Wire.opened==prior)
 }
 var managed:String?="header.payload.signature"
 val canonical=ApiClient("https://test.invalid","installation-1",ManagedSessionTokenProvider{managed}){"device-grant"}
 canonical.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone","+250780000001").put("pin","1234"),contractContext=scope)
 ck("managed proof accompanies PIN login",Wire.last?.getRequestProperty("X-BuriMunsi-Collect-Session")==managed)
 ck("managed proof does not replace device grant",Wire.last?.getRequestProperty("X-BuriMunsi-Device")=="device-grant")
 for(value in listOf(null,"malformed")){
  managed=value;val prior=Wire.opened;val e=runCatching{canonical.call("GET","/v1/burimunsi/home",contractContext=scope)}.exceptionOrNull() as ApiFailure
  ck("invalid managed session never downgrades",Wire.opened==prior&&e.code=="managed_session_required")
 }
 for((path,code) in listOf(
  "/home?unexpected=1" to "contract_query",
  "/payments?limit=1e2" to "contract_query",
  "/payments?limit=0x10" to "contract_query",
  "/payments?limit=010" to "contract_query",
  "/payments?limit=1&%6cimit=2" to "contract_query_duplicate",
  "/payments?q=%C3%28" to "contract_query_encoding",
  "/payments?cursor=" to "contract_query",
  "/sms?filter=allocated" to "contract_query",
  "/payments/payment-1/history?q=ignored" to "contract_query")) {
  val prior=Wire.opened
  val e=runCatching{api.call("GET","/v1/burimunsi"+path,token="a".repeat(64),contractContext=scope)}.exceptionOrNull() as ApiFailure
  ck("invalid query cannot dispatch $path",e.code==code&&!e.uncertain&&Wire.opened==prior)
 }
 val beforeCsv=Wire.opened
 val csvError=runCatching{api.call("GET","/v1/burimunsi/members/member-1/ledger.csv?limit=1",csv=true,contractContext=scope)}.exceptionOrNull() as ApiFailure
 ck("CSV does not bypass query admission",csvError.code=="contract_query"&&Wire.opened==beforeCsv)

 // r3 response-framing failures cannot settle an already-dispatched command.
 for((headers,code) in listOf(
  mapOf("Content-Length" to listOf("999999")) to "contract_response_truncated",
  mapOf("Content-Length" to listOf("1")) to "contract_content_length",
  mapOf("Content-Length" to listOf("-1")) to "contract_content_length",
  mapOf("Content-Length" to listOf("3, 3")) to "contract_content_length",
  mapOf("Content-Length" to listOf("3","3")) to "contract_response_header",
  mapOf("Content-Length" to listOf("2000001")) to "response_too_large",
  mapOf("content-type" to listOf("application/json")) to "contract_response_header",
  mapOf("Content-Encoding" to listOf("gzip")) to "contract_content_encoding",
  mapOf("Transfer-Encoding" to listOf("chunked"),"Content-Length" to listOf("123")) to "contract_transfer_encoding",
  mapOf("Transfer-Encoding" to listOf("gzip")) to "contract_transfer_encoding")) {
   Wire.reply=Reply(headers=headers)
   ck("response framing $code preserves command",failure(true).let{it.code==code&&it.uncertain})
 }
 for(type in listOf("application/json; charset=iso-8859-1","application/json; charset=utf-8; charset=utf-16","application/json; ignored=1")) {
   Wire.reply=Reply(type=type)
   ck("ambiguous media cannot settle command",failure(true).let{it.code=="contract_content_type"&&it.uncertain})
 }
 Wire.reply=Reply(type="application/json; charset=\"UTF-8\"")
 ck("quoted UTF-8 response remains compatible",JSONObject(request()).getLong("groupBalanceRwf")==17000L)
 ck("transparent compression is disabled",Wire.last?.getRequestProperty("Accept-Encoding")=="identity")
 Wire.reply=Reply(streamFactory={object:InputStream(){override fun read()=0;override fun read(b:ByteArray,o:Int,n:Int)=0}})
 ck("non-progress stream rejected",failure(true).let{it.code=="contract_response_stream"&&it.uncertain})
 Wire.reply=Reply(streamFactory={object:ByteArrayInputStream("{}".toByteArray()){override fun close(){throw IOException("private-cleanup")}}})
 ck("cleanup failure cannot settle command or leak detail",failure(true).let{it.code=="connection_unavailable"&&it.uncertain&&!it.message.orEmpty().contains("private")})
 Wire.reply=Reply()
 fun outcome()=api.call("GET","/v1/burimunsi/operations/$id",token="a".repeat(64),contractContext=scope)
 for(effect in listOf("posted","reversed","corrected")) {
  Wire.reply=Reply(transform={it.put("data",it.getJSONObject("data").put("financialState",effect))})
  ck("strict native transport retains A04 v2 $effect outcome",JSONObject(outcome()).getString("financialState")==effect)
 }
 for((label,edit) in listOf<Pair<String,(JSONObject)->Unit>>(
  "old v1" to {it.remove("contractVersion");Unit},
  "foreign actor" to {it.put("actorId","other");Unit},
  "wrong group" to {it.put("groupId","other");Unit},
  "unresolved commit" to {it.put("financialState","unresolved");Unit},
  "financial no-effect" to {it.put("financialState","not_applicable");Unit}
 )) {
  Wire.reply=Reply(transform={val data=it.getJSONObject("data");edit(data);it.put("data",data)})
  ck("strict native transport refuses $label status",runCatching{outcome()}.exceptionOrNull() is ApiFailure)
 }
 Wire.reply=Reply()
 val prefix="/functions/v1/collect-api"
 val shared=ApiClient("https://test.invalid","installation-1",prefix){"device-grant"}
 ck("shared Edge prefix preserves logical home contract",JSONObject(shared.call("GET","/v1/burimunsi/home",token="a".repeat(64),contractContext=scope)).getLong("groupBalanceRwf")==17000L)
 ck("shared Edge URL is exact and same origin",Wire.last!!.url.toString()=="https://test.invalid$prefix/v1/burimunsi/home")
 ck("shared Edge retains contract and operator identity",Wire.last!!.getRequestProperty("X-BuriMunsi-Contract")==BuriMunsiSchemas.VERSION&&Wire.last!!.getRequestProperty("Authorization")=="Bearer "+"a".repeat(64))
 val search="q=hello%20world%2Fteam&filter=all"
 shared.call("GET","/v1/burimunsi/payments?$search",token="a".repeat(64),contractContext=scope)
 ck("shared Edge preserves validated query bytes",Wire.last!!.url.toString()=="https://test.invalid$prefix/v1/burimunsi/payments?$search")
 val originalDigest="b".repeat(64)
 val proof=JSONObject(shared.call("GET","/v1/burimunsi/operations/$id/recovery",token="a".repeat(64),recoveryOrigin=originalDigest,contractContext=scope))
 ck("shared Edge recovery keeps exact original route",Wire.last!!.url.toString()=="https://test.invalid$prefix/v1/burimunsi/operations/$id/recovery")
 ck("shared Edge recovery preserves original digest selector",Wire.last!!.getRequestProperty("X-BuriMunsi-Operation-Origin")==originalDigest&&proof.getString("originDigest")==originalDigest)
 val managedAccess="header.payload.signature"
 val managedShared=ApiClient("https://test.invalid","installation-1",ManagedSessionTokenProvider{managedAccess},prefix){"device-grant"}
 managedShared.call("GET","/v1/burimunsi/home",token="a".repeat(64),contractContext=scope)
 ck("shared Edge keeps managed proof separate from native bearer",Wire.last!!.getRequestProperty("X-BuriMunsi-Collect-Session")==managedAccess&&Wire.last!!.getRequestProperty("Authorization")=="Bearer "+"a".repeat(64))
 for(badPrefix in listOf("functions/v1/collect-api","/functions/v1/collect-api/","/functions/v1/../collect-api",
  "/functions/v1/collect-api?x=1","/functions/v1/collect-api#fragment","/functions%2fv1/collect-api",
  "/functions/v1/collect-api%2F..","//foreign.invalid/functions/v1/collect-api","https://foreign.invalid/functions/v1/collect-api")) {
  val beforeBad=Wire.opened
  ck("unsafe Edge prefix is refused: $badPrefix",runCatching{ApiClient("https://test.invalid","installation-1",badPrefix){"device-grant"}}.isFailure&&Wire.opened==beforeBad)
 }
 for(badPath in listOf("https://foreign.invalid/v1/burimunsi/home","//foreign.invalid/v1/burimunsi/home",
  "/v1/burimunsi/../home","/v1/burimunsi/../../session","/v1/burimunsi/%2e%2e/session",
  "/v1/burimunsi/home%2f..","/v1/burimunsi/home\\outside","/v1/burimunsi/home#fragment")) {
  val beforeBad=Wire.opened
  ck("shared Edge cannot escape logical route: $badPath",runCatching{shared.call("GET",badPath,token="a".repeat(64),contractContext=scope)}.isFailure&&Wire.opened==beforeBad)
 }
 val beforeBadQuery=Wire.opened
 ck("shared Edge does not bypass logical query validation",runCatching{shared.call("GET","/v1/burimunsi/home?unexpected=1",token="a".repeat(64),contractContext=scope)}.isFailure&&Wire.opened==beforeBadQuery)
 ck("origin cannot carry a second API prefix",runCatching{ApiClient("https://test.invalid$prefix","installation-1",prefix){"device-grant"}}.isFailure)
 Wire.reply=Reply()
 println("RESULT: $count real ApiClient checks passed with fake HttpURLConnection; not TLS/Android certification.")
}
