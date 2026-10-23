package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

class MomoMultipartPolicyTest {
    private fun pdu(total: Int, sequence: Int, reference: Int = 3): ByteArray = byteArrayOf(
        0, 0x40, 2, 0x91.toByte(), 0x21, 0, 0,
        0, 0, 0, 0, 0, 0, 0,
        10, 5, 0, 3, reference.toByte(), total.toByte(), sequence.toByte(), 0x41,
    )
    @Test fun transactionIdAcrossMultipartBoundaryNeedsEverySequence() {
        val first = MomoMultipartPolicy.part(pdu(2, 1), "3gpp")
        val second = MomoMultipartPolicy.part(pdu(2, 2), "3gpp")
        assertTrue(MomoMultipartPolicy.complete(listOf(first, second)))
        assertFalse(MomoMultipartPolicy.complete(listOf(first)))
        assertFalse(MomoMultipartPolicy.complete(listOf(second)))
    }
    @Test fun duplicateAndMixedConcatenationPartsAreIncomplete() {
        val first = MomoMultipartPolicy.part(pdu(2, 1), "3gpp")
        assertFalse(MomoMultipartPolicy.complete(listOf(first, first)))
        assertFalse(MomoMultipartPolicy.complete(listOf(first, MomoMultipartPolicy.part(pdu(2, 2, 8), "3gpp"))))
        assertFalse(MomoMultipartPolicy.complete(listOf(first, MomoMultipartPolicy.part(pdu(3, 2), "3gpp"))))
    }
    @Test fun unknownAndTruncatedTransportAbstains() {
        assertNull(MomoMultipartPolicy.part(pdu(2, 1), "3gpp2"))
        assertNull(MomoMultipartPolicy.part(byteArrayOf(0), "3gpp"))
        assertFalse(MomoMultipartPolicy.complete(listOf(null)))
        assertFalse(MomoMultipartPolicy.complete(emptyList()))
    }
    @Test fun oneCompleteGsmMessageNeedsNoConcatenationHeader() {
        val single = pdu(2, 1).also { it[1] = 0 }
        assertEquals(MomoMultipartPolicy.Part(null, 1, 1), MomoMultipartPolicy.part(single, "3gpp"))
        assertTrue(MomoMultipartPolicy.complete(listOf(MomoMultipartPolicy.part(single, "3gpp"))))
    }
}
