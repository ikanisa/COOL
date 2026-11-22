package rw.ikanisa.burimunsi.core

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.Locale

/** Stable product display contract. Never use this to rewrite raw receipt evidence or wire values. */
object ExactDisplay {
    private val kigali = ZoneId.of("Africa/Kigali")
    private val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    private val wire = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})")
    private fun language(tag: String): String = if (Locale.forLanguageTag(tag).language == "rw") "rw" else "en"
    /** Exact signed integer grouping, including Long.MIN_VALUE; unknown is never fabricated as zero. */
    fun amount(value: Long?, languageTag: String = "en", positiveSign: Boolean = false): String? {
        if (value == null) return null
        val digits = value.toString().removePrefix("-")
        val separator = if (language(languageTag) == "rw") "." else ","
        val grouped = digits.reversed().chunked(3).joinToString(separator).reversed()
        return (if (value < 0) "−" else if (value > 0 && positiveSign) "+" else "") + grouped
    }
    fun date(value: LocalDate, languageTag: String = "en"): String? {
        if (value.year !in 1..9999) return null
        return if (language(languageTag) == "rw") "%02d/%02d/%04d".format(Locale.ROOT, value.dayOfMonth, value.monthValue, value.year)
        else "${value.dayOfMonth} ${months[value.monthValue - 1]} ${value.year}"
    }
    /** Require explicit seconds and known offset. Reject lenient corrections and ambiguous local time. */
    fun timestamp(raw: String?, languageTag: String = "en"): String? {
        if (raw == null || raw.length !in 20..35 || !wire.matches(raw) || raw.endsWith("-00:00")) return null
        val parsed = try { OffsetDateTime.parse(raw, DateTimeFormatter.ISO_OFFSET_DATE_TIME.withResolverStyle(ResolverStyle.STRICT)) }
            catch (_: java.time.DateTimeException) { return null }
        if (parsed.year !in 1..9999 || kotlin.math.abs(parsed.offset.totalSeconds) > 14 * 3600) return null
        val local = parsed.toInstant().atZone(kigali)
        val date = date(local.toLocalDate(), languageTag) ?: return null
        val fraction = raw.substringAfter('.', "").takeWhile { it in '0'..'9' }
        val clock = local.format(DateTimeFormatter.ofPattern("HH:mm:ss", Locale.ROOT)) +
            if (fraction.isEmpty()) "" else "." + local.nano.toString().padStart(9, '0').take(fraction.length)
        // Historical Kigali offsets must not be mislabeled as today's CAT.
        val offset = if (local.offset.totalSeconds == 0) "+00:00" else local.offset.id
        return "$date $clock UTC$offset"
    }
    fun epochTimestamp(epochMillis: Long?, languageTag: String = "en"): String? =
        epochMillis?.let { timestamp(Instant.ofEpochMilli(it).toString(), languageTag) }
}
