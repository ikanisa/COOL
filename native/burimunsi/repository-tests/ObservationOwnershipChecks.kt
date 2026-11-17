package rw.ikanisa.burimunsi.observationownershiptests

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.data.ApiClient
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository
import rw.ikanisa.burimunsi.storage.SecureStore
import rw.ikanisa.burimunsi.core.SessionAuthority
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Test-only storage/transport doubles. No Android or server authority claim. */
fun main(){
    val context=Context();var actor="admin-a";var token="a".repeat(64);var role="admin"
    fun session()=JSONObject().put("token",token).put("expiresAt",System.currentTimeMillis()+3_600_000)
        .put("profile",JSONObject().put("id",actor).put("name","Synthetic Admin").put("phone","+250780000001")
            .put("role",role).put("capabilities",if(role=="admin")JSONArray().put("records.read").put("sms.read").put("gateway.manage")else JSONArray().put("records.read"))).toString()
    val api=ApiClient();api.installationProfile="internal_receiver"
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    val field=NativeRepository::class.java.getDeclaredField("processSessionAuthority");field.isAccessible=true
    val authority=field.get(null) as SessionAuthority
    check(authority.revision()==0L)
    SecureStore.records["session"]=JSONObject(session()).put("groupId","group-1").toString()
    check(NativeRepository.observationOwner(context)!=null&&NativeRepository.canRestoreObservationOwner(context))
    api.handler={throw ApiFailure("connection_unavailable",0)}
    val cold=NativeRepository(context,api,"group-1")
    check(runCatching{cold.restore()}.isFailure)
    check(NativeRepository.observationOwner(context)!=null&&NativeRepository.canRestoreObservationOwner(context))
    val expired=JSONObject(SecureStore.records.getValue("session")).put("expiresAt",System.currentTimeMillis()-1)
    SecureStore.records["session"]=expired.toString()
    check(NativeRepository.observationOwner(context)==null&&NativeRepository.canRestoreObservationOwner(context))
    check(NativeRepository.restorableObservationOwner(context)?.accountId==actor)
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    check(cold.restore()?.id==actor&&NativeRepository.observationOwner(context)!=null)
    cold.logout()
    println("PASS genuine cold/offline unexpired capture survives; expired metadata permits renewal only")
    SecureStore.reset()
    val repo=NativeRepository(context,api,"group-1")
    repo.login("0780000001","2468");val first=NativeRepository.observationOwner(context)?:error("Missing first session")
    check(NativeRepository.withObservationOwner(context,first){_,_->true}==true)
    val savedBeforeFailure=SecureStore.records.getValue("session")
    val renewedDeadline=System.currentTimeMillis()+7_200_000
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()
        else JSONObject(session()).put("expiresAt",renewedDeadline).toString()}
    SecureStore.dropWrite="session"
    check(runCatching{repo.refreshSession()}.isFailure)
    check(SecureStore.records.getValue("session")==savedBeforeFailure&&
        NativeRepository.observationOwner(context)==null&&!NativeRepository.canRestoreObservationOwner(context))
    SecureStore.dropWrite=null
    check(repo.restore()?.id==actor&&NativeRepository.observationOwner(context)!=null&&NativeRepository.canRestoreObservationOwner(context))
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    println("PASS a failed durable server-profile save quarantines retained future proof until confirmed revalidation")
    fun revocation(group:String,proof:String)=JSONObject().put("entries",JSONArray().put(JSONObject()
        .put("id","00000000-0000-4000-8000-000000000001").put("groupId",group).put("token",proof))).toString()
    SecureStore.records["session-revocations"]=revocation("another-group",token)
    check(NativeRepository.observationOwner(context)!=null)
    SecureStore.records["session-revocations"]=revocation("group-1",token)
    check(NativeRepository.observationOwner(context)==null&&!NativeRepository.canRestoreObservationOwner(context))
    SecureStore.records.remove("session-revocations")
    println("PASS matching retained revocation blocks capture before restore; another scope does not")
    repo.logout();check(NativeRepository.withObservationOwner(context,first){_,_->true}==null)
    repo.login("0780000001","2468");val sameAccount=NativeRepository.observationOwner(context)?:error("Missing renewed session")
    check(first.owner==sameAccount.owner&&first.generation!=sameAccount.generation)
    check(NativeRepository.withObservationOwner(context,first){_,_->true}==null)
    repo.logout();actor="admin-b";token="b".repeat(64);repo.login("0780000001","2468")
    val replacement=NativeRepository.observationOwner(context)?:error("Missing replacement session")
    check(replacement.owner!=first.owner&&NativeRepository.withObservationOwner(context,first){_,_->true}==null)
    // Simulate process death without clearing the saved record or queue. The
    // background repository must revalidate it before observation upload.
    SecureStore(context,"observation-queue-test").write("retained-ciphertext-fixture")
    (field.get(null) as SessionAuthority).retire{}
    check(NativeRepository.observationOwner(context)==null&&!NativeRepository.canRestoreObservationOwner(context))
    val afterRestart=NativeRepository(context,api,"group-1")
    val entered=CountDownLatch(1);val released=CountDownLatch(1);var restored:String?=null
    api.handler={request->if(request.path.endsWith("/session")){entered.countDown();check(released.await(5,TimeUnit.SECONDS));session()}
        else JSONObject().put("signedOut",true).toString()}
    val restoring=thread{restored=afterRestart.restore()?.id}
    check(entered.await(5,TimeUnit.SECONDS))
    check(authority.hasActive()&&NativeRepository.observationOwner(context)==null&&!NativeRepository.canRestoreObservationOwner(context))
    released.countDown();restoring.join(6000);check(!restoring.isAlive&&restored=="admin-b")
    check(NativeRepository.observationOwner(context)?.owner==replacement.owner)
    check(SecureStore(context,"observation-queue-test").read()=="retained-ciphertext-fixture")
    (field.get(null) as SessionAuthority).retire{}
    api.handler={request->if(request.path.endsWith("/session"))throw ApiFailure("invalid_session",401) else session()}
    val revoked=NativeRepository(context,api,"group-1")
    SecureStore.retainClear="session"
    check(runCatching{revoked.restore()}.isFailure)
    check("session" in SecureStore.records&&NativeRepository.observationOwner(context)==null&&!NativeRepository.canRestoreObservationOwner(context))
    SecureStore.retainClear=null
    check(runCatching{revoked.restore()}.isFailure&&"session" !in SecureStore.records)
    check(SecureStore(context,"observation-queue-test").read()=="retained-ciphertext-fixture")
    println("PASS invalidated future saved proof stays quarantined during delayed revalidation and failed deletion")
    SecureStore.reset();actor="admin-a";role="admin";token="e".repeat(64)
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    val changing=NativeRepository(context,api,"group-1");changing.login("0780000001","2468")
    api.handler={request->if(request.path.endsWith("/passcode"))throw ApiFailure("connection_unavailable",0,true)else session()}
    check(runCatching{changing.changePin("2468","8642","8642")}.isFailure)
    check(JSONObject(SecureStore.records.getValue("session")).getLong("expiresAt")>System.currentTimeMillis())
    check(NativeRepository.observationOwner(context)==null&&!NativeRepository.canRestoreObservationOwner(context))
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    val recovered=NativeRepository(context,api,"group-1");check(recovered.restore()?.id==actor)
    check(NativeRepository.observationOwner(context)!=null&&NativeRepository.canRestoreObservationOwner(context))
    recovered.logout()
    println("PASS in-flight uncertain PIN blocks capture; confirmed candidate recovery releases quarantine")
    // A lost logout response must not resurrect the saved session after a real
    // process handoff; the revocation proof survives independently of the queue.
    SecureStore.reset();actor="admin-a";role="admin";token="d".repeat(64)
    api.handler={request->if(request.path.endsWith("/logout"))throw ApiFailure("connection_unavailable",0,true)else session()}
    val beforeLogout=NativeRepository(context,api,"group-1")
    beforeLogout.login("0780000001","2468")
    SecureStore(context,"observation-queue-test").write("retained-ciphertext-fixture")
    val uncertain=runCatching{beforeLogout.logout()}.exceptionOrNull()
    check(uncertain is ApiFailure&&uncertain.uncertain&&"signed-out" in SecureStore.records&&"session-revocations" in SecureStore.records)
    (field.get(null) as SessionAuthority).retire{}
    val afterLogoutRestart=NativeRepository(context,api,"group-1")
    check(afterLogoutRestart.restore()==null&&NativeRepository.observationOwner(context)==null)
    check("session-revocations" in SecureStore.records&&SecureStore(context,"observation-queue-test").read()=="retained-ciphertext-fixture")
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    check(afterLogoutRestart.retryPendingSignOuts()&&"session-revocations" !in SecureStore.records)
    check(afterLogoutRestart.restore()==null&&SecureStore(context,"observation-queue-test").read()=="retained-ciphertext-fixture")
    println("PASS uncertain logout survives process restart and retries without restoring login or clearing queue")
    SecureStore.reset();actor="staff-a";role="staff";token="c".repeat(64)
    api.handler={request->if(request.path.endsWith("/logout"))JSONObject().put("signedOut",true).toString()else session()}
    val staff=NativeRepository(context,api,"group-1")
    check(staff.login("0780000001","2468").role==rw.ikanisa.burimunsi.core.Role.STAFF)
    check(api.installationProfile=="internal_receiver"&&NativeRepository.observationOwner(context)==null)
    staff.logout()
    println("PASS observation ownership fences logout, same-account relogin and account replacement")
    println("PASS synthetic process restart revalidates saved session; revocation stops ownership without clearing retained queue fixture")
    println("PASS both Admin and Staff sign in under the receiver profile; only Admin becomes observation owner")
}
