package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

/** Pure synthetic TPDU vectors; this does not execute Android's SmsMessage decoder. */
class MomoTextFidelityRegressionTest {
    private fun octets(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    private val serviceCentreMillis = 1793190896000L // 2026-10-28 12:34:56 UTC.

    private fun deliver(dcs: Int, udl: Int, data: ByteArray, udhi: Boolean = false): ByteArray =
        // Alphanumeric address septets 4d 54 4e = MTN; swapped-BCD service-centre time.
        octets(0, if (udhi) 0x40 else 0, 6, 0xd0, 0x4d, 0xaa, 0x13, 0, dcs,
            0x62, 0x01, 0x82, 0x21, 0x43, 0x65, 0, udl) + data

    @Test fun byteCompleteSingleWithDroppedTrailingGsmEscapeIsNotTextComplete() {
        // GSM7 septets for "RWF 100" followed by an unpaired ESC: 8 septets / 7 octets.
        val frame = deliver(0, 8, octets(0xd2, 0xab, 0x11, 0x14, 0x83, 0xc1, 0x36))
        assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
        // AOSP's individual-PDU decoder drops the final ESC; this body is an
        // explicit source-derived expectation, not an executed Android decode.
        val result = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(serviceCentreMillis),
            listOf("RWF 100"), listOf(frame), "3gpp")
        assertFalse(result.complete)
        assertEquals("RWF 100", result.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", result.body))
        assertFalse(MomoMultipartPolicy.memberCaptureEligible("MTN", result))
    }

    @Test fun incompleteSegmentsCannotHideVerificationMarkerFromMemberCapture() {
        fun segment(sequence: Int, text: String): ByteArray {
            val payload = text.toByteArray(Charsets.US_ASCII)
            val header = octets(5, 0, 3, 7, 3, sequence)
            return deliver(4, header.size + payload.size, header + payload, udhi = true)
        }
        fun assemble(vararg segments: Pair<Int, String>): MomoMultipartPolicy.Assembly =
            MomoMultipartPolicy.assemble(
                segments.map { "MTN" }, segments.map { serviceCentreMillis },
                segments.map { it.second }, segments.map { segment(it.first, it.second) }, "3gpp",
            )

        val missingMiddle = assemble(1 to "RWF 100 ", 3 to "code 123456")
        assertEquals("RWF 100 code 123456", missingMiddle.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", missingMiddle.body))
        assertFalse(missingMiddle.complete)
        assertFalse(MomoMultipartPolicy.memberCaptureEligible("MTN", missingMiddle))

        val fullCode = assemble(1 to "RWF 100 ", 2 to "verification ", 3 to "code 123456")
        assertTrue(fullCode.complete)
        assertFalse(MomoMultipartPolicy.memberCaptureEligible("MTN", fullCode))

        val receipt = assemble(1 to "received ", 2 to "RWF 100 ", 3 to "reference 123456")
        assertTrue(receipt.complete)
        assertTrue(MomoMultipartPolicy.memberCaptureEligible("MTN", receipt))
    }

    @Test fun validExtensionsRemainValidButReservedAndDanglingEscapesAbstain() {
        // 41 1b 65: A then an extended-table code; 41 1b 1b: A then reserved double escape.
        assertNotNull(MomoMultipartPolicy.part(deliver(0, 3, octets(0xc1, 0x4d, 0x19)), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(0, 3, octets(0xc1, 0xcd, 0x06)), "3gpp"))
        // 41 1b 1b 1b: a paired double escape and one dangling escape.
        assertNull(MomoMultipartPolicy.part(deliver(0, 4, octets(0xc1, 0xcd, 0x66, 0x03)), "3gpp"))
        assertNotNull(MomoMultipartPolicy.part(deliver(0, 0, byteArrayOf()), "3gpp"))
    }

    @Test fun danglingGsmEscapeIsDetectedAtAllSevenHeaderFillAlignments() {
        // Each vector has a valid UDH and encodes payload septets 41 1b.
        // The 7-octet header uses a 16-bit concat IE; the others use an 8-bit
        // IE plus, when needed, a bounded unrelated IE. Data are fixed bytes.
        val cases = listOf(
            9 to octets(0x05,0x00,0x03,0x03,0x02,0x01,0x82,0x1b),
            10 to octets(0x06,0x08,0x04,0x00,0x03,0x02,0x01,0xc1,0x0d),
            12 to octets(0x07,0x00,0x03,0x03,0x02,0x01,0x70,0x00,0x40,0x70,0x03),
            13 to octets(0x08,0x00,0x03,0x03,0x02,0x01,0x70,0x01,0x00,0x20,0xb8,0x01),
            14 to octets(0x09,0x00,0x03,0x03,0x02,0x01,0x70,0x02,0x00,0x01,0x10,0xdc,0x00),
            15 to octets(0x0a,0x00,0x03,0x03,0x02,0x01,0x70,0x03,0x00,0x01,0x02,0x08,0x6e,0x00),
            16 to octets(0x0b,0x00,0x03,0x03,0x02,0x01,0x70,0x04,0x00,0x01,0x02,0x03,0x04,0x37),
        )
        for ((udl, data) in cases) {
            assertNull(MomoMultipartPolicy.part(deliver(0, udl, data, udhi = true), "3gpp"))
        }
    }

    @Test fun payloadAbstentionDoesNotChangeStructuralOrderOrPrivacyFilter() {
        val first = deliver(0, 9, octets(5,0,3,3,2,1,0x82,0x1b), udhi = true)
        val second = deliver(0, 8, octets(5,0,3,3,2,2,0x84), udhi = true)
        val result = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(serviceCentreMillis, serviceCentreMillis),
            listOf("B", "A"), listOf(second, first), "3gpp")
        assertFalse(result.complete)
        assertEquals("AB", result.body)
        // This separate filter-only body intentionally is not the encoded payload.
        val blocked = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(serviceCentreMillis, serviceCentreMillis),
            listOf("WF 100", "OTP R"), listOf(second, first), "3gpp")
        assertFalse(blocked.complete)
        assertEquals("OTP RWF 100", blocked.body)
        assertFalse(MomoGatewayPolicy.memberSource("MTN", blocked.body))
    }

