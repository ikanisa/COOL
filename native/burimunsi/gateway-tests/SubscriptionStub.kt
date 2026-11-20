package android.telephony
import app.cool.mobile.receiver_sms.ReceiverFixture
class SubscriptionInfo(val subscriptionId:Int)
class SubscriptionManager{
 val activeSubscriptionInfoList:List<SubscriptionInfo>? get()=ReceiverFixture.subscriptions?.map{SubscriptionInfo(it)}
}
