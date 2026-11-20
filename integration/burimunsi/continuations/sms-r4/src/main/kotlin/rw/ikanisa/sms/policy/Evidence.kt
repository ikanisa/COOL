package rw.ikanisa.sms.policy

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.Collections

enum class Contract { BURI_COLLECT_V2, MMONEY_LEDGER_V1 }
enum class InputMode { LIVE, PROVIDER }
enum class Completeness { PDU_SET, PROVIDER_BODY_ONLY, INCOMPLETE, AMBIGUOUS, UNSUPPORTED }
internal fun <T> frozen(items: Collection<T>): List<T> = Collections.unmodifiableList(ArrayList(items))
object EvidenceHash {
    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }
    fun wellFormed(s: String): Boolean {
        var i = 0
        while (i < s.length) {
            val c = s[i++]
            if (c == '\u0000') return false
            if (c.isHighSurrogate()) {
                if (i == s.length || !s[i++].isLowSurrogate()) return false
            } else if (c.isLowSurrogate()) return false
        }
        return true
    }
    fun utf8(s: String): String? = if (wellFormed(s)) sha256(s.toByteArray(Charsets.UTF_8)) else null
    /** Framed UTF-16 code units distinguish null/empty/invalid originals without lossy replacement. */
    fun framed(values: List<String?>): String {
        val md = MessageDigest.getInstance("SHA-256")
        for (value in values) {
            md.update(ByteBuffer.allocate(4).putInt(value?.length ?: -1).array())
            value?.forEach { c -> md.update((c.code ushr 8).toByte()); md.update(c.code.toByte()) }
        }
        return md.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    fun identity(value: String): Boolean = value.isNotBlank() && value.length <= 128 && wellFormed(value) &&
        value.none { it.code < 32 || it.code == 127 }
}
/** Decoded metadata, not a PDU decoder or proof of carrier origin. Hex is an immutable byte representation. */
data class SmsPart(
    val sequence: Int?, val total: Int?, val reference: Int?, val referenceBits: Int?,
    val sender: String?, val body: String?, val serviceCentreMillis: Long?, val subscriptionId: Int?,
    val dcs: Int? = 0, val applicationPort: String? = null,
    val envelopeValidated: Boolean = false, val pduHex: String? = null,
) {
    override fun toString() = "SmsPart(sequence=$sequence,total=$total)"
}
class SmsInput(val mode: InputMode, val format: String?, parts: List<SmsPart>) {
    val parts = frozen(parts)
    val fingerprint = EvidenceHash.framed(listOf(mode.name, format) + this.parts.flatMap {
        listOf(it.sequence?.toString(), it.total?.toString(), it.reference?.toString(), it.referenceBits?.toString(),
            it.sender, it.body, it.serviceCentreMillis?.toString(), it.subscriptionId?.toString(),
            it.dcs?.toString(), it.applicationPort, it.envelopeValidated.toString(), it.pduHex)
    })
    override fun toString() = "SmsInput(mode=$mode,parts=${parts.size},evidence=$fingerprint)"
}
class Assembly internal constructor(val input: SmsInput, val completeness: Completeness,
                                     val body: String?, val sender: String?, val reason: String) {
    override fun toString() = "Assembly(completeness=$completeness,reason=$reason)"
}
object MultipartPolicy {
    const val MAX_PARTS = 255
    const val MAX_UTF8_BYTES = 65536
    fun inspect(input: SmsInput): Assembly {
        fun fail(c: Completeness, r: String) = Assembly(input,c,null,null,r)
        val p = input.parts
        if (p.size !in 1..MAX_PARTS) return fail(Completeness.INCOMPLETE,"PART_COUNT")
        if (input.mode == InputMode.PROVIDER) {
            if (p.size != 1 || p[0].body == null || p[0].sender.isNullOrBlank())
                return fail(Completeness.INCOMPLETE,"PROVIDER_ROW")
            val body = p[0].body!!
            if (!validBody(body)) return fail(Completeness.UNSUPPORTED,"BODY_ENCODING_OR_SIZE")
            return Assembly(input,Completeness.PROVIDER_BODY_ONLY,body,p[0].sender,"NO_PDU_COMPLETENESS")
        }
        if (input.format != "3gpp" || p.any { !it.envelopeValidated })
            return fail(Completeness.UNSUPPORTED,"UNVALIDATED_ENVELOPE")
        if (p.any { it.body == null || it.sender.isNullOrBlank() || it.serviceCentreMillis == null || it.serviceCentreMillis <= 0 })
            return fail(Completeness.INCOMPLETE,"MISSING_DECODED_FIELD")
        if (p.map { it.sender }.distinct().size != 1 || p.map { it.serviceCentreMillis }.distinct().size != 1 ||
            p.map { it.subscriptionId }.distinct().size != 1 || p.map { it.dcs }.distinct().size != 1 ||
            p.map { it.applicationPort }.distinct().size != 1)
            return fail(Completeness.AMBIGUOUS,"MIXED_PART_METADATA")
        // Only uncompressed general GSM7/UCS2 text. No data-port or binary SMS admission.
        if (p.any { it.dcs == null || it.dcs !in 0..31 || ((it.dcs shr 2) and 3) !in setOf(0,2) || it.applicationPort != null })
            return fail(Completeness.UNSUPPORTED,"NON_TEXT_OR_CODING")
        if (p.any { it.pduHex == null || it.pduHex.length !in 2..8192 || !Regex("(?:[0-9a-fA-F]{2})+").matches(it.pduHex) })
            return fail(Completeness.UNSUPPORTED,"PDU_EVIDENCE_REQUIRED")
        val first = p.first()
        if (p.any { it.total != first.total || it.reference != first.reference || it.referenceBits != first.referenceBits })
            return fail(Completeness.AMBIGUOUS,"MIXED_CONCATENATION")
        if (first.total !in 1..MAX_PARTS || first.total != p.size) return fail(Completeness.INCOMPLETE,"MISSING_PARTS")
        if (p.any { it.sequence == null || it.sequence !in 1..p.size } || p.map { it.sequence }.toSet().size != p.size)
            return fail(Completeness.AMBIGUOUS,"DUPLICATE_OR_INVALID_SEQUENCE")
        if (first.reference == null) {
            if (p.size != 1 || first.referenceBits != null) return fail(Completeness.AMBIGUOUS,"MISSING_CONCAT_REFERENCE")
        } else if (first.referenceBits !in setOf(8,16) || first.reference !in 0..(if (first.referenceBits == 8) 255 else 65535))
            return fail(Completeness.AMBIGUOUS,"INVALID_CONCAT_REFERENCE")
        if (p.sumOf { it.body!!.length.toLong() } > MAX_UTF8_BYTES || p.any { !EvidenceHash.wellFormed(it.body!!) })
            return fail(Completeness.UNSUPPORTED,"BODY_ENCODING_OR_SIZE")
        val body = p.sortedBy { it.sequence }.joinToString("") { it.body!! }
        if (!validBody(body)) return fail(Completeness.UNSUPPORTED,"BODY_ENCODING_OR_SIZE")
        return Assembly(input,Completeness.PDU_SET,body,first.sender,"COMPLETE")
    }
    private fun validBody(s: String): Boolean = s.isNotEmpty() && s.length <= MAX_UTF8_BYTES &&
        EvidenceHash.wellFormed(s) && s.toByteArray(Charsets.UTF_8).size <= MAX_UTF8_BYTES
}
