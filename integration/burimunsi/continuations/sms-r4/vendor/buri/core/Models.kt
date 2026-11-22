package rw.ikanisa.burimunsi.core

enum class Role { ADMIN, STAFF }
enum class Route { LOGIN, HOME, PAYMENTS, PAYMENT, MEMBERS, MEMBER, SMS, SETTINGS }
enum class Capability(val key: String) {
    READ("records.read"), ENROLL("members.enroll"), ALLOCATE("payments.allocate"), STAFF("staff.manage"), SMS("sms.read"), GATEWAY("gateway.manage")
}
data class Operator(val id: String, val name: String, val phone: String, val role: Role, val capabilities: Set<String>, val expiresAt: Long)
data class Payment(val id: String, val payerNameRaw: String, val payerPhoneRaw: String, val amountRwf: Long, val atRaw: String,
    val ftId: String, val state: String, val version: Long, val memberId: String? = null, val memberPhone: String? = null, val sourceId: String? = null)
data class Member(val id: String, val name: String, val phone: String, val balanceRwf: Long, val active: Boolean, val version: Long)
data class LedgerRow(val id: String, val transactionId: String?, val amountRwf: Long, val atRaw: String, val ftId: String, val payerNameRaw: String)
data class SmsRow(val id: String, val sender: String, val at: String, val preview: String, val state: String, val transactionId: String?)
data class RawSms(val id: String, val sender: String, val at: String, val body: String, val transactionId: String?)
data class StaffAccount(val id: String, val name: String, val phone: String, val active: Boolean, val version: Long, val capabilities: Set<String>)
data class AuditRow(val id: String, val action: String, val at: String)
data class PaymentEvent(val id:String,val transactionId:String,val kind:String,val recordedAt:String,val amountRwf:Long?,val memberId:String?)
data class Page<T>(val items: List<T>, val nextCursor: String?, val totalCount: Int, val revision: String, val asOf: String)
data class Home(val balanceRwf: Long, val todayRwf: Long, val memberCount: Int, val unallocatedCount: Int, val recent: List<Payment>, val asOf: String)
data class GatewayStatus(val authorized: Boolean, val captureEnabled: Boolean, val subscriptionId: Int?, val pending: Int, val oldest: String?, val lastCapture: String?, val lastUpload: String?, val problem: String?)

object Access {
    fun allows(operator: Operator?, capability: Capability, now: Long, receiverVariant: Boolean = false, boundGateway: Boolean = false): Boolean {
        if (operator == null || now >= operator.expiresAt || capability.key !in operator.capabilities) return false
        if (capability in setOf(Capability.STAFF, Capability.SMS, Capability.GATEWAY) && operator.role != Role.ADMIN) return false
        if (capability in setOf(Capability.SMS, Capability.GATEWAY) && (!receiverVariant || !boundGateway)) return false
        return true
    }
    fun routeAllowed(operator: Operator?, route: Route, now: Long, receiverVariant: Boolean, boundGateway: Boolean): Boolean = when(route) {
        Route.LOGIN -> true
        Route.SMS -> allows(operator, Capability.SMS, now, receiverVariant, boundGateway)
        else -> allows(operator, Capability.READ, now)
    }
}
