package rw.ikanisa.sms.adapters.mmoney
import rw.ikanisa.sms.policy.*
import com.ikanisa.mmoney.core.SmsPolicy
import com.ikanisa.mmoney.core.MAX_RWF
import com.ikanisa.mmoney.core.ReferenceState
import com.ikanisa.mmoney.core.observeReferenceIdentity

/** Screened extraction candidates, not parsed financial facts. Original text is never normalized. */
class MmoneySmsClassifier: MessageClassifier {
    private val currency = Regex("(?i)\\b(?:RWF|FRW)\\b")
    private val token = Regex("(?i)(?<![\\p{L}\\p{N}.,+\\-])([+\\-]?[0-9][0-9.,]*)\\s*(?:RWF|FRW)\\b|\\b(?:RWF|FRW)\\s*([+\\-]?[0-9][0-9.,]*)(?![\\p{L}\\p{N}.,])")
    private val integer = Regex("(?:0|[1-9][0-9]*|[1-9][0-9]{0,2}(?:,[0-9]{3})+)")
    private val primary = Regex("(?i)\\byou (?:have )?(?:received|sent|paid|transferred|withdrawn|deposited)\\b|\\byour payment of\\b")
    override fun classify(assembly: Assembly): Classification {
        fun result(kind: ClassificationKind,code: String) = Classification(Contract.MMONEY_LEDGER_V1,kind,code,
            "sms-policy-r2/mmoney-candidate-v1",assembly.input.fingerprint)
        if (assembly.completeness !in setOf(Completeness.PDU_SET,Completeness.PROVIDER_BODY_ONLY)) return result(
            if (assembly.completeness == Completeness.AMBIGUOUS) ClassificationKind.AMBIGUOUS else ClassificationKind.INCOMPLETE,"INPUT_COMPLETENESS")
        if (!SmsPolicy.isEligibleSender(assembly.sender)) return result(ClassificationKind.UNSUPPORTED,"UNSUPPORTED_SENDER")
        val body = assembly.body ?: return result(ClassificationKind.INCOMPLETE,"BODY_REQUIRED")
        if (!SmsPolicy.mayUpload(body) || Regex("[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]").containsMatchIn(body))
            return result(ClassificationKind.UNSUPPORTED,"UNSUPPORTED_OR_SENSITIVE_BODY")
        val matches = token.findAll(body).toList()
        val amounts = matches.map { it.groupValues[1].ifEmpty { it.groupValues[2] } }
        if (amounts.isEmpty() || currency.findAll(body).count() != matches.size || amounts.any {
            !integer.matches(it) || it.replace(",","").toLongOrNull()?.let { n -> n in 0..MAX_RWF } != true
        }) return result(ClassificationKind.AMBIGUOUS,"AMBIGUOUS_AMOUNT_LITERAL")
        if (observeReferenceIdentity(body).state !in setOf(ReferenceState.ABSENT,ReferenceState.AGREED))
            return result(ClassificationKind.AMBIGUOUS,"AMBIGUOUS_REFERENCE_IDENTITY")
        if (primary.findAll(body).count() > 1) return result(ClassificationKind.AMBIGUOUS,"MULTIPLE_MOVEMENT_STATEMENTS")
        return result(ClassificationKind.SUPPORTED_CANDIDATE,"SCREENED_CANDIDATE_NOT_FINANCIAL_FACT")
    }
}
