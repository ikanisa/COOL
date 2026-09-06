import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/pending_shared_group_intent_store.dart';

/// Runs the same route/state assertions in native UAT and the current gallery.
/// Host captures are explicitly widget renders, never native OS evidence.
class MobileMatrixCapture {
  MobileMatrixCapture._(this.native);

  static const widgetMode = bool.fromEnvironment('COLLECT_WIDGET_REVIEW');
  static const _key = ValueKey('current-mobile-matrix');
  final IntegrationTestWidgetsFlutterBinding? native;
  WidgetTester? _tester;

  static MobileMatrixCapture initialize() {
    if (!widgetMode) {
      return MobileMatrixCapture._(
        IntegrationTestWidgetsFlutterBinding.ensureInitialized(),
      );
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() async {
      for (final font in {
        'Inter': 'assets/typefaces/Inter-Variable.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
    });
    setUp(() {
      const platform = String.fromEnvironment('COLLECT_REVIEW_PLATFORM');
      debugDefaultTargetPlatformOverride = platform == 'ios'
          ? TargetPlatform.iOS
          : TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'checkPermissionStatus' ? 0 : null,
          );
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            null,
          );
    });
    return MobileMatrixCapture._(null);
  }

  static Widget wrap(Widget child) =>
      widgetMode ? RepaintBoundary(key: _key, child: child) : child;

  static List<Override> get overrides => widgetMode
      ? [
          pendingSharedGroupIntentStoreProvider.overrideWithValue(
            PendingSharedGroupIntentStore(
              preferences: _MemoryIntentPreferences(),
            ),
          ),
        ]
      : [];

  static Future<void> flush(WidgetTester tester) async {
    if (!widgetMode) return;
    // Native frames advance real I/O; the host binding needs explicit async
    // turns for fixture file storage and image decoding.
    for (var frame = 0; frame < 3; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> prepare(WidgetTester tester) async {
    _tester = tester;
    if (!widgetMode) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> finish(WidgetTester tester) async {
    if (!widgetMode) return;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> convertFlutterSurfaceToImage() async {
    if (native != null) await native!.convertFlutterSurfaceToImage();
  }

  Future<void> takeScreenshot(String name) async {
    if (native != null) {
      await native!.takeScreenshot(name);
      return;
    }
    final tester = _tester!;
    final context = tester.element(find.byKey(_key));
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .toSet();
    await tester.runAsync(() async {
      for (final image in images) {
        await precacheImage(image, context);
      }
    });
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull, reason: name);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        Platform.environment['COLLECT_MATRIX_CAPTURE_DIR']!,
      )..createSync(recursive: true);
      File(
        '${directory.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }
}

class _MemoryIntentPreferences implements PendingSharedGroupIntentPreferences {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
