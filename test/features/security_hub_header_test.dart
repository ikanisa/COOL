import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/settings/security_hub_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/font_awesome_flutter/FontAwesomeSolid':
          'packages/font_awesome_flutter/lib/fonts/Font-Awesome-7-Free-Solid-900.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final dark in [false, true]) {
    for (final (width, scale) in [(390.0, 1.0), (390.0, 3.2), (320.0, 3.2)]) {
      testWidgets(
        'security header keeps full scaled title and Back usable ${dark ? 'dark' : 'light'} $width $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var backs = 0;
          final semantics = tester.ensureSemantics();
          const boundary = ValueKey('security-header-review');
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    highContrast: scale > 1,
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SecurityHubHeader(onBack: () => backs++),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final title = find.text('Security');
          final rect = tester.getRect(title);
          expect(rect.left, greaterThanOrEqualTo(16));
          expect(rect.right, lessThanOrEqualTo(width - 16));
          expect(rect.bottom, lessThan(844));
          expect(
            tester
                .getSemantics(title)
                .getSemanticsData()
                .flagsCollection
                .isHeader,
            isTrue,
          );
          final back = find.byTooltip('Back');
          expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(48));
          expect(
            tester
                .getSemantics(back)
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          await tester.tap(back);
          expect(backs, 1);

          final folder =
              Platform.environment['COLLECT_SECURITY_HEADER_CAPTURE_DIR'];
          if (folder != null) {
            final render = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(boundary),
            );
            await tester.runAsync(() async {
              final pixels = await render.toImage(pixelRatio: 1);
              final bytes = (await pixels.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await Directory(folder).create(recursive: true);
              await File(
                '$folder/${dark ? 'dark' : 'light'}-$width-$scale.png',
              ).writeAsBytes(bytes.buffer.asUint8List());
              pixels.dispose();
            });
          }
          semantics.dispose();
        },
      );
    }
  }
}
