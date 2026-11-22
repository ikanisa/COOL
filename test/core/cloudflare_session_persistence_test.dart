import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mobile session uses a distinct protected native namespace', () async {
    const channel = MethodChannel('collect/secure_auth_session');
    final methods = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call);
      return call.method == 'read' ? 'synthetic-protected-value' : true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const storage = CollectNativeSessionStorage();
    expect(await storage.read(), 'synthetic-protected-value');
    await storage.write('synthetic-renewable-session');
    await storage.clear();
    expect(methods.map((m) => m.method), ['read', 'write', 'clear']);
    expect(
      (methods[1].arguments as Map)['owner_id'],
      '00000000-0000-4000-8000-000000000001',
    );
  });
  test('failed native clear cannot be acknowledged as successful', () async {
    const channel = MethodChannel('collect/secure_auth_session');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      const CollectNativeSessionStorage().clear(),
      throwsStateError,
    );
  });
}
