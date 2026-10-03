import 'package:flutter/material.dart';

import 'gateway/gateway_app.dart';

Future<void> main() => gatewayMain();

// GatewayActivity always requests this entrypoint. A default member bundle
// cannot launch the sender UI/native initialization path.
@pragma('vm:entry-point')
Future<void> gatewayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CollectGatewayApp());
}
