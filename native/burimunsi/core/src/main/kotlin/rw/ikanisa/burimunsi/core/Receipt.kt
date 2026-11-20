package rw.ikanisa.burimunsi.core

import java.util.Locale

/** Supported grammar is intentionally narrow. Unknown formats never become payments. */
data class ReceiptProfile(val version: String, val senders: Set<String>, val offsetMinutes: Int,
    val incomingPrefixes:Set<String> = emptySet(),val currencyAliases:Set<String> = emptySet(),
    val transactionIdPrefixes:Set<String> = emptySet())
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
    private fun approved(sender:String,profile:ReceiptProfile) {
        checkContract(profile.version.isNotBlank() && profile.version != "unverified" && profile.senders.isNotEmpty(), "provider_profile_required")
        checkContract(profile.senders.any{it.lowercase(Locale.ROOT)==sender.lowercase(Locale.ROOT)}, "unsupported_sender")
    }
    fun parse(sender: String, body: String, complete: Boolean, profile: ReceiptProfile): ReceiptFacts {
        approved(sender,profile)
        checkContract(complete, "incomplete_receipt")
        return textFacts(sender,body,profile)
    }
    /** Local display only. Inbox text cannot prove PDU completeness or a receiving wallet. */
    internal fun inboxTextHint(sender:String,body:String,profile:ReceiptProfile):ReceiptFacts {
        approved(sender,profile);return textFacts(sender,body,profile)
    }
    private fun textFacts(sender:String,body:String,profile:ReceiptProfile):ReceiptFacts {
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
/** Intake only. These approved markers select candidate payment messages; the
 * server still extracts and validates source evidence before any ledger action. */
object ReceiptCandidate {
    private val secret=Regex("\\b(?:otp|one[ -]time|password|passcode|verification(?:[ -]code)?|activation[ -]code|security[ -]code|pin(?:[ -]code)?|authori[sz]ation[ -]code|mot\\s+de\\s+passe)\\b",RegexOption.IGNORE_CASE)
    private val controls=Regex("[\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]")
    fun accepts(sender:String,body:String,profile:ReceiptProfile):Boolean {
        val lists=listOf(profile.senders,profile.incomingPrefixes,profile.currencyAliases,profile.transactionIdPrefixes)
        if(profile.version.isBlank()||profile.version=="unverified"||lists.any{values->
            values.isEmpty()||values.size>30||values.any{it.length>160||it.trim().isEmpty()||it.any{c->c=='\r'||c=='\n'||c=='\u0000'}}
        })return false
        if(sender.length !in 1..96||profile.senders.none{it.lowercase(Locale.ROOT)==sender.lowercase(Locale.ROOT)}||body.isEmpty()||
            body.toByteArray(Charsets.UTF_8).size>8192||controls.containsMatchIn(body)||secret.containsMatchIn(body)||body.none{it in '0'..'9'})return false
        val folded=body.lowercase(Locale.ROOT)
        return listOf(profile.incomingPrefixes,profile.currencyAliases,profile.transactionIdPrefixes)
            .all{values->values.any{folded.contains(it.lowercase(Locale.ROOT))}}
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
