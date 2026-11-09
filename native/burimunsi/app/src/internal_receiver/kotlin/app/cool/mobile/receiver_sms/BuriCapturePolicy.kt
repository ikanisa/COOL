package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SubscriptionManager
import app.cool.mobile.BuildConfig
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.*

/** Format filtering and subscription routing are not carrier authentication or posting authority. */
internal object BuriCapturePolicy {
    private fun profile() = ReceiptProfile(BuildConfig.RECEIPT_PROFILE_VERSION,
        setOf("M-Money"), BuildConfig.RECEIPT_UTC_OFFSET)
    private fun profileReady(binding: JSONObject?): Boolean = binding != null &&
        binding.optString("collection_id") == BuildConfig.BURI_GROUP_ID && BuildConfig.BURI_GROUP_ID.isNotBlank() &&
        BuildConfig.RECEIPT_PROFILE_VERSION.isNotBlank() && BuildConfig.RECEIPT_UTC_OFFSET in -840..840
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
    fun retain(context: Context, binding: JSONObject?, sender: String, body: String, subscription: Int?): Boolean {
        if (!routeConfigured(binding, subscription)) return false
        return try {
            ReceiptParser.parse(sender, body, true, profile()); true
        } catch (_: ContractFailure) {
            val prefs = context.getSharedPreferences("burimunsi_capture_health", Context.MODE_PRIVATE)
            synchronized(this) {
                prefs.edit().putLong("rejected_receipt_count", prefs.getLong("rejected_receipt_count", 0) + 1).apply()
            }
            false // Never log or retain OTPs, unrelated bodies, phone numbers or parser excerpts.
        }
    }
}
