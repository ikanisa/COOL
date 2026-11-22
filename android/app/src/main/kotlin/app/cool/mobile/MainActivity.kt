package app.cool.mobile

import android.content.Intent
import android.os.Build
import android.os.Bundle
import app.cool.mobile.receiver_sms.MemberSmsJobs
import app.cool.mobile.receiver_sms.MomoGatewayActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var turnstileHost: CollectTurnstileHost? = null
    private val smsAccess = MemberSmsAccessChannel(this)
    private val momo = MemberMomoChannel(this)
    private val playIntegrity = MemberPlayIntegrityChannel(this)
    private val storage = MemberProtectedChannels(this, smsAccess)

    override fun onDestroy() {
        momo.cancelPendingPermission()
        turnstileHost?.dispose()
        turnstileHost = null
        super.onDestroy()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Flutter paints focus on individual controls. Android's default
            // host-view highlight adds a green frame around the whole app
            // after hardware keyboard input, including while the IME is open.
            findViewById<FlutterView>(FLUTTER_VIEW_ID)
                ?.setDefaultFocusHighlightEnabled(false)
        }
    }

    override fun onResume() {
        super.onResume()
        MemberSmsJobs.ensure(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        turnstileHost?.dispose()
        val challengeHost = CollectTurnstileHost(this)
        turnstileHost = challengeHost
        MethodChannel(messenger, "collect/turnstile")
            .setMethodCallHandler { call, result -> challengeHost.handle(call, result) }

        storage.register(messenger)
        smsAccess.registerEvents(messenger)
        MethodChannel(messenger, "collect/momo_gateway")
            .setMethodCallHandler { call, result ->
                if (call.method != "openMomoGateway") result.notImplemented()
                else if (BuildConfig.FLAVOR != "internal_receiver") result.success(false)
                else {
                    startActivity(Intent(this, MomoGatewayActivity::class.java))
                    result.success(true)
                }
            }
        smsAccess.registerMethods(messenger)
        momo.register(messenger)
        playIntegrity.register(messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        momo.cancelPendingPermission()
        smsAccess.unregisterEvents()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (!momo.onRequestPermissionsResult(requestCode)) {
            smsAccess.onRequestPermissionsResult(requestCode)
        }
    }
}
