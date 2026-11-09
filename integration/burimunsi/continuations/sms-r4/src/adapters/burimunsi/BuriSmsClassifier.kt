package rw.ikanisa.sms.adapters.burimunsi
import rw.ikanisa.sms.policy.*
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.ReceiptParser
import rw.ikanisa.burimunsi.core.ReceiptProfile

/** Uses the pinned application's receipt grammar; never authorizes financial posting. */
class BuriSmsClassifier(profile: ReceiptProfile = ReceiptProfile(ReceiptParser.VERSION,setOf("M-Money"),120)): MessageClassifier {
    private val profile = profile.copy(senders=profile.senders.toSet())
    override fun classify(assembly: Assembly): Classification {
        fun result(kind: ClassificationKind,code: String) = Classification(Contract.BURI_COLLECT_V2,kind,code,
            "sms-policy-r2/buri/${profile.version}/${profile.offsetMinutes}",assembly.input.fingerprint)
        if (profile.version != ReceiptParser.VERSION || profile.senders != setOf("M-Money") || profile.offsetMinutes !in -840..840)
            return result(ClassificationKind.UNSUPPORTED,"UNSUPPORTED_PROFILE")
        if (assembly.completeness != Completeness.PDU_SET) return result(
            if (assembly.completeness == Completeness.AMBIGUOUS) ClassificationKind.AMBIGUOUS else ClassificationKind.INCOMPLETE,"PDU_COMPLETENESS_REQUIRED")
        val body = assembly.body ?: return result(ClassificationKind.INCOMPLETE,"BODY_REQUIRED")
        val sender = assembly.sender ?: return result(ClassificationKind.UNSUPPORTED,"SENDER_REQUIRED")
        return try {
            ReceiptParser.parse(sender,body,true,profile)
            result(ClassificationKind.SUPPORTED_RECEIPT,"SUPPORTED_RECEIPT_NOT_POSTING_AUTHORITY")
        } catch (e: ContractFailure) { result(ClassificationKind.UNSUPPORTED,e.code) }
    }
}
