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
 fun signedOut()=JSONObject().put("signedOut",true).toString()
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
 api.handler={r->when{r.path.endsWith("/session/login")||r.path.endsWith("/session")->session();r.path.endsWith("/logout")->signedOut();r.path.endsWith("/home")->home();r.path.endsWith("/payments/tx-1")->pay();r.path.contains("/sms?")||r.path.contains("/staff?")->emptyPage();else->"{}"}}
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
 api.handler={throw ApiFailure("session_unavailable",401)}
 ck("401 invalidates operator",runCatching{repo.home()}.exceptionOrNull() is ApiFailure&&repo.current()==null)
 ck("401 clears records",!SecureStore.records.containsKey("records"))
 SecureStore.records["session"]="not-json";ck("corrupt stored session fails closed",repo.restore()==null&&"session" !in SecureStore.records)
 SecureStore.records["session"]=JSONObject().put("groupId","other-group").put("token",token).put("expiresAt",System.currentTimeMillis()+5000).toString()
 ck("wrong group cannot restore",repo.restore()==null)
 SecureStore.records["session"]=JSONObject().put("groupId","group-1").put("token",token).put("expiresAt",0).toString()
 ck("invalid zero session deadline refused",repo.restore()==null)
 api.handler=happy;repo.login("0780000001","2468")
 val restored=NativeRepository(Context(),api,"group-1");ck("restore requires server-confirmed profile",restored.restore()?.id=="admin-1")
 val expired=JSONObject(SecureStore.records.getValue("session")).put("expiresAt",System.currentTimeMillis()-1000)
 SecureStore.records["session"]=expired.toString()
 val renewed=NativeRepository(Context(),api,"group-1");ck("expired saved deadline is revalidated by server without another PIN",renewed.restore()?.id=="admin-1"&&api.calls.last().path.endsWith("/session"))
 ck("server-renewed expiry is saved durably",JSONObject(SecureStore.records.getValue("session")).getLong("expiresAt")>System.currentTimeMillis())
 api.handler={throw ApiFailure("connection_unavailable",0)}
 val offlineRestore=NativeRepository(Context(),api,"group-1");runCatching{offlineRestore.restore()}
 ck("offline restore retains encrypted credential without installing an operator",offlineRestore.current()==null&&"session" in SecureStore.records)
 val offlineCalls=api.calls.size;ck("offline restore cannot read protected records",runCatching{offlineRestore.home()}.isFailure&&api.calls.size==offlineCalls)
 api.handler=happy;ck("reconnection restores saved session without another PIN",offlineRestore.restore()?.id=="admin-1"&&api.calls.last().path.endsWith("/session"))
 api.handler={throw ApiFailure("connection_unavailable",0)}
 val offlineLogout=NativeRepository(Context(),api,"group-1");runCatching{offlineLogout.restore()}
 val offlineSignOut=runCatching{offlineLogout.logout()}.exceptionOrNull()
 ck("offline logout clears the login and retains a protected revocation obligation",offlineLogout.current()==null&&"session" !in SecureStore.records&&
  "session-revocations" in SecureStore.records&&offlineSignOut is ApiFailure&&offlineSignOut.uncertain)
 api.handler=happy;repo.login("0780000001","2468")
 SecureStore.retainClear="session"
 ck("logout does not report success if protected session deletion fails",runCatching{repo.logout()}.isFailure&&"session" in SecureStore.records)
 SecureStore.retainClear=null;api.handler={throw ApiFailure("connection_unavailable",0)}
 ck("unconfirmed sign-out cannot restore a retained credential",NativeRepository(Context(),api,"group-1").restore()==null&&"session" !in SecureStore.records&&"session-revocations" in SecureStore.records)
 api.handler=happy;repo.logout();ck("failed local logout can be completed without restoring the bearer","session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 api.handler={throw ApiFailure("session_unavailable",401)}
 ck("confirmed revocation clears saved session",runCatching{NativeRepository(Context(),api,"group-1").restore()}.isFailure&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 api.handler={throw ApiFailure("access_denied",403)}
 ck("confirmed access denial clears saved session",runCatching{NativeRepository(Context(),api,"group-1").restore()}.isFailure&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 for(status in listOf(401,403))for(code in listOf("invalid_api_response","contract_json","contract_version","contract_response_truncated")){
  api.handler={req->if(req.path.endsWith("/session"))throw ApiFailure(code,status,false) else happy(req)}
  val rejected=runCatching{NativeRepository(Context(),api,"group-1").restore()}.exceptionOrNull()
  ck("malformed $status $code retains saved login for retry",rejected is ApiFailure&&rejected.code=="session_revalidation_unavailable"&&
   "session" in SecureStore.records&&repo.current()!=null)
 }
 api.handler=happy
 api.handler={session("other-admin")}
 ck("stored operator cannot silently change during restoration",runCatching{NativeRepository(Context(),api,"group-1").restore()}.isFailure&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 val restoreEntered=CountDownLatch(1);val releaseRestore=CountDownLatch(1);val newBearer="b".repeat(64)
 api.handler={r->if(r.path.endsWith("/session/login"))session(t=newBearer) else if(r.path.endsWith("/logout"))signedOut() else {
  restoreEntered.countDown();check(releaseRestore.await(5,TimeUnit.SECONDS));session()
 }}
 val racing=NativeRepository(Context(),api,"group-1");var lateFailure:Throwable?=null
 val restoreThread=thread{lateFailure=runCatching{racing.restore()}.exceptionOrNull()}
 check(restoreEntered.await(5,TimeUnit.SECONDS));racing.logout();racing.login("0780000001","2468");releaseRestore.countDown();restoreThread.join(6000)
 ck("late restore cannot replace a newer login",!restoreThread.isAlive&&lateFailure is ContractFailure&&racing.current()?.id=="admin-1"&&JSONObject(SecureStore.records.getValue("session")).getString("token")==newBearer)
 racing.logout();api.handler=happy;repo.login("0780000001","2468")
 val renewalEntered=CountDownLatch(1);val releaseRenewal=CountDownLatch(1)
 api.handler={r->if(r.path.endsWith("/session")){renewalEntered.countDown();check(releaseRenewal.await(5,TimeUnit.SECONDS));session()}else if(r.path.endsWith("/logout"))signedOut() else "{}"}
 var renewalFailure:Throwable?=null
 val renewalThread=thread{renewalFailure=runCatching{repo.refreshSession()}.exceptionOrNull()}
 check(renewalEntered.await(5,TimeUnit.SECONDS));repo.logout();releaseRenewal.countDown();renewalThread.join(6000)
 ck("late session renewal cannot undo explicit logout",!renewalThread.isAlive&&renewalFailure is ContractFailure&&repo.current()==null&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 val p=decodePayment(JSONObject(pay()));val m=Member("member-1","Example Member","+250780000816",0,true,1)
 val automatic=JSONObject(pay()).put("amountRwf",JSONObject.NULL).put("ftId",JSONObject.NULL).put("state","recorded")
  .put("direction","outgoing").put("outcome","pending").put("sourceKind","observation")
  .put("feeRwf",0).put("walletBalanceAfterRwf",1900)
 val decoded=decodePayment(automatic)
 ck("automatic transaction preserves nullable values and direction",decoded.amountRwf==null&&decoded.ftId==null&&
  decoded.direction=="outgoing"&&decoded.outcome=="pending"&&decoded.sourceKind=="observation"&&
  decoded.feeRwf==0L&&decoded.walletBalanceAfterRwf==1900L&&!PaymentPresentation.canAllocate(decoded))
 ck("automatic transaction rejects unknown direction",runCatching{decodePayment(JSONObject(automatic.toString()).put("direction","invented"))}.isFailure)
 ck("automatic transaction rejects fractional fees",runCatching{decodePayment(JSONObject(automatic.toString()).put("feeRwf",1.5))}.isFailure)
 api.handler={req->if(req.path.endsWith("/allocate"))throw ApiFailure("connection_unavailable",0,true) else happy(req)}
 runCatching{repo.allocate(p,m,"Verified full identity")}
 ck("uncertain allocation leaves durable UNKNOWN",repo.pending()?.state==OperationState.UNKNOWN)
 val request=repo.pending()!!.requestId
 repo.clearOperator();ck("sign-out preserves pending operation",repo.pending()?.requestId==request)
 val anotherScope=NativeRepository(Context(),api,"approved-other-group")
 ck("dynamic repository scope retains original unresolved command",anotherScope.restore()==null&&anotherScope.pending()?.requestId==request&&anotherScope.pending()?.groupId=="group-1")
 api.handler=happy;anotherScope.login("0780000001","2468");val beforeForeignRecovery=api.calls.size
 ck("another approved scope cannot reconcile original group's journal",runCatching{anotherScope.reconcilePending()}.exceptionOrNull() is ContractFailure&&api.calls.size==beforeForeignRecovery&&anotherScope.pending()?.requestId==request)
 anotherScope.clearOperator()
 api.handler=happy;repo.login("0780000001","2468")
 api.handler={req->if(req.path.contains("/operations/"))recovered(req,"committed",request) else happy(req)}
 repo.reconcilePending();ck("authenticated commit reconciles exactly one pending command",repo.pending()==null)
 ck("commit invalidates cached financial data",!SecureStore.records.containsKey("records"))
 // Definitive economic outcomes MUST be read from the original request receipt.
 // A client retry action is a status query, never an implicit financial POST.
 api.handler=happy
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
 repo.clearOperator();SecureStore.reset()

 api.handler=happy;repo.login("0780000001","2468");repo.home()
 val callCount=api.calls.size
 ck("same passcode rejected without dispatch",runCatching{repo.changePin("2468","2468","2468")}.isFailure&&api.calls.size==callCount&&repo.current()!=null)
 api.handler={req->if(req.path.endsWith("/passcode"))throw ApiFailure("invalid_current_pin",400,false) else happy(req)}
 val wrongPin=runCatching{repo.changePin("2468","8642","8642")}.exceptionOrNull()
 ck("wrong current PIN preserves valid session",wrongPin is ApiFailure&&wrongPin.code=="invalid_current_pin"&&repo.current()!=null&&
  !JSONObject(SecureStore.records.getValue("session")).has("pendingPasscode"))
 api.handler={req->if(req.path.endsWith("/passcode"))JSONObject().put("reauthenticationRequired",false).put("expiresAt",System.currentTimeMillis()+600000).toString() else happy(req)}
 val switched=repo.changePin("2468","8642","8642")
 val replacement=api.calls.last().body!!.getString("replacementToken")
 ck("successful PIN change installs random server-approved candidate",switched.id=="admin-1"&&Regex("[a-f0-9]{64}").matches(replacement)&&replacement!=token&&
  JSONObject(SecureStore.records.getValue("session")).getString("token")==replacement&&repo.current()!=null)
 ck("persisted session contains no PIN",!SecureStore.records.getValue("session").contains("2468")&&!SecureStore.records.getValue("session").contains("8642"))
 api.handler=happy;repo.logout();repo.login("0780000001","2468")
 api.handler={req->if(req.path.endsWith("/passcode"))throw ApiFailure("invalid_api_response",401,true) else happy(req)}
 val truncated=runCatching{repo.changePin("2468","8642","8642")}.exceptionOrNull()
 val truncatedCandidate=JSONObject(SecureStore.records.getValue("session")).getJSONObject("pendingPasscode").getString("token")
 ck("malformed post-dispatch 401 retains the replacement candidate",truncated is ApiFailure&&truncated.uncertain&&repo.current()==null&&
  Regex("[a-f0-9]{64}").matches(truncatedCandidate))
 api.handler={req->if(req.path.endsWith("/session"))session(t=req.token!!) else happy(req)}
 ck("malformed 401 can recover through the candidate without replay",repo.restore()?.id=="admin-1"&&
  JSONObject(SecureStore.records.getValue("session")).getString("token")==truncatedCandidate)
 api.handler=happy;repo.logout();repo.login("0780000001","2468")
 api.handler={req->if(req.path.endsWith("/passcode"))throw ApiFailure("connection_unavailable",0,true) else happy(req)}
 runCatching{repo.changePin("2468","8642","8642")}
 val authorityField=NativeRepository::class.java.getDeclaredField("processSessionAuthority").also{it.isAccessible=true}
 val processAuthority=authorityField.get(null) as SessionAuthority
 var transientAuthority=false;val detachEmptyLogout=repo.observeProcessSession{if(processAuthority.hasActive())transientAuthority=true}
 api.handler=happy;repo.logout();detachEmptyLogout()
 ck("logout of an empty process slot never transiently reactivates the saved proof",!transientAuthority&&!processAuthority.hasActive()&&"session" !in SecureStore.records)
 repo.login("0780000001","2468")
 var candidateAccepted=false
 api.handler={req->when{
  req.path.endsWith("/passcode")->throw ApiFailure("connection_unavailable",0,true)
  req.path.endsWith("/session")&&!candidateAccepted->throw ApiFailure("session_unavailable",401)
  req.path.endsWith("/session")->session(t=req.token!!)
  else->happy(req)
 }}
 val unknown=runCatching{repo.changePin("2468","8642","8642")}.exceptionOrNull()
 val pendingRotation=JSONObject(SecureStore.records.getValue("session")).getJSONObject("pendingPasscode").getString("token")
 ck("uncertain PIN change keeps encrypted candidate and hides the old session",unknown is ApiFailure&&unknown.uncertain&&repo.current()==null)
 val passcodePosts=api.calls.count{it.path.endsWith("/passcode")}
 ck("candidate 401 cannot settle an in-flight change",runCatching{NativeRepository(Context(),api,"group-1").restore()}.exceptionOrNull().let{it is ApiFailure&&it.uncertain}&&
  JSONObject(SecureStore.records.getValue("session")).getJSONObject("pendingPasscode").getString("token")==pendingRotation)
 val loginDuringUnknown=runCatching{NativeRepository(Context(),api,"group-1").login("0780000001","2468")}.exceptionOrNull()
 ck("new login cannot discard an in-flight candidate",loginDuringUnknown is ApiFailure&&loginDuringUnknown.uncertain&&
  JSONObject(SecureStore.records.getValue("session")).getJSONObject("pendingPasscode").getString("token")==pendingRotation)
 candidateAccepted=true
 val recoveredSession=NativeRepository(Context(),api,"group-1")
 ck("candidate recovery restores session without replaying PIN change",recoveredSession.restore()?.id=="admin-1"&&
  JSONObject(SecureStore.records.getValue("session")).getString("token")==pendingRotation&&api.calls.count{it.path.endsWith("/passcode")}==passcodePosts)
 api.handler=happy;recoveredSession.logout();repo.login("0780000001","2468")
 val pinEntered=CountDownLatch(1);val releasePin=CountDownLatch(1);var pinRace:Throwable?=null;var logoutProof:Request?=null
 api.handler={req->when{
  req.path.endsWith("/passcode")->{pinEntered.countDown();check(releasePin.await(5,TimeUnit.SECONDS));
   JSONObject().put("reauthenticationRequired",false).put("expiresAt",System.currentTimeMillis()+600000).toString()}
  req.path.endsWith("/logout")->{logoutProof=req;signedOut()}
  else->happy(req)
 }}
 val pinThread=thread{pinRace=runCatching{repo.changePin("2468","8642","8642")}.exceptionOrNull()}
 check(pinEntered.await(5,TimeUnit.SECONDS));repo.logout();releasePin.countDown();pinThread.join(6000)
 ck("late PIN success cannot undo logout",!pinThread.isAlive&&pinRace is ContractFailure&&repo.current()==null&&"session" !in SecureStore.records)
 ck("logout atomically revokes predecessor and candidate",logoutProof?.token==token&&
  Regex("[a-f0-9]{64}").matches(logoutProof?.body?.optString("replacementToken").orEmpty())&&"session-revocations" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 api.handler={req->if(req.path.endsWith("/logout"))throw ApiFailure("session_unavailable",401) else happy(req)}
 val deniedLogout=runCatching{repo.logout()}.exceptionOrNull()
 ck("logout 401 alone retains its non-login proof for a later retry",deniedLogout is ApiFailure&&deniedLogout.uncertain&&
  repo.current()==null&&"session" !in SecureStore.records&&"session-revocations" in SecureStore.records)
 api.handler=happy;ck("affirmative server logout settles the retained proof",repo.retryPendingSignOuts()&&"session-revocations" !in SecureStore.records)
 repo.login("0780000001","2468")
 SecureStore.failWrite="session-revocations"
 val lostJournal=runCatching{repo.logout()}.exceptionOrNull()
 ck("journal write failure still signs out locally and reports unconfirmed server revocation",lostJournal is ApiFailure&&lostJournal.uncertain&&
  repo.current()==null&&"session" in SecureStore.records&&"signed-out" in SecureStore.records)
 ck("a blocked journal cannot turn the retained proof back into a login",NativeRepository(Context(),api,"group-1").restore()==null&&"session" in SecureStore.records)
 SecureStore.failWrite=null
 ck("restart transfers the proof before deleting it",NativeRepository(Context(),api,"group-1").restore()==null&&
  "session" !in SecureStore.records&&"session-revocations" in SecureStore.records)
 ck("transferred proof can be revoked",repo.retryPendingSignOuts())
 repo.login("0780000001","2468")
 SecureStore.failWrites=setOf("signed-out","session-revocations")
 val noRetry=runCatching{repo.logout()}.exceptionOrNull()
 ck("lost sign-out proof reports no server retry",noRetry is ApiFailure&&noRetry.code=="logout_unconfirmed_no_retry"&&
  repo.current()==null&&"session" !in SecureStore.records&&"signed-out" !in SecureStore.records&&"session-revocations" !in SecureStore.records)
 SecureStore.failWrites=emptySet()
 ck("a cleared local session stays signed out even without a retry proof",NativeRepository(Context(),api,"group-1").restore()==null)
 repo.login("0780000001","2468")
 SecureStore.failWrites=setOf("signed-out","session-revocations");SecureStore.retainClear="session"
 val noLocalProof=runCatching{repo.logout()}.exceptionOrNull()
 ck("simultaneous persistent-storage failure reports local sign-out unconfirmed",noLocalProof is ApiFailure&&noLocalProof.code=="logout_local_unconfirmed"&&repo.current()==null&&"session" in SecureStore.records)
 SecureStore.failWrites=emptySet();SecureStore.retainClear=null;repo.logout()
 repo.login("0780000001","2468")
 val fullEntries=JSONArray();repeat(50){index->fullEntries.put(JSONObject().put("id",java.util.UUID.randomUUID().toString())
  .put("groupId","group-1").put("token",("%064x".format(index+1))))}
 SecureStore.records["session-revocations"]=JSONObject().put("entries",fullEntries).toString()
 val fullJournal=runCatching{repo.logout()}.exceptionOrNull()
 ck("full revocation journal still fences local logout",fullJournal is ApiFailure&&fullJournal.uncertain&&
  repo.current()==null&&"session" in SecureStore.records&&"signed-out" in SecureStore.records&&
  NativeRepository(Context(),api,"group-1").restore()==null)
 SecureStore.records.remove("session-revocations")
 ck("journal capacity recovery transfers the retained proof",NativeRepository(Context(),api,"group-1").restore()==null&&
  "session" !in SecureStore.records&&"session-revocations" in SecureStore.records&&repo.retryPendingSignOuts())
 repo.login("0780000001","2468")
 val crashSaved=JSONObject(SecureStore.records.getValue("session")).put("pendingPasscode",JSONObject()
  .put("token","c".repeat(64)).put("state","inflight")).toString()
 repo.clearOperator() // Synthetic process death: in-memory owner is gone.
 SecureStore.records["session"]=crashSaved;SecureStore.records["signed-out"]="signed-out"
 ck("crash after sign-out marker transfers both proofs before deletion",NativeRepository(Context(),api,"group-1").restore()==null&&
  "session" !in SecureStore.records&&JSONObject(SecureStore.records.getValue("session-revocations")).getJSONArray("entries").getJSONObject(0).getString("candidate")=="c".repeat(64))
 SecureStore.records["session"]=crashSaved
 ck("crash after journal append retries transfer idempotently",NativeRepository(Context(),api,"group-1").restore()==null&&
  "session" !in SecureStore.records&&JSONObject(SecureStore.records.getValue("session-revocations")).getJSONArray("entries").length()==1)
 ck("crash after session deletion remains signed out",NativeRepository(Context(),api,"group-1").restore()==null&&repo.retryPendingSignOuts())
 repo.login("0780000001","2468")
 api.handler={req->if(req.path.endsWith("/logout"))throw ApiFailure("connection_unavailable",0,true) else happy(req)}
 runCatching{repo.logout()}
 val b="b".repeat(64)
 api.handler={req->if(req.path.endsWith("/session/login"))session(t=b) else happy(req)};repo.login("0780000001","2468")
 val retryEntered=CountDownLatch(1);val retryRelease=CountDownLatch(1)
 api.handler={req->if(req.path.endsWith("/logout")){retryEntered.countDown();check(retryRelease.await(5,TimeUnit.SECONDS));signedOut()}else happy(req)}
 val retryThread=thread{runCatching{repo.retryPendingSignOuts()}};check(retryEntered.await(5,TimeUnit.SECONDS))
 var concurrentLogout:Throwable?=null;val concurrentLogoutThread=thread{concurrentLogout=runCatching{repo.logout()}.exceptionOrNull()}
 concurrentLogoutThread.join(1500)
 ck("slow retry never blocks recording a new local logout",!concurrentLogoutThread.isAlive&&concurrentLogout is ApiFailure&&
  repo.current()==null&&JSONObject(SecureStore.records.getValue("session-revocations")).getJSONArray("entries").length()==2)
 retryRelease.countDown();retryThread.join(6000)
 ck("retry reconciliation preserves a concurrently appended obligation",JSONObject(SecureStore.records.getValue("session-revocations")).getJSONArray("entries").length()==1)
 api.handler=happy;ck("later retry confirms the remaining logout",repo.retryPendingSignOuts()&&"session-revocations" !in SecureStore.records)
 repo.login("0780000001","2468")
 val refreshPeer=NativeRepository(Context(),api,"group-1");check(refreshPeer.restore()!=null)
 val olderExpiry=System.currentTimeMillis()+120_000;val newerExpiry=System.currentTimeMillis()+3_600_000
 val olderEntered=CountDownLatch(1);val releaseOlder=CountDownLatch(1);val newerStarted=CountDownLatch(1);val newerEntered=CountDownLatch(1)
 val renewalCalls=java.util.concurrent.atomic.AtomicInteger();var olderFailure:Throwable?=null;var newerFailure:Throwable?=null
 api.handler={req->if(req.path.endsWith("/session")){
  val call=renewalCalls.incrementAndGet()
  if(call==1){olderEntered.countDown();check(releaseOlder.await(5,TimeUnit.SECONDS))}else newerEntered.countDown()
  JSONObject(session()).put("expiresAt",if(call==1)olderExpiry else newerExpiry).toString()
 }else happy(req)}
 val older=thread{olderFailure=runCatching{repo.refreshSession()}.exceptionOrNull()};check(olderEntered.await(5,TimeUnit.SECONDS))
 val newer=thread{newerStarted.countDown();newerFailure=runCatching{refreshPeer.refreshSession()}.exceptionOrNull()};check(newerStarted.await(5,TimeUnit.SECONDS))
 val overtook=newerEntered.await(100,TimeUnit.MILLISECONDS)
 releaseOlder.countDown();older.join(6000);newer.join(6000)
 ck("UI and supervisor renewals cannot persist an older reply after a newer deadline",!overtook&&!older.isAlive&&!newer.isAlive&&
  olderFailure==null&&newerFailure==null&&renewalCalls.get()==2&&JSONObject(SecureStore.records.getValue("session")).getLong("expiresAt")==newerExpiry)
 api.handler=happy
 val refreshFirst=CountDownLatch(1);val refreshRelease=CountDownLatch(1);val pinInFlight=CountDownLatch(1);val pinRelease=CountDownLatch(1)
 val refreshLate=CountDownLatch(1);val lateRelease=CountDownLatch(1);var refreshCalls=0;var delayedRefresh:Throwable?=null;var delayedPin:Throwable?=null
 api.handler={req->when{
  req.path.endsWith("/session")->{refreshCalls++;if(refreshCalls==1){refreshFirst.countDown();check(refreshRelease.await(5,TimeUnit.SECONDS))}
   else{refreshLate.countDown();check(lateRelease.await(5,TimeUnit.SECONDS))};session(t=req.token!!)}
  req.path.endsWith("/passcode")->{pinInFlight.countDown();check(pinRelease.await(5,TimeUnit.SECONDS));
   JSONObject().put("reauthenticationRequired",false).put("expiresAt",System.currentTimeMillis()+600000).toString()}
  req.path.endsWith("/logout")->signedOut()
  else->happy(req)
 }}
 val firstRefresh=thread{runCatching{repo.refreshSession()}}
 check(refreshFirst.await(5,TimeUnit.SECONDS))
 val pendingPin=thread{delayedPin=runCatching{repo.changePin("2468","8642","8642")}.exceptionOrNull()}
 check(pinInFlight.await(5,TimeUnit.SECONDS));refreshRelease.countDown();firstRefresh.join(6000)
 ck("delayed refresh preserves in-flight replacement metadata",!firstRefresh.isAlive&&
  JSONObject(SecureStore.records.getValue("session")).getJSONObject("pendingPasscode").getString("state")=="inflight")
 val secondRefresh=thread{delayedRefresh=runCatching{repo.refreshSession()}.exceptionOrNull()}
 check(refreshLate.await(5,TimeUnit.SECONDS));repo.logout();lateRelease.countDown();pinRelease.countDown();secondRefresh.join(6000);pendingPin.join(6000)
 ck("logout fences delayed refresh and passcode responses",delayedRefresh is ContractFailure&&delayedPin is ContractFailure&&repo.current()==null&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 val rejectedRefreshStarted=CountDownLatch(1);val releaseRejectedRefresh=CountDownLatch(1);val rejectedPinStarted=CountDownLatch(1);val releaseRejectedPin=CountDownLatch(1)
 var refreshAfterRotation:Throwable?=null;var pinAfterRotation:Throwable?=null
 api.handler={req->when{
  req.path.endsWith("/session")->{rejectedRefreshStarted.countDown();check(releaseRejectedRefresh.await(5,TimeUnit.SECONDS));throw ApiFailure("session_unavailable",401)}
  req.path.endsWith("/passcode")->{rejectedPinStarted.countDown();check(releaseRejectedPin.await(5,TimeUnit.SECONDS));
   JSONObject().put("reauthenticationRequired",false).put("expiresAt",System.currentTimeMillis()+600000).toString()}
  else->happy(req)
 }}
 val rejectedRefresh=thread{refreshAfterRotation=runCatching{repo.refreshSession()}.exceptionOrNull()}
 check(rejectedRefreshStarted.await(5,TimeUnit.SECONDS));val rejectedPin=thread{pinAfterRotation=runCatching{repo.changePin("2468","8642","8642")}.exceptionOrNull()}
 check(rejectedPinStarted.await(5,TimeUnit.SECONDS));releaseRejectedRefresh.countDown();rejectedRefresh.join(6000);releaseRejectedPin.countDown();rejectedPin.join(6000)
 ck("old-session 401 retains candidate while rotation may have committed",refreshAfterRotation is ApiFailure&&
  (refreshAfterRotation as ApiFailure).uncertain&&pinAfterRotation is ApiFailure&&(pinAfterRotation as ApiFailure).uncertain&&
  repo.current()==null&&JSONObject(SecureStore.records.getValue("session")).getJSONObject("pendingPasscode").getString("state")=="inflight")
 api.handler={req->if(req.path.endsWith("/session"))session(t=req.token!!) else happy(req)}
 ck("candidate resolves delayed old-session 401 without new PIN",repo.restore()?.id=="admin-1")
 api.handler=happy;repo.logout();repo.login("0780000001","2468")
 val failedSecond=NativeRepository(Context(),api,"group-1")
 api.handler={req->if(req.path.endsWith("/session/login"))throw ApiFailure("invalid_credentials",401) else happy(req)}
 ck("failed login in a second repository preserves the first session",runCatching{failedSecond.login("0780000001","0000")}.isFailure&&repo.current()!=null&&
  JSONObject(SecureStore.records.getValue("session")).getString("token")==token)
 api.handler=happy;repo.logout()
 val lateLoginEntered=CountDownLatch(1);val releaseLateLogin=CountDownLatch(1);var lateLoginFailure:Throwable?=null
 api.handler={req->when{
  req.path.endsWith("/session/login")->{lateLoginEntered.countDown();check(releaseLateLogin.await(5,TimeUnit.SECONDS));session(t="f".repeat(64))}
  req.path.endsWith("/logout")->signedOut()
  else->happy(req)
 }}
 val lateLogin=thread{lateLoginFailure=runCatching{failedSecond.login("0780000001","2468")}.exceptionOrNull()}
 check(lateLoginEntered.await(5,TimeUnit.SECONDS));repo.logout();releaseLateLogin.countDown();lateLogin.join(6000)
 ck("superseded login never installs a late bearer",lateLoginFailure is ContractFailure&&repo.current()==null&&failedSecond.current()==null&&"session" !in SecureStore.records)
 ck("superseded returned bearer remains only in the revocation journal",JSONObject(SecureStore.records.getValue("session-revocations"))
  .getJSONArray("entries").getJSONObject(0).getString("token")=="f".repeat(64))
 ck("late returned bearer can be revoked",failedSecond.retryPendingSignOuts())
 api.handler=happy;repo.login("0780000001","2468")
 val crossReadEntered=CountDownLatch(1);val crossReadRelease=CountDownLatch(1);var crossReads=0;var crossFailure:Throwable?=null;var observedChanges=0
 val detachCross=repo.observeProcessSession{observedChanges++}
 val otherActivity=NativeRepository(Context(),api,"group-1")
 ck("another repository can restore the shared encrypted session",otherActivity.restore()?.id=="admin-1")
 ck("same-bearer reattachment preserves the first activity",repo.current()?.id=="admin-1"&&observedChanges==0)
 api.handler={req->when{
  req.path.endsWith("/session")->{crossReads++;if(crossReads==1){crossReadEntered.countDown();check(crossReadRelease.await(5,TimeUnit.SECONDS))};session(t=req.token!!)}
  req.path.endsWith("/logout")->signedOut()
  else->happy(req)
 }}
 val crossThread=thread{crossFailure=runCatching{repo.refreshSession()}.exceptionOrNull()}
 check(crossReadEntered.await(5,TimeUnit.SECONDS))
 otherActivity.logout();crossReadRelease.countDown();crossThread.join(6000)
 ck("another repository logout fences a delayed old refresh",!crossThread.isAlive&&crossFailure is ContractFailure&&
  repo.current()==null&&otherActivity.current()==null&&"session" !in SecureStore.records)
 detachCross();api.handler=happy;repo.login("0780000001","2468")
 val secondSame=NativeRepository(Context(),api,"group-1");check(secondSame.restore()!=null)
 api.handler={req->when{
  req.path.endsWith("/passcode")->JSONObject().put("reauthenticationRequired",false).put("expiresAt",System.currentTimeMillis()+600000).toString()
  req.path.endsWith("/session")->session(t=req.token!!)
  req.path.endsWith("/logout")->signedOut()
  else->happy(req)
 }}
 secondSame.changePin("2468","8642","8642")
 ck("same-owner activity can reattach to an active rotated session",repo.current()==null&&
  repo.reattachSameOwner("admin-1","group-1")?.id=="admin-1"&&repo.current()!=null&&secondSame.current()!=null)
 secondSame.changePin("8642","1357","1357")
 val reattachEntered=CountDownLatch(1);val reattachRelease=CountDownLatch(1);var reattachFailure:Throwable?=null
 api.handler={req->if(req.path.endsWith("/session")){reattachEntered.countDown();check(reattachRelease.await(5,TimeUnit.SECONDS));session(t=req.token!!)}
  else if(req.path.endsWith("/logout"))signedOut() else happy(req)}
 val reattachThread=thread{reattachFailure=runCatching{repo.reattachSameOwner("admin-1","group-1")}.exceptionOrNull()}
 check(reattachEntered.await(5,TimeUnit.SECONDS));secondSame.logout();reattachRelease.countDown();reattachThread.join(6000)
 ck("concurrent logout prevents a late same-owner reattachment",!reattachThread.isAlive&&reattachFailure is ContractFailure&&repo.current()==null&&
  secondSame.current()==null&&"session" !in SecureStore.records)
 api.handler=happy;repo.login("0780000001","2468")
 val peer=NativeRepository(Context(),api,"group-1");check(peer.restore()!=null)
 api.handler={req->when{
  req.path.endsWith("/passcode")->JSONObject().put("reauthenticationRequired",false).put("expiresAt",System.currentTimeMillis()+600000).toString()
  req.path.endsWith("/session")->throw ApiFailure("connection_unavailable",0)
  req.path.endsWith("/logout")->signedOut()
  else->happy(req)
 }}
 peer.changePin("2468","8642","8642")
 ck("failed reattachment clears only the stale local operator",runCatching{repo.reattachSameOwner("admin-1","group-1")}.isFailure&&repo.current()==null)
 peer.logout()
 api.handler={req->if(req.path.endsWith("/session/login"))session("other-admin",t="b".repeat(64)) else if(req.path.endsWith("/logout"))signedOut() else happy(req)}
 val switchedAccount=NativeRepository(Context(),api,"group-1");switchedAccount.login("0780000001","2468")
 ck("stale logout cannot revoke a later different account",runCatching{repo.logout()}.exceptionOrNull() is ContractFailure&&
  switchedAccount.current()?.id=="other-admin"&&JSONObject(SecureStore.records.getValue("session")).getString("token")=="b".repeat(64))
 switchedAccount.logout();api.handler=happy;repo.login("0780000001","2468")
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
 api.handler=happy
 val sourceBody="M-Money: amafaranga 10,000 RWF; inyemezabwishyu 🧾"
 val reviewReason="  Gusuzuma inyemezabwishyu y’umunyamuryango 🧾  "
 val rawResult=JSONObject().put("id","sms-1").put("sender","").put("at","2026-11-08T10:00:00Z").put("rawBody",sourceBody).put("transactionId",JSONObject.NULL).toString()
 api.handler={r->if(r.path.endsWith("/reveal"))rawResult else happy(r)}
 val storageBefore=SecureStore.records.toMap();val rawCalls=api.calls.size
 ck("explicit raw disclosure preserves Unicode and original body",repo.raw("sms-1",reviewReason).body==sourceBody)
 val reveal=api.calls.last()
 ck("raw disclosure uses only bounded POST reason",reveal.method=="POST"&&reveal.path=="/v1/burimunsi/sms/sms-1/reveal"&&reveal.body?.length()==1&&reveal.body?.getString("reason")==reviewReason.trim())
 ck("raw disclosure never writes plaintext or reason to storage",SecureStore.records==storageBefore&&repo.pending()==null&&api.calls.size==rawCalls+1)
 for(reason in listOf("short","        ","valid reason\n","x".repeat(1001),"valid reason\u0085")){
  val calls=api.calls.size
  ck("invalid raw reason cannot dispatch",runCatching{repo.raw("sms-1",reason)}.isFailure&&api.calls.size==calls)
 }
 ck("Unicode reason counts code points",RawDisclosureInput.reason("🧾".repeat(1000))!=null&&RawDisclosureInput.reason("🧾".repeat(1001))==null)
 api.handler={throw ApiFailure("connection_unavailable",0,true)}
 val lostCalls=api.calls.size
 ck("unknown disclosure never reads cache or creates a replay journal",runCatching{repo.raw("sms-1",reviewReason)}.exceptionOrNull() is ApiFailure&&api.calls.size==lostCalls+1&&repo.pending()==null&&SecureStore.records==storageBefore)
 api.handler={r->if(r.path.endsWith("/allocate"))throw ApiFailure("connection_unavailable",0,true) else happy(r)}
 runCatching{repo.allocate(p,m,"Verified original membership")}
 val originalPending=repo.pending()!!;val originalJournal=SecureStore.records["pending-command"]
 api.handler={r->if(r.path.endsWith("/reveal"))rawResult else happy(r)}
 repo.raw("sms-1",reviewReason)
 ck("audited reveal cannot overwrite an unresolved financial command",repo.pending()?.requestId==originalPending.requestId&&repo.pending()?.state==OperationState.UNKNOWN&&SecureStore.records["pending-command"]==originalJournal)
 repo.clearOperator();SecureStore.reset()
 val bootstrapApi=ApiClient("same-physical-installation").also{it.resolvesLoginScope=true}
 var selectedGroup="first-approved-group"
 var selectedId="first-real-operator"
 bootstrapApi.handler={r->when{
  r.path.endsWith("/session/login")->JSONObject(session(selectedId)).put("groupId",selectedGroup).toString()
  r.path.endsWith("/session")->JSONObject(session(selectedId)).put("groupId",selectedGroup).toString()
  r.path.endsWith("/session/logout")->"{\"signedOut\":true}"
  else->error("Unexpected dynamic scope request")
 }}
 val dynamic=NativeRepository(Context(),bootstrapApi)
 ck("fresh native install has no preapproved collection",dynamic.boundCollectionId==null&&dynamic.current()==null)
 dynamic.login("0780000001","2468")
 ck("phone PIN resolves real collection after successful credentials",dynamic.boundCollectionId=="first-approved-group"&&dynamic.current()?.id==selectedId)
 ck("bootstrap never submits cached group as account authority",!bootstrapApi.calls.last().contractContext.containsKey("groupId"))
 dynamic.refreshSession()
 ck("native reads assert only server-bound collection",bootstrapApi.calls.last().contractContext["groupId"]=="first-approved-group")
 dynamic.logout();selectedGroup="second-approved-group";selectedId="second-real-operator"
 dynamic.login("0780000001","2468")
 ck("same installation can sign in as another approved operator and scope",dynamic.boundCollectionId==selectedGroup&&dynamic.current()?.id==selectedId&&bootstrapApi.calls.last().token==null)
 val dynamicRestored=NativeRepository(Context(),bootstrapApi)
 ck("dynamic restoration revalidates stored scope at the server",dynamicRestored.restore()?.id==selectedId&&bootstrapApi.calls.last().path.endsWith("/session")&&bootstrapApi.calls.last().contractContext["groupId"]==selectedGroup)
 dynamicRestored.clearOperator();bootstrapApi.handler={session()}
 val unbound=NativeRepository(Context(),bootstrapApi)
 ck("missing server collection cannot create native login authority",runCatching{unbound.login("0780000001","2468")}.exceptionOrNull() is ApiFailure&&unbound.boundCollectionId==null&&unbound.current()==null)
 println("RESULT: $checks actual Repository/DTO/OperationStore checks passed; in-memory storage, synthetic transport and test-only JSON adapter, not Android Keystore/HTTP/JSON or device execution.")
}
