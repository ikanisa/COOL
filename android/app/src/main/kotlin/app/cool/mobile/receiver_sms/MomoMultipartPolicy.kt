package app.cool.mobile.receiver_sms

/** GSM SMS-DELIVER metadata and bounded payload checks; unsupported transports abstain. */
object MomoMultipartPolicy {
    data class ApplicationPort(val widthBits: Int, val destination: Int, val originator: Int)
    data class Part(val reference: Int?, val total: Int, val sequence: Int,
                    val referenceBits: Int? = null, val dcs: Int? = null,
                    val applicationPort: ApplicationPort? = null,
                    val portMetadataUnambiguous: Boolean = true)
    data class Assembly(val body: String, val complete: Boolean)

    /** Member capture cannot safely classify text whose segments or decoding are uncertain. */
    fun memberCaptureEligible(sender: String, assembly: Assembly): Boolean =
        assembly.complete && MomoGatewayPolicy.memberSource(sender, assembly.body)
    private enum class Alphabet { GSM7, OCTETS, UCS2 }
    private data class Frame(val part: Part, val dcs: Int, val udl: Int, val dataStart: Int,
                             val headerOctets: Int, val applicationPort: ApplicationPort? = null,
                             val portMetadataUnambiguous: Boolean = true,
                             val singleShiftTable: Int = 0,
                             val lockingShiftTable: Int = 0)

    // Nonblank entries in the inspected GSM default extension table. Unknown
    // slots have defined fallback behavior but are not evidence of fidelity.
    private val defaultExtensionCodes = setOf(0x0a, 0x14, 0x28, 0x29, 0x2f,
        0x3c, 0x3d, 0x3e, 0x40, 0x65)

    /** Reserved, compressed, unsupported or device-dependent codings do not prove completeness. */
    private fun alphabet(dcs: Int): Alphabet? = when {
        dcs and 0x80 == 0 -> if (dcs and 0x20 != 0) null else when ((dcs shr 2) and 3) {
            0 -> Alphabet.GSM7
            1 -> Alphabet.OCTETS
            2 -> Alphabet.UCS2
            else -> null
        }
        (dcs and 0xf0 == 0xc0 || dcs and 0xf0 == 0xd0) && dcs and 4 == 0 -> Alphabet.GSM7
        dcs and 0xf0 == 0xe0 && dcs and 4 == 0 -> Alphabet.UCS2
        dcs and 0xf0 == 0xf0 && dcs and 8 == 0 ->
            if (dcs and 4 == 0) Alphabet.GSM7 else Alphabet.OCTETS
        else -> null
    }

    /** Parse only the physically present, bounded header. This alone never proves completeness. */
    private fun frame(pdu: ByteArray, format: String?): Frame? {
        if (format != "3gpp") return null
        fun value(index: Int) = pdu[index].toInt() and 255
        return try {
            var cursor = 1 + value(0) // SMSC length excludes its own octet.
            val flags = value(cursor++)
            if (flags and 3 != 0) return null // Only incoming SMS-DELIVER.
            val addressLength = value(cursor++)
            cursor++ // Originating address type.
            cursor += (addressLength + 1) / 2
            cursor++ // Protocol identifier.
            val dcs = value(cursor++)
            cursor += 7 // Service-centre timestamp.
            val udl = value(cursor++)
            val dataStart = cursor
            if (flags and 64 == 0) return Frame(Part(null, 1, 1), dcs, udl, dataStart, 0)
            val headerOctets = 1 + value(cursor)
            // Every supported alphabet needs at least this many UDL units for
            // the header. Limit header parsing independently of trailing bytes.
            if (headerOctets > 140 || headerOctets > udl || headerOctets > pdu.size - dataStart) return null
            val end = dataStart + headerOctets
            cursor++
            var concatenation: Part? = null
            var applicationPort: ApplicationPort? = null
            var portSeen = false
            var portMetadataUnambiguous = true
            var singleShiftTable = 0
            var lockingShiftTable = 0
            while (cursor < end) {
                if (cursor + 2 > end) return null
                val kind = value(cursor++)
                val length = value(cursor++)
                if (cursor + length > end) return null
                // The Android SmsHeader parser consumes fixed bytes for these
                // known IEs. A different declared length can hide subsequent
                // metadata from one parser; it cannot establish safe ordering.
                val fixedLength = when (kind) {
                    0 -> 3 // 8-bit concatenation reference
                    1 -> 2 // special SMS message indication
                    4 -> 2 // 8-bit application port
                    5 -> 4 // 16-bit application port
                    8 -> 4 // 16-bit concatenation reference
                    0x24, 0x25 -> 1 // national-language shift identifiers
                    else -> null
                }
                if (fixedLength != null && length != fixedLength) return null
                val parsed = when {
                    kind == 0 && length == 3 -> Part(value(cursor), value(cursor + 1), value(cursor + 2), 8)
                    kind == 8 && length == 4 -> Part(value(cursor) * 256 + value(cursor + 1), value(cursor + 2), value(cursor + 3), 16)
                    else -> null
                }
                if (parsed != null) {
                    if (concatenation != null) return null
                    concatenation = parsed
                }
                // The inspected Android parser uses the last IE of each kind.
                // These are per-segment decoding data, not message identity.
                if (kind == 0x24) singleShiftTable = value(cursor)
                if (kind == 0x25) lockingShiftTable = value(cursor)
                // An application-port IE, when present, is a separate identity
                // signal. Keep duplicate port metadata ambiguous;
                // unrelated IEs are deliberately not compared across segments.
                if (kind == 4 || kind == 5) {
                    if (portSeen) portMetadataUnambiguous = false
                    portSeen = true
                    if (applicationPort == null) {
                        applicationPort = if (kind == 4) {
                            ApplicationPort(8, value(cursor), value(cursor + 1))
                        } else {
                            ApplicationPort(16, value(cursor) * 256 + value(cursor + 1),
                                value(cursor + 2) * 256 + value(cursor + 3))
                        }
                    }
                }
                cursor += length
            }
            Frame(concatenation ?: Part(null, 1, 1), dcs, udl, dataStart, headerOctets,
                applicationPort, portMetadataUnambiguous, singleShiftTable, lockingShiftTable)
        } catch (_: IndexOutOfBoundsException) { null }
    }

