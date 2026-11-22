package app.cool.mobile.receiver_sms

import android.content.Context
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.ObservationOwner
import rw.ikanisa.burimunsi.core.ReceiptCandidate
import rw.ikanisa.burimunsi.core.Values
import java.time.Instant

/** Unknown or paused legacy ownership never becomes authority for a new source. */
internal object ObservationLegacyOwnership {
    enum class Decision { OWNED, UNOWNED, HOLD }
    private fun classifyLocked(context:Context,store:MomoGatewayStore,state:JSONObject?,owner:ObservationOwner,id:Long,
        receivedAt:Long?,sender:String,body:String,subscription:Int?):Decision {
        if(state?.has("control_transition")==true)return Decision.HOLD
        if(state==null)return Decision.UNOWNED
        if(!state.has("binding"))return if(state.opt("receiver_retired")==true||state.opt("retirement_pending")==true)Decision.HOLD else Decision.UNOWNED
        val binding=state.optJSONObject("binding")?:return Decision.HOLD
        if(binding.opt("collection_id")!=owner.collectionId)return Decision.HOLD
        return store.withCurrentBinding(binding){
            val current=store.read()?:return@withCurrentBinding Decision.HOLD
            val verified=current.optJSONObject("binding")?:return@withCurrentBinding Decision.HOLD
            val profile=BuriReceiverProfile.current(verified)?:return@withCurrentBinding Decision.HOLD
            if(!ReceiptCandidate.accepts(sender,body,profile))return@withCurrentBinding Decision.UNOWNED
            when(BuriCapturePolicy.route(context,verified,subscription)){
                BuriReceiverReliability.Route.OTHER_SIM->Decision.UNOWNED
                BuriReceiverReliability.Route.HOLD_SIM,BuriReceiverReliability.Route.HOLD_PROFILE->Decision.HOLD
                BuriReceiverReliability.Route.ACCEPT->{
                    val created=runCatching{Instant.parse(verified.getString("created_at")).toEpochMilli()}.getOrNull()
                    val baseline=if(current.has("inbox_binding_baseline"))current.getLong("inbox_binding_baseline")else null
                    if(receivedAt==null||created==null)Decision.HOLD
                    else if(BuriReceiverReliability.inboxAfterBinding(id,baseline,receivedAt,created))Decision.OWNED else Decision.UNOWNED
                }
            }
        }?:Decision.HOLD
    }
    /** The callback includes any queue write and cursor advance; do not perform network I/O here. */
    fun <T> withDecision(context:Context,owner:ObservationOwner,id:Long,receivedAt:Long?,sender:String,body:String,
        subscription:Int?,action:(Decision)->T):T? = try {
        val app=context.applicationContext;val store=MomoGatewayStore(app)
        store.withObservationState{state->action(classifyLocked(app,store,state,owner,id,receivedAt,sender,body,subscription))}
    }catch(_:Exception){null}
    fun classify(context:Context,owner:ObservationOwner,id:Long,receivedAt:Long?,sender:String,body:String,subscription:Int?):Decision =
        withDecision(context,owner,id,receivedAt,sender,body,subscription){it}?:Decision.HOLD

    /** Lock order is legacy receiver, then observation/session; no network under this lock. */
    fun <T> withoutControlTransition(context:Context,action:()->T):T? = try {
        MomoGatewayStore(context.applicationContext).withObservationState{state->
            if(state?.has("control_transition")==true)null else action()
        }
    }catch(_:Exception){null}
    fun controlTransitionClear(context:Context):Boolean = withoutControlTransition(context){true}==true

    /** A routing match alone is not proof that the canonical receiver retained this row. */
    fun retained(context:Context,sender:String,body:String,serviceCentreAt:Long?,receivedAt:Long?,subscription:Int?):Boolean = try {
        val app=context.applicationContext;val store=MomoGatewayStore(app)
        store.withObservationState{state->
            val binding=state?.optJSONObject("binding")?:return@withObservationState false
            val installation=store.existingInstallationId()?:return@withObservationState false
            val at=serviceCentreAt?.takeIf{it>0}?:receivedAt?.takeIf{it>0}?:return@withObservationState false
            val bindingId=binding.getString("id");val version=binding.getInt("version")
            val captureId=MomoGatewayPolicy.captureId(installation,bindingId,sender,body,at,subscription)
            SmsQueueStore(app).hasGatewaySource(binding.getString("owner_user_id"),captureId,bindingId,version,Values.sha256(body))
        }
    }catch(_:Exception){false}
}
