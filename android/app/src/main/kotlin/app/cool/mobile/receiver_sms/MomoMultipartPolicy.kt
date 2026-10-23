package app.cool.mobile.receiver_sms

/** Minimal GSM SMS-DELIVER UDH reader. Unknown transports abstain rather than claiming completeness. */
object MomoMultipartPolicy {
    data class Part(val reference: Int?, val total: Int, val sequence: Int)
    fun part(pdu: ByteArray, format: String?): Part? {
        if (format != "3gpp") return null
        fun value(index: Int) = pdu[index].toInt() and 255
        return try {
            var cursor = 1 + value(0) // SMSC length excludes its own octet.
            val flags = value(cursor++)
            if (flags and 3 != 0) return null // Only incoming SMS-DELIVER.
            val addressLength = value(cursor++)
            cursor++ // Originating address type.
            cursor += (addressLength + 1) / 2
            cursor += 2 + 7 // Protocol, coding scheme and service-centre timestamp.
            value(cursor++) // User data length must exist.
            if (flags and 64 == 0) return Part(null, 1, 1)
            val end = cursor + 1 + value(cursor)
            cursor++
            if (end > pdu.size) return null
            var concatenation: Part? = null
            while (cursor < end) {
                val kind = value(cursor++)
                val length = value(cursor++)
                if (cursor + length > end) return null
                val parsed = when {
                    kind == 0 && length == 3 -> Part(value(cursor), value(cursor + 1), value(cursor + 2))
                    kind == 8 && length == 4 -> Part(value(cursor) * 256 + value(cursor + 1), value(cursor + 2), value(cursor + 3))
                    else -> null
                }
                if (parsed != null) {
                    if (concatenation != null) return null
                    concatenation = parsed
                }
                cursor += length
            }
            concatenation ?: Part(null, 1, 1)
        } catch (_: IndexOutOfBoundsException) { null }
    }

    fun complete(parts: List<Part?>): Boolean {
        if (parts.isEmpty() || parts.any { it == null }) return false
        val checked = parts.filterNotNull()
        val first = checked.first()
        return first.total == checked.size && checked.all {
            it.reference == first.reference && it.total == first.total && it.sequence in 1..first.total
        } && checked.map { it.sequence }.toSet().size == first.total &&
            (checked.size == 1 || first.reference != null)
    }
}
