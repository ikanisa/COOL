package app.cool.mobile.gateway

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import java.security.cert.Certificate
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class GatewayTransportTest {
    private class Connection(url: URL, val status: Int = 200, val body: ByteArray = "{}".toByteArray(), val waitMs: Long = 0,
                             val onOutput: () -> Unit = {}) : HttpsURLConnection(url) {
        val output = ByteArrayOutputStream()
        @Volatile var disconnected = false
        override fun connect() = Unit
        override fun disconnect() { disconnected = true }
        override fun usingProxy() = false
        override fun getCipherSuite() = "synthetic"
        override fun getLocalCertificates(): Array<Certificate>? = null
        override fun getServerCertificates(): Array<Certificate> = emptyArray()
        override fun getOutputStream(): OutputStream { onOutput(); if (waitMs > 0) Thread.sleep(waitMs); return output }
        override fun getInputStream(): InputStream = ByteArrayInputStream(body)
        override fun getResponseCode() = status
    }
    private fun unknown(action: () -> Unit) {
        try { action(); fail("Expected unknown outcome") }
        catch (error: GatewayStateException) { assertEquals("gateway_http_outcome_unknown", error.reasonCode) }
    }
    @Test fun exactBytesAndSignatureHeadersUseOnlyGovernedHttpsWithoutBearerOrRedirects() {
        var calls=0; var signed:ByteArray?=null; lateinit var connection:Connection
        val transport=GatewayHttpsTransport({"a".repeat(64)}, { signed=it.copyOf(); "synthetic DER base64" }, { url ->
            calls++; assertEquals("https",url.protocol); assertEquals(GatewayHttpsTransport.HOST,url.host)
            assertEquals("/functions/v1/collect-android-gateway",url.path); assertNull(url.query)
            Connection(url).also { connection=it }
        })
        val bytes="{\"issued_at\":\"synthetic\",\"request_id\":\"opaque\"}".toByteArray()
        transport.postExact(bytes)
        assertEquals(1,calls); assertArrayEquals(bytes,signed); assertArrayEquals(bytes,connection.output.toByteArray())
        assertEquals("a".repeat(64),connection.getRequestProperty("X-Collect-Gateway-Key-Id"))
        assertNull(connection.getRequestProperty("Authorization")); assertFalse(connection.instanceFollowRedirects)
        assertFalse(connection.useCaches); assertTrue(connection.disconnected)
    }
    @Test fun redirectAndRevocationAreUnknownWithoutASecondRequest() {
        for (status in listOf(301,302,307,401,403,500)) {
            var calls=0
            val transport=GatewayHttpsTransport({"a".repeat(64)},{"synthetic"},{ url -> calls++; Connection(url,status) })
            unknown { transport.postExact("{}".toByteArray()) }; assertEquals(1,calls)
        }
    }
    @Test fun overBoundResponseStaysUnknownAndIsNotRetried() {
        var calls=0
        val transport=GatewayHttpsTransport({"a".repeat(64)},{"synthetic"},{ url -> calls++; Connection(url,body=ByteArray(65537)) })
        unknown { transport.postExact("{}".toByteArray()) }; assertEquals(1,calls)
    }
    @Test fun timeoutDisconnectsAndPreservesUnknownWithoutRetry() {
        val calls=AtomicInteger(); val outputStarted=CountDownLatch(1)
        lateinit var connection:Connection
        val transport=GatewayHttpsTransport({"a".repeat(64)},{"synthetic"},{ url ->
            calls.incrementAndGet()
            Connection(url,waitMs=10_000,onOutput={ outputStarted.countDown() }).also { connection=it }
        },5_000)
        val caller=Executors.newSingleThreadExecutor()
        try {
            val outcome=caller.submit { unknown { transport.postExact("{}".toByteArray()) } }
            assertTrue("The fake I/O must start before checking its timeout cleanup",outputStarted.await(4,TimeUnit.SECONDS))
            outcome.get(8,TimeUnit.SECONDS)
            assertEquals(1,calls.get()); assertTrue(connection.disconnected)
        } finally { caller.shutdownNow() }
    }
    @Test fun deadlineBeforeConnectionDoesNotOpenConnectionAfterSignerReturns() {
        val signingStarted=CountDownLatch(1); val releaseSigner=CountDownLatch(1)
        val signerFinished=CountDownLatch(1); val calls=AtomicInteger()
        val transport=GatewayHttpsTransport({"a".repeat(64)},{
            signingStarted.countDown()
            // Model a platform operation which ignores interruption until it
            // completes. Abandonment must still win before the HTTP seam.
            while (releaseSigner.count > 0) {
                try { releaseSigner.await() } catch (_:InterruptedException) { }
            }
            signerFinished.countDown(); "synthetic"
        },{ url -> calls.incrementAndGet(); Connection(url) },5_000)
        val caller=Executors.newSingleThreadExecutor()
        try {
            val outcome=caller.submit { unknown { transport.postExact("{}".toByteArray()) } }
            assertTrue(signingStarted.await(4,TimeUnit.SECONDS))
            outcome.get(8,TimeUnit.SECONDS)
            releaseSigner.countDown()
            assertTrue(signerFinished.await(2,TimeUnit.SECONDS))
            // Queue a normal request on the same single worker: its completion
            // proves the abandoned task has passed its connection gate.
            GatewayHttpsTransport({"a".repeat(64)},{"synthetic"},{ url -> Connection(url) }).postExact("{}".toByteArray())
            assertEquals(0,calls.get())
        } finally { releaseSigner.countDown(); caller.shutdownNow() }
    }
    @Test fun missingIdentityOrOversizedRequestCannotOpenConnection() {
        var calls=0
        val invalid=GatewayHttpsTransport({"bad"},{"synthetic"},{ url -> calls++; Connection(url) })
        try { invalid.postExact("{}".toByteArray()); fail() } catch (_:GatewayStateException) { }
        val large=GatewayHttpsTransport({"a".repeat(64)},{"synthetic"},{ url -> calls++; Connection(url) })
        try { large.postExact(ByteArray(32769)); fail() } catch (_:GatewayStateException) { }
        assertEquals(0,calls)
    }
}
