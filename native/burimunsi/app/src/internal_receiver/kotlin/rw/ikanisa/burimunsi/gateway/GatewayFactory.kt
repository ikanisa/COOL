package rw.ikanisa.burimunsi.gateway

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import app.cool.mobile.BuildConfig
import app.cool.mobile.receiver_sms.*
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import rw.ikanisa.burimunsi.core.GatewayStatus

object GatewayFactory {
    fun installationId(context:Context):String=MomoGatewayStore(context).installationId()
    fun create(context:Context):GatewayPort=CollectGateway(context.applicationContext)
}
private class CollectGateway(private val context:Context):GatewayPort {
    private val store=MomoGatewayStore(context)
    override fun bound():Boolean=if(BuildConfig.IS_QUALIFICATION)false else try{store.binding()?.let{it.optString("collection_id")==BuildConfig.BURI_GROUP_ID&&BuildConfig.BURI_GROUP_ID.isNotBlank()}==true}catch(_:Exception){false}
    override fun status():GatewayStatus {
        val s=store.read();val b=s?.optJSONObject("binding")
        val meta=if(b!=null)SmsQueueStore(context).queueMetadata(b.getString("owner_user_id")) else 0 to null
        val reason=when{
            BuildConfig.IS_QUALIFICATION->"qualification_offline"
            !bound()->"pairing_required"
            requiredPermissions().any{context.checkSelfPermission(it)!=PackageManager.PERMISSION_GRANTED}->"permission_required"
            !BuriCapturePolicy.deviceReady(context,b)->"sim_or_profile_uncertain"
            s?.optString("reason")?.isNotBlank()==true->s.optString("reason")
            !MomoGatewayPolicy.gatewayUploadsAdmitted()->"uploads_on_hold"
            else->null
        }
        return GatewayStatus(bound(),s?.optBoolean("capture_enabled")==true,b?.optionalInt("subscription_id"),meta.first,meta.second,
            s?.optString("last_sms_at")?.ifBlank{null},s?.optString("last_upload_at")?.ifBlank{null},reason)
    }
    override fun requiredPermissions()=arrayOf(Manifest.permission.RECEIVE_SMS,Manifest.permission.READ_SMS,Manifest.permission.READ_PHONE_STATE)
    override fun start(){if(!BuildConfig.IS_QUALIFICATION&&bound())MomoGatewayJobs.ensure(context)}
    override fun setPaused(paused:Boolean){
        check(!BuildConfig.IS_QUALIFICATION) { "Offline qualification only" }
        check(bound());val snapshot=store.read()!!;val binding=snapshot.getJSONObject("binding");val queue=SmsQueueStore(context)
        if(paused){store.update{it.put("capture_enabled",false)};check(queue.disablePreservingQueue(binding.getString("owner_user_id")));return}
        check(snapshot.optString("reason")!="authorization_required") { "Reauthorization required" }
        check(requiredPermissions().all{context.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED})
        check(BuriCapturePolicy.deviceReady(context,binding)) { "Authorized SIM or receipt profile unavailable" }
        val baseline=if(snapshot.has("inbox_binding_baseline"))snapshot.getLong("inbox_binding_baseline")else MomoGatewayRecovery(context).latestInboxId()
        check(queue.enableForOwner(binding.getString("owner_user_id")))
        store.update{it.put("capture_enabled",true).put("reason","");if(baseline!=null)it.put("inbox_binding_baseline",baseline)}
        start()
    }
    override fun pair(code:String){
        check(!BuildConfig.IS_QUALIFICATION) { "Offline qualification only" }
        require(code.trim().length in 4..128)
        // Capture must be paused before requesting a replacement; retained sources keep
        // the original binding. Server must enforce the singleton and operator approval.
        if(store.binding()!=null){
            store.update{it.put("capture_enabled",false)}
            val queue=SmsQueueStore(context)
            check(queue.disablePreservingQueue(store.owner()))
            // Unreadable evidence throws. Preserve old binding, token and cursor.
            check(BuriReceiverReliability.canReplace(queue.queueMetadata(store.owner()).first,false)) {
                "Reconcile retained sources before replacing this device binding"
            }
        }
        val response=MomoGatewayHttp().request("pair",body=JSONObject().put("pairing_code",code.trim()).put("installation_id",store.installationId()))
        val b=response.getJSONObject("binding");val token=response.getString("gateway_token")
        // Required scoped extension; the legacy response cannot silently authorize this app.
        check(b.getString("collection_id")==BuildConfig.BURI_GROUP_ID && BuildConfig.BURI_GROUP_ID.isNotBlank())
        check(b.getString("id").isNotBlank()&&b.getInt("version")>0&&b.getString("owner_user_id").isNotBlank()&&b.getString("receiving_account_id").isNotBlank()&&b.optionalInt("subscription_id")!=null&&token.isNotBlank())
        val queue=SmsQueueStore(context);check(queue.enableForOwner(b.getString("owner_user_id")));check(queue.disablePreservingQueue(b.getString("owner_user_id")))
        store.update{
            it.optJSONObject("binding")?.let{old->val history=it.optJSONArray("previous_bindings")?:JSONArray();history.put(old);it.put("previous_bindings",history)}
            it.put("binding",b).put("gateway_token",token).put("paired_at",Instant.now().toString()).put("capture_enabled",false).put("reason","").put("inbox_checkpoint",0L)
            it.remove("inbox_binding_baseline")
        }
    }
}
