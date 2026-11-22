package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

/** Synthetic frame and caller inputs; Android decoding and transport are not exercised. */
class MomoFixedHeaderRegressionTest {
    private fun pdu(elements: ByteArray, sequence: Int? = null, dcs: Int = 0): ByteArray {
        val concat = if (sequence == null) byteArrayOf() else
            byteArrayOf(0x00, 0x03, 0x03, 0x02, sequence.toByte())
        val fields = concat + elements
        val header = byteArrayOf(fields.size.toByte()) + fields
        val udl = if (dcs == 0) (header.size * 8 + 6) / 7 + 2 else header.size + 2
        val octets = if (dcs == 0) (udl * 7 + 7) / 8 else udl
        return byteArrayOf(
            0, 0x40, 2, 0x91.toByte(), 0x21, 0, dcs.toByte(),
            0, 0, 0, 0, 0, 0, 0, udl.toByte(),
        ) + header + ByteArray(octets - header.size) { 0x41 }
    }

    @Test fun declaredExtraLanguageByteCannotHideAConcatenationElement() {
        // AOSP SmsHeader reads one shift byte; the older candidate skipped both.
        for (kind in listOf(0x24, 0x25)) {
            val hidden = byteArrayOf(kind.toByte(), 0x02, 0x01, 0x00, 0x03, 0x02, 0x02, 0x01)
            val frame = pdu(hidden)
            assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
            val result = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(10L),
                listOf("RWF 100"), listOf(frame), "3gpp")
            assertFalse(result.complete)
            assertEquals("RWF 100", result.body)
        }
    }

    @Test fun malformedSpecialAndPortLengthsCannotConcealAConcatenationElement() {
        // The final five bytes form an AOSP 8-bit concat IE after fixed-byte consumption.
        val special = byteArrayOf(0x01, 0x03, 0x00, 0x01, 0x00, 0x03, 0x02, 0x02, 0x01)
        val port = byteArrayOf(0x04, 0x03, 0xf0.toByte(), 0xf1.toByte(), 0x00, 0x03, 0x02, 0x02, 0x01)
        for (elements in listOf(special, port)) {
            assertNull(MomoMultipartPolicy.part(pdu(elements), "3gpp"))
        }
    }

    @Test fun everyKnownAospFixedLengthAbstainsForShortAndLongDeclarations() {
        for ((kind, correct) in listOf(0x00 to 3, 0x01 to 2, 0x04 to 2, 0x05 to 4,
            0x08 to 4, 0x24 to 1, 0x25 to 1)) {
            for (length in listOf(correct - 1, correct + 1)) {
                val elements = byteArrayOf(kind.toByte(), length.toByte()) + ByteArray(length) { 0x01 }
                for (dcs in listOf(0, 4, 8)) {
                    val part = MomoMultipartPolicy.part(pdu(elements, dcs = dcs), "3gpp")
                    assertNull(part)
                    assertFalse(MomoMultipartPolicy.complete(listOf(part)))
                }
            }
        }
    }

    @Test fun validPerSegmentAndRepeatedShiftOrSpecialElementsStillRemainIndependent() {
        val firstElements = byteArrayOf(0x24, 0x01, 0x01, 0x24, 0x01, 0x02,
            0x01, 0x02, 0x00, 0x01)
        val secondElements = byteArrayOf(0x25, 0x01, 0x01,
            0x01, 0x02, 0x00, 0x02, 0x01, 0x02, 0x00, 0x03)
        val a = MomoMultipartPolicy.part(pdu(firstElements, 1), "3gpp")
        val b = MomoMultipartPolicy.part(pdu(secondElements, 2), "3gpp")
        assertNotNull(a)
        assertNotNull(b)
        assertTrue(MomoMultipartPolicy.complete(listOf(a, b)))
    }

    @Test fun malformedStructureDoesNotAssertOrderOrBypassTheExistingMemberFilter() {
        val bad = pdu(byteArrayOf(0x24, 0x02, 0x01, 0x00), 1)
        val valid = pdu(byteArrayOf(), 2)
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "R"), listOf(valid, bad), "3gpp")
        assertFalse(result.complete)
        assertEquals("WF 100R", result.body)
        assertFalse(MomoGatewayPolicy.memberSource("MTN", result.body))
    }
}
