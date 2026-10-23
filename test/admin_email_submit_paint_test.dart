import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository extends AdminEvidenceRepository {
  final sends = <String>[];
  @override
  Future<void> sendEmailOtp({required String email}) async => sends.add(email);
}

Future<void> _visibleForeground(
  WidgetTester tester,
  Finder item,
  Finder boundaryFinder,
  Color background,
) async {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: item, matching: find.byType(RichText)).first,
  );
  final span = paragraph.text as TextSpan;
  final foreground = span.style!.color!;
  final light = foreground.computeLuminance();
  final dark = background.computeLuminance();
  final contrast = light > dark
      ? (light + 0.05) / (dark + 0.05)
      : (dark + 0.05) / (light + 0.05);
  expect(contrast, greaterThanOrEqualTo(4.5));
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final region = tester.getRect(item).shift(-tester.getTopLeft(boundaryFinder));
  final brightPixels = await tester.runAsync(() async {
    final frame = await boundary.toImage();
    final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    var count = 0;
    for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
      for (var x = region.left.ceil(); x < region.right.floor(); x++) {
        final offset = (y * frame.width + x) * 4;
        if (data!.getUint8(offset) > 230 &&
            data.getUint8(offset + 1) > 230 &&
            data.getUint8(offset + 2) > 230) {
          count++;
        }
      }
    }
    frame.dispose();
    return count;
  });
  expect(
    brightPixels,
    greaterThan(8),
    reason: 'Foreground glyphs must be painted visibly in the actual frame.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'retained email form keeps readable submit glyphs across theme changes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      final mode = ValueNotifier(ThemeMode.light);
      addTearDown(mode.dispose);
      const boundaryKey = Key('retained-email-submit-paint');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
            collectBackendClientProvider.overrideWithValue(null),
          ],
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: mode,
            builder: (_, value, child) => MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: value,
              home: child,
            ),
            child: const RepaintBoundary(
              key: boundaryKey,
              child: AdminLoginPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('admin-operator-email')),
        'operator@collect.example',
      );
      for (final verify in [false, true]) {
        if (verify) {
          await tester.tap(find.text('Send code'));
          await tester.pumpAndSettle();
        }
        for (final next in [ThemeMode.dark, ThemeMode.light]) {
          mode.value = next;
          await tester.pumpAndSettle();
          final label = find.text(verify ? 'Verify code' : 'Send code');
          final button = find
              .ancestor(of: label, matching: find.byType(FilledButton))
              .first;
          final material = tester.widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)).first,
          );
          expect(material.color, Colors.black);
          await _visibleForeground(
            tester,
            label,
            find.byKey(boundaryKey),
            material.color!,
          );
          await _visibleForeground(
            tester,
            find.descendant(
              of: button,
              matching: find.byIcon(
                verify ? Icons.verified_user_outlined : Icons.mail_outline,
              ),
            ),
            find.byKey(boundaryKey),
            material.color!,
          );
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const Key('admin-operator-email')),
                )
                .controller!
                .text,
            'operator@collect.example',
          );
          expect(tester.takeException(), isNull);
        }
      }
      expect(repository.sends, ['operator@collect.example']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final verify in [false, true]) {
      testWidgets(
        '${brightness.name} ${verify ? 'Verify code' : 'Send code'} label and icon are painted with readable contrast',
        (tester) async {
          tester.view.physicalSize = const Size(1440, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = _Repository();
          const key = Key('email-submit-paint');
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                adminRepositoryProvider.overrideWithValue(repository),
                collectBackendClientProvider.overrideWithValue(null),
              ],
              child: MaterialApp(
                theme: brightness == Brightness.light
                    ? AppTheme.light()
                    : AppTheme.dark(),
                home: const RepaintBoundary(key: key, child: AdminLoginPage()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (verify) {
            await tester.enterText(
              find.byKey(const Key('admin-operator-email')),
              'operator@collect.example',
            );
            await tester.tap(find.text('Send code'));
            await tester.pumpAndSettle();
            expect(repository.sends, ['operator@collect.example']);
          }
          final label = find.text(verify ? 'Verify code' : 'Send code');
          final button = find
              .ancestor(of: label, matching: find.byType(FilledButton))
              .first;
          final material = tester.widget<Material>(
            find.descendant(of: button, matching: find.byType(Material)).first,
          );
          expect(material.color, Colors.black);
          final icon = find.descendant(
            of: button,
            matching: find.byIcon(
              verify ? Icons.verified_user_outlined : Icons.mail_outline,
            ),
          );
          await _visibleForeground(
            tester,
            label,
            find.byKey(key),
            material.color!,
          );
          await _visibleForeground(
            tester,
            icon,
            find.byKey(key),
            material.color!,
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(key),
              );
              final frame = await boundary.toImage();
              final png = await frame.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '.cache/test-captures/email-operator/email-submit-${verify ? 'verify' : 'send'}-${brightness.name}-synthetic.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              frame.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
