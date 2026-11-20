package rw.ikanisa.burimunsi.core

/** Supported grammar is intentionally narrow. Unknown formats never become payments. */
data class ReceiptProfile(val version: String, val senders: Set<String>, val offsetMinutes: Int)
data class ReceiptFacts(
    val amountRwf: Long,
    val payerNameRaw: String,
    val payerPhoneRaw: String,
    val fullPayerPhone: String?,
    val atRaw: String,
    val at: String,
    val walletBalanceRwf: Long,
    val ftId: String,
    val rawBody: String,
    val rawSender: String,
    val profileVersion: String,
)
object ReceiptParser {
    const val VERSION = "burimunsi.mmoney.en-ftid.v1"
    private val amount = "(0|[1-9][0-9]*|[1-9][0-9]{0,2}(?:,[0-9]{3})+)"
    private val grammar = Regex("^You have received $amount RWF from ([^()\\r\\n]{1,160}) \\(([^()\\r\\n]{1,40})\\) at ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\\. Balance: $amount RWF\\. FT Id: ([0-9]{6,32})\\.$")
    private val forbidden = Regex("\\b(otp|one[- ]time|password|passcode|verification|activation code|security code|pin)\\b", RegexOption.IGNORE_CASE)
    fun parse(sender: String, body: String, complete: Boolean, profile: ReceiptProfile): ReceiptFacts {
        checkContract(profile.version.isNotBlank() && profile.version != "unverified" && profile.senders.isNotEmpty(), "provider_profile_required")
        checkContract(sender in profile.senders, "unsupported_sender")
        checkContract(complete, "incomplete_receipt")
        checkContract(body.length in 1..2048 && !Regex("[\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]").containsMatchIn(body) && !forbidden.containsMatchIn(body), "unsupported_receipt")
        val m = grammar.matchEntire(body) ?: throw ContractFailure("unsupported_receipt")
        val name = m.groupValues[2]
        checkContract(name == name.trim() && name.isNotEmpty(), "invalid_payer")
        val phone = m.groupValues[3]
        val masked = Regex("\\*{3,}[0-9]{3,4}").matches(phone)
        val full = if (masked) null else Values.phone(phone)
        return ReceiptFacts(Values.amount(m.groupValues[1]), name, phone, full, m.groupValues[4],
            Values.at(m.groupValues[4], profile.offsetMinutes), Values.amount(m.groupValues[5], false),
            m.groupValues[6], body, sender, profile.version)
    }
}
sealed class CaptureDecision {
    data class Retain(val facts: ReceiptFacts) : CaptureDecision()
    data class Reject(val code: String) : CaptureDecision()
}
object CaptureFilter {
    fun evaluate(sender: String, body: String, complete: Boolean, expectedSubscription: Int?, observedSubscription: Int?, profile: ReceiptProfile): CaptureDecision {
        if (expectedSubscription == null || observedSubscription == null || expectedSubscription != observedSubscription) return CaptureDecision.Reject("sim_uncertain")
        return try { CaptureDecision.Retain(ReceiptParser.parse(sender, body, complete, profile)) }
        catch (e: ContractFailure) { CaptureDecision.Reject(e.code) }
    }
}
