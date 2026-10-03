import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:collect_app/gateway/gateway_platform.dart';
import 'gateway_device_probe.dart';

Future<void> main() => gatewayMain();

// The real restricted flavor's GatewayActivity selects this entrypoint.
@pragma('vm:entry-point')
Future<void> gatewayMain() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android gateway observes local identity and state without sends',
    (tester) async {
      binding.reportData = await observeGatewayWithoutSending(
        const NativeGatewayPlatform(),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
