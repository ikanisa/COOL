package com.ikanisa.mmoney.platform

/**
 * Bounded 3GPP SMS-DELIVER envelope inspection, not another text decoder. Android decodes
 * address/body. Complete UDH groups are checked and ordered; fragments are never buffered.
 * Unsupported formats and ambiguous envelopes use the existing provider recovery path.
 * Primary field references: docs/sms-acceptance/sources.md.
 */
internal object SmsMultipartEnvelope {
    private data class Header(val reference: Int, val wide: Boolean, val count: Int, val sequence: Int)
    private data class Envelope(val header: Header?, val dcs: Int, val origin: List<Byte>)

    fun order(pdus: List<ByteArray>, format: String?): List<Int>? {
        if (format != "3gpp" || pdus.size !in 1..SmsBroadcastPolicy.MAX_PARTS) return null
        val parsed = pdus.map { inspect(it) ?: return null }
        val first = parsed.first()
        if (parsed.any { it.dcs != first.dcs || it.origin != first.origin }) return null
        val header = first.header
        if (header == null) return if (pdus.size == 1) listOf(0) else null
        if (header.count != pdus.size) return null
        if (parsed.any { it.header?.let { h -> h.reference != header.reference || h.wide != header.wide ||
                    h.count != header.count } != false }) return null
        val sequences = parsed.map { it.header!!.sequence }
        if (sequences.toSet() != (1..header.count).toSet()) return null
        return parsed.indices.sortedBy { sequences[it] }
    }

    private fun inspect(pdu: ByteArray): Envelope? {
        if (pdu.isEmpty() || pdu.size > 4096) return null
        fun u(index: Int) = pdu[index].toInt() and 255
        var offset = 1 + u(0) // SMSC prefix length in octets.
        if (offset + 3 > pdu.size) return null
        val firstOctet = u(offset++)
        if (firstOctet and 3 != 0) return null // SMS-DELIVER only.
        val originStart = offset
        val addressBytes = 2 + (u(offset) + 1) / 2
        if (addressBytes > pdu.size - offset) return null
        offset += addressBytes
        if (offset + 10 > pdu.size) return null // PID, DCS, SCTS[7], UDL.
        offset++
        val dcs = u(offset++)
        offset += 7
        val userDataLength = u(offset++)
        // Only uncompressed general coding groups are interpreted. No DCS guessing.
        if (dcs and 0xC0 != 0 || dcs and 0x20 != 0) return null
        val alphabet = (dcs shr 2) and 3
        if (alphabet == 3) return null
        val octets = if (alphabet == 0) (userDataLength * 7 + 7) / 8 else userDataLength
        if (octets > 140 || octets > pdu.size - offset) return null
        val origin = pdu.copyOfRange(originStart, originStart + addressBytes).toList()
        if (firstOctet and 0x40 == 0) return Envelope(null, dcs, origin)
        if (octets == 0) return null
        val end = offset + 1 + u(offset)
        if (end > offset + octets) return null
        offset++
        var header: Header? = null
        while (offset < end) {
            if (offset + 2 > end) return null
            val id = u(offset++)
            val size = u(offset++)
            if (size > end - offset) return null
            if (id == 0 || id == 8) {
                if (header != null || size != if (id == 0) 3 else 4) return null
                val wide = id == 8
                val reference = if (wide) (u(offset) shl 8) or u(offset + 1) else u(offset)
                val count = u(offset + if (wide) 2 else 1)
                val sequence = u(offset + if (wide) 3 else 2)
                if (count == 0 || sequence !in 1..count) return null
                header = Header(reference, wide, count, sequence)
            }
            offset += size
        }
        return Envelope(header, dcs, origin)
    }
}
