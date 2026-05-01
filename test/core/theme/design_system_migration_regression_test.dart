import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/repo_paths.dart';

/// Regression test to ensure no feature code uses the deprecated
/// `coolPalette` token directly. All feature code should use
/// `context.coolSemanticColors` instead.
///
/// The only file allowed to reference `coolPalette` is the definition
/// file itself (`cool_palette.dart`) and the theme wiring (`app_theme.dart`).
void main() {
  group('Migration regression', () {
    test('no feature code references coolPalette', () {
      final featuresDir = repoDir('lib/features');
      if (!featuresDir.existsSync()) {
        // Graceful skip if running from a different CWD
        return;
      }

      final violations = <String>[];
      for (final file
          in featuresDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final content = file.readAsStringSync();
        if (content.contains('coolPalette')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Feature code should not reference coolPalette. '
            'Use context.coolSemanticColors instead.\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test('no feature code uses raw GoogleFonts.barlow(', () {
      final featuresDir = repoDir('lib/features');
      if (!featuresDir.existsSync()) return;

      final violations = <String>[];
      for (final file
          in featuresDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final content = file.readAsStringSync();
        if (content.contains('GoogleFonts.barlow(')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Feature code should use context.coolText.display() '
            'instead of raw GoogleFonts.barlow().\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test('no feature code uses AppColors directly', () {
      final featuresDir = repoDir('lib/features');
      if (!featuresDir.existsSync()) return;

      final violations = <String>[];
      for (final file
          in featuresDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final content = file.readAsStringSync();
        // Skip files that import AppColors for migration compat
        if (content.contains('AppColors.') &&
            !content.contains('// legacy-compat')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Feature code should use CoolSemanticColors '
            'instead of AppColors.\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test('admin route screens do not define ad hoc app bars', () {
      final adminScreensDir = repoDir('lib/features/admin/screens');
      if (!adminScreensDir.existsSync()) return;

      final violations = <String>[];
      for (final file
          in adminScreensDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final content = file.readAsStringSync();
        if (content.contains('AppBar(') || content.contains('appBar:')) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Admin route screens should inherit shared admin scaffolds '
            'instead of defining route-level AppBars.\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test(
      'PWA shell no longer references legacy Barlow assets or old theme colors',
      () {
        final pwaDir = repoDir('apps/pwa');
        if (!pwaDir.existsSync()) return;

        final violations = <String>[];
        final bannedPatterns = <Pattern>['Barlow-', '#F3F0EA', '#0D110E'];

        for (final file
            in pwaDir
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.endsWith('.html') ||
                      f.path.endsWith('.css') ||
                      f.path.endsWith('.js') ||
                      f.path.endsWith('.webmanifest'),
                )) {
          final content = file.readAsStringSync();
          if (bannedPatterns.any(content.contains)) {
            violations.add(file.path);
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'PWA assets should use the monolith font pipeline and theme '
              'metadata, not legacy Barlow references or old shell colors.\n'
              'Violations:\n${violations.join('\n')}',
        );
      },
    );
  });
}
