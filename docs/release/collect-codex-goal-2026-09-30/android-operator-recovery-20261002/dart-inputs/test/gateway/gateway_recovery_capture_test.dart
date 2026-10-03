import 'dart:io';
import 'dart:ui' as ui;
import 'package:collect_app/gateway/gateway_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gateway_recovery_test.dart' show FakeRecovery, parsed, recovery;
import 'gateway_safety_test.dart' show FakeGateway;

void main() {
  final directory =
      Platform.environment['COLLECT_GATEWAY_RECOVERY_CAPTURE_DIR'];
  if (directory == null) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  for (final variant in ['dark_task', 'dark_opaque']) {
    testWidgets('capture recovery $variant', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakeRecovery();
      if (variant == 'dark_opaque') {
        fake.current = parsed(
          recovery(
            operation: 'restore',
            state: 'complete',
            phase: 'complete',
            key: false,
            count: 12,
            files: 12,
            sha: 'a' * 64,
          ),
        );
      }
      const key = ValueKey('recovery-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: CollectGatewayApp(
            platform: FakeGateway(),
            recoveryPlatform: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Journal recovery'));
      await tester.tap(find.text('Journal recovery'));
      await tester.pumpAndSettle();
      if (variant == 'dark_opaque') {
        await tester.ensureVisible(find.text('Inactive evidence retained'));
      }
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Capture unavailable');
        final output = Directory(directory);
        await output.create(recursive: true);
        await File(
          '${output.path}/$variant.png',
        ).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }
}
