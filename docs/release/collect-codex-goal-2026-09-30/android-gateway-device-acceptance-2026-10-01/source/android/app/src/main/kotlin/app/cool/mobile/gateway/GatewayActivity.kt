package app.cool.mobile.gateway

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/** Default/member Dart bundles have no gatewayMain entrypoint and cannot
 * initialize this sender. The production member MainActivity is untouched. */
class GatewayActivity : FlutterActivity() {
    private var bridge: GatewayBridge? = null
    override fun getDartEntrypointFunctionName(): String = "gatewayMain"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = GatewayBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        bridge?.permissionResult(code)
    }
}
