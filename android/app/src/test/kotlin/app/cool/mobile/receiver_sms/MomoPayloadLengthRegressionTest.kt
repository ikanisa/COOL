package app.cool.mobile.receiver_sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Same source is intended to be run against baseline and successor separately. */
class MomoPayloadLengthRegressionTest {
    private fun single(dcs: Int, udl: Int, data: ByteArray): ByteArray = byteArrayOf(
        0, 0, 2, 0x91.toByte(), 0x21, 0, dcs.toByte(), 0, 0, 0, 0, 0, 0, 0, udl.toByte(),
    ) + data

    @Test fun declaredPayloadMustActuallyBePresent() {
        for ((dcs, udl, bytes) in listOf(Triple(0, 10, 9), Triple(4, 4, 4), Triple(8, 4, 4))) {
            assertEquals(MomoMultipartPolicy.Part(null, 1, 1), MomoMultipartPolicy.part(single(dcs, udl, ByteArray(bytes)), "3gpp"))
            assertNull(MomoMultipartPolicy.part(single(dcs, udl, ByteArray(bytes - 1)), "3gpp"))
        }
    }

    @Test fun validMaximumIsAcceptedButOversizeIsNotComplete() {
        for ((dcs, maximum, excess) in listOf(Triple(0, 160, 161), Triple(4, 140, 141), Triple(8, 140, 142))) {
            val maxOctets = if (dcs == 0) 140 else maximum
            val excessOctets = if (dcs == 0) 141 else excess
            assertEquals(MomoMultipartPolicy.Part(null, 1, 1), MomoMultipartPolicy.part(single(dcs, maximum, ByteArray(maxOctets)), "3gpp"))
            assertNull(MomoMultipartPolicy.part(single(dcs, excess, ByteArray(excessOctets)), "3gpp"))
        }
    }
}
