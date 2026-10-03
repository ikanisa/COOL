import 'dart:async';

import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/features/status/native_permission_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });
  for (final viewport in [const Size(320, 640), const Size(740, 360)]) {
    for (final camera in [true, false]) {
      testWidgets(
        '${camera ? 'Camera' : 'SMS'} recovery remains readable and reachable '
        'at $viewport with 200% text',
        (tester) async {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(bottom: 24);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          var retries = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: CollectTheme.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => unawaited(
                      camera
                          ? showCameraAccessSheet(
                              context,
                              onRetry: () => retries++,
                            )
                          : showSmsAccessSheet(
                              context,
                              onRetry: () => retries++,
                            ),
                    ),
                    child: const Text('Open permission'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open permission'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final explanation = find.textContaining(
            camera ? 'without storing photos' : 'does not read inbox history',
          );
          expect(explanation, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(explanation).didExceedMaxLines,
            isFalse,
          );
          final retry = find.text(camera ? 'Scan again' : 'Retry');
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          expect(retry.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.byType(Scrollable)).bottom,
            lessThanOrEqualTo(viewport.height - 24),
            reason: 'the sheet stays above native bottom system chrome',
          );
          expect(find.text('Open app settings').hitTestable(), findsOneWidget);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(retries, 1);
          expect(explanation, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
