package app.cool.mobile.momo_sms

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import java.time.Instant

data class MomoSmsNativeConfig(
    val enabled: Boolean,
    val userId: String?,
    val accessToken: String?,
    val refreshToken: String?,
    val accessTokenExpiresAtEpochSeconds: Long?,
    val supabaseUrl: String?,
    val supabaseAnonKey: String?,
    val approvedSenderTokens: Set<String>,
)

class MomoSmsPrefs private constructor(private val context: Context) {
    companion object {
        private const val prefsName = "cool_momo_sms_native_config"
        private const val keyEnabled = "enabled"
        private const val keyUserId = "user_id"
        private const val keyAccessToken = "access_token"
        private const val keyRefreshToken = "refresh_token"
        private const val keyAccessTokenExpiresAt = "access_token_expires_at"
        private const val keySupabaseUrl = "supabase_url"
        private const val keySupabaseAnonKey = "supabase_anon_key"
        private const val keyApprovedSenders = "approved_sender_tokens"

        private val defaultApprovedSenderTokens = setOf(
            "mmoney",
            "mmoneyalerts",
            "mobilemoney",
            "momo",
            "momoalerts",
            "mtnmomo",
            "mtnmomorwanda",
        )

        @Volatile
        private var instance: MomoSmsPrefs? = null

        fun getInstance(context: Context): MomoSmsPrefs {
            return instance ?: synchronized(this) {
                instance ?: MomoSmsPrefs(context.applicationContext).also {
                    instance = it
                }
            }
        }
    }

    private val prefs: SharedPreferences by lazy { createPreferences() }

    private fun createPreferences(): SharedPreferences {
        return try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                prefsName,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (_: Throwable) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        }
    }

    fun load(): MomoSmsNativeConfig {
        return MomoSmsNativeConfig(
            enabled = prefs.getBoolean(keyEnabled, false),
            userId = prefs.getString(keyUserId, null),
            accessToken = prefs.getString(keyAccessToken, null),
            refreshToken = prefs.getString(keyRefreshToken, null),
            accessTokenExpiresAtEpochSeconds = prefs.getLong(keyAccessTokenExpiresAt, 0L)
                .takeIf { value -> value > 0L },
            supabaseUrl = prefs.getString(keySupabaseUrl, null),
            supabaseAnonKey = prefs.getString(keySupabaseAnonKey, null),
            approvedSenderTokens = approvedSenderTokens(),
        )
    }

    fun configure(
        enabled: Boolean,
        userId: String?,
        accessToken: String?,
        refreshToken: String?,
        accessTokenExpiresAtEpochSeconds: Long?,
        supabaseUrl: String?,
        supabaseAnonKey: String?,
        approvedSenderTokens: Collection<String>?,
    ) {
        prefs.edit().apply {
            putBoolean(keyEnabled, enabled)
            writeNullableString(keyUserId, userId)
            writeNullableString(keyAccessToken, accessToken)
            writeNullableString(keyRefreshToken, refreshToken)
            writeNullableString(keySupabaseUrl, supabaseUrl)
            writeNullableString(keySupabaseAnonKey, supabaseAnonKey)
            if (accessTokenExpiresAtEpochSeconds == null || accessTokenExpiresAtEpochSeconds <= 0L) {
                remove(keyAccessTokenExpiresAt)
            } else {
                putLong(keyAccessTokenExpiresAt, accessTokenExpiresAtEpochSeconds)
            }
            if (approvedSenderTokens != null) {
                putString(
                    keyApprovedSenders,
                    JSONArray(approvedSenderTokens.map(MomoSmsNormalizer::normalizeSender)).toString(),
                )
            }
        }.apply()
    }

    fun updateSession(
        accessToken: String,
        refreshToken: String?,
        accessTokenExpiresAtEpochSeconds: Long?,
    ) {
        prefs.edit().apply {
            putString(keyAccessToken, accessToken)
            writeNullableString(keyRefreshToken, refreshToken)
            if (accessTokenExpiresAtEpochSeconds == null || accessTokenExpiresAtEpochSeconds <= 0L) {
                remove(keyAccessTokenExpiresAt)
            } else {
                putLong(keyAccessTokenExpiresAt, accessTokenExpiresAtEpochSeconds)
            }
        }.apply()
    }

    fun clearSession() {
        prefs.edit().apply {
            remove(keyUserId)
            remove(keyAccessToken)
            remove(keyRefreshToken)
            remove(keyAccessTokenExpiresAt)
        }.apply()
    }

    fun currentUserId(): String? = prefs.getString(keyUserId, null)

    fun isEnabled(): Boolean = prefs.getBoolean(keyEnabled, false)

    fun approvedSenderTokens(): Set<String> {
        val raw = prefs.getString(keyApprovedSenders, null)
        if (raw.isNullOrBlank()) {
            return defaultApprovedSenderTokens
        }
        return try {
            val array = JSONArray(raw)
            buildSet {
                for (index in 0 until array.length()) {
                    val token = MomoSmsNormalizer.normalizeSender(array.optString(index))
                    if (token.isNotBlank()) {
                        add(token)
                    }
                }
            }.ifEmpty { defaultApprovedSenderTokens }
        } catch (_: Throwable) {
            defaultApprovedSenderTokens
        }
    }

    fun isApprovedSender(sender: String?): Boolean {
        val token = MomoSmsNormalizer.normalizeSender(sender)
        return token.isNotBlank() && approvedSenderTokens().contains(token)
    }

    fun hasSyncConfiguration(): Boolean {
        val config = load()
        return config.enabled &&
            !config.userId.isNullOrBlank() &&
            !config.supabaseUrl.isNullOrBlank() &&
            !config.supabaseAnonKey.isNullOrBlank()
    }

    fun hasUsableAccessToken(now: Instant = Instant.now()): Boolean {
        val accessToken = prefs.getString(keyAccessToken, null)
        if (accessToken.isNullOrBlank()) {
            return false
        }
        val expiresAt = prefs.getLong(keyAccessTokenExpiresAt, 0L)
        if (expiresAt <= 0L) {
            return true
        }
        return now.plusSeconds(60).epochSecond < expiresAt
    }

    private fun SharedPreferences.Editor.writeNullableString(
        key: String,
        value: String?,
    ) {
        if (value.isNullOrBlank()) {
            remove(key)
        } else {
            putString(key, value)
        }
    }
}
