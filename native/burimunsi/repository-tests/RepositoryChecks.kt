package rw.ikanisa.burimunsi.repositorytests
import android.content.Context
import org.json.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

fun main(){
 var checks=0
 fun ck(label:String,test:Boolean){check(test){label};println("PASS $label");checks++}
 fun profile(id:String="admin-1")=JSONObject().put("id",id).put("name","Example Admin").put("phone","+250780000001").put("role","admin").put("capabilities",JSONArray().put("records.read").put("members.enroll").put("payments.allocate"))
 val token="a".repeat(64)
 fun session(id:String="admin-1",t:String=token)=JSONObject().put("token",t).put("expiresAt",System.currentTimeMillis()+3600000).put("profile",profile(id)).toString()
 fun home()=JSONObject().put("groupBalanceRwf",17000).put("todayRwf",10000).put("memberCount",2).put("unallocatedCount",1).put("recentPayments",JSONArray()).put("asOf","2026-11-08T10:00:00Z").toString()
 fun pay()=JSONObject().put("id","tx-1").put("groupId","group-1").put("memberId",JSONObject.NULL).put("memberPhone",JSONObject.NULL).put("sourceId",JSONObject.NULL).put("payerNameRaw","Example payer").put("payerPhoneRaw","+250780000816").put("amountRwf",17000).put("atRaw","2026-11-08 12:00:00").put("ftId","10001").put("state","unallocated").put("version",1).toString()
 fun emptyPage()=JSONObject().put("items",JSONArray()).put("totalCount",0).put("nextCursor",JSONObject.NULL).put("revision","v1").put("asOf","2026-11-08T10:00:00Z").toString()
 fun recovered(req:Request,state:String,id:String=if(req.path.endsWith("/recovery"))req.path.substringBeforeLast('/').substringAfterLast('/') else req.path.substringAfterLast('/'))=if(!req.path.endsWith("/recovery")) JSONObject()
  .put("contractVersion",2).put("requestId",id).put("groupId","group-1").put("actorId","admin-1")
  .put("state",state).put("operation","burimunsi.allocate").put("financialState","posted").toString() else JSONObject()
  .put("protocol","burimunsi.operation-recovery.v1").put("requestId",id).put("state",state)
  .put("originDigest",req.recoveryOrigin).put("groupId","group-1").put("actorId","admin-1").put("installationId","installation-1").toString()
 val api=ApiClient()
 api.handler={r->when{r.path.endsWith("/session/login")||r.path.endsWith("/session")->session();r.path.endsWith("/home")->home();r.path.endsWith("/payments/tx-1")->pay();r.path.contains("/sms?")||r.path.contains("/staff?")->emptyPage();else->"{}"}}
 val happy=api.handler
 SecureStore.reset();val repo=NativeRepository(Context(),api,"group-1")
 ck("empty store restores no session",repo.restore()==null)
 val before=System.currentTimeMillis();repo.login("0780000001","2468")
 ck("login compiles and records an actual timestamp",repo.lastReadSavedAt!!>=before&&repo.lastReadSavedAt!!<=System.currentTimeMillis())
 ck("server operator installed",repo.current()?.id=="admin-1")
 ck("phone normalized before dispatch",api.calls.last().body!!.getString("phone")=="+250780000001")
 val count=api.calls.size;runCatching{repo.login("bad","2468")};ck("invalid login does not dispatch or replace operator",api.calls.size==count&&repo.current()?.id=="admin-1")
 ck("home reads authoritative balance",repo.home().balanceRwf==17000L)
 ck("live read is not cached provenance",!repo.lastReadFromCache&&repo.lastReadSavedAt!=null)
 api.handler={throw ApiFailure("connection_unavailable",0)}
 ck("offline home reuses owner-bound cache",repo.home().balanceRwf==17000L&&repo.lastReadFromCache)
 api.handler=happy;repo.sms();ck("successful noncached SMS clears stale cache flag",!repo.lastReadFromCache)
 api.handler={throw ApiFailure("connection_unavailable",0)};repo.home()
 api.handler=happy;repo.refreshSession();ck("session refresh clears previous read provenance",!repo.lastReadFromCache)
 val cache=JSONObject(SecureStore.records.getValue("records"));cache.getJSONObject("entries").getJSONObject("/home").put("savedAt",0L)
 // Adapter returns independent objects, matching JSON snapshot mutation explicitly below.
 val entries=cache.getJSONObject("entries");val entry=entries.getJSONObject("/home").put("savedAt",0L);entries.put("/home",entry);cache.put("entries",entries);SecureStore.records["records"]=cache.toString()
 api.handler={throw ApiFailure("connection_unavailable",0)}
 ck("expired cache refused",runCatching{repo.home()}.exceptionOrNull() is ApiFailure)
 api.handler=happy;repo.home()
 api.handler={throw ApiFailure("invalid_api_response",200)}
 ck("protocol error never falls back to cache",runCatching{repo.home()}.exceptionOrNull()?.let{it is ApiFailure&&it.code=="invalid_api_response"}==true)
 api.handler=happy
 val old=repo.current()!!;val wrongSession=session("other-admin")
 api.handler={wrongSession};ck("changed principal rejected on refresh",runCatching{repo.refreshSession()}.exceptionOrNull() is ContractFailure)
 ck("changed principal clears local credentials and cache",repo.current()==null&&"session" !in SecureStore.records&&"records" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468");repo.home()
 api.handler={throw ApiFailure("access_denied",401)}
 ck("401 invalidates operator",runCatching{repo.home()}.exceptionOrNull() is ApiFailure&&repo.current()==null)
 ck("401 clears records",!SecureStore.records.containsKey("records"))
 SecureStore.records["session"]="not-json";ck("corrupt stored session fails closed",repo.restore()==null&&"session" !in SecureStore.records)
 SecureStore.records["session"]=JSONObject().put("groupId","other-group").put("token",token).put("expiresAt",System.currentTimeMillis()+5000).toString()
 ck("wrong group cannot restore",repo.restore()==null)
 SecureStore.records["session"]=JSONObject().put("groupId","group-1").put("token",token).put("expiresAt",0).toString()
 ck("expired stored session refused",repo.restore()==null)
 api.handler=happy;repo.login("0780000001","2468")
 val restored=NativeRepository(Context(),api,"group-1");ck("restore requires server-confirmed profile",restored.restore()?.id=="admin-1")
 api.handler={throw ApiFailure("connection_unavailable",0)}
 val offlineRestore=NativeRepository(Context(),api,"group-1");runCatching{offlineRestore.restore()}
 ck("failed restore does not retain usable bearer",offlineRestore.current()==null&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 val p=decodePayment(JSONObject(pay()));val m=Member("member-1","Example Member","+250780000816",0,true,1)
 api.handler={req->if(req.path.endsWith("/allocate"))throw ApiFailure("connection_unavailable",0,true) else happy(req)}
 runCatching{repo.allocate(p,m,"Verified full identity")}
 ck("uncertain allocation leaves durable UNKNOWN",repo.pending()?.state==OperationState.UNKNOWN)
 val request=repo.pending()!!.requestId
 repo.clearOperator();ck("sign-out preserves pending operation",repo.pending()?.requestId==request)
 api.handler=happy;repo.login("0780000001","2468")
 api.handler={req->if(req.path.contains("/operations/"))recovered(req,"committed",request) else happy(req)}
 repo.reconcilePending();ck("authenticated commit reconciles exactly one pending command",repo.pending()==null)
 ck("commit invalidates cached financial data",!SecureStore.records.containsKey("records"))
 // Definitive economic outcomes MUST be read from the original request receipt.
 // A client retry action is a status query, never an implicit financial POST.
 api.handler=happy;repo.login("0780000001","2468")
 var postCalls=0;var outcomeCalls=0;var requestedState="pending";var forcedPostFailure=true
 api.handler={req->when{
  req.path.endsWith("/allocate")->{postCalls++;if(forcedPostFailure)throw ApiFailure("connection_unavailable",0,true);"{}"}
  req.path.contains("/operations/")->{if(req.path.endsWith("/recovery"))outcomeCalls++;recovered(req,requestedState)}
  else->happy(req)
 }}
 runCatching{repo.allocate(p,m,"Authenticated pending state test")}
 val unresolved=repo.pending()!!
 ck("uncertain first allocation remains UNKNOWN",unresolved.state==OperationState.UNKNOWN&&postCalls==1)
 val pendingResult=repo.reconcilePending()
 ck("authoritative pending is returned without new POST",pendingResult.getString("state")=="pending"&&postCalls==1&&outcomeCalls==1)
 ck("pending remains durable with original request ID",repo.pending()?.requestId==unresolved.requestId)
 ck("repeat tapping identical allocation is refused",runCatching{repo.allocate(p,m,"Authenticated pending state test")}.isFailure&&postCalls==1)
 ck("explicit retry cannot reissue UNKNOWN request",runCatching{repo.retryPending()}.isFailure&&postCalls==1)
 requestedState="committed";repo.reconcilePending()
 ck("only authenticated committed status terminates pending",repo.pending()==null&&postCalls==1&&outcomeCalls==2)
 forcedPostFailure=false;requestedState="pending";postCalls=0;outcomeCalls=0
 val uncertainSuccess=runCatching{repo.allocate(p,m,"Transport success without outcome")}.exceptionOrNull()
 ck("POST success plus pending status is NOT marked credited",uncertainSuccess is ApiFailure&&uncertainSuccess.uncertain&&repo.pending()?.state==OperationState.UNKNOWN&&postCalls==1&&outcomeCalls==1)
 requestedState="rejected";val rejected=runCatching{repo.reconcilePending()}
 ck("unsupported rejection cannot erase pending operation",rejected.isFailure&&repo.pending()!=null&&postCalls==1)
 requestedState="committed";repo.reconcilePending()
 forcedPostFailure=false;requestedState="committed";postCalls=0;outcomeCalls=0
 val resultVerified=repo.allocate(p,m,"Verified receipt after successful POST")
 ck("success needs a matching retained command outcome",resultVerified.getString("state")=="committed"&&postCalls==1&&outcomeCalls==1&&repo.pending()==null)
 // The mutation may have committed before a status GET receives a 401.
 // It must remain UNKNOWN, not a definite rejected command.
 postCalls=0;outcomeCalls=0
 api.handler={req->when{
  req.path.endsWith("/allocate")->{postCalls++;"{}"}
  req.path.contains("/operations/")->{outcomeCalls++;throw ApiFailure("session_unavailable",401,false)}
  else->happy(req)
 }}
 runCatching{repo.allocate(p,m,"POST accepted but status 401")}
 ck("post-ack status 401 cannot erase possible commit",repo.pending()?.state==OperationState.UNKNOWN&&postCalls==1&&outcomeCalls==1)
 // Fresh explicit login is needed, and server-side operator-bound reconciliation
 // will require an approved principal-scoped journal before cross-token recovery.
 repo.login("0780000001","2468")
 api.handler={req->if(req.path.contains("/operations/"))recovered(req,"committed") else happy(req)}
 repo.reconcilePending()

 forcedPostFailure=false;requestedState="pending";postCalls=0;outcomeCalls=0
 api.handler={req->if(req.path.endsWith("/allocate")){postCalls++;"{}"}else if(req.path.contains("/operations/")){outcomeCalls++;JSONObject().put("requestId",req.path.substringAfterLast('/')).put("state","pending").toString()}else happy(req)}
 runCatching{repo.allocate(p,m,"Verify request identity before closing")}
 val identity=repo.pending()!!.requestId
 api.handler={req->if(req.path.contains("/operations/"))JSONObject().put("requestId","other-request").put("state","committed").toString() else happy(req)}
 ck("mismatched signed outcome cannot terminate operation",runCatching{repo.reconcilePending()}.isFailure&&repo.pending()?.requestId==identity)
 api.handler={req->if(req.path.contains("/operations/"))recovered(req,"committed",identity) else happy(req)}
 repo.reconcilePending()
 forcedPostFailure=true;postCalls=0;outcomeCalls=0
 api.handler={req->when{
  req.path.endsWith("/allocate")->{postCalls++;throw ApiFailure("connection_unavailable",0,true)}
  req.path.contains("/operations/")->{outcomeCalls++;JSONObject().put("requestId",req.path.substringAfterLast('/')).put("state","pending").toString()}
  else->happy(req)
 }}
 runCatching{repo.allocate(p,m,"Session crossover protection")}
 repo.clearOperator()
 api.handler={req->if(req.path.endsWith("/session/login"))session(t="b".repeat(64)) else if(req.path.contains("/operations/")){outcomeCalls++;JSONObject().put("requestId",req.path.substringAfterLast('/')).put("state","pending").toString()}else happy(req)}
 repo.login("0780000001","2468") // Same operator, new bearer.
 val queriesBefore=outcomeCalls
 ck("new bearer cannot accept unverified legacy status",runCatching{repo.reconcilePending()}.isFailure&&outcomeCalls==queriesBefore+1&&repo.pending()!=null)
 // A legacy unversioned result cannot satisfy the new recovery contract.
 SecureStore.reset()

 api.handler=happy;repo.login("0780000001","2468");repo.home()
 api.handler={req->if(req.path.endsWith("/passcode"))throw ApiFailure("connection_unavailable",0,true) else happy(req)}
 runCatching{repo.changePin("2468","8642","8642")}
 ck("uncertain passcode change forces reauthentication",repo.current()==null)
 api.handler=happy;repo.login("0780000001","2468")
 val sent=CountDownLatch(1);val finish=CountDownLatch(1);var failure:Throwable?=null
 api.handler={req->if(req.path.endsWith("/home")){sent.countDown();check(finish.await(5,TimeUnit.SECONDS));home()}else happy(req)}
 val reader=thread{try{repo.home()}catch(e:Throwable){failure=e}}
 check(sent.await(5,TimeUnit.SECONDS));repo.clearOperator();finish.countDown();reader.join(6000)
 ck("late read cannot restore signed-out records",failure is ContractFailure&&repo.current()==null&&!SecureStore.records.containsKey("records"))
 // History endpoint and precise DTO/page contracts. Synthetic JSON/storage, actual repository code.
 api.handler=happy;repo.login("0780000001","2468")
 fun event(id:String="transaction:tx-1",kind:String="transaction_recorded",delta:Long?=null)=JSONObject()
  .put("id",id).put("groupId","group-1").put("transactionId","tx-1").put("kind",kind)
  .put("recordedAt","2026-11-08T10:00:00Z").put("amountRwf",delta?:JSONObject.NULL)
  .put("memberId",if(kind=="ledger_entry")"member-1" else JSONObject.NULL)
 fun events(vararg rows:JSONObject)=JSONObject().put("items",JSONArray().also{a->rows.forEach{a.put(it)}})
  .put("nextCursor",JSONObject.NULL).put("totalCount",rows.size).put("revision","history-v1").put("asOf","2026-11-08T10:00:02Z")
 val history=events(event(),event("ledger:l-1","ledger_entry",-17000)).toString()
 api.handler={r->if(r.path.contains("/history"))history else happy(r)}
 val result=repo.paymentHistory("tx-1")
 ck("history endpoint decodes signed canonical ledger changes",result.items[1].amountRwf==-17000L&&result.items[0].amountRwf==null)
 ck("history uses the scoped transaction URL",api.calls.last().path=="/v1/burimunsi/payments/tx-1/history?")
 api.handler={throw ApiFailure("connection_unavailable",0)}
 ck("history supports owner-bound offline cache",repo.paymentHistory("tx-1").items.size==2&&repo.lastReadFromCache)
 api.handler={r->if(r.path.contains("/history"))history else happy(r)};repo.paymentHistory("tx-1")
 ck("history fresh read clears saved-data flag",!repo.lastReadFromCache)
 fun invalid(label:String,row:JSONObject){ck(label,runCatching{decodePaymentHistory(events(row).toString(),"group-1","tx-1")}.isFailure)}
 invalid("history rejects foreign group",event().put("groupId","other"))
 invalid("history rejects foreign transaction",event().put("transactionId","other"))
 invalid("history rejects guessed stage",event().put("kind","confirmed"))
 invalid("history rejects invalid date",event().put("recordedAt","2026-02-30T10:00:00Z"))
 invalid("history rejects timezone-free date",event().put("recordedAt","2026-11-08 10:00:00"))
 invalid("history observation cannot imply credit",event().put("amountRwf",10000))
 invalid("history requires a member on ledger entries",event("ledger:l-1","ledger_entry",17000).put("memberId",JSONObject.NULL))
 invalid("history rejects zero-value ledger entries",event("ledger:l-1","ledger_entry",0))
 invalid("history rejects mismatched event source",event("transaction:other"))
 ck("history rejects duplicate event IDs",runCatching{decodePaymentHistory(events(event(),event()).toString(),"group-1","tx-1")}.isFailure)
 for((label,value) in listOf("fractional" to 1.5,"negative" to -1,"overflow" to 2147483648L,"coerced string" to "1")){
  ck("page refuses $label count",runCatching{page(events(event()).put("totalCount",value).toString()){it.getString("id")}}.isFailure)
 }
 ck("page refuses empty continuation",runCatching{page(events().put("nextCursor","cursor").toString()){it.getString("id")}}.isFailure)
 ck("page refuses blank revision",runCatching{page(events(event()).put("revision","").toString()){it.getString("id")}}.isFailure)
 ck("page refuses count smaller than its rows",runCatching{page(events(event()).put("totalCount",0).toString()){it.getString("id")}}.isFailure)
 ck("page refuses oversized cursor",runCatching{page(events(event()).put("nextCursor","c".repeat(8193)).toString()){it.getString("id")}}.isFailure)
 println("RESULT: $checks actual Repository/DTO/OperationStore checks passed; in-memory storage, synthetic transport and test-only JSON adapter, not Android Keystore/HTTP/JSON or device execution.")
}
