package rw.ikanisa.burimunsi.staffsecretchecks

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import java.util.UUID

/** Real repository and journal with isolated API/storage doubles. No phone, PIN,
 * request body, credential, or fake value is printed by these checks. */
fun main(){
    var checks=0
    fun ck(name:String,ok:Boolean){check(ok){name};println("PASS $name");checks++}
    val token="a".repeat(64);val fixturePin="4682"
    fun session()=JSONObject().put("token",token).put("expiresAt",System.currentTimeMillis()+3_600_000)
        .put("profile",JSONObject().put("id","admin-1").put("name","Synthetic Admin")
            .put("phone","+250780000001").put("role","admin").put("capabilities",JSONArray().put("records.read").put("staff.manage"))).toString()
    fun staff(action:String)=JSONObject().put("action",action).put("name","Synthetic Staff")
        .put("phone","+250780000002").put("pin",fixturePin).put("capabilities",JSONArray().put("records.read"))
        .also{if(action!="create")it.put("id","staff-1").put("expectedVersion",1)}
    fun proof(request:Request,state:String,operation:String):String {
        val v1=request.path.endsWith("/recovery")||request.path.endsWith("/staff-resolution")
        val id=if(v1)request.path.substringBeforeLast('/').substringAfterLast('/') else request.path.substringAfterLast('/')
        return if(v1)JSONObject().put("protocol","burimunsi.operation-recovery.v1")
            .put("requestId",id).put("state",state).put("originDigest",request.recoveryOrigin)
            .put("groupId","group-1").put("actorId","admin-1").put("installationId","installation-1")
            .also{if(state=="cancelled")it.put("operation",operation)}.toString()
        else JSONObject().put("contractVersion",2).put("requestId",id).put("groupId","group-1")
            .put("actorId","admin-1").put("state","committed").put("operation",operation)
            .put("financialState","not_applicable").toString()
    }
    fun fixture():Pair<NativeRepository,ApiClient>{
        SecureStore.reset();val api=ApiClient();api.handler={r->
            if(r.path.endsWith("/session/login")||r.path.endsWith("/session"))session() else error("Unexpected fixture route")
        }
        val repo=NativeRepository(Context(),api,"group-1");repo.login("0780000001","1357");return repo to api
    }
    fun redactedJournal():JSONObject {
        val stored=JSONObject(SecureStore.records.getValue("pending-command"))
        val payload=JSONObject(stored.getString("body"))
        check(payload.get("credentialOmitted")==true&&!payload.getJSONObject("body").has("pin"))
        check(stored.getString("bodySha256")==Values.sha256(stored.getString("body")))
        // Random request IDs and digests can contain the same four digits by
        // chance. Check for the actual serialized credential value instead.
        check(!stored.getString("body").contains("\"$fixturePin\"")&&
            !stored.toString().contains("\"$fixturePin\"")&&!stored.toString().contains(Values.sha256(fixturePin)))
        return payload
    }

    for(action in listOf("create","edit","reset")){
        val (repo,api)=fixture();var posts=0;var readbacks=0;var status="pending"
        api.handler={r->when{
            r.path.endsWith("/staff")->{
                posts++;check(r.body!!.getString("pin")==fixturePin)
                val redacted=redactedJournal()
                val original=JSONObject().put("method",r.method).put("path","/staff").put("body",staff(action)).toString()
                check(JSONObject(SecureStore.records.getValue("pending-command")).getString("bodySha256")!=Values.sha256(original))
                check(redacted.getJSONObject("body").getString("action")==action)
                throw ApiFailure("connection_unavailable",0,true)
            }
            r.path.contains("/operations/")->{readbacks++;proof(r,status,"burimunsi.staff.$action")}
            r.path.endsWith("/session")->session()
            else->error("Unexpected fixture route")
        }}
        check(runCatching{repo.staffAction(staff(action))}.isFailure)
        val original=repo.pending()!!;val saved=SecureStore.records.getValue("pending-command")
        ck("$action stores redacted intent and sends PIN only on first attempt",posts==1&&original.state==OperationState.UNKNOWN&&redactedJournal().getJSONObject("body").getString("action")==action)
        val restarted=NativeRepository(Context(),api,"group-1");check(restarted.restore()!=null)
        ck("$action restart reads pending status without replay",restarted.reconcilePending(ReadOnlyRecoveryRetry(original),0).getString("state")=="pending"&&posts==1&&readbacks==1&&SecureStore.records["pending-command"]==saved)
        ck("$action pending retry cannot redispatch",runCatching{restarted.retryPending()}.isFailure&&posts==1)
        status="committed";restarted.reconcilePending()
        ck("$action exact committed recovery clears only its own journal",restarted.pending()==null&&posts==1&&readbacks==3)
    }

    for(interruptState in listOf("PREPARED","SENT")){
        val (repo,api)=fixture();var posts=0;var interrupted=false
        api.handler={r->when{
            r.path.endsWith("/staff")->{posts++;"{}"}
            r.path.endsWith("/recovery")->proof(r,"pending","burimunsi.staff.create")
            else->session()
        }}
        SecureStore.afterRead={name,value->
            if(!interrupted&&name=="pending-command"&&value!=null&&JSONObject(value).getString("state")==interruptState){
                interrupted=true;throw InterruptedException("synthetic interruption")
            }
        }
        check(runCatching{repo.staffAction(staff("create"))}.isFailure);SecureStore.afterRead=null
        val op=repo.pending()!!;redactedJournal()
        ck("$interruptState interruption keeps redacted journal and sends nothing",interrupted&&posts==0&&op.state.name==interruptState)
        ck("$interruptState interruption cannot reconstruct a PIN for retry",runCatching{repo.retryPending()}.isFailure&&posts==0)
        ck("$interruptState interruption permits only original status read",repo.reconcilePending(ReadOnlyRecoveryRetry(op),0).getString("state")=="pending"&&repo.pending()?.requestId==op.requestId&&posts==0)
    }

    val (legacy,api)=fixture();var legacyPosts=0;var legacyStatus="pending"
    val legacyBody=JSONObject().put("method","POST").put("path","/staff").put("body",staff("create")).toString()
    val legacyOp=PendingOperation(UUID.randomUUID().toString(),Values.sha256(token),"POST /staff",legacyBody,Values.sha256(legacyBody),OperationState.UNKNOWN,1,"admin-1","group-1")
    AndroidOperationStore(Context()).save(legacyOp);val originalBytes=SecureStore.records.getValue("pending-command")
    api.handler={r->when{
        r.path.endsWith("/staff")->{legacyPosts++;error("Legacy command must never replay")}
        r.path.contains("/operations/")->proof(r,legacyStatus,"burimunsi.staff.create")
        else->session()
    }}
    ck("legacy encrypted-record format loads unchanged",legacy.pending()==legacyOp)
    ck("legacy pending recovery leaves original bytes unchanged",legacy.reconcilePending(ReadOnlyRecoveryRetry(legacyOp),0).getString("state")=="pending"&&SecureStore.records["pending-command"]==originalBytes&&legacyPosts==0)
    legacyStatus="committed";legacy.reconcilePending()
    ck("legacy committed recovery completes without replay",legacy.pending()==null&&legacyPosts==0)
    val (legacyPrepared,legacyApi)=fixture();var preparedPosts=0
    val prepared=legacyOp.copy(state=OperationState.PREPARED,attemptCount=0)
    AndroidOperationStore(Context()).save(prepared);val preparedBytes=SecureStore.records.getValue("pending-command")
    legacyApi.handler={r->when{
        r.path.endsWith("/staff")->{preparedPosts++;error("Legacy credential command must never replay")}
        r.path.endsWith("/recovery")->proof(r,"pending","burimunsi.staff.create")
        else->session()
    }}
    ck("legacy PREPARED staff credential cannot redispatch",runCatching{legacyPrepared.retryPending()}.isFailure&&preparedPosts==0&&SecureStore.records["pending-command"]==preparedBytes)
    ck("legacy PREPARED credential retains exact read-only recovery",legacyPrepared.reconcilePending(ReadOnlyRecoveryRetry(prepared),0).getString("state")=="pending"&&preparedPosts==0&&SecureStore.records["pending-command"]==preparedBytes)

    for(originalState in listOf(OperationState.PREPARED,OperationState.UNKNOWN)){
        val (recover,transport)=fixture();var state="pending";var staffPosts=0;var resolutionPosts=0;var loseAck=true
        val old=legacyOp.copy(requestId=UUID.randomUUID().toString(),state=originalState,attemptCount=if(originalState==OperationState.PREPARED)0 else 1)
        AndroidOperationStore(Context()).save(old);val bytes=SecureStore.records.getValue("pending-command")
        transport.handler={r->when{
            r.path.endsWith("/staff")->{staffPosts++;error("Never replay the staff command")}
            r.path.endsWith("/staff-resolution")->{
                resolutionPosts++;check(r.method=="POST"&&r.recoveryOrigin==old.sessionScope)
                check(r.body!!.keys().asSequence().toSet()==setOf("operation")&&r.body.getString("operation")=="burimunsi.staff.create")
                check(SecureStore.records["pending-command"]==bytes)
                state="cancelled";if(loseAck){loseAck=false;throw ApiFailure("connection_unavailable",0,true)}
                proof(r,state,"burimunsi.staff.create")
            }
            r.path.endsWith("/recovery")->proof(r,state,"burimunsi.staff.create")
            else->session()
        }}
        check(runCatching{recover.reconcilePending()}.isFailure)
        ck("$originalState lost cancellation acknowledgement keeps exact journal",recover.pending()==old&&SecureStore.records["pending-command"]==bytes&&staffPosts==0&&resolutionPosts==1)
        val out=recover.reconcilePending()
        ck("$originalState check recovers cancellation without replay",out.getString("state")=="cancelled"&&recover.pending()==null&&staffPosts==0&&resolutionPosts==1)
    }
    run {
        val (repo,api)=fixture();var staffPosts=0;var state="pending";var resolutionPosts=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{staffPosts++;throw ApiFailure("fresh_auth_required",403,false)}
            r.path.endsWith("/recovery")->proof(r,state,"burimunsi.staff.create")
            r.path.endsWith("/staff-resolution")->{resolutionPosts++;state="cancelled";proof(r,state,"burimunsi.staff.create")}
            else->session()
        }}
        val failure=runCatching{repo.staffAction(staff("create"))}.exceptionOrNull() as ApiFailure
        val op=repo.pending()!!;val bytes=SecureStore.records.getValue("pending-command")
        ck("stale sign-in retains the original unknown command",failure.code=="fresh_auth_required"&&op.state==OperationState.UNKNOWN&&staffPosts==1)
        ck("stale staff command cannot be replayed",runCatching{repo.retryPending()}.isFailure&&SecureStore.records["pending-command"]==bytes&&staffPosts==1)
        ck("stale staff command clears only after durable cancellation",repo.reconcilePending().getString("state")=="cancelled"&&repo.pending()==null&&staffPosts==1&&resolutionPosts==1)
    }
    fun blankEdit()=staff("edit").also{it.remove("pin")}
    for((code,status) in listOf("access_denied" to 403,"new_passcode_required" to 400,"duplicate_phone" to 409)){
        val (repo,api)=fixture();var edits=0;var reads=0;var resolutions=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;check(!r.body!!.has("pin"));throw ApiFailure(code,status,false)}
            r.path.endsWith("/recovery")->{reads++;proof(r,"pending","burimunsi.staff.edit")}
            r.path.endsWith("/staff-resolution")->{resolutions++;check(r.body!!.getString("operation")=="burimunsi.staff.edit");proof(r,"cancelled","burimunsi.staff.edit")}
            else->session()
        }}
        val failure=runCatching{repo.staffAction(blankEdit(),true)}.exceptionOrNull() as ApiFailure
        ck("$code closes only the proven cancelled blank-PIN edit",failure.code==code&&repo.pending()==null&&repo.current()!=null&&edits==1&&reads==1&&resolutions==1)
    }
    run {
        val (repo,api)=fixture();var edits=0;var resolutions=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;throw ApiFailure("access_denied",403,false)}
            r.path.endsWith("/recovery")->proof(r,"committed","burimunsi.staff.edit")
            r.path.endsWith("/staff-resolution")->{resolutions++;error("Committed operation cannot be cancelled")}
            r.path.contains("/operations/")->proof(r,"committed","burimunsi.staff.edit")
            else->session()
        }}
        val outcome=repo.staffAction(blankEdit(),true)
        ck("a proven committed edit is reported as success without a second edit",outcome.getString("state")=="committed"&&repo.pending()==null&&edits==1&&resolutions==0)
    }
    run {
        val (repo,api)=fixture();var edits=0;var reads=0;var resolutions=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;throw ApiFailure("access_denied",403,false)}
            r.path.endsWith("/recovery")->{reads++;proof(r,if(reads==1)"pending" else "committed","burimunsi.staff.edit")}
            r.path.endsWith("/staff-resolution")->{resolutions++;proof(r,"committed","burimunsi.staff.edit")}
            r.path.contains("/operations/")->proof(r,"committed","burimunsi.staff.edit")
            else->session()
        }}
        val outcome=repo.staffAction(blankEdit(),true)
        ck("a commitment racing resolution is rechecked before success",outcome.getString("state")=="committed"&&repo.pending()==null&&edits==1&&reads==2&&resolutions==1)
    }
    run {
        val (repo,api)=fixture();var edits=0;var resolutions=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;throw ApiFailure("access_denied",403,false)}
            r.path.endsWith("/recovery")->proof(r,"pending","burimunsi.staff.edit")
            r.path.endsWith("/staff-resolution")->{resolutions++;throw ApiFailure("connection_unavailable",0,true)}
            else->session()
        }}
        val failure=runCatching{repo.staffAction(blankEdit(),true)}.exceptionOrNull() as ApiFailure
        ck("unknown cancellation outcome retains the original edit without replay",failure.uncertain&&repo.pending()?.state==OperationState.UNKNOWN&&edits==1&&resolutions==1)
    }
    run {
        val (repo,api)=fixture();var edits=0;var resolutions=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;throw ApiFailure("access_denied",403,false)}
            r.path.endsWith("/recovery")->{repo.clearOperator();proof(r,"pending","burimunsi.staff.edit")}
            r.path.endsWith("/staff-resolution")->{resolutions++;error("Session changed")}
            else->session()
        }}
        val failure=runCatching{repo.staffAction(blankEdit(),true)}.exceptionOrNull()
        ck("session change stops automatic resolution and retains its journal",failure is ContractFailure&&failure.code=="session_changed"&&repo.pending()!=null&&repo.current()==null&&edits==1&&resolutions==0)
    }
    run {
        val (repo,api)=fixture();var edits=0;var recovery=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;throw ApiFailure("connection_unavailable",0,true)}
            r.path.contains("/operations/")->{recovery++;error("Ambiguous response is not a definite denial")}
            else->session()
        }}
        val failure=runCatching{repo.staffAction(blankEdit(),true)}.exceptionOrNull() as ApiFailure
        ck("ambiguous responses never trigger automatic cancellation",failure.uncertain&&repo.pending()!=null&&edits==1&&recovery==0)
    }
    run {
        val (repo,api)=fixture();var edits=0;var reads=0;var resolutions=0
        api.handler={r->when{
            r.path.endsWith("/staff")->{edits++;"{}"}
            r.path.endsWith("/recovery")->{reads++;throw ApiFailure("access_denied",403,false)}
            r.path.endsWith("/staff-resolution")->{resolutions++;error("Readback denial is not an edit denial")}
            else->session()
        }}
        val failure=runCatching{repo.staffAction(blankEdit(),true)}.exceptionOrNull() as ApiFailure
        ck("a denial during post-commit readback never triggers automatic cancellation",failure.code=="access_denied"&&repo.pending()!=null&&edits==1&&reads==1&&resolutions==0)
    }
    run {
        val (repo,api)=fixture();var edits=0
        api.handler={r->if(r.path.endsWith("/staff")){edits++;"{}"}else session()}
        val failure=runCatching{repo.staffAction(staff("edit"),true)}.exceptionOrNull()
        ck("automatic blank-PIN recovery cannot be selected for a credential-bearing request",failure is ContractFailure&&repo.pending()==null&&edits==0)
    }
    println("RESULT: $checks staff PIN journal checks passed with API/storage doubles; not Android Keystore or live-network proof.")
}