    @Test fun unpackedEightBitTextStopsOrSubstitutesForHighBytes() {
        val plausiblePrefix = octets(0x52,0x57,0x46,0x20,0x31,0x30,0x30)
        for (suspect in listOf(0x80, 0xfe, 0xff)) {
            val frame = deliver(4, plausiblePrefix.size + 2, plausiblePrefix + octets(suspect, 0x41))
            assertNull(MomoMultipartPolicy.part(frame, "3gpp"))
            val body = if (suspect == 0xff) "RWF 100" else "RWF 100 A"
            val result = MomoMultipartPolicy.assemble(listOf("MTN"), listOf(serviceCentreMillis),
                listOf(body), listOf(frame), "3gpp")
            assertFalse(result.complete)
            assertEquals(body, result.body)
        }
        assertNull(MomoMultipartPolicy.part(deliver(4, 2, octets(0x41, 0x1b)), "3gpp"))
        assertNotNull(MomoMultipartPolicy.part(deliver(4, 3, octets(0x41, 0x1b, 0x65)), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(4, 3, octets(0x41, 0x1b, 0x1b)), "3gpp"))
    }

    @Test fun highBytesInHeaderAndUcs2AreNotTreatedAsEightBitPayload() {
        fun part(sequence: Int) = deliver(4, 13,
            octets(11,0,3,3,2,sequence,5,4,0xff,0x00,0x00,0xff,0x41), udhi = true)
        val first = MomoMultipartPolicy.part(part(1), "3gpp")
        val second = MomoMultipartPolicy.part(part(2), "3gpp")
        assertNotNull(first)
        assertNotNull(second)
        assertEquals(MomoMultipartPolicy.ApplicationPort(16, 0xff00, 0x00ff), first!!.applicationPort)
        assertTrue(MomoMultipartPolicy.complete(listOf(first, second)))
        assertNotNull(MomoMultipartPolicy.part(deliver(8, 2, octets(0x00, 0xff)), "3gpp"))
    }

    @Test fun highByteOnlyPortChangesAreComparedAndValuesAreUnsigned() {
        fun part(sequence: Int, destinationHigh: Int, originatorHigh: Int): MomoMultipartPolicy.Part? =
            MomoMultipartPolicy.part(deliver(4, 13,
                octets(11,0,3,3,2,sequence,5,4,destinationHigh,1,originatorHigh,2,0x41),
                udhi = true), "3gpp")
        val a = part(1, 0x80, 0x80)
        val same = part(2, 0x80, 0x80)
        val changedDestination = part(2, 0x81, 0x80)
        val changedOriginator = part(2, 0x80, 0x81)
        assertNotNull(a)
        assertEquals(MomoMultipartPolicy.ApplicationPort(16, 0x8001, 0x8002), a!!.applicationPort)
        assertEquals(MomoMultipartPolicy.ApplicationPort(16, 0x8101, 0x8002), changedDestination!!.applicationPort)
        assertEquals(MomoMultipartPolicy.ApplicationPort(16, 0x8001, 0x8102), changedOriginator!!.applicationPort)
        assertTrue(MomoMultipartPolicy.complete(listOf(a, same)))
        assertFalse(MomoMultipartPolicy.complete(listOf(a, changedDestination)))
        assertFalse(MomoMultipartPolicy.complete(listOf(a, changedOriginator)))
    }
}
