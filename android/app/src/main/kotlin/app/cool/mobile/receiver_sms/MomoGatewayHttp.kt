package app.cool.mobile.receiver_sms

import app.cool.mobile.BuildConfig
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class MomoGatewayHttp {
    class ResponseFailure(val status: Int) : Exception("Gateway request needs attention")
    fun request(path: String, token: String? = null, body: JSONObject? = null): JSONObject {
        require(path in setOf("pair", "ingest", "status", "heartbeat"))
        val connection = URL("https://${BuildConfig.COLLECT_API_HOST}${BuildConfig.COLLECT_API_PATH_PREFIX}/v1/momo/gateway/$path").openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 15_000
        connection.readTimeout = 20_000
        connection.requestMethod = if (body == null) "GET" else "POST"
        connection.setRequestProperty("Accept", "application/json")
        if (BuildConfig.COLLECT_PUBLISHABLE_KEY.isNotEmpty()) connection.setRequestProperty("apikey", BuildConfig.COLLECT_PUBLISHABLE_KEY)
        if (token != null) {
            require(token.length in 1..16_384 && !token.contains('\r') && !token.contains('\n'))
            connection.setRequestProperty("Authorization", "Bearer $token")
        }
        try {
            if (body != null) {
                val bytes = body.toString().toByteArray(Charsets.UTF_8)
                require(bytes.size <= 262_144)
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
            }
            val status = connection.responseCode
            if (status !in 200..299) throw ResponseFailure(status)
            val bytes = connection.inputStream.use { stream ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    check(out.size() + count <= 131_072) { "Gateway response limit exceeded" }
                    out.write(buffer, 0, count)
                }
                out.toByteArray()
            }
            return JSONObject(bytes.toString(Charsets.UTF_8))
        } finally { connection.disconnect() }
    }
}
