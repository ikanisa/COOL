package android.provider

import android.content.Intent
class SmsMessage(val originatingAddress:String?,val timestampMillis:Long,val messageBody:String?)
object Telephony {object Sms {object Intents {
    const val SMS_RECEIVED_ACTION="android.provider.Telephony.SMS_RECEIVED"
    @Suppress("UNCHECKED_CAST") fun getMessagesFromIntent(intent:Intent)=(intent.values["messages"] as? Array<SmsMessage>)?:emptyArray()
}}}