    /**
     * Byte-count completeness does not guarantee that Android's per-PDU text
     * decoder consumed the entire payload. These checks are conservative and
     * do not attempt to decode text or prove the supplied body matches the PDU.
     */
    private fun textPayloadAmbiguous(pdu: ByteArray, frame: Frame, alphabet: Alphabet,
                                     headerUnits: Int): Boolean {
        var escaped = false
        when (alphabet) {
            Alphabet.GSM7 -> {
                // UDH consumes whole septets, including the fill bits after its
                // final octet. Walk payload septets, not header or padding.
                for (i in 0 until (frame.udl - headerUnits)) {
                    val bit = (headerUnits + i) * 7
                    val index = frame.dataStart + bit / 8
                    if (index !in pdu.indices) return true
                    val shift = bit % 8
                    var packed = (pdu[index].toInt() and 255) ushr shift
                    if (shift > 1) {
                        if (index + 1 !in pdu.indices) return true
                        packed = packed or ((pdu[index + 1].toInt() and 255) shl (8 - shift))
                    }
                    val septet = packed and 0x7f
                    // The inspected Android decoder substitutes a space for
                    // the reserved double-escape sequence.
                    if (escaped && septet == 0x1b) return true
                    // National single-shift tables vary by segment. We do not
                    // claim those tables without an independently bound map.
                    if (escaped && (frame.singleShiftTable != 0 || septet !in defaultExtensionCodes)) return true
                    escaped = if (escaped) false else septet == 0x1b
                }
            }
            Alphabet.OCTETS -> {
                val start = frame.dataStart + frame.headerOctets
                for (index in start until pdu.size) {
                    val octet = pdu[index].toInt() and 255
                    // AOSP's GSM 8-bit text decoder stops at 0xff and maps
                    // other high-bit octets to spaces; OEM decoding may differ.
                    if (octet >= 0x80) return true
                    if (escaped && octet == 0x1b) return true
                    // The inspected AOSP 8-bit text decoder uses default tables.
                    if (escaped && octet !in defaultExtensionCodes) return true
                    escaped = if (escaped) false else octet == 0x1b
                }
            }
            Alphabet.UCS2 -> {
                // Android's observed path uses UTF-16: absent a BOM it is big
                // endian; FF FE selects little endian for this PDU's payload.
                var index = frame.dataStart + frame.headerOctets
                val end = pdu.size
                var littleEndian = false
                if (index + 1 < end) {
                    val first = pdu[index].toInt() and 255
                    val second = pdu[index + 1].toInt() and 255
                    if (first == 0xff && second == 0xfe) {
                        littleEndian = true
                        index += 2
                    } else if (first == 0xfe && second == 0xff) {
                        index += 2
                    }
                }
                fun unit(at: Int): Int {
                    val first = pdu[at].toInt() and 255
                    val second = pdu[at + 1].toInt() and 255
                    return if (littleEndian) second * 256 + first else first * 256 + second
                }
                while (index < end) {
                    if (index + 1 >= end) return true
                    val current = unit(index)
                    when (current) {
                        in 0xd800..0xdbff -> {
                            if (index + 3 >= end || unit(index + 2) !in 0xdc00..0xdfff) return true
                            index += 4
                        }
                        in 0xdc00..0xdfff -> return true
                        else -> index += 2
                    }
                }
                return false
            }
        }
        // Android decodes each PDU separately; an unpaired final escape can
        // disappear before concatenation, even when every octet is present.
        return escaped
    }

