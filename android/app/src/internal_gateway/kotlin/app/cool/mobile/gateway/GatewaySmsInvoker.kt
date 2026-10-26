package app.cool.mobile.gateway

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import app.cool.mobile.BuildConfig

internal class AndroidGatewaySmsInvoker(private val context: Context, private val custody: GatewayInvocationCustody) : GatewaySmsInvoker {
    private fun manager(subscription: Int): SmsManager {
        if (BuildConfig.FLAVOR != "internal_gateway") throw GatewayStateException("gateway_flavor_required")
        return if (Build.VERSION.SDK_INT >= 31) context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscription)
            else SmsManager.getSmsManagerForSubscriptionId(subscription)
    }

    override fun divide(body: String, subscriptionId: Int): List<String> = manager(subscriptionId).divideMessage(body)

    override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) = synchronized(GatewayJournal.PROCESS_LOCK) {
        custody.requireEntered(record)
        if (grant.attemptId != record.attemptId || grant.deviceId != record.deviceId || grant.fence != record.fence ||
            sha256(grant.body) != record.bodySha256 || sha256(grant.destinationE164) != record.destinationSha256 ||
            parts.size != record.segments.size) throw GatewayStateException("gateway_grant_invalid")
        fun callback(index: Int, kind: CallbackKind): PendingIntent {
            val segment = record.segments[index]
            val id = if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId
            val intent = Intent(context, GatewaySmsCallbackReceiver::class.java)
                .setAction("app.cool.mobile.gateway.${kind.name}")
                .setData(Uri.parse("collect-gateway://callback/$id"))
                .putExtra("callback_id", id).putExtra("device_id", record.deviceId).putExtra("attempt_id", record.attemptId)
                .putExtra("fence", record.fence).putExtra("segment_index", index).putExtra("nonce", record.callbackNonce)
                .putExtra("callback_kind", kind.name)
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT)
        }
        val sent = ArrayList(parts.indices.map { callback(it, CallbackKind.SENT) })
        val delivery = ArrayList(parts.indices.map { callback(it, CallbackKind.DELIVERY) })
        manager(subscriptionId).sendMultipartTextMessage(grant.destinationE164, null, ArrayList(parts), sent, delivery)
    }
}
