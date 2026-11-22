package app.cool.mobile.receiver_sms

import org.junit.Assert.*
import org.junit.Test

class MomoMultipartPolicyTest {
    private fun pdu(total: Int, sequence: Int, reference: Int = 3): ByteArray = byteArrayOf(
        0, 0x40, 2, 0x91.toByte(), 0x21, 0, 0,
        0, 0, 0, 0, 0, 0, 0,
        // Six header octets occupy seven septets; the eighth is payload.
        8, 5, 0, 3, reference.toByte(), total.toByte(), sequence.toByte(), 0x41,
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
        assertNull(MomoMultipartPolicy.part(pdu(2, 1).dropLast(1).toByteArray(), "3gpp"))
        assertFalse(MomoMultipartPolicy.complete(listOf(null)))
        assertFalse(MomoMultipartPolicy.complete(emptyList()))
    }
    @Test fun oneCompleteGsmMessageNeedsNoConcatenationHeader() {
        val single = byteArrayOf(0, 0, 2, 0x91.toByte(), 0x21, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 1, 0x41)
        assertEquals(MomoMultipartPolicy.Part(null, 1, 1), MomoMultipartPolicy.part(single, "3gpp"))
        assertTrue(MomoMultipartPolicy.complete(listOf(MomoMultipartPolicy.part(single, "3gpp"))))
    }

    private fun deliver(dcs: Int, udl: Int, data: ByteArray, udhi: Boolean = false): ByteArray =
        byteArrayOf(
            0, if (udhi) 0x40.toByte() else 0.toByte(), 2, 0x91.toByte(), 0x21,
            0, dcs.toByte(), 0, 0, 0, 0, 0, 0, 0, udl.toByte(),
        ) + data

    private fun multipart(dcs: Int, udl: Int, sequence: Int, tail: ByteArray): ByteArray =
        deliver(dcs, udl, byteArrayOf(5, 0, 3, 3, 2, sequence.toByte()) + tail, udhi = true)

    @Test fun singlePartsRequireAllDeclaredUserDataForEachAlphabet() {
        val cases = listOf(
            Triple(0x00, 10, ByteArray(9) { 0x41 }), // 10 GSM7 septets -> 9 octets.
            Triple(0x04, 4, byteArrayOf(0x41, 0x42, 0x43, 0x44)), // 8-bit octets.
            Triple(0x08, 4, byteArrayOf(0, 0x41, 0, 0x42)), // Two UCS2 units.
        )
        for ((dcs, udl, payload) in cases) {
            val valid = deliver(dcs, udl, payload)
            assertEquals(MomoMultipartPolicy.Part(null, 1, 1), MomoMultipartPolicy.part(valid, "3gpp"))
            assertNull(MomoMultipartPolicy.part(valid.copyOf(valid.size - 1), "3gpp"))
            assertNull(MomoMultipartPolicy.part(valid.copyOf(15), "3gpp"))
            assertNull(MomoMultipartPolicy.part(valid + byteArrayOf(0), "3gpp"))
        }
    }

    @Test fun everyConcatenatedPartRequiresItsDeclaredPayload() {
        val cases = listOf(
            Triple(0x00, 10, byteArrayOf(0x41, 0x22, 0x08)), // 6 header octets = 7 septets.
            Triple(0x04, 10, byteArrayOf(0x41, 0x42, 0x43, 0x44)),
            Triple(0x08, 10, byteArrayOf(0, 0x41, 0, 0x42)),
        )
        for ((dcs, udl, tail) in cases) {
            val first = multipart(dcs, udl, 1, tail)
            val second = multipart(dcs, udl, 2, tail)
            assertTrue(MomoMultipartPolicy.complete(listOf(
                MomoMultipartPolicy.part(first, "3gpp"), MomoMultipartPolicy.part(second, "3gpp"),
            )))
            assertNull(MomoMultipartPolicy.part(first.copyOf(first.size - 1), "3gpp"))
            assertFalse(MomoMultipartPolicy.complete(listOf(
                MomoMultipartPolicy.part(first.copyOf(first.size - 1), "3gpp"),
                MomoMultipartPolicy.part(second, "3gpp"),
            )))
        }
    }

    @Test fun sixteenBitConcatenationReferenceUsesSevenOctetHeader() {
        fun part(sequence: Int): ByteArray = deliver(
            0x00, 11, byteArrayOf(6, 8, 4, 0x12, 0x34, 2, sequence.toByte(), 0x41, 0x22, 0x08),
            udhi = true,
        )
        val first = part(1)
        val second = part(2)
        assertEquals(MomoMultipartPolicy.Part(0x1234, 2, 1, 16, 0x00), MomoMultipartPolicy.part(first, "3gpp"))
        assertTrue(MomoMultipartPolicy.complete(listOf(
            MomoMultipartPolicy.part(first, "3gpp"), MomoMultipartPolicy.part(second, "3gpp"),
        )))
        assertNull(MomoMultipartPolicy.part(first.copyOf(first.size - 1), "3gpp"))
    }

