package rw.ikanisa.burimunsi.core

import java.math.BigInteger
import java.net.URI
import java.security.MessageDigest
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.UUID

class ContractFailure(val code: String) : IllegalArgumentException(code)
fun checkContract(test: Boolean, code: String) { if (!test) throw ContractFailure(code) }
object Values {
    const val MAX_RWF: Long = 9_007_199_254_740_991L
    fun phone(input: String): String {
        checkContract(input.length <= 40 && Regex("[+0-9 ()-]+").matches(input), "invalid_phone")
        var p = input.trim().replace(Regex("[ ()-]"), "")
        if (p.startsWith("00")) p = "+" + p.drop(2)
        p = when {
            Regex("0[0-9]{9}").matches(p) -> "+250" + p.drop(1)
            Regex("[0-9]{9}").matches(p) -> "+250$p"
            Regex("250[0-9]{9}").matches(p) -> "+$p"
            else -> p
        }
        checkContract(Regex("\\+2507[2389][0-9]{7}").matches(p), "invalid_phone")
        return p
    }
    fun pin(input: String): String {
        checkContract(Regex("[0-9]{4}").matches(input), "invalid_passcode")
        return input
    }
    fun amount(raw: String, positive: Boolean = true): Long {
        checkContract(raw.length <= 24 && Regex("(0|[1-9][0-9]*|[1-9][0-9]{0,2}(,[0-9]{3})+)").matches(raw), "invalid_amount")
        val n = BigInteger(raw.replace(",", ""))
        checkContract(n >= BigInteger.valueOf(if (positive) 1 else 0) && n <= BigInteger.valueOf(MAX_RWF), "invalid_amount")
        return n.toLong()
    }
    fun at(raw: String, offsetMinutes: Int): String {
        checkContract(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}").matches(raw), "invalid_timestamp")
        checkContract(offsetMinutes in -840..840, "provider_timezone_required")
        val format = DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm:ss").withResolverStyle(ResolverStyle.STRICT)
        val local = try { LocalDateTime.parse(raw, format) } catch (_: Exception) { throw ContractFailure("invalid_timestamp") }
        return local.toInstant(ZoneOffset.ofTotalSeconds(offsetMinutes * 60)).toString()
    }
    fun requestId(input: String): String {
        checkContract(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}").matches(input), "invalid_request_id")
        return UUID.fromString(input).toString()
    }
    fun id(input: String): String {
        checkContract(Regex("[A-Za-z0-9][A-Za-z0-9_-]{0,127}").matches(input), "invalid_id")
        return input
    }
    fun sha256(input: String): String = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    fun apiOrigin(input: String): URI {
        val uri = try { URI(input) } catch (_: Exception) { throw ContractFailure("configuration_required") }
        checkContract(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.rawQuery == null && uri.rawFragment == null && (uri.path.isNullOrEmpty() || uri.path == "/"), "configuration_required")
        return URI(uri.scheme, null, uri.host, uri.port, null, null, null)
    }
}
