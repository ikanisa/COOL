package rw.ikanisa.burimunsi.core

enum class Role { ADMIN, STAFF }
enum class Route { LOGIN, HOME, PAYMENTS, PAYMENT, MEMBERS, MEMBER, SMS, SETTINGS }
enum class Capability(val key: String) {
    READ("records.read"), ENROLL("members.enroll"), ALLOCATE("payments.allocate"), STAFF("staff.manage"), SMS("sms.read"), GATEWAY("gateway.manage")
}
data class Operator(val id: String, val name: String, val phone: String, val role: Role, val capabilities: Set<String>, val expiresAt: Long) {
    fun hasSameAccess(other: Operator) = id == other.id && role == other.role && capabilities == other.capabilities
}
data class Payment(val id: String, val payerNameRaw: String, val payerPhoneRaw: String, val amountRwf: Long?, val atRaw: String,
    val ftId: String?, val state: String, val version: Long, val memberId: String? = null, val memberPhone: String? = null, val sourceId: String? = null,
    val direction:String="incoming",val outcome:String="successful",val sourceKind:String="canonical",
    val feeRwf:Long?=null,val walletBalanceAfterRwf:Long?=null,val paymentReference:String?=null)
data class Member(val id: String, val name: String, val phone: String, val balanceRwf: Long, val active: Boolean, val version: Long)
data class AllocationReadback(val paymentId: String, val fromVersion: Long)
data class LedgerRow(val id: String, val transactionId: String?, val amountRwf: Long, val atRaw: String, val ftId: String, val payerNameRaw: String,val state:String?=null)
data class SmsRow(val id: String, val sender: String, val at: String, val preview: String, val state: String, val transactionId: String?, val simLabel:String?=null)
data class RawSms(val id: String, val sender: String, val at: String, val body: String, val transactionId: String?, val simLabel:String?=null) {
    override fun toString() = "RawSms(redacted)"
}
data class StaffAccount(val id: String, val name: String, val phone: String, val active: Boolean, val version: Long, val capabilities: Set<String>)
data class AuditRow(val id: String, val action: String, val at: String)
data class PaymentEvent(val id:String,val transactionId:String,val kind:String,val recordedAt:String,val amountRwf:Long?,val memberId:String?)
data class Page<T>(val items: List<T>, val nextCursor: String?, val totalCount: Int, val revision: String, val asOf: String)
data class Home(val balanceRwf: Long, val todayRwf: Long, val memberCount: Int, val unallocatedCount: Int, val recent: List<Payment>, val asOf: String, val unallocatedAmountRwf:Long?=null)
data class GatewayStatus(val authorized: Boolean, val captureEnabled: Boolean, val subscriptionId: Int?, val pending: Int, val oldest: String?, val lastCapture: String?, val lastUpload: String?, val problem: String?,
    /** Public receiving code from this installation's scoped pairing snapshot, if supplied. */
    val pairedReceivingCode:String?=null,
    /** Approved sender snapshot, scoped to this receiver and its expiry. */
    val approvedSenders:List<String>?=null,
    /** Observation status never claims a verified receiving account. */
    val observationMode:Boolean=false)

object Access {
    fun allows(operator: Operator?, capability: Capability, now: Long, receiverVariant: Boolean = false): Boolean {
        if (operator == null || now >= operator.expiresAt || capability.key !in operator.capabilities) return false
        if (capability in setOf(Capability.STAFF, Capability.SMS, Capability.GATEWAY) && operator.role != Role.ADMIN) return false
        if (capability in setOf(Capability.SMS, Capability.GATEWAY) && !receiverVariant) return false
        return true
    }
    fun routeAllowed(operator: Operator?, route: Route, now: Long, receiverVariant: Boolean): Boolean = when(route) {
        Route.LOGIN -> true
        Route.SMS -> allows(operator, Capability.SMS, now, receiverVariant)
        else -> allows(operator, Capability.READ, now)
    }
}