    fun part(pdu: ByteArray, format: String?): Part? {
        val frame = frame(pdu, format) ?: return null
        val alphabet = alphabet(frame.dcs) ?: return null
        // This only qualifies the inspected Android 35 GSM7 table slots. The
        // empty locking slot 2 and out-of-range IDs can fall back or fail in
        // that implementation; abstain without calling the message malformed.
        // Leave frame() structural parsing and OCTETS/UCS2 behavior unchanged.
        if (alphabet == Alphabet.GSM7 &&
            (frame.singleShiftTable !in 0..13 || frame.lockingShiftTable !in 0..13 ||
                frame.lockingShiftTable == 2)) return null
        // TP-UDL is septets for GSM7 and octets for 8-bit/UCS2.
        val octets = when (alphabet) {
            Alphabet.GSM7 -> (frame.udl * 7 + 7) / 8
            Alphabet.OCTETS, Alphabet.UCS2 -> frame.udl
        }
        if (octets > 140 || (alphabet == Alphabet.GSM7 && frame.udl > 160)) return null
        // A truncated or padded frame cannot establish complete payload bytes.
        if (pdu.size - frame.dataStart != octets) return null
        val headerUnits = when (alphabet) {
            Alphabet.GSM7 -> (frame.headerOctets * 8 + 6) / 7
            Alphabet.OCTETS, Alphabet.UCS2 -> frame.headerOctets
        }
        if (headerUnits > frame.udl) return null
        if (alphabet == Alphabet.UCS2 && (frame.udl - frame.headerOctets) % 2 != 0) return null
        if (textPayloadAmbiguous(pdu, frame, alphabet, headerUnits)) return null
        // Carry the declared coding into the completeness decision. Structural
        // ordering is intentionally independent of this conservative evidence.
        return frame.part.copy(
            dcs = if (frame.part.reference != null) frame.dcs else null,
            applicationPort = frame.applicationPort,
            portMetadataUnambiguous = frame.portMetadataUnambiguous,
        )
    }

    private fun structuralComplete(parts: List<Part?>): Boolean {
        if (parts.isEmpty() || parts.any { it == null }) return false
        val checked = parts.filterNotNull()
        val first = checked.first()
        return first.total == checked.size && checked.all {
            it.reference == first.reference && it.referenceBits == first.referenceBits &&
                it.total == first.total && it.sequence in 1..first.total
        } && checked.map { it.sequence }.toSet().size == first.total &&
            (if (first.reference == null) checked.size == 1 && first.referenceBits == null
            else first.referenceBits == 8 || first.referenceBits == 16)
    }

    /** Distinct coding octets are ambiguous, not proof of a bad carrier message. */
    fun complete(parts: List<Part?>): Boolean {
        if (!structuralComplete(parts)) return false
        val first = parts.first()!!
        if (parts.any { it?.portMetadataUnambiguous != true }) return false
        if (first.reference == null) return true
        val dcs = first.dcs ?: return false
        return dcs in 0..255 && alphabet(dcs) != null && parts.all {
            it != null && it.dcs == dcs && it.applicationPort == first.applicationPort
        }
    }

    /** Order only coherent structural sets; the independent payload check still sets completeness. */
    fun assemble(senders: List<String>, timestamps: List<Long>, bodies: List<String?>,
                 pdus: List<ByteArray?>, format: String?): Assembly {
        val coherent = MomoGatewayPolicy.completeParts(senders, timestamps, bodies)
        val parts = pdus.map { it?.let { bytes -> part(bytes, format) } }
        val complete = coherent && parts.size == bodies.size && complete(parts)
        val ordering = if (complete) parts else pdus.map { it?.let { bytes -> frame(bytes, format)?.part } }
        val orderEstablished = coherent && ordering.size == bodies.size && structuralComplete(ordering)
        val body = if (orderEstablished) bodies.indices.sortedBy { ordering[it]!!.sequence }
            .joinToString("") { bodies[it].orEmpty() }
            else bodies.joinToString("") { it.orEmpty() }
        return Assembly(body, complete)
    }
}
