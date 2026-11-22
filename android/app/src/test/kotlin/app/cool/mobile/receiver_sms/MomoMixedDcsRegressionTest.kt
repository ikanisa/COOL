package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

/** Same test source is intended to run against the prior and new candidates. */
class MomoMixedDcsRegressionTest {
    private fun pdu(dcs: Int, sequence: Int): ByteArray {
        val tail = when (dcs) {
            0x00, 0x10, 0xf8 -> byteArrayOf(0x41, 0x22, 0x08) // 10 septets = 9 octets.
            0x04 -> byteArrayOf(0x41, 0x42, 0x43, 0x44)
            0x08 -> byteArrayOf(0, 0x41, 0, 0x42)
            else -> throw IllegalArgumentException("Unknown synthetic vector")
        }
        return byteArrayOf(
            0, 0x40, 2, 0x91.toByte(), 0x21, 0, dcs.toByte(),
            0, 0, 0, 0, 0, 0, 0, 10, 5, 0, 3, 3, 2, sequence.toByte(),
        ) + tail
    }

    @Test fun separatelyValidDifferentAlphabetsRemainAmbiguousAndOrdered() {
        for ((firstDcs, secondDcs) in listOf(0x00 to 0x08, 0x00 to 0x04, 0x04 to 0x08)) {
            val first = pdu(firstDcs, 1)
            val second = pdu(secondDcs, 2)
            val firstPart = MomoMultipartPolicy.part(first, "3gpp")
            val secondPart = MomoMultipartPolicy.part(second, "3gpp")
            assertNotNull(firstPart)
            assertNotNull(secondPart)
            assertFalse(MomoMultipartPolicy.complete(listOf(firstPart, secondPart)))
            assertFalse(MomoMultipartPolicy.complete(listOf(secondPart, firstPart)))
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
        }
    }

    @Test fun differentCodingOctetsWithSameAlphabetRemainAmbiguous() {
        // 0x00 and 0x10 both use GSM7 here; the other DCS bits differ.
        val first = pdu(0x00, 1)
        val second = pdu(0x10, 2)
        assertNotNull(MomoMultipartPolicy.part(first, "3gpp"))
        assertNotNull(MomoMultipartPolicy.part(second, "3gpp"))
        assertFalse(MomoMultipartPolicy.complete(listOf(
            MomoMultipartPolicy.part(first, "3gpp"), MomoMultipartPolicy.part(second, "3gpp"),
        )))
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "R"), listOf(second, first), "3gpp")
        assertFalse(result.complete)
        assertEquals("RWF 100", result.body)
    }

    @Test fun supportedSameCodingStillCompletesForEachAlphabet() {
        for (dcs in listOf(0x00, 0x04, 0x08, 0x10)) {
            val first = pdu(dcs, 1)
            val second = pdu(dcs, 2)
            assertTrue(MomoMultipartPolicy.complete(listOf(
                MomoMultipartPolicy.part(first, "3gpp"), MomoMultipartPolicy.part(second, "3gpp"),
            )))
            val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
                listOf("WF 100", "R"), listOf(second, first), "3gpp")
            assertTrue(result.complete)
            assertEquals("RWF 100", result.body)
        }
    }

    @Test fun absentCodingEvidenceCannotCompleteAConstructedMultipartSet() {
        assertFalse(MomoMultipartPolicy.complete(listOf(
            MomoMultipartPolicy.Part(3, 2, 1, 8), MomoMultipartPolicy.Part(3, 2, 2, 8),
        )))
        assertTrue(MomoMultipartPolicy.complete(listOf(MomoMultipartPolicy.Part(null, 1, 1))))
    }

    @Test fun unsupportedCodingOrdersButUnmatchedMetadataNeverDoes() {
        val first = pdu(0xf8, 1)
        val second = pdu(0x00, 2)
        val ordered = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "R"), listOf(second, first), "3gpp")
        assertFalse(ordered.complete)
        assertEquals("RWF 100", ordered.body)
        val differentTime = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 11L),
            listOf("WF 100", "R"), listOf(second, first), "3gpp")
        assertFalse(differentTime.complete)
        assertEquals("WF 100R", differentTime.body)
    }
}
