package app.cool.mobile

import android.app.Activity
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class MemberPlayIntegrityChannel(private val activity: Activity) {
    private var standardIntegrityProvider:
        StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private val pendingIntegrityResults = mutableListOf<Pair<String, MethodChannel.Result>>()
    private var preparingIntegrityProvider = false

    fun register(messenger: BinaryMessenger) {
        MethodChannel(
            messenger,
            "collect/play_integrity",
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestStandardToken") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val requestHash = call.argument<String>("request_hash")?.trim().orEmpty()
            if (!requestHash.matches(Regex("^[0-9a-f]{64}$"))) {
                result.error("play_integrity_bad_request", "request_hash is invalid", null)
                return@setMethodCallHandler
            }
            requestPlayIntegrityToken(requestHash, result)
        }
    }

    private fun requestPlayIntegrityToken(
        requestHash: String,
        result: MethodChannel.Result,
    ) {
        val cloudProjectNumber = BuildConfig.PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER
        if (cloudProjectNumber <= 0L) {
            result.error(
                "play_integrity_not_configured",
                "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER is not configured",
                null,
            )
            return
        }
        val provider = standardIntegrityProvider
        if (provider != null) {
            provider.request(
                StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
                    .setRequestHash(requestHash)
                    .build(),
            ).addOnSuccessListener { token -> result.success(token.token()) }
                .addOnFailureListener { error ->
                    result.error(
                        "play_integrity_token_failed",
                        error.message ?: "Play Integrity token request failed",
                        null,
                    )
                }
            return
        }
        pendingIntegrityResults.add(Pair(requestHash, result))
        if (preparingIntegrityProvider) return
        preparingIntegrityProvider = true
        IntegrityManagerFactory.createStandard(activity.applicationContext)
            .prepareIntegrityToken(
                StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
                    .setCloudProjectNumber(cloudProjectNumber)
                    .build(),
            )
            .addOnSuccessListener { prepared ->
                standardIntegrityProvider = prepared
                preparingIntegrityProvider = false
                val pending = pendingIntegrityResults.toList()
                pendingIntegrityResults.clear()
                pending.forEach { requestPlayIntegrityToken(it.first, it.second) }
            }
            .addOnFailureListener { error ->
                preparingIntegrityProvider = false
                val pending = pendingIntegrityResults.toList()
                pendingIntegrityResults.clear()
                pending.forEach {
                    it.second.error(
                        "play_integrity_prepare_failed",
                        error.message ?: "Play Integrity preparation failed",
                        null,
                    )
                }
            }
    }
}