    @Test fun headerMustFitDeclaredUnitsAndUcs2PayloadMustBeEven() {
        val header = byteArrayOf(5, 0, 3, 3, 2, 1)
        // Six header octets need seven septets, even when all six octets exist.
        assertNull(MomoMultipartPolicy.part(deliver(0x00, 6, header, udhi = true), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(0x04, 5, header.copyOf(5), udhi = true), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(0x08, 7, header + byteArrayOf(0x41), udhi = true), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(0x08, 3, byteArrayOf(0, 0x41, 0)), "3gpp"))
    }

    @Test fun malformedKnownConcatenationHeadersAreNotSingleParts() {
        val bad8 = byteArrayOf(4, 0, 2, 3, 2, 0x41, 0x42, 0x43, 0x44)
        val bad16 = byteArrayOf(5, 8, 3, 0x12, 0x34, 2, 0x41, 0x42, 0x43, 0x44)
        assertNull(MomoMultipartPolicy.part(deliver(0x04, bad8.size, bad8, udhi = true), "3gpp"))
        assertNull(MomoMultipartPolicy.part(deliver(0x04, bad16.size, bad16, udhi = true), "3gpp"))
        // A well-formed unrelated information element can still be a single part.
        val otherHeader = byteArrayOf(3, 0x70, 1, 0x7f, 0x41, 0x42, 0x43, 0x44)
        assertEquals(MomoMultipartPolicy.Part(null, 1, 1),
            MomoMultipartPolicy.part(deliver(0x04, otherHeader.size, otherHeader, udhi = true), "3gpp"))
    }

    @Test fun knownDcsGroupsUseTheirDeclaredLengthUnits() {
        for (dcs in listOf(0x40, 0xd0, 0xf0)) {
            assertEquals(MomoMultipartPolicy.Part(null, 1, 1),
                MomoMultipartPolicy.part(deliver(dcs, 10, ByteArray(9) { 0x41 }), "3gpp"))
        }
        assertEquals(MomoMultipartPolicy.Part(null, 1, 1),
            MomoMultipartPolicy.part(deliver(0xf4, 4, byteArrayOf(1, 2, 3, 4)), "3gpp"))
        assertEquals(MomoMultipartPolicy.Part(null, 1, 1),
            MomoMultipartPolicy.part(deliver(0xe0, 4, byteArrayOf(0, 0x41, 0, 0x42)), "3gpp"))
    }

    @Test fun unknownOrCompressedDcsAnd3gpp2Abstain() {
        val payload = ByteArray(9) { 0x41 }
        for (dcs in listOf(0x0c, 0x20, 0x80, 0x84, 0xc4, 0xf8)) {
            assertNull(MomoMultipartPolicy.part(deliver(dcs, 10, payload), "3gpp"))
        }
        assertNull(MomoMultipartPolicy.part(deliver(0x00, 10, payload), "3gpp2"))
        assertNull(MomoMultipartPolicy.part(deliver(0x00, 10, payload), null))
    }

    @Test fun tpUserDataRespectsGsm7AndOctetLimits() {
        val cases = listOf(
            Triple(0x00, 160, 161), // 160 septets fit 140 octets; 161 do not.
            Triple(0x04, 140, 141),
            Triple(0x08, 140, 142), // Even UCS2 still exceeds 140 octets.
        )
        for ((dcs, maximum, tooMany) in cases) {
            val maximumOctets = if (dcs == 0) 140 else maximum
            val excessOctets = if (dcs == 0) 141 else tooMany
            assertEquals(MomoMultipartPolicy.Part(null, 1, 1),
                MomoMultipartPolicy.part(deliver(dcs, maximum, ByteArray(maximumOctets)), "3gpp"))
            assertNull(MomoMultipartPolicy.part(deliver(dcs, tooMany, ByteArray(excessOctets)), "3gpp"))
            val maxTail = ByteArray(maximumOctets - 6)
            val tooManyTail = ByteArray(excessOctets - 6)
            assertTrue(MomoMultipartPolicy.complete(listOf(
                MomoMultipartPolicy.part(multipart(dcs, maximum, 1, maxTail), "3gpp"),
                MomoMultipartPolicy.part(multipart(dcs, maximum, 2, maxTail), "3gpp"),
            )))
            assertNull(MomoMultipartPolicy.part(multipart(dcs, tooMany, 1, tooManyTail), "3gpp"))
        }
    }

