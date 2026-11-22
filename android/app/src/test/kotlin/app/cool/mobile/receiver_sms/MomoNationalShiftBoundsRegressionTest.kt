package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

/** Source-derived synthetic vectors, not an Android decoder or provider integration test. */
class MomoNationalShiftBoundsRegressionTest {
    private fun octets(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    private val time = 1793190896000L

    private fun deliver(dcs: Int, udl: Int, data: ByteArray, udhi: Boolean = false): ByteArray =
        octets(0, if (udhi) 0x40 else 0, 6, 0xd0, 0x4d, 0xaa, 0x13, 0, dcs,
            0x62, 0x01, 0x82, 0x21, 0x43, 0x65, 0, udl) + data

    // Pack explicit septets after a UDH, including the required fill bits.
    private fun gsm(header: IntArray, vararg payload: Int): ByteArray {
        val headerOctets = header.size + 1
        val headerSeptets = (headerOctets * 8 + 6) / 7
        val udl = headerSeptets + payload.size
        val data = ByteArray((udl * 7 + 7) / 8)
        data[0] = header.size.toByte()
        header.forEachIndexed { index, value -> data[index + 1] = value.toByte() }
        payload.forEachIndexed { index, value ->
            require(value in 0..127)
            for (offset in 0..6) {
                if (value and (1 shl offset) != 0) {
                    val bit = (headerSeptets + index) * 7 + offset
                    data[bit / 8] = (data[bit / 8].toInt() or (1 shl (bit % 8))).toByte()
                }
            }
        }
        return deliver(0, udl, data, udhi = true)
    }

    private fun one(kind: Int, id: Int) = gsm(intArrayOf(kind, 1, id), 0x41)
    private fun repeat(kind: Int, first: Int, last: Int) =
        gsm(intArrayOf(kind, 1, first, kind, 1, last), 0x41)

    @Test fun supportedSourceSlotsAcceptNoEscapeAndUnsupportedSlotsAbstain() {
        // Android 35 AOSP arrays have 14 entries each; locking index 2 is empty.
        for (id in 0..255) {
            val single = MomoMultipartPolicy.part(one(0x24, id), "3gpp")
            val locking = MomoMultipartPolicy.part(one(0x25, id), "3gpp")
            if (id in 0..13) assertNotNull(single) else assertNull(single)
            if (id in 0..13 && id != 2) assertNotNull(locking) else assertNull(locking)
        }
    }

    @Test fun independentlyReviewedBoundaryFourteenAbstainsForBothIes() {
        // Byte-for-byte source-review counterexamples; body was not decoded here.
        for (kind in listOf(0x24, 0x25)) {
            val frame = deliver(0, 6, octets(3, kind, 1, 14, 0x08, 0x02), udhi = true)
            assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
            val result = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(time),
                listOf("RWF 100"), listOf(frame), "3gpp")
            assertFalse(result.complete)
            assertEquals("RWF 100", result.body)
        }
    }

    @Test fun independentlyReviewedLockingFifteenFallbackIsNotComplete() {
        val frame = deliver(0, 12,
            octets(3,0x25,1,15,0x90,0x5e,0x8d,0xa0,0x18,0x0c,0x06), udhi = true)
        assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
        // Source-derived expected fallback is not an executed platform decode.
        val result = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(time),
            listOf("RWF 100"), listOf(frame), "3gpp")
        assertFalse(result.complete)
        assertEquals("RWF 100", result.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", result.body))
    }

    @Test fun lastSingleShiftIeControlsQualification() {
        assertNotNull(MomoMultipartPolicy.part(repeat(0x24, 14, 1), "3gpp"))
        assertNull(MomoMultipartPolicy.part(repeat(0x24, 1, 14), "3gpp"))
        assertNotNull(MomoMultipartPolicy.part(repeat(0x24, 255, 2), "3gpp"))
        assertNull(MomoMultipartPolicy.part(repeat(0x24, 2, 255), "3gpp"))
    }

