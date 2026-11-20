package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SubscriptionManager
import app.cool.mobile.BuildConfig
import org.json.JSONObject
import java.net.URI
import java.time.Instant
import rw.ikanisa.burimunsi.core.*

/** Format filtering and subscription routing are not carrier authentication or posting authority. */
internal object BuriCapturePolicy {
    private fun profileReady(binding: JSONObject?): Boolean = binding != null &&
        ReceiverCollectionScope.collection(binding.opt("collection_id")) != null &&
        BuriReceiverProfile.current(binding)!=null
    fun senderAllowed(binding:JSONObject?,sender:String):Boolean = BuriReceiverProfile.senderAllowed(binding,sender)
    fun sourceAllowed(binding:JSONObject?,sender:String,body:String):Boolean {
        val profile=BuriReceiverProfile.current(binding)?:return false
        return ReceiptCandidate.accepts(sender,body,profile)
    }
    fun routeConfigured(binding: JSONObject?, subscription: Int?): Boolean =
        binding != null && profileReady(binding) && binding.optionalInt("subscription_id") != null &&
        subscription != null && binding.optionalInt("subscription_id") == subscription
    private fun activeSubscriptions(context: Context): Set<Int>? = try {
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) null
        else context.getSystemService(SubscriptionManager::class.java)?.activeSubscriptionInfoList
            ?.map { it.subscriptionId }?.toSet()
    } catch (_: Exception) { null }
    fun route(context: Context, binding: JSONObject?, subscription: Int?): BuriReceiverReliability.Route =
        BuriReceiverReliability.route(binding?.optionalInt("subscription_id"), subscription,
            activeSubscriptions(context), profileReady(binding))
    fun deviceReady(context: Context, binding: JSONObject?): Boolean =
        route(context, binding, binding?.optionalInt("subscription_id")) == BuriReceiverReliability.Route.ACCEPT
    /** The separately protected paired receiver survives operator logout. A
     * current operator is required by GatewayFactory to explicitly resume it;
     * the server revalidates this credential and custodian on every upload. */
    private fun ready(context: Context, store: MomoGatewayStore, state: JSONObject, expectedBinding: JSONObject?,
        controlRecovery: Boolean = false): Boolean {
        val binding = state.optJSONObject("binding")
        val endpoint = URI(BuildConfig.RECEIVER_API_BASE_URL)
        return !BuildConfig.IS_QUALIFICATION && BuildConfig.IS_GATEWAY && BuildConfig.FLAVOR == "internal_receiver" &&
            endpoint.scheme == "https" && !endpoint.host.isNullOrBlank() && endpoint.rawUserInfo == null &&
            endpoint.rawQuery == null && endpoint.rawFragment == null &&
            endpoint.toString().trimEnd('/') == "https://${BuildConfig.COLLECT_API_HOST}${BuildConfig.COLLECT_API_PATH_PREFIX}" &&
            binding != null && profileReady(binding) && (controlRecovery || !state.has("control_transition")) &&
            state.opt("receiver_retired") != true && state.opt("retirement_pending") != true &&
            listOf("receiver_retired", "retirement_pending").all { !state.has(it) || state.opt(it) is Boolean } &&
            state.optString("reason") !in setOf("authorization_required", "receiver_retired") &&
            (state.opt("gateway_token") as? String)?.matches(Regex("[a-f0-9]{64}")) == true &&
            (state.opt("installation_id") as? String)?.let {
                Values.requestId(it); it == store.existingInstallationId() && BuriReceiverProfile.installation(binding)==it
            } == true && BuriReceiverReliability.bindingMatches(binding::opt, binding::opt) &&
            listOf("id", "owner_user_id", "receiving_account_id").all { ReceiverCollectionScope.collection(binding.opt(it)) != null } &&
            (expectedBinding == null || BuriReceiverReliability.bindingMatches(expectedBinding::opt, binding::opt)) &&
            arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS, Manifest.permission.READ_PHONE_STATE)
                .all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED } && deviceReady(context, binding)
    }
    fun receiverReady(context: Context, expectedBinding: JSONObject? = null): Boolean = try {
        val store = MomoGatewayStore(context)
        store.withReceiverState { ready(context, store, it, expectedBinding) } == true
    } catch (_: Exception) { false }
    /** Checks eligibility only; it never admits capture while a transition marker exists. */
    fun receiverReadyForControl(context: Context, expectedBinding: JSONObject): Boolean = try {
        val store = MomoGatewayStore(context)
        store.withReceiverState { ready(context, store, it, expectedBinding, controlRecovery = true) } == true
    } catch (_: Exception) { false }
    fun uploadsAdmitted(context: Context): Boolean = try {
        val store = MomoGatewayStore(context)
        store.withReceiverState { ready(context, store, it, null) && it.opt("capture_enabled") == true &&
            it.optString("reason") != "permission_required" } == true
    } catch (_: Exception) { false }
    fun uploadRequestAdmitted(context: Context, token: String?, body: JSONObject?): Boolean = try {
        val store = MomoGatewayStore(context)
        store.withReceiverState { state ->
            val binding = state.optJSONObject("binding")
            ready(context, store, state, null) && state.opt("capture_enabled") == true &&
                state.optString("reason") != "permission_required" && binding != null &&
                token == state.opt("gateway_token") && body != null &&
                body.opt("gateway_binding_id") == binding.opt("id") &&
                body.opt("gateway_binding_version") == binding.opt("version") &&
                body.opt("subscription_id") == binding.opt("subscription_id") &&
                captureSourceAllowed(body,binding) &&
                (body.opt("raw_sender") as? String)?.let{sender->
                    (body.opt("raw_body") as? String)?.let{text->sourceAllowed(binding,sender,text)}
                }==true
        } == true
    } catch (_: Exception) { false }
    /** Inbox observations are synced as incomplete, never as PDU-complete live captures. */
    private fun captureSourceAllowed(body:JSONObject,binding:JSONObject):Boolean = when {
        body.opt("source_mode")=="live" && body.opt("complete")==true -> true
        body.opt("source_mode")=="catch_up" && body.opt("complete")==false -> try {
            val received=Instant.parse(body.getString("inbox_received_at"))
            val paired=Instant.parse(binding.getString("created_at"))
            !received.isBefore(paired)
        } catch (_:Exception) { false }
        else -> false
    }
    fun retain(context: Context, binding: JSONObject?, sender: String, body: String, subscription: Int?): Boolean {
        if (!routeConfigured(binding, subscription)) return false
        return if(sourceAllowed(binding,sender,body))true else {
            val prefs = context.getSharedPreferences("burimunsi_capture_health", Context.MODE_PRIVATE)
            synchronized(this) {
                prefs.edit().putLong("rejected_receipt_count", prefs.getLong("rejected_receipt_count", 0) + 1).apply()
            }
            false // Never log or retain OTPs, unrelated bodies, phone numbers or parser excerpts.
        }
    }
}