    @Test fun mixedEightAndSixteenBitReferencesDoNotFormOneMessage() {
        val first = multipart(0x04, 9, 1, ByteArray(3))
        val second = deliver(0x04, 10, byteArrayOf(6, 8, 4, 0, 3, 2, 2, 0, 0, 0), udhi = true)
        assertEquals(MomoMultipartPolicy.Part(3, 2, 1, 8, 0x04), MomoMultipartPolicy.part(first, "3gpp"))
        assertEquals(MomoMultipartPolicy.Part(3, 2, 2, 16, 0x04), MomoMultipartPolicy.part(second, "3gpp"))
        assertFalse(MomoMultipartPolicy.complete(listOf(
            MomoMultipartPolicy.part(first, "3gpp"), MomoMultipartPolicy.part(second, "3gpp"),
        )))
    }

    @Test fun unverifiedDcsOrTrailingBytesKeepCoherentOrderWithoutClaimingComplete() {
        val senders = listOf("MTN", "MTN")
        val times = listOf(1700000000000L, 1700000000000L)
        val tail = byteArrayOf(0x41, 0x22, 0x08)
        val variants = listOf(
            multipart(0xf8, 10, 1, tail) to multipart(0xf8, 10, 2, tail),
            (multipart(0x00, 10, 1, tail) + byteArrayOf(0)) to (multipart(0x00, 10, 2, tail) + byteArrayOf(0)),
        )
        for ((first, second) in variants) {
            val reverse = MomoMultipartPolicy.assemble(senders, times, listOf("WF 100", "R"), listOf(second, first), "3gpp")
            val forward = MomoMultipartPolicy.assemble(senders, times, listOf("R", "WF 100"), listOf(first, second), "3gpp")
            assertFalse(reverse.complete)
            assertFalse(forward.complete)
            assertEquals("RWF 100", reverse.body)
            assertEquals(forward.body, reverse.body)
            assertTrue(MomoGatewayPolicy.memberSource("MTN", reverse.body))
            assertFalse(MomoMultipartPolicy.memberCaptureEligible("MTN", reverse))
            val normalId = MomoGatewayPolicy.captureId("installation", "binding", "MTN", forward.body, times[0], 7)
            assertEquals(normalId, MomoGatewayPolicy.captureId("installation", "binding", "MTN", reverse.body, times[0], 7))
            assertNotEquals(normalId, MomoGatewayPolicy.captureId("installation", "binding", "MTN", "WF 100R", times[0], 7))
        }
    }

    @Test fun incoherentOrMalformedSequencesAreNotReordered() {
        val first = multipart(0xf8, 10, 1, ByteArray(3))
        val second = multipart(0xf8, 10, 2, ByteArray(3))
        val bodies = listOf("WF 100", "R")
        val wrongTime = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 11L), bodies, listOf(second, first), "3gpp")
        val wrongSender = MomoMultipartPolicy.assemble(listOf("MTN", "Airtel"), listOf(10L, 10L), bodies, listOf(second, first), "3gpp")
        val malformed = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L), bodies, listOf(second, first.copyOf(17)), "3gpp")
        val unknownFormat = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L), bodies, listOf(second, first), "3gpp2")
        for (value in listOf(wrongTime, wrongSender, malformed, unknownFormat)) {
            assertFalse(value.complete)
            assertEquals("WF 100R", value.body)
            assertFalse(MomoGatewayPolicy.memberSource("MTN", value.body))
        }
    }

    @Test fun orderedIncompleteBodiesStillUseExistingPrivacyFilter() {
        val first = multipart(0xf8, 10, 1, ByteArray(3))
        val second = multipart(0xf8, 10, 2, ByteArray(3))
        for (prefix in listOf("OTP R", "promo R")) {
            val value = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
                listOf("WF 100", prefix), listOf(second, first), "3gpp")
            assertFalse(value.complete)
            assertEquals(prefix + "WF 100", value.body)
            assertFalse(MomoGatewayPolicy.memberSource("MTN", value.body))
        }
    }

    @Test fun supportedCompletePartsKeepSameBodyInEitherSequenceOrder() {
        val first = multipart(0x00, 10, 1, byteArrayOf(0x41, 0x22, 0x08))
        val second = multipart(0x00, 10, 2, byteArrayOf(0x41, 0x22, 0x08))
        val forward = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("R", "WF 100"), listOf(first, second), "3gpp")
        val reverse = MomoMultipartPolicy.assemble(listOf("MTN", "MTN"), listOf(10L, 10L),
            listOf("WF 100", "R"), listOf(second, first), "3gpp")
        assertTrue(forward.complete)
        assertTrue(reverse.complete)
        assertEquals("RWF 100", forward.body)
        assertEquals(forward.body, reverse.body)
        assertTrue(MomoGatewayPolicy.memberSource("MTN", reverse.body))
        assertTrue(MomoMultipartPolicy.memberCaptureEligible("MTN", reverse))
    }
}
