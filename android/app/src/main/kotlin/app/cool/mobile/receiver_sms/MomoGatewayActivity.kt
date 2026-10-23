package app.cool.mobile.receiver_sms

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import app.cool.mobile.BuildConfig
import androidx.core.net.toUri
import org.json.JSONObject
import org.json.JSONArray
import java.time.Instant
import java.util.concurrent.Executors

/** Dedicated receiving-phone task surface. Neutral utility treatment, adapted from LIVE-006. */
class MomoGatewayActivity : Activity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var busy = false
    private var error: String? = null
    private var codeDraft = ""
    private var codeInput: EditText? = null
    private var pairingAgain = false
    private var foreground = false
    private val queueListener: (Long) -> Unit = { runOnUiThread { if (foreground && !busy) render() } }
    private lateinit var store: MomoGatewayStore
    private var inter: Typeface? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (BuildConfig.FLAVOR != "internal_receiver") { finish(); return }
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        store = MomoGatewayStore(applicationContext)
        inter = try { Typeface.createFromAsset(assets, "flutter_assets/assets/typefaces/Inter-Variable.ttf") } catch (_: Exception) { Typeface.DEFAULT }
        codeDraft = savedInstanceState?.getString("code_draft").orEmpty()
        pairingAgain = savedInstanceState?.getBoolean("pairing_again") ?: false
        SmsQueueEventBus.addListener(queueListener)
    }
    override fun onResume() {
        super.onResume(); foreground = true; render()
        try { MomoGatewayJobs.ensure(this) } catch (_: Exception) { error = "Background sync needs attention."; render() }
    }
    override fun onPause() { foreground = false; super.onPause() }
    override fun onDestroy() { SmsQueueEventBus.removeListener(queueListener); executor.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("code_draft", codeInput?.text?.toString() ?: codeDraft)
        out.putBoolean("pairing_again", pairingAgain)
        super.onSaveInstanceState(out)
    }

    private fun render() {
        if (isFinishing || isDestroyed) return
        codeInput?.let { codeDraft = it.text.toString() }
        codeInput = null
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.BLACK); isFillViewport = true }
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(24), dp(24), dp(32)) }
        scroll.addView(layout)
        scroll.setOnApplyWindowInsetsListener { view, insets ->
            view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }
        layout.addView(text("Collect", 18, true))
        layout.addView(text("MoMo receiving phone", 30, true), margin(20))
        layout.addView(text("Capture provider receipts and sync them securely.", 16, false, MUTED), margin(10))
        val state = try { store.read() } catch (_: Exception) {
            layout.addView(text("Protected phone data is unavailable. Unlock and reopen Collect. Existing evidence has been retained.", 17), margin(24))
            setContentView(scroll); return
        }
        error?.let { layout.addView(text(it, 16, false, ERROR).apply { accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE }, margin(20)) }
        val binding = state?.optJSONObject("binding")
        if (binding == null || pairingAgain) {
            layout.addView(text("Pair this dedicated phone", 20, true), margin(28))
            layout.addView(text("Enter the single-use pairing code from an authorised Collect administrator.", 16, false, MUTED), margin(8))
            codeInput = EditText(this).apply {
                setText(codeDraft); hint = "Pairing code"; contentDescription = "Pairing code"
                setTextColor(Color.WHITE); setHintTextColor(MUTED); textSize = 18f; typeface = inter
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                setPadding(dp(16), dp(14), dp(16), dp(14)); background = rounded(SURFACE, 16)
                isEnabled = !busy
                if (android.os.Build.VERSION.SDK_INT >= 26) importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            }
            layout.addView(codeInput, margin(20))
            layout.addView(button(if (busy) "Pairing…" else "Pair phone", true) { pair() }, margin(16))
            if (binding != null) layout.addView(button("Cancel pairing") { pairingAgain = false; render() }, margin(8))
        } else {
            val owner = binding.getString("owner_user_id")
            val queue = try { SmsQueueStore(this).readForGateway(owner) } catch (_: Exception) { null }
            val unresolved = queue?.let { rows -> (0 until rows.length()).count {
                val row = rows.getJSONObject(it)
                row.optBoolean("source_unresolved", true) || row.optString("gateway_binding_id") != binding.getString("id") ||
                    row.optInt("gateway_binding_version") != binding.getInt("version")
            } }
            val reason = state.optString("reason")
            val cases = state.optJSONObject("source_cases") ?: JSONObject()
            val parkedCount = queue?.let { rows -> (0 until rows.length()).count { cases.sourceParked(rows.getJSONObject(it).optString("id")) } } ?: 0
            val overflowed = getSharedPreferences(SmsQueueStore.SMS_ACCESS_PREFS, MODE_PRIVATE)
                .getBoolean(SmsQueueStore.SMS_QUEUE_OVERFLOW_KEY, false)
            val permissions = granted(Manifest.permission.RECEIVE_SMS) && granted(Manifest.permission.READ_SMS)
            val status = when {
                reason == "authorization_required" || parkedCount > 0 || queue == null || overflowed -> "Action needed"
                !permissions || !state.optBoolean("capture_enabled") || reason == "permission_required" -> "Capture paused"
                reason == "connection_waiting" -> "Waiting for connection"
                unresolved != null && unresolved > 0 -> "Source review needed"
                else -> "Ready to capture"
            }
            val card = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(18), dp(20), dp(18)); background = rounded(SURFACE, 24) }
            card.addView(text(binding.optString("recipient_name", "Receiving account"), 20, true))
            card.addView(text("MoMo code ${binding.optString("public_code")}", 17, false, MUTED), margin(8))
            card.addView(text(status, 18, true).apply { accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE }, margin(22))
            card.addView(text("Pending uploads  ${queue?.length()?.toString() ?: "Unavailable"}", 16), margin(14))
            if (unresolved != null && unresolved > 0) card.addView(text("$unresolved sources need receiving-account review. Their original messages remain on this phone; they have not been assigned to the current wallet.", 15, false, MUTED), margin(12))
            if (state.optBoolean("historical_backlog_paused")) card.addView(text("Older inbox recovery is paused until retained sources can be reviewed. Space is reserved for new receipts.", 15, false, ERROR), margin(12))
            if (overflowed) card.addView(text("Capture storage reached its limit. Sync retained receipts and ask an administrator to review recovery. Existing evidence has been preserved.", 15, false, ERROR), margin(12))
            if (parkedCount > 0) card.addView(text("$parkedCount uploads need source review. Other eligible receipts continue syncing.", 15, false, ERROR), margin(12))
            card.addView(text("Last upload  ${displayTime(state.optString("last_upload_at"))}", 15, false, MUTED), margin(14))
            card.addView(text("Last provider SMS  ${displayTime(state.optString("last_sms_at"))}", 15, false, MUTED), margin(10))
            layout.addView(card, margin(28))
            if (reason == "authorization_required") {
                layout.addView(text("Ask an administrator to restore this phone’s ingestion authorisation. Pending evidence remains protected.", 16, false, ERROR), margin(18))
            } else if (!permissions || !state.optBoolean("capture_enabled") || reason == "permission_required") {
                layout.addView(button("Enable SMS capture", true) { requestCapture() }, margin(24))
            } else {
                layout.addView(button(if (busy) "Syncing…" else "Sync now", true) { sync() }, margin(24))
                layout.addView(button("Pause capture") { task {
                    store.update { it.put("capture_enabled", false) }
                    check(SmsQueueStore(this).disablePreservingQueue(owner))
                } }, margin(8))
            }
            layout.addView(button("Phone settings") { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:$packageName".toUri())) }, margin(8))
            layout.addView(button("Diagnostics") { diagnostics(state, queue?.length()) }, margin(8))
            if (parkedCount > 0) {
                layout.addView(button("Review retained uploads") {
                    val details = cases.keys().asSequence().filter { cases.sourceParked(it) }.take(20).joinToString("\n\n") { id ->
                        val source = cases.getJSONObject(id)
                        "$id\n${if (source.optString("reason") == "capture_conflict") "Capture conflict" else "Source rejected"} (HTTP ${source.optInt("http_status")})"
                    }
                    AlertDialog.Builder(this).setTitle("Retained source cases").setMessage(details)
                        .setPositiveButton("Done", null).show()
                }, margin(8))
                layout.addView(button("Retry reviewed uploads") {
                    AlertDialog.Builder(this).setTitle("Retry original retained uploads?")
                        .setMessage("Retry after an administrator has reviewed or repaired the source problem. The original messages, identities and receiving bindings stay unchanged.")
                        .setPositiveButton("Retry") { _, _ -> task { store.retryReviewedSources(); MomoGatewayJobs.signal(this) } }
                        .setNegativeButton("Cancel", null).show()
                }, margin(8))
            }
            layout.addView(button("Pair again") {
                AlertDialog.Builder(this).setTitle("Pair this phone again?")
                    .setMessage("Capture will pause. Retained sources keep their original receiving-account binding and may require administrator review.")
                    .setPositiveButton("Continue") { _, _ -> task {
                        store.update { it.put("capture_enabled", false) }
                        check(SmsQueueStore(this).disablePreservingQueue(owner))
                        pairingAgain = true
                    } }.setNegativeButton("Cancel", null).show()
            }, margin(8))
        }
        setContentView(scroll)
    }

    private fun pair() {
        val code = codeInput?.text?.toString()?.trim().orEmpty()
        if (code.length !in 4..128) { error = "Enter the pairing code provided by your administrator."; render(); return }
        codeDraft = code
        task {
            val result = MomoGatewayHttp().request("pair", body = JSONObject().put("pairing_code", code).put("installation_id", store.installationId()))
            val binding = result.getJSONObject("binding")
            val token = result.getString("gateway_token")
            check(binding.getString("id").isNotEmpty() && binding.getInt("version") > 0 && binding.getString("owner_user_id").isNotEmpty() &&
                binding.getString("receiving_account_id").isNotEmpty() && token.isNotEmpty()) { "Invalid pairing response" }
            check(SmsQueueStore(this).enableForOwner(binding.getString("owner_user_id")))
            check(SmsQueueStore(this).disablePreservingQueue(binding.getString("owner_user_id")))
            store.update {
                it.optJSONObject("binding")?.let { previous ->
                    val history = it.optJSONArray("previous_bindings") ?: JSONArray()
                    history.put(previous); it.put("previous_bindings", history)
                }
                it.put("binding", binding).put("gateway_token", token).put("paired_at", Instant.now().toString())
                    .put("capture_enabled", false).put("reason", "").put("inbox_checkpoint", 0L)
                it.remove("inbox_binding_baseline")
            }
            codeDraft = ""
            pairingAgain = false
        }
    }

    private fun requestCapture() {
        AlertDialog.Builder(this).setTitle("Allow provider SMS capture?")
            .setMessage("This dedicated phone will save messages from configured MoMo providers and upload them to Collect. SMS access also recovers retained inbox receipts after an outage. Older messages with an uncertain receiving account stay unassigned for review. Other phone messages are not uploaded.")
            .setPositiveButton("Allow and continue") { _, _ -> requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS), 6041) }
            .setNegativeButton("Not now", null).show()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 6041) return
        if (!granted(Manifest.permission.RECEIVE_SMS) || !granted(Manifest.permission.READ_SMS)) {
            error = "SMS capture needs access to new receipts and inbox recovery. Enable it in phone settings when ready."; render(); return
        }
        task {
            val snapshot = store.read() ?: throw IllegalStateException("Phone is not paired")
            val baseline = if (snapshot.has("inbox_binding_baseline")) snapshot.getLong("inbox_binding_baseline") else MomoGatewayRecovery(this).latestInboxId()
            check(SmsQueueStore(this).enableForOwner(snapshot.getJSONObject("binding").getString("owner_user_id")))
            store.update { it.put("capture_enabled", true).put("reason", ""); if (baseline != null) it.put("inbox_binding_baseline", baseline) }
            MomoGatewayJobs.ensure(this)
        }
    }
    private fun sync() = task {
        MomoGatewayRecovery(this).catchUp()
        MomoGatewayJobs.ensure(this)
        val snapshot = store.read() ?: return@task
        val result = MomoGatewayHttp().request("status", snapshot.getString("gateway_token"))
        val serverPending = result.getInt("pending_processing")
        check(serverPending >= 0)
        store.update { it.put("last_contact_at", Instant.now().toString()).put("server_pending_processing", serverPending) }
    }
    private fun diagnostics(state: JSONObject, count: Int?) {
        val binding = state.getJSONObject("binding")
        val configuredSubscription = binding.optionalInt("subscription_id")
        val retained = try { SmsQueueStore(this).readForGateway(store.owner()) } catch (_: Exception) { null }
        val observedSubscriptions = retained?.let { rows -> (0 until rows.length())
            .mapNotNull { rows.getJSONObject(it).optionalInt("subscription_id") }.distinct().sorted() }
        val sourcesWithoutSubscription = retained?.let { rows -> (0 until rows.length())
            .count { rows.getJSONObject(it).optionalInt("subscription_id") == null } }
        val details = "SMS access: ${if (granted(Manifest.permission.RECEIVE_SMS)) "Allowed" else "Required"}\n" +
            "Inbox recovery: ${if (granted(Manifest.permission.READ_SMS)) "Allowed" else "Required"}\n" +
            "Configured receiving subscription: ${configuredSubscription?.toString() ?: "Not supplied"}\n" +
            "Observed receipt subscription IDs: ${if (observedSubscriptions == null) "Unavailable" else observedSubscriptions.joinToString().ifEmpty { "None retained" }}\n" +
            "Retained sources without subscription metadata: ${sourcesWithoutSubscription?.toString() ?: "Unavailable"}\n" +
            "Observed network: ${observedNetwork()}\n" +
            "Battery optimisation: ${observedPower { if (it.isIgnoringBatteryOptimizations(packageName)) "Exempt" else "Subject to Android optimisation" }}\n" +
            "Battery saver: ${observedPower { if (it.isPowerSaveMode) "On" else "Off" }}\n" +
            "Android background restriction: ${observedBackgroundRestriction()}\n" +
            "Last server contact: ${displayTime(state.optString("last_contact_at"))}\n" +
            "Pending sources: ${count?.toString() ?: "Unavailable"}\n" +
            "Oldest pending: ${try { SmsQueueStore(this).queueMetadata(store.owner()).second ?: "None" } catch (_: Exception) { "Unavailable" }}\n" +
            "App version: ${BuildConfig.VERSION_NAME}\n" +
            "Binding version: ${binding.optInt("version")}\n\n" +
            "On a phone with multiple SIM slots, one inserted SIM does not establish the receiving-account mapping. Ask an administrator to pair this phone with the observed subscription ID for the receiving SIM. No default SIM is selected automatically. If metadata is unavailable, retain the source for authorised review. Subscription IDs may change after a SIM replacement; earlier sources keep their original binding.\n\n" +
            "Unlock after reboot and reopen after a force-stop to recover retained inbox receipts. Background timing depends on Android and the connection."
        AlertDialog.Builder(this).setTitle("Phone diagnostics").setMessage(details).setPositiveButton("Done", null).show()
    }
    private fun observedNetwork(): String = try {
        if (checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) "Unavailable (network-state access missing)"
        else {
            val manager = getSystemService(ConnectivityManager::class.java)
            val network = manager?.activeNetwork
            when {
                manager == null -> "Unavailable"
                network == null -> "No active network observed"
                else -> {
                    val capabilities = manager.getNetworkCapabilities(network)
                    if (capabilities == null) "Unknown (network state changed)"
                    else {
                        val transports = listOf(
                            NetworkCapabilities.TRANSPORT_WIFI to "Wi-Fi",
                            NetworkCapabilities.TRANSPORT_CELLULAR to "Mobile data",
                            NetworkCapabilities.TRANSPORT_ETHERNET to "Ethernet",
                            NetworkCapabilities.TRANSPORT_VPN to "VPN",
                            NetworkCapabilities.TRANSPORT_BLUETOOTH to "Bluetooth",
                        ).filter { capabilities.hasTransport(it.first) }.joinToString(" + ") { it.second }.ifEmpty { "Other transport" }
                        val internet = when {
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL) -> "captive portal observed"
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) -> "internet validated by Android"
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "internet not yet validated"
                            else -> "internet capability not observed"
                        }
                        "$transports; $internet"
                    }
                }
            }
        }
    } catch (_: Exception) { "Unavailable" }
    private fun observedPower(read: (PowerManager) -> String): String = try {
        getSystemService(PowerManager::class.java)?.let(read) ?: "Unavailable"
    } catch (_: Exception) { "Unavailable" }
    private fun observedBackgroundRestriction(): String = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
        "Not available on this Android version"
    } else try {
        getSystemService(ActivityManager::class.java)?.let {
            if (it.isBackgroundRestricted) "Restricted" else "Not restricted by Android"
        } ?: "Unavailable"
    } catch (_: Exception) { "Unavailable" }
    private fun task(action: () -> Unit) {
        if (busy) return
        busy = true; error = null; render()
        executor.execute {
            var failure: String? = null
            try { action() } catch (problem: MomoGatewayHttp.ResponseFailure) {
                failure = when (problem.status) {
                    401, 403 -> "This phone needs renewed authorisation from an administrator."
                    409 -> "The request conflicts with existing evidence. Ask an administrator to review it."
                    else -> "Collect could not complete the request. Check the connection and retry."
                }
                if (problem.status in setOf(401, 403) && store.binding() != null) try { store.park("authorization_required") } catch (_: Exception) { }
            } catch (_: Exception) { failure = "The operation could not be completed. Existing evidence has been retained." }
            runOnUiThread { busy = false; error = failure; if (foreground) render() }
        }
    }
    private fun granted(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    private fun displayTime(value: String): String = if (value.isBlank()) "Not yet observed" else value.replace('T', ' ').removeSuffix("Z") + " UTC"
    private fun text(value: String, size: Int, strong: Boolean = false, colour: Int = Color.WHITE) = TextView(this).apply {
        text = value; textSize = size.toFloat(); setTextColor(colour); typeface = Typeface.create(inter, if (strong) Typeface.BOLD else Typeface.NORMAL); setLineSpacing(dp(3).toFloat(), 1f)
    }
    private fun button(label: String, primary: Boolean = false, action: () -> Unit) = Button(this).apply {
        text = label; isAllCaps = false; textSize = 17f; typeface = inter; minHeight = dp(52); minimumHeight = dp(52)
        setTextColor(if (primary) Color.BLACK else Color.WHITE); background = rounded(if (primary) Color.WHITE else SURFACE, 26)
        setPadding(dp(20), dp(12), dp(20), dp(12)); isEnabled = !busy; alpha = if (busy) .5f else 1f; setOnClickListener { action() }
    }
    private fun margin(top: Int) = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(top) }
    private fun rounded(colour: Int, radius: Int) = GradientDrawable().apply { setColor(colour); cornerRadius = dp(radius).toFloat() }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    companion object { private val SURFACE = Color.rgb(22, 23, 25); private val MUTED = Color.rgb(169, 171, 177); private val ERROR = Color.rgb(255, 157, 157) }
}
