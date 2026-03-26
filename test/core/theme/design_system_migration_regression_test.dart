import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression test to ensure no feature code uses the deprecated
/// `coolPalette` token directly. All feature code should use
/// `context.coolSemanticColors` instead.
///
/// The only file allowed to reference `coolPalette` is the definition
/// file itself (`cool_palette.dart`) and the theme wiring (`app_theme.dart`).
void main() {
  group('Migration regression', () {
    test('no feature code references coolPalette', () {
      final featuresDir = Directory('lib/features');
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
      final featuresDir = Directory('lib/features');
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
            'Feature code should use context.coolText.rayon() '
            'instead of raw GoogleFonts.barlow().\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test('no feature code uses AppColors directly', () {
      final featuresDir = Directory('lib/features');
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
  });
}
