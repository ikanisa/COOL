import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _guardedUiSurfaceFiles = <String>[
  'lib/features/home/screens/home_screen.dart',
  'lib/features/profile/screens/profile_sub_screens.dart',
  'lib/features/biopay/screens/biopay_home_screen.dart',
  'lib/shared/widgets/kill_switch_gate.dart',
];

void main() {
  final repoRoot = Directory.current;

  group('UI surface system regression', () {
    test('guarded surfaces stay on semantic colors and typography helpers', () {
      final offenders = <String>[];
      final bannedPattern = RegExp(
        r'AppColors\.|CoolPalette|GoogleFonts\.|Color\(0x|Colors\.greenAccent',
      );

      for (final relativePath in _guardedUiSurfaceFiles) {
        final source = _readSanitizedSource(repoRoot, relativePath);
        if (bannedPattern.hasMatch(source)) {
          offenders.add(relativePath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Guarded UI surfaces must use semantic theme tokens and '
            'context.coolText helpers instead of raw colors, legacy palettes, '
            'or direct GoogleFonts calls.\n'
            'Violations:\n${offenders.join('\n')}',
      );
    });

    test('guarded surfaces keep the stronger typography floor', () {
      final offenders = <String>[];
      final smallFontPattern = RegExp(r'fontSize:\s*(?:8|9|10|11|12|13)\b');
      final weakWeightPattern = RegExp(r'FontWeight\.(?:w400|w500)\b');

      for (final relativePath in _guardedUiSurfaceFiles) {
        final source = _readSanitizedSource(repoRoot, relativePath);
        if (smallFontPattern.hasMatch(source) ||
            weakWeightPattern.hasMatch(source)) {
          offenders.add(relativePath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Guarded UI surfaces should preserve the current stronger '
            'typography contract.\n'
            'Violations:\n${offenders.join('\n')}',
      );
    });
  });
}

String _readSanitizedSource(Directory repoRoot, String relativePath) {
  return File('${repoRoot.path}/$relativePath')
      .readAsStringSync()
      .replaceAll(RegExp(r'//.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
}
