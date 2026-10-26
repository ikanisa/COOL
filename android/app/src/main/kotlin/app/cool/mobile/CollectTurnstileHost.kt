package app.cool.mobile

import android.app.Activity
import android.app.AlertDialog
import android.content.res.Configuration
import android.net.Uri
import androidx.core.net.toUri
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import org.json.JSONObject

/** Challenge-only browser. No auth credential, device permission or arbitrary URL
 * is exposed to its content. Candidate tokens are verified by the API server. */
class CollectTurnstileHost(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private data class Attempt(
        val id: String,
        val url: String,
        val result: MethodChannel.Result,
        val browser: WebView,
        val dialog: AlertDialog,
        val timeout: Runnable,
    )
    private var pending: Attempt? = null
    private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("attempt_id")
        when (call.method) {
            "cancel" -> {
                if (id != null && pending?.id == id) finish(id, null, "captcha_cancelled")
                result.success(null)
            }
            "acquire" -> {
                val fields = (call.arguments as? Map<*, *>)?.keys
                val boundRouting = fields == setOf("attempt_id", "backend_origin", "backend_path") &&
                    call.argument<String>("backend_origin") == ORIGIN && call.argument<String>("backend_path") == PATH
                if (id == null || !uuid.matches(id) ||
                    (fields != setOf("attempt_id") && !boundRouting) ||
                    (BuildConfig.COLLECT_API_PATH_PREFIX.isNotEmpty() && !boundRouting)) {
                    result.error("captcha_unavailable", "Security verification unavailable", null)
                } else if (pending != null || activity.isFinishing || activity.isDestroyed) {
                    result.error("captcha_pending", "Security verification already open", null)
                } else {
                    open(id, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun open(id: String, result: MethodChannel.Result) {
        try {
            val theme = if ((activity.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES) "dark" else "light"
            // The caller supplies only an attempt ID; routing stays native-owned.
            val url = ORIGIN.toUri().buildUpon().path(PATH)
                .appendQueryParameter("attempt_id", id)
                .appendQueryParameter("parent_origin", ORIGIN)
                .appendQueryParameter("theme", theme).build().toString()
            val browser = WebView(activity)
            browser.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
            }
            CookieManager.getInstance().setAcceptThirdPartyCookies(browser, true)
            browser.contentDescription = "Collect security verification"
            val dialog = AlertDialog.Builder(activity).setView(browser)
                .setNegativeButton("Cancel") { _, _ -> finish(id, null, "captcha_cancelled") }
                .create()
            dialog.setOnCancelListener { finish(id, null, "captcha_cancelled") }
            val timeout = Runnable { finish(id, null, "captcha_unavailable") }
            pending = Attempt(id, url, result, browser, dialog, timeout)

            browser.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (allowed(request.url, request.isForMainFrame, url)) return false
                    if (request.isForMainFrame) finish(id, null, "captcha_unavailable")
                    return true
                }
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    return if (allowed(request.url, request.isForMainFrame, url)) null else
                        WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(),
                            ByteArrayInputStream(ByteArray(0)))
                }
                override fun onPageFinished(view: WebView, location: String) {
                    if (pending?.id != id || location != url || view.url != url) return
                    // Main-page-only injection avoids an addJavascriptInterface
                    // object available to every cross-origin challenge frame.
                    view.evaluateJavascript("""
                        window.CollectTurnstile = Object.freeze({postMessage: function(value) {
                          if (typeof value === 'string' && value.length <= 4096) {
                            window.prompt('collect.turnstile.v1', value);
                          }
                        }});
                        window.dispatchEvent(new Event('collect.turnstile.ready'));
                    """.trimIndent(), null)
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) finish(id, null, "captcha_unavailable")
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    if (request.isForMainFrame && response.statusCode >= 400) finish(id, null, "captcha_unavailable")
                }
                override fun onReceivedSslError(view: WebView, ssl: SslErrorHandler, error: SslError) {
                    ssl.cancel(); finish(id, null, "captcha_unavailable")
                }
            }
            browser.webChromeClient = object : WebChromeClient() {
                override fun onJsPrompt(view: WebView, origin: String, message: String,
                    defaultValue: String?, prompt: JsPromptResult): Boolean {
                    prompt.confirm("")
                    if (pending?.id != id || origin != url || view.url != url ||
                        message != ENVELOPE || defaultValue == null || defaultValue.length > 4096) return true
                    try {
                        val envelope = JSONObject(defaultValue)
                        val token = envelope.opt("token")
                        val keys = envelope.keys().asSequence().toSet()
                        if (envelope.opt("type") != ENVELOPE || envelope.opt("attempt_id") != id ||
                            keys != setOf("type", "attempt_id", "token") || token !is String ||
                            token.isEmpty() || token.length > 2048 || token.any { it <= ' ' || it == '\u007f' }) {
                            finish(id, null, "captcha_unavailable")
                        } else {
                            finish(id, defaultValue, null)
                        }
                    } catch (_: Exception) {
                        finish(id, null, "captcha_unavailable")
                    }
                    return true
                }
                override fun onJsAlert(view: WebView, url: String, message: String, result: JsResult): Boolean {
                    result.cancel(); return true
                }
                override fun onJsConfirm(view: WebView, url: String, message: String, result: JsResult): Boolean {
                    result.cancel(); return true
                }
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                    callback.invoke(origin, false, false)
                }
            }
            dialog.show()
            val metrics = activity.resources.displayMetrics
            dialog.window?.setLayout((metrics.widthPixels * 0.94).toInt(), (metrics.heightPixels * 0.8).toInt())
            handler.postDelayed(timeout, 120_000)
            browser.loadUrl(url)
        } catch (_: Exception) {
            if (pending?.id == id) finish(id, null, "captcha_unavailable") else
                result.error("captcha_unavailable", "Security verification unavailable", null)
        }
    }

    private fun allowed(uri: Uri, main: Boolean, expected: String): Boolean {
        if (main) return uri.toString() == expected
        if (uri.toString() == "about:blank" || uri.toString() == "about:srcdoc") return true
        if (uri.scheme != "https" || !uri.userInfo.isNullOrEmpty() ||
            (uri.port != -1 && uri.port != 443)) return false
        return uri.toString() == expected || uri.host == "challenges.cloudflare.com"
    }

    private fun finish(id: String, envelope: String?, error: String?) {
        val attempt = pending?.takeIf { it.id == id } ?: return
        pending = null
        handler.removeCallbacks(attempt.timeout)
        attempt.browser.stopLoading()
        attempt.browser.webChromeClient = null
        attempt.browser.webViewClient = WebViewClient()
        attempt.dialog.dismiss()
        (attempt.browser.parent as? ViewGroup)?.removeView(attempt.browser)
        attempt.browser.destroy()
        if (error == null) attempt.result.success(envelope) else
            attempt.result.error(error, "Security verification could not finish", null)
    }

    fun dispose() { pending?.let { finish(it.id, null, "captcha_cancelled") } }

    companion object {
        private val ORIGIN = "https://${BuildConfig.COLLECT_API_HOST}"
        private val PATH = "${BuildConfig.COLLECT_API_PATH_PREFIX}/v1/security/challenge"
        private const val ENVELOPE = "collect.turnstile.v1"
    }
}
