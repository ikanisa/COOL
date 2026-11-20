package app.cool.mobile.receiver_sms

import android.telephony.SmsMessage
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.ReceiptParser
import rw.ikanisa.burimunsi.core.ReceiptProfile
import java.io.File
import java.security.MessageDigest

/** Optional, private carrier-observation corpus. This is decoding/replay, NOT live delivery.
 * An absent corpus is skipped, never a passed carrier qualification. Payloads and decoded
 * bodies must never enter assertion messages, logcat, the repository or public test reports.
 */
@RunWith(AndroidJUnit4::class)
class CarrierFixtureReplayTest {
    private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }
    @Test fun decodeConsentedCarrierObservations() {
        val args = InstrumentationRegistry.getArguments()
        val relative = args.getString("carrierFixtureDirectory").orEmpty()
        assumeTrue("NOT_RUN: no approved private carrier corpus supplied", relative.isNotBlank())
        check(relative.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { "Invalid private corpus directory" }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.packageName.endsWith(".debug")) { "Disposable debug package required" }
        val root = File(context.filesDir, relative).canonicalFile
        check(root.parentFile == context.filesDir.canonicalFile && root.isDirectory)
        fun bytes(name: String): ByteArray {
            check(name.matches(Regex("[A-Za-z0-9_.-]{1,100}")) && name !in setOf(".", ".."))
            val file=File(root,name)
            check(file.canonicalFile.parentFile==root && file.isFile && file.length() in 1..65536)
            return file.readBytes()
        }
        val manifest=JSONObject(bytes("manifest.json").toString(Charsets.UTF_8))
        check(manifest.getString("corpus_kind")=="consented_carrier_observations")
        check(manifest.getString("consent_reference").isNotBlank())
        val cases=manifest.getJSONArray("cases"); check(cases.length() in 1..200)
        for (index in 0 until cases.length()) {
            val fixture=cases.getJSONObject(index)
            check(fixture.getString("carrier").isNotBlank() && fixture.getString("observed_at").isNotBlank())
            val format=fixture.getString("format"); check(format in setOf("3gpp","3gpp2"))
            val entries=fixture.getJSONArray("pdus"); check(entries.length() in 1..16)
            val pdus=(0 until entries.length()).map { number ->
                val entry=entries.getJSONObject(number); val raw=bytes(entry.getString("file"))
                check(sha(raw)==entry.getString("sha256")) { "PDU integrity mismatch" }; raw
            }
            val messages=pdus.map { SmsMessage.createFromPdu(it,format) ?: error("PDU decoding failed") }
            val assembled=MomoMultipartPolicy.assemble(messages.map { it.originatingAddress.orEmpty() },
                messages.map { it.timestampMillis }, messages.map { it.messageBody }, pdus, format)
            assertTrue("Decoded body integrity mismatch", sha(assembled.body.toByteArray(Charsets.UTF_8))==fixture.getString("decoded_body_sha256"))
            assertEquals("Completeness result differs", fixture.getBoolean("expected_complete"), assembled.complete)
            var formatAccepted=true
            try {
                ReceiptParser.parse(messages.first().originatingAddress.orEmpty(), assembled.body, true,
                    ReceiptProfile(manifest.getString("profile_version"), setOf("M-Money"), manifest.getInt("utc_offset_minutes")))
            } catch (_: ContractFailure) { formatAccepted=false }
            assertEquals("Receipt grammar result differs",fixture.getBoolean("expected_format_accepted"),formatAccepted)
        }
    }
}
