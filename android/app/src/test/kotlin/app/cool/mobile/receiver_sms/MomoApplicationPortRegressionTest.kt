package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

/** Synthetic helper vectors only; decoded body arguments are not decoded from these PDUs. */
class MomoApplicationPortRegressionTest {
    private val port8 = byteArrayOf(0x04, 0x02, 0xf0.toByte(), 0xf1.toByte())
    private val port16 = byteArrayOf(0x05, 0x04, 0x3e, 0x80.toByte(), 0x3e, 0x81.toByte())

    private fun pdu(sequence: Int?, elements: ByteArray, dcs: Int = 0x04): ByteArray {
        val concat = if (sequence == null) byteArrayOf() else
            byteArrayOf(0x00, 0x03, 0x03, 0x02, sequence.toByte())
        val fields = concat + elements
        val header = byteArrayOf(fields.size.toByte()) + fields
        val udl = if (dcs == 0) (header.size * 8 + 6) / 7 + 2 else header.size + 2
        val octets = if (dcs == 0) (udl * 7 + 7) / 8 else udl
        val payload = ByteArray(octets - header.size) { 0x41 }
        return byteArrayOf(
            0, 0x40, 2, 0x91.toByte(), 0x21, 0, dcs.toByte(),
            0, 0, 0, 0, 0, 0, 0, udl.toByte(),
        ) + header + payload
    }

    private fun complete(first: ByteArray, second: ByteArray): Boolean {
        val a = MomoMultipartPolicy.part(first, "3gpp")
        val b = MomoMultipartPolicy.part(second, "3gpp")
        assertNotNull(a)
        assertNotNull(b)
        return MomoMultipartPolicy.complete(listOf(a, b))
    }

    @Test fun matchingPortWidthsAndAbsentPortsRemainComplete() {
        for (port in listOf(port8, port16, byteArrayOf())) {
            assertTrue(complete(pdu(1, port), pdu(2, port)))
            assertTrue(complete(pdu(2, port), pdu(1, port)))
        }
        assertTrue(MomoMultipartPolicy.complete(listOf(MomoMultipartPolicy.part(pdu(null, port8), "3gpp"))))
    }

    @Test fun differentOrMissingPortIdentityDoesNotProveCompleteness() {
        val differentDestination8 = byteArrayOf(0x04, 0x02, 0xf2.toByte(), 0xf1.toByte())
        val differentOriginator8 = byteArrayOf(0x04, 0x02, 0xf0.toByte(), 0xf2.toByte())
        val differentDestination16 = byteArrayOf(0x05, 0x04, 0x3e, 0x82.toByte(), 0x3e, 0x81.toByte())
        val differentOriginator16 = byteArrayOf(0x05, 0x04, 0x3e, 0x80.toByte(), 0x3e, 0x82.toByte())
        for ((a, b) in listOf(
            port8 to differentDestination8, port8 to differentOriginator8,
            port16 to differentDestination16, port16 to differentOriginator16,
            port8 to port16, port8 to byteArrayOf(), port16 to byteArrayOf(),
        )) {
            assertFalse(complete(pdu(1, a), pdu(2, b)))
            assertFalse(complete(pdu(2, b), pdu(1, a)))
        }
    }

    @Test fun malformedAndDuplicatePortIesAbstainEvenForOnePart() {
        val malformed8 = byteArrayOf(0x04, 0x01, 0xf0.toByte())
        val malformed16 = byteArrayOf(0x05, 0x03, 0x3e, 0x80.toByte(), 0x3e)
        for (malformed in listOf(malformed8, malformed16)) {
            val single = MomoMultipartPolicy.part(pdu(null, malformed), "3gpp")
            val first = MomoMultipartPolicy.part(pdu(1, malformed), "3gpp")
            val second = MomoMultipartPolicy.part(pdu(2, port8), "3gpp")
            assertNull(single)
            assertNull(first)
            assertFalse(MomoMultipartPolicy.complete(listOf(single)))
            assertFalse(MomoMultipartPolicy.complete(listOf(first, second)))
        }
        for (ambiguous in listOf(port8 + port8, port8 + port16, port16 + port8)) {
            val single = MomoMultipartPolicy.part(pdu(null, ambiguous), "3gpp")
            assertNotNull(single)
            assertFalse(MomoMultipartPolicy.complete(listOf(single)))
            assertFalse(complete(pdu(1, ambiguous), pdu(2, port8)))
        }
    }

    @Test fun portIeThatExceedsTheDeclaredHeaderAbstains() {
        val truncatedPort = byteArrayOf(0x04, 0x02, 0xf0.toByte())
        assertNull(MomoMultipartPolicy.part(pdu(1, truncatedPort), "3gpp"))
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "R"), listOf(pdu(2, port8), pdu(1, truncatedPort)), "3gpp")
        assertFalse(result.complete)
        assertEquals("WF 100R", result.body)
    }

    @Test fun distinctLanguageShiftIesAreNotBlanketCompared() {
        val singleShift1 = byteArrayOf(0x24, 0x01, 0x01)
        val singleShift2 = byteArrayOf(0x24, 0x01, 0x02)
        val lockingShift1 = byteArrayOf(0x25, 0x01, 0x01)
        assertTrue(complete(pdu(1, singleShift1, 0), pdu(2, singleShift2 + lockingShift1, 0)))
        assertTrue(complete(pdu(1, singleShift1, 0), pdu(2, byteArrayOf(), 0)))
        assertTrue(complete(pdu(1, port8 + singleShift1, 0), pdu(2, singleShift2 + port8, 0)))
    }

    @Test fun highBytePortValuesAreComparedUnsigned() {
        // Synthetic values check parsing only, not port allocation or device routing.
        val high = byteArrayOf(0x05, 0x04, 0x80.toByte(), 0x01, 0x80.toByte(), 0x02)
        val changed = byteArrayOf(0x05, 0x04, 0x80.toByte(), 0x01, 0x80.toByte(), 0x03)
        assertTrue(complete(pdu(1, high), pdu(2, high)))
        assertFalse(complete(pdu(1, high), pdu(2, changed)))
    }

    @Test fun ambiguousPortsRemainIncompleteWhileExistingStructuralOrderAndFilterRemain() {
        val differentPort = byteArrayOf(0x04, 0x02, 0xf2.toByte(), 0xf1.toByte())
        val first = pdu(1, port8)
        val second = pdu(2, differentPort)
        val forward = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("R", "WF 100"), listOf(first, second), "3gpp")
        val reverse = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "R"), listOf(second, first), "3gpp")
        assertFalse(forward.complete)
        assertFalse(reverse.complete)
        assertEquals("RWF 100", forward.body)
        assertEquals(forward.body, reverse.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", reverse.body))
        assertEquals(MomoGatewayPolicy.captureId("fixture", "binding", "MTN", forward.body, 10L, 7),
            MomoGatewayPolicy.captureId("fixture", "binding", "MTN", reverse.body, 10L, 7))
        val excluded = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "OTP R"), listOf(second, first), "3gpp")
        assertFalse(excluded.complete)
        assertEquals("OTP RWF 100", excluded.body)
        assertFalse(MomoGatewayPolicy.memberSource("MTN", excluded.body))
    }
}
