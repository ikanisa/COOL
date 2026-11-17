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
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.QueuedObservationSnapshot
import rw.ikanisa.burimunsi.core.ReceiverCollectionScope
import rw.ikanisa.burimunsi.core.ReceiverRetirementAck
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.data.ApiFailure

object GatewayFactory {
    fun installationId(context:Context):String=MomoGatewayStore(context).installationId()
    fun create(context:Context,managedCollection:()->String?={null},pairGateway:(String,Boolean)->JSONObject={_,_->error("Sign in first")},
        retirementPending:()->Boolean={false},recoverRetirement:()->JSONObject?={null},authorizeControl:()->Boolean={false},
        refreshProfile:()->Boolean={BuriReceiverProfile.refresh(context.applicationContext)}):GatewayPort=
        CollectGateway(context.applicationContext,managedCollection,pairGateway,retirementPending,recoverRetirement,authorizeControl,refreshProfile)
}
private class CollectGateway(private val context:Context,private val managedCollection:()->String?,private val pairGateway:(String,Boolean)->JSONObject,
    private val hasRetirement:()->Boolean,private val readRetirement:()->JSONObject?,private val authorizeControl:()->Boolean,
    private val refreshProfile:()->Boolean):GatewayPort {
    private val store=MomoGatewayStore(context)
    /** A different or damaged legacy binding is not an unpaired installation. */
    private fun observationOnly():Boolean {
        val state=store.read()?:return true
        return !state.has("binding")&&!state.has("control_transition")&&state.optBoolean("receiver_retired")!=true&&state.optBoolean("retirement_pending")!=true
    }
    private fun pairedReceivingCode(binding:JSONObject?):String? =
        (binding?.opt("public_code") as? String)?.takeIf { value ->
            value.length in 1..128 && value==value.trim() && value.none { c ->
                c.isISOControl() || c in '\u202a'..'\u202e' || c in '\u2066'..'\u2069'
            }
        }
    override fun bound():Boolean=if(BuildConfig.IS_QUALIFICATION)false else try{store.read()?.optBoolean("receiver_retired")!=true&&store.binding()?.let{ReceiverCollectionScope.matches(it.opt("collection_id"),managedCollection())}==true}catch(_:Exception){false}
    override fun queuedObservations(query:String)=ObservationGateway.queued(context,query)
    override fun publishQueued(snapshot:QueuedObservationSnapshot,publish:()->Unit)=ObservationGateway.publishQueued(context,snapshot,publish)
    override fun foregroundChanged(resumed:Boolean)=BuriContinuousSupervisor.foregroundChanged(context,resumed)
    override fun continuousHealth()=BuriContinuousSupervisor.health()
    override fun stopContinuous()=BuriContinuousSupervisor.stop(context)
    override fun recoverContinuous()=BuriContinuousSupervisor.recover(context)
    override fun retirementPending():Boolean=if(BuildConfig.IS_QUALIFICATION)false else {
        val snapshot=store.read()
        snapshot?.optBoolean("receiver_retired")!=true&&(snapshot?.optBoolean("retirement_pending")==true||hasRetirement())
    }
    override fun status():GatewayStatus {
        if(!bound())return if(observationOnly())ObservationGateway.status(context) else
            GatewayStatus(false,false,null,0,null,null,null,"authorization_required")
        // An interrupted transition is recovered only to the safe paused state.
        // Different accounts cannot clear another owner's protected marker.
        if(store.read()?.has("control_transition")==true)runCatching{setPaused(true)}
        runCatching{refreshProfile()}
        val s=store.read();val b=s?.optJSONObject("binding")
        val meta=if(b!=null)SmsQueueStore(context).queueMetadata(b.getString("owner_user_id")) else 0 to null
        val reason=when{
            BuildConfig.IS_QUALIFICATION->"qualification_offline"
            !bound()->"pairing_required"
            s?.has("control_transition")==true->"control_unconfirmed"
            requiredPermissions().any{context.checkSelfPermission(it)!=PackageManager.PERMISSION_GRANTED}->"permission_required"
            BuriReceiverProfile.current(b)==null->"profile_unavailable"
            !BuriCapturePolicy.deviceReady(context,b)->"sim_or_profile_uncertain"
            s?.optString("reason")?.isNotBlank()==true->s.optString("reason")
            s?.opt("capture_enabled")==true&&!BuriCapturePolicy.uploadsAdmitted(context)->"uploads_on_hold"
            else->null
        }
        return GatewayStatus(bound(),s?.let{it.optBoolean("capture_enabled")&&!it.has("control_transition")}==true,b?.optionalInt("subscription_id"),meta.first,meta.second,
            s?.optString("last_sms_at")?.ifBlank{null},s?.optString("last_upload_at")?.ifBlank{null},reason,pairedReceivingCode(b),
            BuriReceiverProfile.current(b)?.senders?.sorted())
    }
    override fun requiredPermissions()=if(bound())arrayOf(Manifest.permission.RECEIVE_SMS,Manifest.permission.READ_SMS,Manifest.permission.READ_PHONE_STATE)
        else arrayOf(Manifest.permission.RECEIVE_SMS,Manifest.permission.READ_SMS)
    override fun start(){
        if(BuildConfig.IS_QUALIFICATION||retirementPending()||store.read()?.optBoolean("receiver_retired")==true)return
        if(!bound()&&!observationOnly())return
        try{ObservationGateway.start(context);BuriContinuousSupervisor.start(context)}catch(_:Exception){/* Durable observation state remains for a later retry. */}
        if(!bound())return
        // Pairing is the existing consent to receive. If Android permission or
        // the approved profile arrives later, resume once on the next foreground.
        if(store.read()?.opt("auto_resume_pending")==true&&authorizeControl()){
            val resumed=try{
                if(!refreshProfile())false else store.withReceiverState{current->
                    // A Pause or replacement may have happened during the profile request.
                    if(current.opt("auto_resume_pending")!=true)false else{setPaused(false);true}
                }==true
            }catch(_:Exception){false}
            if(resumed)return
        }
        if(BuriCapturePolicy.uploadsAdmitted(context))MomoGatewayJobs.ensure(context)
    }
    override fun sync(){
        check(!retirementPending()&&store.read()?.optBoolean("receiver_retired")!=true){"Receiving authorization unavailable"}
        if(!bound()){check(observationOnly()){ "Receiving scope unavailable" };ObservationGateway.sync(context);return}
        check(!BuildConfig.IS_QUALIFICATION&&!retirementPending()&&bound()&&authorizeControl()&&
            ReceiverCollectionScope.collection(managedCollection())!=null) { "Sign in to the receiving collection first" }
        check(requiredPermissions().all{context.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED})
        check(BuriCapturePolicy.deviceReady(context,store.binding())) { "Authorized SIM or receipt profile unavailable" }
        check(BuriCapturePolicy.uploadsAdmitted(context)) { "Resume the receiving gateway first" }
        MomoGatewayJobs.ensure(context)
        MomoGatewayJobs.signal(context)
        ObservationGateway.sync(context)
    }
    private fun acknowledgement(value:JSONObject):ReceiverRetirementAck {
        check(value.keys().asSequence().toSet()==setOf("retired","handoffId","requestId","reauthenticationRequired"))
        check(value.get("retired")==true&&value.get("reauthenticationRequired")==true&&value.get("handoffId") is String&&value.get("requestId") is String)
        return ReceiverRetirementAck(Values.requestId(value.getString("handoffId")),Values.requestId(value.getString("requestId")))
    }
    private fun applyRetirement(ack:ReceiverRetirementAck):Boolean {
        val snapshot=store.read()?:error("Receiving state unavailable")
        val prior=snapshot.optJSONObject("retirement_ack")
        if(prior!=null&&prior.optString("handoffId")==ack.handoffId&&prior.optString("requestId")==ack.requestId)return false
        val binding=snapshot.getJSONObject("binding")
        check(SmsQueueStore(context).disablePreservingQueue(binding.getString("owner_user_id")))
        store.update{
            // Preserve original binding/token, all retained evidence and cursors.
            check(BuriReceiverReliability.bindingMatches(binding::opt,it.getJSONObject("binding")::opt))
            it.put("capture_enabled",false).put("auto_resume_pending",false).put("receiver_retired",true).put("retirement_pending",false).put("reason","receiver_retired")
                .put("retirement_ack",JSONObject().put("handoffId",ack.handoffId).put("requestId",ack.requestId))
        }
        check(store.read()?.optBoolean("receiver_retired")==true&&store.read()?.optBoolean("capture_enabled")==false)
        return true
    }
    override fun recoverRetirement():ReceiverRetirementAck? {
        if(BuildConfig.IS_QUALIFICATION)return null
        val value=readRetirement()?:return null
        val ack=acknowledgement(value)
        return if(applyRetirement(ack))ack else null
    }
    override fun replace(code:String):ReceiverRetirementAck {
        check(!BuildConfig.IS_QUALIFICATION) { "Offline qualification only" }
        if(retirementPending())return recoverRetirement()?:throw ApiFailure("gateway_retirement_unconfirmed",503,true)
        check(store.read()?.has("control_transition")!=true){"Resolve receiving control first"}
        check(bound());require(Regex("[a-f0-9]{64}").matches(code.trim()))
        val binding=store.binding()?:error("Receiving state unavailable")
        store.update{check(!it.has("control_transition")){"Resolve receiving control first"};it.put("capture_enabled",false).put("auto_resume_pending",false)}
        val queue=SmsQueueStore(context);check(queue.disablePreservingQueue(binding.getString("owner_user_id")))
        check(BuriReceiverReliability.canReplace(queue.queueMetadata(binding.getString("owner_user_id")).first,false)) {
            "Reconcile retained sources before replacing this device binding"
        }
        // Pending derives from the durable repository intent, including a
        // terminal ACK not yet applied here. A crash before that intent exists
        // must leave only paused capture, never a fabricated unknown command.
        var received=false
        try{
            val value=pairGateway(code.trim(),true);received=true
            val ack=acknowledgement(value);applyRetirement(ack);return ack
        }catch(error:Exception){
            // Repository wraps every post-dispatch error as unconfirmed and
            // retains its proof. Only a definite local preflight may unpark UI.
            if(!received&&!hasRetirement()&&(error is rw.ikanisa.burimunsi.core.ContractFailure||
                    error is ApiFailure&&error.code!="gateway_retirement_unconfirmed")){
                store.update{it.put("retirement_pending",false)};throw error
            }
            throw ApiFailure("gateway_retirement_unconfirmed",503,true)
        }
    }
    private fun transitionMatches(marker:JSONObject,binding:JSONObject,owner:ObservationOwner):Boolean = try {
        marker.keys().asSequence().toSet()==setOf("kind","collectionId","accountId","bindingId","bindingVersion")&&
            marker.getString("kind") in setOf("pause","resume")&&marker.getString("collectionId")==owner.collectionId&&
            marker.getString("accountId")==owner.accountId&&marker.getString("bindingId")==binding.getString("id")&&
            marker.getInt("bindingVersion")==binding.getInt("version")
    }catch(_:Exception){false}
    override fun setPaused(paused:Boolean){
        check(!BuildConfig.IS_QUALIFICATION) { "Offline qualification only" }
        check(!retirementPending()&&store.read()?.optBoolean("receiver_retired")!=true){"Receiving authorization unavailable"}
        if(!bound()){
            store.withObservationState{
                check(!bound()&&observationOnly()){ "Receiving scope unavailable" }
                ObservationGateway.setPaused(context,paused)
            }
            if(paused)BuriContinuousSupervisor.halt(context,"paused")else BuriContinuousSupervisor.start(context)
            return
        }
        val complete=store.withReceiverState{snapshot->
            check(!retirementPending()&&bound())
            val binding=snapshot.getJSONObject("binding");val queue=SmsQueueStore(context)
            ObservationGateway.withControl(context){owner,config->
                check(ReceiverCollectionScope.matches(binding.opt("collection_id"),owner.collectionId))
                if(snapshot.has("control_transition"))
                    check(transitionMatches(snapshot.getJSONObject("control_transition"),binding,owner)){"Receiving control requires the original administrator"}
                if(!paused){
                    check(authorizeControl()&&ReceiverCollectionScope.collection(managedCollection())!=null) { "Sign in to the receiving collection first" }
                    check(snapshot.optString("reason")!="authorization_required") { "Reauthorization required" }
                    check(requiredPermissions().all{context.checkSelfPermission(it)==PackageManager.PERMISSION_GRANTED})
                    check(BuriCapturePolicy.deviceReady(context,binding)) { "Authorized SIM or receipt profile unavailable" }
                    check(BuriCapturePolicy.receiverReadyForControl(context,binding)) { "Receiving authorization unavailable" }
                }
                // If permission was unavailable at Pair, use the binding time for catch-up.
                val baseline=if(paused)null else if(snapshot.has("inbox_binding_baseline"))snapshot.getLong("inbox_binding_baseline")
                    else if(snapshot.opt("auto_resume_pending")==true)null else MomoGatewayRecovery(context).latestInboxId()
                val marker=JSONObject().put("kind",if(paused)"pause" else "resume")
                    .put("collectionId",owner.collectionId).put("accountId",owner.accountId)
                    .put("bindingId",binding.getString("id")).put("bindingVersion",binding.getInt("version"))
                store.update{current->
                    check(BuriReceiverReliability.bindingMatches(binding::opt,current.getJSONObject("binding")::opt))
                    if(current.has("control_transition"))check(transitionMatches(current.getJSONObject("control_transition"),binding,owner))
                    current.put("control_transition",marker)
                }
                check(store.read()?.optJSONObject("control_transition")?.let{transitionMatches(it,binding,owner)}==true)
                if(paused){
                    config.setPaused(owner,true);check(config.controlState(owner).paused)
                    store.update{it.put("capture_enabled",false).put("auto_resume_pending",false)}
                    check(queue.disablePreservingQueue(binding.getString("owner_user_id")))
                }else{
                    check(queue.enableForOwner(binding.getString("owner_user_id")))
                    store.update{it.put("capture_enabled",true).put("auto_resume_pending",false).put("reason","");if(baseline!=null)it.put("inbox_binding_baseline",baseline)}
                    config.setPaused(owner,false);check(!config.controlState(owner).paused)
                }
                val finished=store.read()?:error("Receiving control unavailable")
                check(finished.opt("capture_enabled")==!paused&&finished.optJSONObject("control_transition")?.let{transitionMatches(it,binding,owner)}==true)
                store.update{current->
                    check(BuriReceiverReliability.bindingMatches(binding::opt,current.getJSONObject("binding")::opt))
                    check(transitionMatches(current.getJSONObject("control_transition"),binding,owner))
                    current.remove("control_transition")
                }
                check(store.read()?.has("control_transition")==false)
                true
            }
        }
        check(complete==true){"Receiving control unavailable"}
        if(!paused)start()else BuriContinuousSupervisor.halt(context,"paused")
    }
    override fun pair(code:String){pairAuthorized(code);try{start()}catch(_:Exception){/* Pairing already succeeded; status remains available for recovery. */}}
    private fun pairAuthorized(code:String){
        check(!BuildConfig.IS_QUALIFICATION) { "Offline qualification only" }
        check(!retirementPending()) { "Check the original receiver retirement outcome" }
        check(store.read()?.has("control_transition")!=true){"Resolve receiving control first"}
        require(code.trim().length in 4..128)
        val expectedCollection=managedCollection()
        // Capture must be paused before requesting a replacement; retained sources keep
        // the original binding. Server must enforce the singleton and operator approval.
        if(store.binding()!=null){
            store.update{check(!it.has("control_transition")){"Resolve receiving control first"};it.put("capture_enabled",false).put("auto_resume_pending",false)}
            val queue=SmsQueueStore(context)
            check(queue.disablePreservingQueue(store.owner()))
            // Unreadable evidence throws. Preserve old binding, token and cursor.
            check(BuriReceiverReliability.canReplace(queue.queueMetadata(store.owner()).first,false)) {
                "Reconcile retained sources before replacing this device binding"
            }
        }
        // Record the inbox boundary before dispatch so messages arriving during
        // pairing can be caught up after the server binding's creation time.
        val inboxBaseline=if(context.checkSelfPermission(Manifest.permission.READ_SMS)==PackageManager.PERMISSION_GRANTED)
            runCatching{MomoGatewayRecovery(context).latestInboxId()}.getOrNull() else null
        val response=pairGateway(code.trim(),false)
        val b=response.getJSONObject("binding");val token=response.getString("gateway_token")
        check(!retirementPending()) { "Check the original receiver retirement outcome" }
        // Required scoped extension; the legacy response cannot silently authorize this app.
        check(ReceiverCollectionScope.matches(b.opt("collection_id"),expectedCollection)&&
            ReceiverCollectionScope.matches(b.opt("collection_id"),managedCollection()))
        check(b.getString("id").isNotBlank()&&b.getInt("version")>0&&b.getString("owner_user_id").isNotBlank()&&b.getString("receiving_account_id").isNotBlank()&&b.optionalInt("subscription_id")!=null&&token.isNotBlank())
        val queue=SmsQueueStore(context);check(queue.enableForOwner(b.getString("owner_user_id")));check(queue.disablePreservingQueue(b.getString("owner_user_id")))
        store.update{
            check(!it.has("control_transition")){"Resolve receiving control first"}
            it.optJSONObject("binding")?.let{old->val history=it.optJSONArray("previous_bindings")?:JSONArray();history.put(old);it.put("previous_bindings",history)}
            it.put("binding",b).put("gateway_token",token).put("paired_at",Instant.now().toString()).put("capture_enabled",false).put("auto_resume_pending",true).put("reason","").put("inbox_checkpoint",inboxBaseline?:0L)
            it.put("receiver_retired",false).put("retirement_pending",false)
            if(inboxBaseline==null)it.remove("inbox_binding_baseline") else it.put("inbox_binding_baseline",inboxBaseline)
        }
    }
}
