package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

/** Synthetic PDU / caller vectors only; Android decoding is not exercised here. */
class MomoCharsetCompletenessRegressionTest {
    private fun octets(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    private val time = 1793190896000L

    private fun deliver(dcs: Int, udl: Int, data: ByteArray, udhi: Boolean = false): ByteArray =
        octets(0, if (udhi) 0x40 else 0, 6, 0xd0, 0x4d, 0xaa, 0x13, 0, dcs,
            0x62, 0x01, 0x82, 0x21, 0x43, 0x65, 0, udl) + data

    private fun ucs(data: ByteArray): ByteArray = deliver(8, data.size, data)

    @Test fun sourceDerivedReceiptWithAnUnpairedSurrogateIsIncomplete() {
        val data = octets(0,0x52,0,0x57,0,0x46,0,0x20,0,0x31,0,0x30,0,0x30,0xd8,0)
        val frame = ucs(data)
        assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
        // Replacement is a source-derived expectation, not an executed Android decode.
        val body = "RWF 100\ufffd"
        val value = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(time), listOf(body),
            listOf(frame), "3gpp")
        assertFalse(value.complete)
        assertEquals(body, value.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", body))
    }

    @Test fun utf16PairsAndBmpAreAcceptedWithBigEndianAndBomSelectedLittleEndian() {
        val accepted = listOf(
            byteArrayOf(), octets(0,0x41,0,0xff),
            octets(0xd8,0,0xdc,0), octets(0xdb,0xff,0xdf,0xff),
            octets(0xfe,0xff,0xd8,0x3d,0xde,0x00),
            octets(0xff,0xfe,0x3d,0xd8,0x00,0xde),
            octets(0xd7,0xff,0xe0,0x00), octets(0xfe,0xff), octets(0xff,0xfe),
        )
        for (data in accepted) {
            assertNotNull(MomoMultipartPolicy.part(ucs(data), "3gpp"))
        }
        // FF FE in the UDH is a port value, not a payload byte-order mark.
        val data = octets(6,5,4,0xff,0xfe,0,1,0,0x41)
        val part = MomoMultipartPolicy.part(deliver(8, data.size, data, udhi = true), "3gpp")
        assertNotNull(part)
        assertEquals(MomoMultipartPolicy.ApplicationPort(16, 0xfffe, 1), part!!.applicationPort)
    }

    @Test fun loneOrMismatchedUtf16SurrogatesAreIncompleteInBothByteOrders() {
        val invalid = listOf(
            octets(0xd8,0), octets(0xdb,0xff), octets(0xdc,0), octets(0xdf,0xff),
            octets(0xd8,0,0,0x41), octets(0,0x41,0xdc,0),
            octets(0xd8,0,0xd8,1,0xdc,0),
            octets(0xfe,0xff,0xd8,0), octets(0xfe,0xff,0xdc,0),
            octets(0xff,0xfe,0,0xd8), octets(0xff,0xfe,0,0xdc),
            octets(0xff,0xfe,0,0xd8,0x41,0),
        )
        for (data in invalid) assertNull(MomoMultipartPolicy.part(ucs(data), "3gpp"))
        assertNull(MomoMultipartPolicy.part(ucs(octets(0,0x41,0)), "3gpp"))
    }

    @Test fun crossSegmentSurrogateHalvesRemainIncompleteButStructuralOrderRemains() {
        val first = octets(5,0,3,3,2,1,0xd8,0x3d)
        val second = octets(5,0,3,3,2,2,0xde,0x00)
        val a = deliver(8, first.size, first, udhi = true)
        val b = deliver(8, second.size, second, udhi = true)
        assertNull(MomoMultipartPolicy.part(a, "3gpp"))
        assertNull(MomoMultipartPolicy.part(b, "3gpp"))
        // The placeholders are intentionally not an Android-decoded body.
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(time, time),
            listOf("B", "A"), listOf(b, a), "3gpp")
        assertFalse(result.complete)
        assertEquals("AB", result.body)
    }