    @Test fun lastLockingShiftIeControlsQualificationIncludingEmptySlot() {
        assertNotNull(MomoMultipartPolicy.part(repeat(0x25, 15, 3), "3gpp"))
        assertNull(MomoMultipartPolicy.part(repeat(0x25, 3, 15), "3gpp"))
        assertNotNull(MomoMultipartPolicy.part(repeat(0x25, 2, 1), "3gpp"))
        assertNull(MomoMultipartPolicy.part(repeat(0x25, 1, 2), "3gpp"))
    }

    @Test fun theTwoShiftKindsHaveIndependentLastIeState() {
        val supportedLast = gsm(intArrayOf(0x24,1,14,0x25,1,15,0x24,1,2,0x25,1,3), 0x41)
        val badSingleLast = gsm(intArrayOf(0x24,1,2,0x25,1,3,0x24,1,14,0x25,1,1), 0x41)
        val badLockLast = gsm(intArrayOf(0x24,1,14,0x25,1,3,0x24,1,1,0x25,1,2), 0x41)
        assertNotNull(MomoMultipartPolicy.part(supportedLast, "3gpp"))
        assertNull(MomoMultipartPolicy.part(badSingleLast, "3gpp"))
        assertNull(MomoMultipartPolicy.part(badLockLast, "3gpp"))
    }

    @Test fun distinctSupportedSegmentTablesDoNotBecomeMessageIdentity() {
        val first = gsm(intArrayOf(0,3,7,2,1,0x25,1,1,0x24,1,2), 0x41)
        val second = gsm(intArrayOf(0,3,7,2,2,0x25,1,3,0x24,1,13), 0x42)
        assertNotNull(MomoMultipartPolicy.part(first, "3gpp"))
        assertNotNull(MomoMultipartPolicy.part(second, "3gpp"))
        // Supplied bodies are deliberately independent of these synthetic PDUs.
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(time, time),
            listOf("WF 100", "R"), listOf(second, first), "3gpp")
        assertTrue(result.complete)
        assertEquals("RWF 100", result.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", result.body))
    }

    @Test fun unsupportedTablesAbstainButStructuralOrderingAndOtpFilterRemain() {
        val first = gsm(intArrayOf(0,3,7,2,1,0x25,1,14), 0x41)
        val second = gsm(intArrayOf(0,3,7,2,2,0x25,1,1), 0x42)
        assertNull(MomoMultipartPolicy.part(first, "3gpp"))
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(time, time),
            listOf("WF 100", "OTP R"), listOf(second, first), "3gpp")
        assertFalse(result.complete)
        assertEquals("OTP RWF 100", result.body)
        assertFalse(MomoGatewayPolicy.memberSource("MTN", result.body))
    }

    @Test fun shiftIdQualificationDoesNotChangeOctetsOrUcs2Paths() {
        for (kind in listOf(0x24, 0x25)) for (id in listOf(0,1,2,3,13,14,15,255)) {
            val octetData = octets(3,kind,1,id,0x41)
            val ucsData = octets(3,kind,1,id,0,0x41)
            assertNotNull(MomoMultipartPolicy.part(deliver(4, octetData.size, octetData, true), "3gpp"))
            assertNotNull(MomoMultipartPolicy.part(deliver(8, ucsData.size, ucsData, true), "3gpp"))
        }
    }

    @Test fun supportedLockingTableCanUseDefaultExtensionWhileNationalEscapeStillAbstains() {
        val lockingWithDefaultExtension = gsm(intArrayOf(0x25,1,1), 0x1b, 0x65)
        val nationalSingleExtension = gsm(intArrayOf(0x24,1,1), 0x1b, 0x65)
        assertNotNull(MomoMultipartPolicy.part(lockingWithDefaultExtension, "3gpp"))
        assertNull(MomoMultipartPolicy.part(nationalSingleExtension, "3gpp"))
    }
}
