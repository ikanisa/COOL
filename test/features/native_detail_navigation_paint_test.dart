import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/collect_repository_fixture.dart';

void main() {
  testWidgets('iOS group detail keeps four painted navigation targets', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final router = createAppRouter(initialLocation: '/groups');
      final captureKey = GlobalKey();
      addTearDown(() {
        router.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
              collectAuthenticatedUserIdProvider.overrideWithValue(
                'local-user',
              ),
              collectRepositoryProvider.overrideWith(
                (ref) => FixtureCollectRepository(),
              ),
              appRouterProvider.overrideWithValue(router),
              collectThemeModeProvider.overrideWith(
                (ref) => CollectThemeModeController(loadPersistedMode: false),
              ),
            ],
            child: const CollectApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/groups/qa-private-group');
      await tester.pumpAndSettle();
      expect(find.text('QA private group'), findsWidgets);
      expect(tester.takeException(), isNull);

      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      );
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final pixels = data!.buffer.asUint8List();
      final width = image!.width;
      for (final name in ['home', 'groups', 'activity', 'profile']) {
        final target = find.byKey(ValueKey('collect-nav-$name'));
        final rect = tester.getRect(target);
        var foregroundPixels = 0;
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
          for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
            final offset = (y * width + x) * 4;
            if (pixels[offset] > 100 &&
                pixels[offset + 1] > 100 &&
                pixels[offset + 2] > 100 &&
                pixels[offset + 3] > 200) {
              foregroundPixels++;
            }
          }
        }
        expect(
          foregroundPixels,
          greaterThan(50),
          reason: '$name must paint its foreground inside the navigation pill',
        );
      }
      image.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