    @Test fun defaultGsmFallbackIsNotPromotedToComplete() {
        // Septets for "RWF 100" followed by ESC 00: AOSP default table falls back to '@'.
        val data = octets(0xd2,0xab,0x11,0x14,0x83,0xc1,0x36,0x00)
        val frame = deliver(0, 9, data)
        assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
        val body = "RWF 100@" // Source-derived expected fallback; platform not executed.
        val result = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(time), listOf(body),
            listOf(frame), "3gpp")
        assertFalse(result.complete)
        assertEquals(body, result.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", body))
        // ESC 65 is a represented extension in the same source-derived alphabet.
        assertNotNull(MomoMultipartPolicy.part(deliver(0, 9,
            octets(0xd2,0xab,0x11,0x14,0x83,0xc1,0x36,0x65)), "3gpp"))
    }

    @Test fun onlyRepresentedDefaultExtensionPositionsProveGsmTextCompleteness() {
        val represented = setOf(0x0a,0x14,0x28,0x29,0x2f,0x3c,0x3d,0x3e,0x40,0x65)
        for (code in 0..0x7f) {
            // Exact packing of the two septets ESC and code without a header.
            val data = octets(0x1b or ((code and 1) shl 7), code ushr 1)
            val part = MomoMultipartPolicy.part(deliver(0, 2, data), "3gpp")
            if (code in represented) assertNotNull(part) else assertNull(part)
        }
    }

    @Test fun singleShiftMetadataIsPerSegmentAndUnknownNationalEscapesAbstain() {
        // Explicit national single-shift IE: no escape is still structurally valid.
        assertNotNull(MomoMultipartPolicy.part(deliver(0, 6,
            octets(3,0x24,1,1,0x08,0x02), udhi = true), "3gpp"))
        // The same national table with ESC 65 is conservatively unqualified.
        assertNull(MomoMultipartPolicy.part(deliver(0, 7,
            octets(3,0x24,1,1,0xd8,0x94,1), udhi = true), "3gpp"))
        // AOSP SmsHeader uses the last repeated single-shift IE; inspect each PDU.
        // Code 0 is reserved by ETSI; these are synthetic parser-order vectors.
        assertNotNull(MomoMultipartPolicy.part(deliver(0, 10,
            octets(6,0x24,1,1,0x24,1,0,0x9b,0x32), udhi = true), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(0, 10,
            octets(6,0x24,1,0,0x24,1,1,0x9b,0x32), udhi = true), "3gpp"))
    }

    @Test fun unpackedEightBitExtensionUsesDefaultTableRegardlessOfHeader() {
        for (code in listOf(0x0a,0x14,0x28,0x29,0x2f,0x3c,0x3d,0x3e,0x40,0x65)) {
            assertNotNull(MomoMultipartPolicy.part(deliver(4, 2, octets(0x1b, code)), "3gpp"))
        }
        for (code in listOf(0,1,0x0d,0x1b,0x7f)) {
            assertNull(MomoMultipartPolicy.part(deliver(4, 2, octets(0x1b, code)), "3gpp"))
        }
        // AOSP's GSM8 text path uses default tables even with a single-shift IE.
        assertNotNull(MomoMultipartPolicy.part(deliver(4, 6,
            octets(3,0x24,1,1,0x1b,0x65), udhi = true), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(4, 6,
            octets(3,0x24,1,1,0x1b,0), udhi = true), "3gpp"))
    }

    @Test fun unknownExtensionLeavesOrderingAndExistingOtpFilterIntact() {
        val first = deliver(0, 10, octets(5,0,3,3,2,1,0x82,0x1b,0), udhi = true)
        val second = deliver(0, 8, octets(5,0,3,3,2,2,0x84), udhi = true)
        val value = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(time, time),
            listOf("B", "A@"), listOf(second, first), "3gpp")
        assertFalse(value.complete)
        assertEquals("A@B", value.body)
        // This body is for filter policy only, not the decoded contents of the fixture.
        val blocked = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(time, time),
            listOf("WF 100", "OTP R"), listOf(second, first), "3gpp")
        assertFalse(blocked.complete)
        assertEquals("OTP RWF 100", blocked.body)
        assertFalse(MomoGatewayPolicy.memberSource("MTN", blocked.body))
    }
}
