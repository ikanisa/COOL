import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/gateway/gateway_app.dart';
import 'package:collect_app/gateway/gateway_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gateway_safety_test.dart' show FakeGateway;

void main() {
  final directory = Platform.environment['COLLECT_GATEWAY_CAPTURE_DIR'];
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
  for (final name in [
    'dark_offline',
    'light_offline',
    'dark_failure',
    'dark_loading',
    'dark_enrollment',
  ]) {
    testWidgets('capture synthetic gateway $name', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue =
          name.startsWith('light') ? Brightness.light : Brightness.dark;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final fake = FakeGateway()..failInitialization = name == 'dark_failure';
      final pending = Completer<GatewaySnapshot>();
      if (name == 'dark_loading') fake.initial = pending.future;
      const key = ValueKey('gateway-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: CollectGatewayApp(platform: fake),
        ),
      );
      if (name == 'dark_loading') {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
      if (name == 'dark_enrollment') {
        await tester.ensureVisible(find.text('Public identity and enrollment'));
        await tester.tap(find.text('Public identity and enrollment'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        await tester.pumpAndSettle();
      }
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Gateway capture unavailable');
        final output = Directory(directory);
        await output.create(recursive: true);
        await File(
          '${output.path}/$name.png',
        ).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      if (name == 'dark_loading') {
        pending.complete(fake.state);
        await tester.pumpAndSettle();
      }
    });
  }
}
