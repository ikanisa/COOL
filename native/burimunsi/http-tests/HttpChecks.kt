package rw.ikanisa.burimunsi.httptests
import java.net.*
import java.io.*
import org.json.JSONObject
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.wire.BuriMunsiSchemas
import rw.ikanisa.wire.WireContract

private data class Reply(val status:Int=200,val type:String="application/json",val body:String?=null,
    val breakWrite:Boolean=false,val bytes:ByteArray?=null,val headers:Map<String,List<String>> = emptyMap(),
    val streamFactory:(()->InputStream)?=null,val transform:(JSONObject)->Unit={},
    val headerFactory:((Connection)->Map<String,List<String>>)?=null,
    val headerFailure:IOException?=null)
private object Wire { var reply=Reply();var opened=0;var last:Connection?=null }
private class Connection(url:URL):HttpURLConnection(url){
 val written=ByteArrayOutputStream()
 val declaredBodyLength get()=fixedContentLength
 var headerReadTimeout:Int?=null
 init{Wire.last=this;Wire.opened++}
 override fun disconnect(){}
 override fun usingProxy()=false
 override fun connect(){}
 override fun getResponseCode():Int {
  headerReadTimeout=readTimeout
  Wire.reply.headerFailure?.let{throw it}
  return Wire.reply.status
 }
 override fun getHeaderFields():Map<String,List<String>> = mapOf("Content-Type" to listOf(Wire.reply.type)) + (Wire.reply.headerFactory?.invoke(this)?:emptyMap()) + Wire.reply.headers
 override fun getHeaderField(name:String):String?=when(name.lowercase()){"content-type"->Wire.reply.type;"x-burimunsi-contract"->BuriMunsiSchemas.VERSION;else->null}
 private fun envelope():String {
   val binding=JSONObject().put("requestId",getRequestProperty("X-BuriMunsi-Request")).put("generation",getRequestProperty("X-BuriMunsi-Generation"))
       .put("installationId",getRequestProperty("X-BuriMunsi-Installation")).put("actorId","actor-1").put("groupId","group-1")
   val profile=JSONObject("""{"id":"actor-1","name":"Synthetic operator","phone":"+250780000001","role":"admin","capabilities":["records.read"]}""")
   val data=when {
    url.path.endsWith("/gateway/replace")->JSONObject().put("retired",true).put("handoffId","00000000-0000-4000-8000-000000000055")
        .put("requestId",JSONObject(written.toString("UTF-8")).getString("requestId")).put("reauthenticationRequired",true)
    url.path.contains("/gateway/replacements/")->JSONObject().put("protocol","burimunsi.receiver-retirement.v1")
        .put("requestId",url.path.substringBeforeLast('/').substringAfterLast('/')).put("fingerprint",getRequestProperty("X-BuriMunsi-Handoff-Fingerprint"))
        .put("state","unknown").put("ack",JSONObject.NULL)
    url.path.endsWith("/session/login")->JSONObject().put("token","a".repeat(64)).put("expiresAt",System.currentTimeMillis()+3600000).put("profile",profile)
    url.path.endsWith("/recovery")->JSONObject().put("protocol","burimunsi.operation-recovery.v1").put("requestId",url.path.substringBeforeLast('/').substringAfterLast('/'))
        .put("state","pending").put("originDigest",getRequestProperty("X-BuriMunsi-Operation-Origin")).put("groupId","group-1").put("actorId","actor-1").put("installationId","installation-1")
    url.path.endsWith("/staff-resolution")->JSONObject().put("protocol","burimunsi.operation-recovery.v1").put("requestId",url.path.substringBeforeLast('/').substringAfterLast('/'))
        .put("state","cancelled").put("operation",JSONObject(written.toString("UTF-8")).getString("operation"))
        .put("originDigest",getRequestProperty("X-BuriMunsi-Operation-Origin")).put("groupId","group-1").put("actorId","actor-1").put("installationId","installation-1")
    url.path.contains("/operations/")->JSONObject().put("contractVersion",2).put("requestId",url.path.substringAfterLast('/'))
        .put("groupId","group-1").put("actorId","actor-1").put("state","committed")
        .put("operation","burimunsi.allocate").put("financialState","posted")
    url.path.endsWith("/allocate")->JSONObject("""{"transactionId":"payment-1","memberId":"member-1","amountRwf":1000,"currency":"RWF","ledgerEntryId":"ledger-1","memberBalanceRwf":1000,"groupBalanceRwf":1000}""")
    url.path.contains("/sms/observations/")&&url.path.endsWith("/reveal")-> {
        val text="Received 1,000 RWF";val amount="1,000 RWF";val start=text.indexOf(amount)
        JSONObject().put("groupId","group-1").put("sourceKind","observation").put("sourceId","source-1")
            .put("status","source_unresolved").put("at","2026-11-09T08:00:00Z").put("sender","M-Money").put("rawBody",text)
            .put("financialEffects",0).put("displayHints",JSONObject().put("schemaVersion",1).put("kind","partial_inbox_display_only")
                .put("profileVersion","approved-v1").put("profileSha256","a".repeat(64))
                .put("bodySha256",rw.ikanisa.burimunsi.core.Values.sha256(text))
                .put("hints",org.json.JSONArray().put(JSONObject().put("kind","quoted_incoming_amount").put("text",amount).put("start",start).put("end",start+amount.length))))
    }
    url.path.endsWith("/reveal")->JSONObject().put("id","sms-1").put("groupId","group-1").put("sender","").put("at","2026-11-09T08:00:00Z").put("rawBody","SMS y’umwimerere 🧾").put("transactionId",JSONObject.NULL)
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
 val observationWire=WireContract("burimunsi","test",emptyMap())
 fun envelope(data:Map<String,Any?>)=mapOf<String,Any?>("binding" to emptyMap<String,Any?>(),"data" to data)
 val observationExpected=mapOf<String,Any?>("commandRequestId" to "request-1","observationBodySha256" to "a".repeat(64))
 val observationData=mapOf<String,Any?>("requestId" to "request-1","bodySha256" to "a".repeat(64),"status" to "source_unresolved","financialEffects" to 0L)
 ck("observation ACK accepts only the submitted request and body digest",runCatching{observationWire.semantics("observation",envelope(observationData),observationExpected)}.isSuccess)
 for((key,bad) in listOf("requestId" to "other","bodySha256" to "b".repeat(64),"status" to "posted","financialEffects" to 1L))
  ck("observation ACK rejects mismatched $key",runCatching{observationWire.semantics("observation",envelope(observationData+(key to bad)),observationExpected)}.isFailure)
 val heldKey="c".repeat(64)
 val heldExpected=observationExpected+("sourceKey" to heldKey)
 val heldBase=(observationData-"status")+mapOf("sourceKey" to heldKey,"retryAllowed" to false)
 val resultShapes=listOf(
  "observation" to observationData,
  "observationRecoverHeld" to (observationData+("autoProcessing" to "held")),
  "observationRecoverHeldAck" to (heldBase+mapOf("state" to "acknowledged","sourceId" to "source-1","autoProcessing" to "held")),
  "observationRecoverHeldAck" to (heldBase+mapOf("state" to "unconfirmed","sourceId" to null,"autoProcessing" to "unknown")))
 for((operation,shape) in resultShapes){
  val label=operation+" "+(shape["state"]?:shape["status"])
  ck("$label accepts an exact integer zero",runCatching{observationWire.semantics(operation,envelope(shape),heldExpected)}.isSuccess)
  ck("$label rejects missing financial effects",runCatching{observationWire.semantics(operation,envelope(shape-"financialEffects"),heldExpected)}.isFailure)
  for((kind,value) in listOf("nonzero" to 1L,"decimal zero" to 0.0,"fraction" to 0.5,"string zero" to "0")){
   ck("$label rejects $kind financial effects",runCatching{observationWire.semantics(operation,envelope(shape+("financialEffects" to value)),heldExpected)}.isFailure)
  }
 }
 val reconcileExpected=mapOf<String,Any?>("sourceKey" to "a".repeat(64))
 val reconcileData=mapOf<String,Any?>("sourceKey" to "a".repeat(64),"state" to "matched","sourceId" to "source-1")
 ck("reconciliation binds a matched response to the submitted key",runCatching{observationWire.semantics("observationReconcile",envelope(reconcileData),reconcileExpected)}.isSuccess)
 ck("reconciliation rejects a different key",runCatching{observationWire.semantics("observationReconcile",envelope(reconcileData+("sourceKey" to "b".repeat(64))),reconcileExpected)}.isFailure)
 ck("reconciliation rejects a matched response without a source",runCatching{observationWire.semantics("observationReconcile",envelope(reconcileData+("sourceId" to null)),reconcileExpected)}.isFailure)
 ck("reconciliation rejects a missing response with a source",runCatching{observationWire.semantics("observationReconcile",envelope(reconcileData+("state" to "missing")),reconcileExpected)}.isFailure)
 val batchExpected=mapOf<String,Any?>("sourceKeys" to listOf("a".repeat(64),"b".repeat(64)))
 val batchItems=listOf(mapOf("sourceKey" to "a".repeat(64),"state" to "matched","sourceId" to "source-1"),
     mapOf("sourceKey" to "b".repeat(64),"state" to "missing","sourceId" to null))
 val batchData=mapOf<String,Any?>("items" to batchItems)
 ck("batch reconciliation binds ordered keys and outcomes",runCatching{observationWire.semantics("observationReconcileBatch",envelope(batchData),batchExpected)}.isSuccess)
 ck("batch reconciliation rejects reordered keys",runCatching{observationWire.semantics("observationReconcileBatch",envelope(batchData+("items" to batchItems.reversed())),batchExpected)}.isFailure)
 ck("batch reconciliation rejects incomplete results",runCatching{observationWire.semantics("observationReconcileBatch",envelope(batchData+("items" to batchItems.take(1))),batchExpected)}.isFailure)
 ck("batch reconciliation rejects forged match",runCatching{observationWire.semantics("observationReconcileBatch",envelope(batchData+("items" to listOf(batchItems[0]+("sourceId" to null),batchItems[1]))),batchExpected)}.isFailure)
 ck("batch reconciliation rejects duplicate requested keys",runCatching{observationWire.semantics("observationReconcileBatch",envelope(batchData),mapOf("sourceKeys" to listOf("a".repeat(64),"a".repeat(64))))}.isFailure)
 ck("collection status rejects inconsistent recorded count",runCatching{observationWire.semantics("observationReconcileStatus",envelope(mapOf("hasRecorded" to false,"recordedCount" to 1L)),emptyMap())}.isFailure)
 val consentExpected=mapOf<String,Any?>("consentEnabled" to true,"consentGeneration" to 3L)
 ck("consent ACK matches permission and generation",runCatching{observationWire.semantics("observationConsentSet",envelope(mapOf("enabled" to true,"generation" to 3L)),consentExpected)}.isSuccess)
 ck("stale consent ACK is rejected",runCatching{observationWire.semantics("observationConsentSet",envelope(mapOf("enabled" to false,"generation" to 2L)),consentExpected)}.isFailure)
 val profileNow=1_800_000_000_000L
 ck("approved observation profile must be current",runCatching{observationWire.semantics("observationProfile",envelope(mapOf("issuedAt" to profileNow,"expiresAt" to profileNow+86_400_000)),mapOf("now" to profileNow))}.isSuccess)
 ck("expired observation profile is rejected",runCatching{observationWire.semantics("observationProfile",envelope(mapOf("issuedAt" to profileNow-86_400_000,"expiresAt" to profileNow)),mapOf("now" to profileNow))}.isFailure)
 val row=mapOf<String,Any?>("id" to "source-1","sourceId" to "source-1","groupId" to "group-1",
     "sourceKind" to "observation","status" to "source_unresolved","financialEffects" to 0L)
 fun page(item:Map<String,Any?>)=mapOf<String,Any?>("binding" to mapOf("groupId" to "group-1"),
     "data" to mapOf("items" to listOf(item),"totalCount" to 1L,"nextCursor" to null))
 ck("observation page preserves explicit source type and scope",runCatching{observationWire.semantics("observationPage",page(row),emptyMap())}.isSuccess)
 ck("observation page rejects canonical source tag",runCatching{observationWire.semantics("observationPage",page(row+("sourceKind" to "canonical")),emptyMap())}.isFailure)
 val observationRevealed=mapOf<String,Any?>("sourceKind" to "observation","sourceId" to "source-1","status" to "source_unresolved","financialEffects" to 0L)
 ck("typed reveal cannot return a different source",runCatching{observationWire.semantics("observationReveal",envelope(observationRevealed),mapOf("recordId" to "source-2"))}.isFailure)
 val body="Received 1,000 RWF, reference REF-1";val amount="1,000 RWF";val start=body.indexOf(amount)
 val hint=mapOf<String,Any?>("kind" to "quoted_incoming_amount","text" to amount,"start" to start.toLong(),"end" to (start+amount.length).toLong())
 val hintSet=mapOf<String,Any?>("schemaVersion" to 1L,"kind" to "partial_inbox_display_only","profileVersion" to "v1",
  "profileSha256" to "a".repeat(64),"bodySha256" to rw.ikanisa.burimunsi.core.Values.sha256(body),"hints" to listOf(hint))
 val hintData=observationRevealed+mapOf("rawBody" to body,"displayHints" to hintSet)
 val hintContext=mapOf<String,Any?>("recordId" to "source-1","displayHintsVersion" to 1L)
 ck("opted-in reveal accepts an exact quoted partial-inbox hint",runCatching{observationWire.semantics("observationReveal",envelope(hintData),hintContext)}.isSuccess)
 ck("unrequested hints are rejected",runCatching{observationWire.semantics("observationReveal",envelope(hintData),mapOf("recordId" to "source-1"))}.isFailure)
 ck("opted-in reveal cannot silently omit its hint result",runCatching{observationWire.semantics("observationReveal",envelope(observationRevealed),hintContext)}.isFailure)
 ck("forged quoted text is rejected",runCatching{observationWire.semantics("observationReveal",envelope(hintData+("displayHints" to (hintSet+("hints" to listOf(hint+("text" to "9,000 RWF")))))),hintContext)}.isFailure)
 ck("mismatched body hash is rejected",runCatching{observationWire.semantics("observationReveal",envelope(hintData+("displayHints" to (hintSet+("bodySha256" to "b".repeat(64))))),hintContext)}.isFailure)
 val support=SupportContactClient("https://test.invalid","/functions/v1/collect-api")
 Wire.reply=Reply(body="""{"support_channels":[{"key":"support.whatsapp","channel_type":"whatsapp","is_active":true,"value":"250780000001"}]}""")
 ck("public support contact is dynamically normalized",support.read()=="+250780000001")
 ck("support uses exact shared public route without credentials",Wire.last?.url?.path=="/functions/v1/collect-api/v1/rpc/get_public_runtime_config"&&Wire.last?.requestMethod=="POST"&&Wire.last?.written?.toString("UTF-8")=="{}"&&Wire.last?.getRequestProperty("Authorization")==null&&Wire.last?.getRequestProperty("X-BuriMunsi-Device")==null)
 ck("support disallows redirects and transport caching",Wire.last?.instanceFollowRedirects==false&&Wire.last?.useCaches==false)
 for((label,body) in listOf(
  "missing" to """{"support_channels":[]}""",
  "inactive" to """{"support_channels":[{"key":"support.whatsapp","is_active":false,"value":"250780000001"}]}""",
  "duplicate" to """{"support_channels":[{"key":"support.whatsapp","value":"250780000001"},{"key":"support.whatsapp","value":"250780000002"}]}""",
  "wrong channel" to """{"support_channels":[{"key":"support.whatsapp","channel_type":"email","value":"250780000001"}]}""",
  "unsafe phone" to """{"support_channels":[{"key":"support.whatsapp","value":"250780000001?x=1"}]}""",
  "duplicate JSON key" to """{"support_channels":[],"support_channels":[]}""")){
  Wire.reply=Reply(body=body);ck("support $label is unavailable",support.read()==null)
 }
 Wire.reply=Reply(status=302,body="{}");ck("support redirect is unavailable",support.read()==null)
 Wire.reply=Reply(type="text/html",body="{}");ck("support non-JSON is unavailable",support.read()==null)
 Wire.reply=Reply(body=" ".repeat(65_537));ck("support oversized response is unavailable",support.read()==null)
 Wire.reply=Reply(streamFactory={throw IOException("offline")});ck("offline support never invents a fallback",support.read()==null)
 Wire.reply=Reply()
 val scope=mapOf<String,Any?>("groupId" to "group-1","actorId" to "actor-1","generation" to "3")
 val api=ApiClient("https://test.invalid","installation-1"){"d".repeat(64)}
 fun reconciliation() {
  val first="a".repeat(64); val second="b".repeat(64)
  val source="00000000-0000-4000-8000-000000000001"
  fun item(key:String)=JSONObject().put("sourceKey",key).put("bodySha256","c".repeat(64)).put("rawSender","Synthetic")
   .put("serviceCentreAt",JSONObject.NULL).put("inboxReceivedAt","2026-11-20T00:00:00Z").put("subscriptionId",JSONObject.NULL)
  fun matched(key:String)=JSONObject().put("sourceKey",key).put("state","matched").put("sourceId",source)
  fun respond(data:JSONObject){Wire.reply=Reply(transform={it.put("data",data)})}
  fun call(path:String,body:JSONObject?=null)=JSONObject(api.call(if(body==null)"GET" else "POST",
   "/v1/burimunsi/sms/observations/"+path,token="a".repeat(64),body=body,contractContext=scope))
  val single=matched(first).put("groupId","group-1").put("latestRecordedSourceId",source)
  respond(single);ck("real ApiClient binds a single read-only observation witness",call("reconcile",item(first)).getString("sourceId")==source)
  respond(single.put("sourceKey",second))
  ck("real ApiClient refuses a foreign single observation witness",runCatching{call("reconcile",item(first))}.isFailure)
  val batch=JSONObject().put("items",org.json.JSONArray().put(item(first)).put(item(second)))
  fun batchReply(a:String,b:String)=JSONObject().put("groupId","group-1").put("items",org.json.JSONArray().put(matched(a)).put(matched(b)))
  respond(batchReply(first,second));ck("real ApiClient accepts two ordered observation keys",call("reconcile-batch",batch).getJSONArray("items").length()==2)
  respond(batchReply(second,first))
  ck("real ApiClient rejects reordered observation keys",runCatching{call("reconcile-batch",batch)}.isFailure)
  respond(JSONObject().put("groupId","group-1").put("hasPending",false).put("hasRecorded",true).put("recordedCount",1)
    .put("hasUnmatchedCanonical",false).put("revision","f".repeat(64)))
  ck("real ApiClient reads scoped reconciliation status without a body",call("reconcile-status").getInt("recordedCount")==1&&Wire.last!!.written.size()==0)
  val opened=Wire.opened
  ck("the reconciliation contract refuses raw message text before transport",
    runCatching{call("reconcile",item(first).put("rawBody","synthetic private message"))}.isFailure&&Wire.opened==opened)
  Wire.reply=Reply()
 }
 reconciliation()
 fun importPreview() {
  val disclosure=rw.ikanisa.burimunsi.core.MemberImportScope.OCR_DISCLOSURE_VERSION
  val flow="77777777-7777-4777-8777-777777777777"
  val photo=JSONObject().put("mimeType","image/png").put("fileBytes","iVBORw0KGgo=")
   .put("externalOcrConsent",true).put("importFlowId",flow).put("ocrDisclosureVersion",disclosure)
  fun call(body:JSONObject)=JSONObject(api.call("POST","/v1/burimunsi/members/import/preview",token="a".repeat(64),body=body,contractContext=scope))
  fun reply(kind:String)=Reply(transform={it.put("data",JSONObject().put("sourceKind",kind).put("rows",org.json.JSONArray()))})
  Wire.reply=reply("image")
  ck("approved OCR disclosure reaches the native preview transport",call(photo).getString("sourceKind")=="image")
  val sent=JSONObject(Wire.last!!.written.toString(Charsets.UTF_8))
  ck("the exact OCR flow and version reach the transport",sent.getString("importFlowId")==flow&&sent.getString("ocrDisclosureVersion")==disclosure)
  val opened=Wire.opened
  for ((invalid,code) in listOf("previous" to "contract_value",1 to "contract_type")) {
   val failure=runCatching{call(JSONObject(photo.toString()).put("ocrDisclosureVersion",invalid))}.exceptionOrNull() as? ApiFailure
   ck("invalid OCR disclosure fails before transmission ($code)",failure?.code==code&&!failure.uncertain&&Wire.opened==opened)
  }
  Wire.reply=reply("csv")
  val csv=JSONObject().put("mimeType","text/csv").put("fileBytes","YQ==").put("externalOcrConsent",false)
  ck("inline CSV preview works without external disclosure fields",call(csv).getString("sourceKind")=="csv")
  Wire.reply=Reply()
 }
 importPreview()
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
 ck("payment reference negotiation stays off unrelated reads",Wire.last?.getRequestProperty(PAYMENT_REFERENCE_VERSION_HEADER)==null)
 ck("ordinary request uses a 20-second response-header timeout",Wire.last?.headerReadTimeout==20_000)
 request(true)
 ck("financial mutation uses a 20-second response-header timeout",Wire.last?.headerReadTimeout==20_000)
 val witness=JSONObject().put("sourceKey","a".repeat(64)).put("bodySha256","b".repeat(64)).put("rawSender","Synthetic sender")
  .put("serviceCentreAt",JSONObject.NULL).put("inboxReceivedAt","2026-11-17T18:00:00.000Z").put("subscriptionId",JSONObject.NULL)
 val reconcileRoutes=listOf(
  "/v1/burimunsi/sms/observations/reconcile" to witness,
  "/v1/burimunsi/sms/observations/reconcile-batch" to JSONObject().put("items",org.json.JSONArray().put(witness))
 )
 for ((path,payload) in reconcileRoutes) {
  fun reconcile()=api.call("POST",path,token="a".repeat(64),body=payload,contractContext=scope)
  Wire.reply=Reply(status=503,body="{}")
  val opened=Wire.opened
  runCatching{reconcile()}
  ck("$path uses a 45-second response-header timeout and a 20-second body bound",
   Wire.opened==opened+1&&Wire.last?.url?.path==path&&Wire.last?.headerReadTimeout==45_000&&
    Wire.last?.readTimeout in 1..20_000)
  Wire.reply=Reply(headerFailure=SocketTimeoutException("synthetic header timeout"))
  val beforeTimeout=Wire.opened
  val timeout=runCatching{reconcile()}.exceptionOrNull() as? ApiFailure
  ck("$path header timeout remains unconfirmed without automatic retry",
   Wire.opened==beforeTimeout+1&&timeout?.code=="connection_unavailable"&&timeout.status==0&&timeout.uncertain)
 }
 Wire.reply=Reply(status=503,body="{}")
 val beforeStatus=Wire.opened
 runCatching{api.call("POST","/v1/burimunsi/sms/observations/processing-status",token="a".repeat(64),
  body=JSONObject().put("sourceIds",org.json.JSONArray().put(id)),contractContext=scope)}
 ck("observation processing status uses a 20-second response-header timeout",
  Wire.opened==beforeStatus+1&&Wire.last?.headerReadTimeout==20_000)
 Wire.reply=Reply()
 fun readPayment()=JSONObject(api.call("GET","/v1/burimunsi/payments/payment-1",token="a".repeat(64),contractContext=scope))
 val originalPayment=JSONObject("""{"id":"payment-1","groupId":"group-1","payerNameRaw":"Fixture","payerPhoneRaw":"masked","amountRwf":1000,"atRaw":"recorded","ftId":"FT-EXAMPLE","state":"reversed","version":3,"memberId":null,"memberPhone":null,"sourceId":"source-1"}""")
 fun paymentReply(reference:Any=JSONObject.NULL,headers:Map<String,List<String>> = mapOf(PAYMENT_REFERENCE_VERSION_HEADER to listOf("1")),row:JSONObject=originalPayment)=
    Reply(headers=headers,transform={it.put("data",JSONObject().put("payment",row).put("paymentReference",reference))})
 Wire.reply=Reply(transform={it.put("data",originalPayment)})
 ck("upgraded client accepts a predecessor response in one payment request",readPayment().getString("ftId")=="FT-EXAMPLE"&&Wire.last?.getRequestProperty(PAYMENT_REFERENCE_VERSION_HEADER)=="1")
 Wire.reply=paymentReply("100000000017")
 ck("negotiated payment retains the exact transaction, provider and source",readPayment().let{it.getString("paymentReference")=="100000000017"&&it.getJSONObject("payment").getString("sourceId")=="source-1"})
 Wire.reply=paymentReply()
 ck("an unlinked transaction has no display reference",readPayment().isNull("paymentReference"))
 for(bad in listOf(paymentReply("010000000017"),paymentReply(100000000017L),paymentReply("100000000017",emptyMap()),
      paymentReply("100000000017",mapOf(PAYMENT_REFERENCE_VERSION_HEADER to listOf("1","1"))),
      paymentReply("100000000017",row=JSONObject(originalPayment.toString()).put("id","other")),
      paymentReply("100000000017",row=JSONObject(originalPayment.toString()).put("groupId","other")),
      Reply(headers=mapOf(PAYMENT_REFERENCE_VERSION_HEADER to listOf("1")),transform={it.put("data",originalPayment)}))){
     Wire.reply=bad
     ck("payment reference profile rejects a mismatched contract",runCatching{readPayment()}.exceptionOrNull() is ApiFailure)
 }
 Wire.reply=Reply()
 ck("correlation has UUID shape",Regex("[0-9a-f-]{36}").matches(Wire.last!!.getRequestProperty("X-BuriMunsi-Request")))
 api.call("GET","/v1/burimunsi/home",contractContext=scope)
 ck("device credential accompanies PIN without operator bearer",Wire.last?.getRequestProperty("X-BuriMunsi-Device")=="d".repeat(64)&&Wire.last?.getRequestProperty("Authorization")==null)
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
 val observationRequest=JSONObject().put("requestId",id).put("rawSender","SyntheticSender").put("rawBody","Synthetic receipt")
  .put("sourceMode","catch_up").put("complete",false).put("capturedAt","2026-11-09T08:00:00Z")
  .put("serviceCentreAt",JSONObject.NULL).put("inboxReceivedAt","2026-11-09T08:00:00Z").put("subscriptionId",JSONObject.NULL)
 fun unresolvedHeaders(connection:Connection)=mapOf(
  "X-BuriMunsi-Observation-Unresolved" to listOf("v1"),
  "X-BuriMunsi-Observation-Request-Id" to listOf(id),
  "X-BuriMunsi-Correlation-Id" to listOf(connection.getRequestProperty("X-BuriMunsi-Request")))
 fun observationFailure()=runCatching{api.call("POST","/v1/burimunsi/sms/observations",token="a".repeat(64),body=observationRequest,contractContext=scope)}.exceptionOrNull()
 Wire.reply=Reply(status=503,body=error("observation_upload_unresolved"),headerFactory=::unresolvedHeaders)
 val unresolved=observationFailure()
 ck("only exact correlated unresolved proof creates the typed non-ACK",unresolved is ObservationUploadUnresolved&&unresolved.requestId==id&&unresolved.uncertain)
 ck("unresolved response proof carries no body or body hash",Wire.last!!.headerFields.none{(name,values)->name.contains("sha256",true)||values.any{it.contains("Synthetic receipt")}})
 for((label,edit) in listOf<Pair<String,(Map<String,List<String>>)->Map<String,List<String>>>>(
  "missing" to {it-"X-BuriMunsi-Observation-Unresolved"},
  "version" to {it+("X-BuriMunsi-Observation-Unresolved" to listOf("v2"))},
  "request" to {it+("X-BuriMunsi-Observation-Request-Id" to listOf("00000000-0000-4000-8000-000000000099"))},
  "correlation" to {it+("X-BuriMunsi-Correlation-Id" to listOf("00000000-0000-4000-8000-000000000099"))},
  "duplicate values" to {it+("X-BuriMunsi-Observation-Unresolved" to listOf("v1","v1"))},
  "duplicate request" to {it+("X-BuriMunsi-Observation-Request-Id" to listOf(id,id))},
  "duplicate correlation" to {it+("X-BuriMunsi-Correlation-Id" to listOf(it.getValue("X-BuriMunsi-Correlation-Id").single(),it.getValue("X-BuriMunsi-Correlation-Id").single()))},
  "duplicate casing" to {it+("x-burimunsi-observation-unresolved" to listOf("v1"))},
  "coalesced" to {it+("X-BuriMunsi-Observation-Unresolved" to listOf("v1, v1"))})){
  Wire.reply=Reply(status=503,body=error("observation_upload_unresolved"),headerFactory={c->edit(unresolvedHeaders(c))})
  val rejected=observationFailure()
  ck("unresolved proof rejects $label",rejected is ApiFailure&&rejected !is ObservationUploadUnresolved&&rejected.uncertain)
 }
 Wire.reply=Reply(status=503,body=error("observation_unavailable"),headerFactory=::unresolvedHeaders)
 ck("an unrelated 503 cannot authorize queue continuation",observationFailure() !is ObservationUploadUnresolved)
 Wire.reply=Reply(status=400,body=error("observation_upload_unresolved"),headerFactory=::unresolvedHeaders)
 ck("the unresolved code at a different status cannot authorize queue continuation",observationFailure() !is ObservationUploadUnresolved)
 Wire.reply=Reply(status=503,body=error("observation_upload_unresolved"),headerFactory=::unresolvedHeaders)
 ck("proof on a different route cannot authorize queue continuation",runCatching{api.call("GET","/v1/burimunsi/session",token="a".repeat(64),contractContext=scope)}.exceptionOrNull() !is ObservationUploadUnresolved)
 for(status in listOf(400,401,403,409)){
  Wire.reply=Reply(status=status,body=error("rejected"));ck("typed HTTP $status rejection",failure(true).let{it.code=="rejected"&&!it.uncertain})
 }
 for(status in listOf(401,403)){
  val malformed=listOf(
   Reply(status=status,type="text/html",body="<html>proxy</html>"),
   Reply(status=status,body="not-json"),
   Reply(status=status,body="""{"contractVersion":"wrong","ok":false,"error":{"code":"session_unavailable"}}"""),
   Reply(status=status,body=error("session_unavailable"),headers=mapOf("Content-Length" to listOf("999999"))))
  for((index,reply) in malformed.withIndex()){
   Wire.reply=reply
   val e=runCatching{api.call("GET","/v1/burimunsi/session",token="a".repeat(64),contractContext=scope)}.exceptionOrNull()
   ck("malformed session denial $status/$index is not a validated native code",e is ApiFailure&&e.status==status&&
    (e.code=="invalid_api_response"||e.code.startsWith("contract_")))
  }
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
 val resolution="/v1/burimunsi/operations/$id/staff-resolution"
 val resolved=JSONObject(api.call("POST",resolution,token="a".repeat(64),body=JSONObject().put("operation","burimunsi.staff.create"),recoveryOrigin=digest,contractContext=scope))
 ck("staff resolution binds original identity and sends no PIN",resolved.getString("state")=="cancelled"&&Wire.last?.getRequestProperty("X-BuriMunsi-Operation-Origin")==digest&&JSONObject(Wire.last!!.written.toString("UTF-8")).keys().asSequence().toSet()==setOf("operation"))
 Wire.reply=Reply(transform={v->v.getJSONObject("data").put("operation","burimunsi.staff.reset")})
 ck("foreign staff cancellation cannot resolve the original",runCatching{api.call("POST",resolution,token="a".repeat(64),body=JSONObject().put("operation","burimunsi.staff.create"),recoveryOrigin=digest,contractContext=scope)}.isFailure)
 Wire.reply=Reply()
 for((method,path,token,origin)in listOf(listOf("POST",recovery,"a".repeat(64),digest),listOf("GET","/v1/burimunsi/home","a".repeat(64),digest),listOf("GET",recovery,"not-a-token",digest),listOf("GET",recovery,"a".repeat(64),"x"),listOf("GET",recovery+"?origin=x","a".repeat(64),digest))){
  val prior=Wire.opened;runCatching{api.call(method,path,token=token,recoveryOrigin=origin,contractContext=scope)};ck("invalid recovery cannot dispatch $method $path",Wire.opened==prior)
 }
 var managed:String?="header.payload.signature"
 var managedGroup="group-1"
 val managedProvider=object:ManagedSessionTokenProvider{
  override fun currentAccessToken()=managed
  override fun currentAccessContext()=managed?.let{ManagedRequestAccess(it,managedGroup)}
 }
 val canonical=ApiClient("https://test.invalid","installation-1",managedProvider){"d".repeat(64)}
 canonical.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone","+250780000001").put("pin","1234"),contractContext=scope)
 ck("managed proof accompanies PIN login",Wire.last?.getRequestProperty("X-BuriMunsi-Collect-Session")==managed)
 ck("managed proof does not replace device grant",Wire.last?.getRequestProperty("X-BuriMunsi-Device")=="d".repeat(64))
 ck("native intent asserts authenticated collection",Wire.last?.getRequestProperty("X-BuriMunsi-Group")=="group-1")
 managedGroup="another-group";val beforeChangedScope=Wire.opened
 val changedScope=runCatching{canonical.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone","+250780000001").put("pin","1234"),contractContext=scope)}.exceptionOrNull() as ApiFailure
 ck("managed collection change refuses PIN before opening a socket",changedScope.code=="managed_scope_changed"&&!changedScope.uncertain&&Wire.opened==beforeChangedScope)
 managedGroup="group-1"
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
  "/payments/payment-1/history?unexpected=ignored" to "contract_query")) {
  val prior=Wire.opened
  val e=runCatching{api.call("GET","/v1/burimunsi"+path,token="a".repeat(64),contractContext=scope)}.exceptionOrNull() as ApiFailure
  ck("invalid query cannot dispatch $path",e.code==code&&!e.uncertain&&Wire.opened==prior)
 }
 ck("payment history accepts its supported search query",BuriMunsiSchemas.contract.query("history","q=receipt")["q"]=="receipt")
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
 val shared=ApiClient("https://test.invalid","installation-1",prefix){"d".repeat(64)}
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
 val managedShared=ApiClient("https://test.invalid","installation-1",object:ManagedSessionTokenProvider{
  override fun currentAccessToken()=managedAccess
  override fun currentAccessContext()=ManagedRequestAccess(managedAccess,"group-1")
 },prefix){"d".repeat(64)}
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
 val observed=api.call("POST","/v1/burimunsi/sms/observations/source-1/reveal",token="a".repeat(64),
  body=JSONObject().put("reason","Review original SMS").put("displayHintsVersion",1),contractContext=scope)
 ck("actual transport validates opted-in partial inbox hints",JSONObject(observed).getJSONObject("displayHints").getJSONArray("hints").getJSONObject(0).getString("text")=="1,000 RWF")
 Wire.reply=Reply(transform={v->v.getJSONObject("data").getJSONObject("displayHints").getJSONArray("hints").getJSONObject(0).put("text","9,000 RWF");Unit})
 ck("actual transport rejects forged partial inbox hint",runCatching{api.call("POST","/v1/burimunsi/sms/observations/source-1/reveal",token="a".repeat(64),
  body=JSONObject().put("reason","Review original SMS").put("displayHintsVersion",1),contractContext=scope)}.isFailure)
 Wire.reply=Reply()
 val reason="Gusuzuma inyemezabwishyu y’umunyamuryango 🧾"
 val revealed=api.call("POST","/v1/burimunsi/sms/sms-1/reveal",token="a".repeat(64),body=JSONObject().put("reason",reason),contractContext=scope)
 ck("raw reveal keeps Unicode response body unchanged",JSONObject(revealed).getString("rawBody")=="SMS y’umwimerere 🧾")
 Wire.reply=Reply(transform={v->v.getJSONObject("data").put("rawBody","A".repeat(16384));Unit})
 ck("raw reveal preserves all canonical capture bytes",JSONObject(api.call("POST","/v1/burimunsi/sms/sms-1/reveal",token="a".repeat(64),body=JSONObject().put("reason",reason),contractContext=scope)).getString("rawBody")=="A".repeat(16384))
 Wire.reply=Reply(transform={v->v.getJSONObject("data").put("rawBody","A".repeat(16385));Unit})
 ck("raw reveal rejects source beyond canonical limit",runCatching{api.call("POST","/v1/burimunsi/sms/sms-1/reveal",token="a".repeat(64),body=JSONObject().put("reason",reason),contractContext=scope)}.isFailure)
 Wire.reply=Reply()
 ck("review reason is UTF-8 JSON rather than a header",JSONObject(Wire.last!!.written.toString("UTF-8")).getString("reason")==reason&&Wire.last!!.getRequestProperty("Content-Type")=="application/json; charset=utf-8"&&Wire.last!!.getRequestProperty("X-Collect-Review-Reason")==null)
 ck("review reason framing counts UTF-8 bytes",Wire.last!!.declaredBodyLength==Wire.last!!.written.size()&&Wire.last!!.written.size()>reason.length)
 val mutableReview=JSONObject().put("reason",reason)
 val snapshotApi=ApiClient("https://test.invalid","installation-1"){
  mutableReview.put("reason","Changed review reason")
  "d".repeat(64)
 }
 snapshotApi.call("POST","/v1/burimunsi/sms/sms-1/reveal",body=mutableReview,contractContext=scope)
 ck("dispatch uses the request snapshot validated before device lookup",mutableReview.getString("reason")!=reason&&
  JSONObject(Wire.last!!.written.toString("UTF-8")).getString("reason")==reason)
 api.call("POST","/v1/burimunsi/sms/sms-1/reveal",body=JSONObject().put("reason","🧾".repeat(1000)),contractContext=scope)
 ck("Kotlin wire accepts the 1000-code-point Unicode boundary",Wire.last!!.written.size()<=8192)
 val opened=Wire.opened
 for(body in listOf(JSONObject(),JSONObject().put("reason","short"),JSONObject().put("reason","x".repeat(1001)),JSONObject().put("reason","valid reason\n"),JSONObject().put("reason",reason).put("requestId",id))){
  runCatching{api.call("POST","/v1/burimunsi/sms/sms-1/reveal",body=body,contractContext=scope)}
  ck("invalid disclosure body is rejected before opening a socket",Wire.opened==opened)
 }
 runCatching{api.call("GET","/v1/burimunsi/sms/sms-1",contractContext=scope)}
 ck("old raw GET cannot dispatch",Wire.opened==opened)
 Wire.reply=Reply(status=503,body=error("audit_unavailable"))
 val lost=runCatching{api.call("POST","/v1/burimunsi/sms/sms-1/reveal",body=JSONObject().put("reason",reason),contractContext=scope)}.exceptionOrNull() as ApiFailure
 ck("uncertain reveal is one request without automatic replay",lost.uncertain&&Wire.opened==opened+1)
 Wire.reply=Reply(transform={v->v.put("data",v.getJSONObject("data").put("groupId","group-1"))})
 val nativeInstall="00000000-0000-4000-8000-000000000087"
 val native=ApiClient.phonePin("https://test.invalid",nativeInstall,"internal_receiver","/functions/v1/collect-api"){"d".repeat(64)}
 val nativeLogin=JSONObject(native.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone","+250780000001").put("pin","2468"),contractContext=mapOf("generation" to "18","groupId" to "stale-cached-group")))
 ck("phone PIN bootstrap adopts server scope without a preconfigured group",nativeLogin.getString("groupId")=="group-1"&&Wire.last?.getRequestProperty("X-BuriMunsi-Group")==null)
 ck("phone PIN mode is explicit and carries only automatic installation proof",Wire.last?.getRequestProperty("X-BuriMunsi-Auth")=="phone_pin"&&Wire.last?.getRequestProperty("X-BuriMunsi-Profile")=="internal_receiver"&&Wire.last?.getRequestProperty("X-BuriMunsi-Device")=="d".repeat(64))
 ck("phone PIN bootstrap does not invent managed or operator proof",Wire.last?.getRequestProperty("X-BuriMunsi-Collect-Session")==null&&Wire.last?.getRequestProperty("Authorization")==null)
 ck("phone PIN bootstrap retains exact Edge mount and installation identity",Wire.last?.url?.path=="/functions/v1/collect-api/v1/burimunsi/session/login"&&Wire.last?.getRequestProperty("X-BuriMunsi-Installation")==nativeInstall)
 val cloud="https://rrlduytparvsjfmegalh.supabase.co";val publishable="sb_publishable_"+"p".repeat(24)
 val cloudClient=ApiClient.phonePin(cloud,nativeInstall,"staff","/functions/v1/collect-api",publishable){"d".repeat(64)}
 cloudClient.call("POST","/v1/burimunsi/session/login",body=JSONObject().put("phone","+250780000001").put("pin","2468"),contractContext=mapOf("generation" to "18"))
 ck("cloud login sends the public project key without inventing an authorization token",Wire.last?.getRequestProperty("apikey")==publishable&&Wire.last?.getRequestProperty("Authorization")==null)
 Wire.reply=Reply(body="""{"support_channels":[{"key":"support.whatsapp","value":"250780000001"}]}""")
 ck("cloud help sends the public project key",SupportContactClient(cloud,"/functions/v1/collect-api",publishable).read()=="+250780000001"&&Wire.last?.getRequestProperty("apikey")==publishable)
 Wire.reply=Reply()
 val beforePublicKeyRefusals=Wire.opened
 for((origin,prefix,key) in listOf(Triple(cloud,"/functions/v1/collect-api",""),Triple(cloud,"/functions/v1/collect-api","sb_secret_"+"x".repeat(24)),
  Triple(cloud,"/functions/v1/collect-api",publishable+"\n"),Triple("https://different-project.supabase.co","/functions/v1/collect-api",publishable),
  Triple(cloud,"",publishable)))
  ck("invalid public key or project is refused before opening a socket",runCatching{ApiClient.phonePin(origin,nativeInstall,"staff",prefix,key){"d".repeat(64)}}.isFailure&&Wire.opened==beforePublicKeyRefusals)
 val noScopeOpened=Wire.opened
 runCatching{native.call("GET","/v1/burimunsi/home",token="a".repeat(64))}
 ck("ordinary native request still refuses missing server-bound collection",Wire.opened==noScopeOpened)
 ck("arbitrary native profile cannot create a fallback client",runCatching{ApiClient.phonePin("https://test.invalid",nativeInstall,"owner"," "){"d".repeat(64)}}.isFailure&&Wire.opened==noScopeOpened)
 Wire.reply=Reply()
 val handoffScope=scope+mapOf("handoffFingerprint" to "b".repeat(64))
 val retirementPath="/v1/burimunsi/gateway/replacements/$id/outcome"
 fun retirement()=native.call("GET",retirementPath,token="a".repeat(64),contractContext=handoffScope)
 ck("retirement recovery is a strict unknown ACK read",JSONObject(retirement()).getString("state")=="unknown")
 ck("retirement selector is a header without body or managed proof",Wire.last?.getRequestProperty("X-BuriMunsi-Handoff-Fingerprint")=="b".repeat(64)&&Wire.last?.written?.size()==0&&Wire.last?.getRequestProperty("X-BuriMunsi-Collect-Session")==null)
 ck("retirement recovery preserves all original opaque phone proofs",Wire.last?.getRequestProperty("Authorization")=="Bearer "+"a".repeat(64)&&Wire.last?.getRequestProperty("X-BuriMunsi-Installation")==nativeInstall&&Wire.last?.getRequestProperty("X-BuriMunsi-Device")=="d".repeat(64)&&Wire.last?.getRequestProperty("X-BuriMunsi-Profile")=="internal_receiver")
 for(edit in listOf<(JSONObject)->Unit>({it.put("fingerprint","c".repeat(64))},{it.put("requestId","00000000-0000-4000-8000-000000000099")},
  {it.put("state","retired")},{it.put("ack",JSONObject().put("gateway_token","c".repeat(64)))})){
  Wire.reply=Reply(transform={v->val d=v.getJSONObject("data");edit(d);v.put("data",d)})
  ck("inconsistent or secret-bearing retirement reply cannot settle",runCatching{retirement()}.exceptionOrNull() is ApiFailure)
 }
 Wire.reply=Reply()
 val beforeRetirement=Wire.opened
 for((method,path,ctx)in listOf(Triple("POST",retirementPath,handoffScope),Triple("GET","/v1/burimunsi/home",handoffScope),Triple("GET",retirementPath,scope),Triple("GET",retirementPath+"?replay=true",handoffScope))){
  runCatching{native.call(method,path,token="a".repeat(64),contractContext=ctx)}
  ck("invalid retirement read cannot open a socket",Wire.opened==beforeRetirement)
 }
 val retirementBody=JSONObject().put("replacementCode","c".repeat(64)).put("requestId",id)
 val positiveAck=JSONObject(native.call("POST","/v1/burimunsi/gateway/replace",token="a".repeat(64),body=retirementBody,contractContext=scope))
 ck("retirement POST returns only ACK and never a gateway credential",positiveAck.keys().asSequence().toSet()==setOf("retired","handoffId","requestId","reauthenticationRequired"))
 Wire.reply=Reply(transform={v->val d=v.getJSONObject("data");d.put("requestId","00000000-0000-4000-8000-000000000099");v.put("data",d)})
 val wrongAck=runCatching{native.call("POST","/v1/burimunsi/gateway/replace",token="a".repeat(64),body=retirementBody,contractContext=scope)}.exceptionOrNull()
 ck("foreign retirement ACK leaves dispatched command uncertain",wrongAck is ApiFailure&&wrongAck.uncertain)
 println("RESULT: $count real ApiClient checks passed with fake HttpURLConnection; not TLS/Android certification.")
}
