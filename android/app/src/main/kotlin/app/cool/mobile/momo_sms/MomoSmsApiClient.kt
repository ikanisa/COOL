package app.cool.mobile.momo_sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import javax.net.ssl.HttpsURLConnection

data class MomoSmsBatchMessageResult(
    val success: Boolean,
    val inserted: Boolean,
    val duplicate: Boolean,
    val errorMessage: String? = null,
)

data class MomoSmsBatchUploadResult(
    val results: Map<String, MomoSmsBatchMessageResult>,
    val rateLimited: Boolean = false,
    val errorMessage: String? = null,
)

class MomoSmsApiClient(context: Context) {
    private val prefs = MomoSmsPrefs.getInstance(context)

    fun uploadBatch(records: List<MomoSmsQueueRecord>): MomoSmsBatchUploadResult {
        if (records.isEmpty()) {
            return MomoSmsBatchUploadResult(emptyMap())
        }
        val config = prefs.load()
        val supabaseUrl = config.supabaseUrl?.trim().orEmpty()
        val supabaseAnonKey = config.supabaseAnonKey?.trim().orEmpty()
        if (supabaseUrl.isBlank() || supabaseAnonKey.isBlank()) {
            return MomoSmsBatchUploadResult(
                emptyMap(),
                errorMessage = "Supabase SMS sync configuration is incomplete.",
            )
        }

        var accessToken = config.accessToken
        if (accessToken.isNullOrBlank() || !prefs.hasUsableAccessToken()) {
            accessToken = refreshSession()
        }
        if (accessToken.isNullOrBlank()) {
            return MomoSmsBatchUploadResult(
                emptyMap(),
                errorMessage = "SMS sync session is unavailable.",
            )
        }

        return postBatch(
            supabaseUrl = supabaseUrl,
            supabaseAnonKey = supabaseAnonKey,
            accessToken = accessToken,
            records = records,
            retryOnUnauthorized = true,
        )
    }

    private fun postBatch(
        supabaseUrl: String,
        supabaseAnonKey: String,
        accessToken: String,
        records: List<MomoSmsQueueRecord>,
        retryOnUnauthorized: Boolean,
    ): MomoSmsBatchUploadResult {
        val endpoint = "${supabaseUrl.trimEnd('/')}/functions/v1/sms-ingest"
        val payload = JSONObject().apply {
            put("messages", JSONArray().apply {
                records.forEach { record ->
                    put(JSONObject().apply {
                        put("sender", record.sender)
                        put("smsBody", record.body)
                        put("smsReceivedAt", record.receivedAt.toString())
                        put("deviceMessageKey", record.deviceMessageKey)
                        put("ingestionSource", record.ingestionSource)
                    })
                }
            })
        }

        val response = executeJsonRequest(
            endpoint = endpoint,
            apikey = supabaseAnonKey,
            accessToken = accessToken,
            payload = payload,
        )

        if (response.statusCode == HttpURLConnection.HTTP_UNAUTHORIZED && retryOnUnauthorized) {
            val refreshedToken = refreshSession()
            if (!refreshedToken.isNullOrBlank()) {
                return postBatch(
                    supabaseUrl = supabaseUrl,
                    supabaseAnonKey = supabaseAnonKey,
                    accessToken = refreshedToken,
                    records = records,
                    retryOnUnauthorized = false,
                )
            }
        }

        if (response.statusCode == 429) {
            return MomoSmsBatchUploadResult(
                results = emptyMap(),
                rateLimited = true,
                errorMessage = response.body.ifBlank { "SMS ingest rate limit exceeded." },
            )
        }

        if (response.statusCode !in 200..299) {
            return MomoSmsBatchUploadResult(
                results = emptyMap(),
                errorMessage = response.body.ifBlank {
                    "SMS ingest failed with HTTP ${response.statusCode}."
                },
            )
        }

        return try {
            val json = JSONObject(response.body)
            val results = mutableMapOf<String, MomoSmsBatchMessageResult>()
            val rows = json.optJSONArray("results") ?: JSONArray()
            for (index in 0 until rows.length()) {
                val row = rows.optJSONObject(index) ?: continue
                val deviceMessageKey = row.optString("deviceMessageKey")
                if (deviceMessageKey.isBlank()) {
                    continue
                }
                val success = row.optBoolean("success", false)
                val inserted = row.optBoolean("inserted", false)
                results[deviceMessageKey] = MomoSmsBatchMessageResult(
                    success = success,
                    inserted = inserted,
                    duplicate = success && !inserted,
                    errorMessage = row.optString("error").ifBlank { null },
                )
            }
            MomoSmsBatchUploadResult(results = results)
        } catch (error: Throwable) {
            MomoSmsBatchUploadResult(
                results = emptyMap(),
                errorMessage = error.message ?: "Unable to parse SMS ingest response.",
            )
        }
    }

    private fun refreshSession(): String? {
        val config = prefs.load()
        val refreshToken = config.refreshToken?.trim().orEmpty()
        val supabaseUrl = config.supabaseUrl?.trim().orEmpty()
        val supabaseAnonKey = config.supabaseAnonKey?.trim().orEmpty()
        if (refreshToken.isBlank() || supabaseUrl.isBlank() || supabaseAnonKey.isBlank()) {
            return null
        }

        val endpoint = "${supabaseUrl.trimEnd('/')}/auth/v1/token?grant_type=refresh_token"
        val payload = JSONObject().apply {
            put("refresh_token", refreshToken)
        }
        val response = executeJsonRequest(
            endpoint = endpoint,
            apikey = supabaseAnonKey,
            accessToken = null,
            payload = payload,
        )
        if (response.statusCode !in 200..299) {
            return null
        }
        return try {
            val json = JSONObject(response.body)
            val accessToken = json.optString("access_token").takeIf { it.isNotBlank() } ?: return null
            val nextRefreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() }
            val expiresAtEpochSeconds = when {
                json.has("expires_at") -> json.optLong("expires_at", 0L).takeIf { it > 0L }
                json.has("expires_in") -> Instant.now().epochSecond + json.optLong("expires_in", 0L)
                else -> null
            }
            prefs.updateSession(
                accessToken = accessToken,
                refreshToken = nextRefreshToken,
                accessTokenExpiresAtEpochSeconds = expiresAtEpochSeconds,
            )
            accessToken
        } catch (_: Throwable) {
            null
        }
    }

    private fun executeJsonRequest(
        endpoint: String,
        apikey: String,
        accessToken: String?,
        payload: JSONObject,
    ): HttpResponse {
        val connection = (URL(endpoint).openConnection() as HttpsURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 20_000
            readTimeout = 30_000
            doInput = true
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("apikey", apikey)
            if (!accessToken.isNullOrBlank()) {
                setRequestProperty("Authorization", "Bearer $accessToken")
            }
        }

        return try {
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(payload.toString())
            }
            val body = readResponseBody(connection)
            HttpResponse(connection.responseCode, body)
        } finally {
            connection.disconnect()
        }
    }

    private fun readResponseBody(connection: HttpsURLConnection): String {
        val stream = try {
            connection.inputStream
        } catch (_: Throwable) {
            connection.errorStream
        } ?: return ""
        return stream.bufferedReader().use { reader -> reader.readText() }
    }

    private data class HttpResponse(
        val statusCode: Int,
        val body: String,
    )
}
