package rw.ikanisa.burimunsi.receiverchecks

import app.cool.mobile.receiver_sms.*
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** Pure JVM tests of the actual pinned receiver policies; no Android API stubs. */
private var count = 0
private fun test(name: String, body: () -> Unit) {
    body()
    count++
    println("ok $count - $name")
}
private fun rejects(body: () -> Unit) {
    var rejected = false
    try { body() } catch (_: Exception) { rejected = true }
    check(rejected) { "Expected rejection" }
}
private fun key(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
private fun cipher(key: SecretKey) = ReceiptCipher({ key }, Base64.getEncoder()::encodeToString, Base64.getDecoder()::decode)
private fun pdu(body: ByteArray, dcs: Int = 4, header: ByteArray? = null): ByteArray {
    val data = (header ?: byteArrayOf()) + body
    // Invented SMS-DELIVER frame, not a carrier fixture or proof of Android decoding.
    return byteArrayOf(0, (if (header == null) 0 else 64).toByte(), 2, 0x91.toByte(), 0x21, 0, dcs.toByte(),
        0, 0, 0, 0, 0, 0, 0, data.size.toByte()) + data
}
private fun concatenation(sequence: Int, total: Int = 2, reference: Int = 7) =
    byteArrayOf(5, 0, 3, reference.toByte(), total.toByte(), sequence.toByte())

fun main() {
    println("TAP version 13")
    val cryptKey = key()
    val crypto = cipher(cryptKey)
    test("AES-GCM roundtrip preserves Unicode and exact receipt bytes") {
        val text = "Synthetic receipt: RWF 1,000 — ubwizigame\n\u0000"
        check(crypto.decrypt(crypto.encrypt(text)) == text)
    }
    test("AES-GCM encryptions use different nonces") {
        val a = crypto.encrypt("same")
        val b = crypto.encrypt("same")
        check(a != b)
        check(a.substringBefore('.') != b.substringBefore('.'))
        check(crypto.decrypt(a) == crypto.decrypt(b))
    }
    test("AES-GCM wrong key rejects ciphertext") {
        rejects { cipher(key()).decrypt(crypto.encrypt("synthetic")) }
    }
    test("AES-GCM modified ciphertext fails authentication") {
        val parts = crypto.encrypt("synthetic").split('.')
        val raw = Base64.getDecoder().decode(parts[1]); raw[0] = (raw[0].toInt() xor 1).toByte()
        rejects { crypto.decrypt(parts[0] + "." + Base64.getEncoder().encodeToString(raw)) }
    }
    test("AES-GCM modified IV fails authentication") {
        val parts = crypto.encrypt("synthetic").split('.')
        val raw = Base64.getDecoder().decode(parts[0]); raw[0] = (raw[0].toInt() xor 1).toByte()
        rejects { crypto.decrypt(Base64.getEncoder().encodeToString(raw) + "." + parts[1]) }
    }
    test("AES-GCM malformed envelope and short tag are rejected") {
        rejects { crypto.decrypt("not-an-envelope") }
        rejects { crypto.decrypt(Base64.getEncoder().encodeToString(ByteArray(12)) + ".AA==") }
        rejects { crypto.decrypt("AA==." + Base64.getEncoder().encodeToString(ByteArray(16))) }
    }
    val row = ReceiptAckPolicy.Envelope("capture-1", "owner-A", "exact synthetic body")
    val hash = ReceiptAckPolicy.sha256(row.rawBody)
    test("Acknowledgement accepts exact owner, identity and body hash") {
        check(ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash), listOf(row)))
    }
    test("Acknowledgement rejects a different owner and mixed stored owners") {
        check(!ReceiptAckPolicy.canAcknowledge("owner-B", "owner-A", mapOf(row.id to hash), listOf(row)))
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash), listOf(row.copy(ownerUserId="owner-B"))))
    }
    test("Acknowledgement rejects wrong body, blank hash and empty request") {
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to "a".repeat(64)), listOf(row)))
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to ""), listOf(row)))
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", emptyMap(), listOf(row)))
    }
    test("Acknowledgement rejects duplicate stored identities") {
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash), listOf(row, row)))
    }
    test("Acknowledgement replay requires matching durable tombstone") {
        check(ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash), emptyList(), mapOf(row.id to hash)))
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash), emptyList()))
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash), emptyList(), mapOf(row.id to "b".repeat(64))))
    }
    test("Acknowledgement batch cannot retire an unproved second identity") {
        check(!ReceiptAckPolicy.canAcknowledge("owner-A", "owner-A", mapOf(row.id to hash, "capture-2" to hash), listOf(row)))
    }
    test("Queue reads require enabled capture and the exact owner") {
        check(SmsQueueOwnerPolicy.canRead(true, "owner-A", "owner-A", listOf("owner-A")))
        check(!SmsQueueOwnerPolicy.canRead(false, "owner-A", "owner-A"))
        check(!SmsQueueOwnerPolicy.canRead(true, "owner-A", "owner-B"))
        check(!SmsQueueOwnerPolicy.canRead(true, "owner-A", "owner-A", listOf("owner-B")))
    }
    test("Queue disable cannot be issued by another owner") {
        check(SmsQueueOwnerPolicy.canDisable("owner-A", "owner-A"))
        check(!SmsQueueOwnerPolicy.canDisable("owner-A", "owner-B"))
        check(!SmsQueueOwnerPolicy.canDisable("", ""))
    }
    test("Gateway upload hold remains closed even for otherwise eligible receipt") {
        check(!MomoGatewayPolicy.gatewayUploadsAdmitted())
        check(!MomoGatewayPolicy.uploadEligible("binding", 1, "binding", 1, false, false, "live", true, "M-Money", "Received 1000 RWF"))
    }
    test("Queue reserve protects live capture capacity") {
        check(MomoGatewayPolicy.queueAdmission(899, 1000, 100) == MomoGatewayPolicy.QueueAdmission.AVAILABLE)
        check(MomoGatewayPolicy.queueAdmission(900, 1000, 100) == MomoGatewayPolicy.QueueAdmission.RESERVED)
        check(MomoGatewayPolicy.queueAdmission(999, 1000, 0) == MomoGatewayPolicy.QueueAdmission.AVAILABLE)
        check(MomoGatewayPolicy.queueAdmission(1000, 1000, 0) == MomoGatewayPolicy.QueueAdmission.FULL)
    }
    test("Invalid queue limits are rejected") {
        rejects { MomoGatewayPolicy.queueAdmission(-1, 1000, 100) }
        rejects { MomoGatewayPolicy.queueAdmission(1, 10, 11) }
        rejects { MomoGatewayPolicy.queueAdmission(1, 0, 0) }
    }
    test("Capture identity is stable but changes with binding and subscription") {
        val a = MomoGatewayPolicy.captureId("device", "binding", "M-Money", "body", 1000, 1)
        check(a == MomoGatewayPolicy.captureId("device", "binding", "M-Money", "body", 1000, 1))
        check(a != MomoGatewayPolicy.captureId("device", "other-binding", "M-Money", "body", 1000, 1))
        check(a != MomoGatewayPolicy.captureId("device", "binding", "M-Money", "body", 1000, 2))
    }
    test("Historical recovery requires enrollment boundary and resolved SIM") {
        check(MomoGatewayPolicy.historicalSourceResolved(11, 10, 1, 1, true))
        check(!MomoGatewayPolicy.historicalSourceResolved(10, 10, 1, 1, true))
        check(!MomoGatewayPolicy.historicalSourceResolved(11, null, 1, 1, true))
        check(!MomoGatewayPolicy.historicalSourceResolved(11, 10, null, null, true))
        check(!MomoGatewayPolicy.historicalSourceResolved(11, 10, 1, 2, true))
    }
    test("Source ambiguity is retained when selected SIM does not match") {
        check(MomoGatewayPolicy.sourceResolved(1, 1, true))
        check(!MomoGatewayPolicy.sourceResolved(1, null, false))
        check(!MomoGatewayPolicy.sourceResolved(null, null, true))
    }
    test("Upload response categories do not convert rejection to success") {
        check(MomoGatewayPolicy.uploadFailure(403) == MomoGatewayPolicy.UploadFailure.AUTHORIZATION)
        check(MomoGatewayPolicy.uploadFailure(409) == MomoGatewayPolicy.UploadFailure.SOURCE_CONFLICT)
        check(MomoGatewayPolicy.uploadFailure(422) == MomoGatewayPolicy.UploadFailure.SOURCE_REJECTED)
        check(MomoGatewayPolicy.uploadFailure(429) == MomoGatewayPolicy.UploadFailure.RETRY)
        check(MomoGatewayPolicy.uploadFailure(503) == MomoGatewayPolicy.UploadFailure.RETRY)
    }
    test("Capture text classifier rejects synthetic OTP and promotion") {
        check(!MomoGatewayPolicy.memberSource("M-Money", "Your OTP is 1234 RWF transaction"))
        check(!MomoGatewayPolicy.memberSource("M-Money", "Promotion 1000 RWF"))
        check(!MomoGatewayPolicy.memberSource("personal", "Received 1000 RWF"))
    }
    test("Single bounded 8-bit frame has structural completeness") {
        check(MomoMultipartPolicy.part(pdu("ok".toByteArray()), "3gpp") != null)
    }
    test("Unknown transport and truncated payload abstain") {
        val bytes = pdu("ok".toByteArray())
        check(MomoMultipartPolicy.part(bytes, "3gpp2") == null)
        check(MomoMultipartPolicy.part(bytes.copyOf(bytes.size-1), "3gpp") == null)
        check(MomoMultipartPolicy.part(bytes + byteArrayOf(0), "3gpp") == null)
    }
    test("Multipart reorders coherent segments without editing original bodies") {
        val a = pdu("first".toByteArray(), header=concatenation(1))
        val b = pdu("second".toByteArray(), header=concatenation(2))
        val result = MomoMultipartPolicy.assemble(listOf("M-Money", "M-Money"), listOf(1000L, 1000L), listOf("second", "first"), listOf(b, a), "3gpp")
        check(result.complete)
        check(result.body == "firstsecond")
    }
    test("Multipart missing or duplicate sequence remains incomplete") {
        val a = pdu("first".toByteArray(), header=concatenation(1))
        check(!MomoMultipartPolicy.assemble(listOf("M-Money"), listOf(1000L), listOf("first"), listOf(a), "3gpp").complete)
        check(!MomoMultipartPolicy.assemble(listOf("M-Money", "M-Money"), listOf(1000L, 1000L), listOf("first", "first"), listOf(a, a), "3gpp").complete)
    }
    test("Multipart conflicting sender and timestamp remain incomplete") {
        val a = pdu("first".toByteArray(), header=concatenation(1))
        val b = pdu("second".toByteArray(), header=concatenation(2))
        check(!MomoMultipartPolicy.assemble(listOf("A", "B"), listOf(1000L, 1000L), listOf("first", "second"), listOf(a,b), "3gpp").complete)
        check(!MomoMultipartPolicy.assemble(listOf("A", "A"), listOf(1000L, 2000L), listOf("first", "second"), listOf(a,b), "3gpp").complete)
    }
    test("Multipart conflicting concatenation references remain incomplete") {
        val a = MomoMultipartPolicy.part(pdu("a".toByteArray(), header=concatenation(1)), "3gpp")
        val b = MomoMultipartPolicy.part(pdu("b".toByteArray(), header=concatenation(2, reference=8)), "3gpp")
        check(!MomoMultipartPolicy.complete(listOf(a,b)))
    }
    test("Multipart differing coding metadata remains incomplete") {
        val a = MomoMultipartPolicy.Part(7,2,1,8,4)
        val b = MomoMultipartPolicy.Part(7,2,2,8,8)
        check(!MomoMultipartPolicy.complete(listOf(a,b)))
    }
    test("Malformed UCS2 code unit and high-bit 8-bit payload abstain") {
        check(MomoMultipartPolicy.part(pdu(byteArrayOf(0xd8.toByte(),0), dcs=8), "3gpp") == null)
        check(MomoMultipartPolicy.part(pdu(byteArrayOf(0x80.toByte()), dcs=4), "3gpp") == null)
        check(MomoMultipartPolicy.part(pdu(byteArrayOf(0,0x41), dcs=8), "3gpp") != null)
    }
    test("Incomplete multipart cannot enter member capture classification") {
        check(!MomoMultipartPolicy.memberCaptureEligible("M-Money", MomoMultipartPolicy.Assembly("Received 1000 RWF", false)))
    }
    test("Wakeup gate has a single concurrent owner") {
        val gate = MomoGatewayWakeupGate()
        val executor = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val done = CountDownLatch(32)
        val wins = AtomicInteger()
        try {
            repeat(32) { executor.execute { try { start.await(); if (gate.begin()) wins.incrementAndGet() } finally { done.countDown() } } }
            start.countDown()
            check(done.await(5,TimeUnit.SECONDS))
            check(wins.get()==1)
        } finally { executor.shutdownNow() }
    }
    test("Wakeup gate serializes finish before recheck") {
        val gate = MomoGatewayWakeupGate()
        val events = mutableListOf<String>()
        check(gate.begin())
        gate.signal { events.add("premature") }
        gate.finish({ events.add("finished") }) { events.add("rechecked"); gate.signal { events.add("scheduled") } }
        check(events == listOf("finished","rechecked","scheduled"))
        check(gate.begin())
    }
    test("Metadata event listener failures do not suppress other listeners") {
        val initial = SmsQueueEventBus.currentSequence()
        var observed = 0L
        val fail: (Long)->Unit = { throw IllegalStateException("synthetic") }
        val good: (Long)->Unit = { observed = it }
        SmsQueueEventBus.addListener(fail)
        SmsQueueEventBus.addListener(good)
        try { SmsQueueEventBus.notifyQueueChanged(); check(observed==initial+1) }
        finally { SmsQueueEventBus.removeListener(fail); SmsQueueEventBus.removeListener(good) }
        SmsQueueEventBus.notifyQueueChanged()
        check(observed==initial+1)
    }
    println("1..$count")
    println("# Scope: actual pinned pure Kotlin receiver policies on JVM; not Android or carrier qualification.")
}
