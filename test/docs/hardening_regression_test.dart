import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/governance_docs.dart';

const _migratedRedesignFiles = <String>[
  'lib/features/admin/widgets/manage_app_config_sections.dart',
  'lib/features/admin/widgets/manage_users_parts.dart',
  'lib/features/admin/widgets/manage_admin_roles_parts.dart',
  'lib/features/groups/screens/groups_screen.dart',
  'lib/features/admin/screens/bank_admin_workspace_screen.dart',
];

void main() {
  final repoRoot = Directory.current;

  group('hardening regression boundaries', () {
    test('public AppRoutes constants map to real router paths', () {
      final routeInventory = buildGovernanceDocs(repoRoot).routeInventory;
      final routePaths = RegExp(
        r'^\| `([^`]+)` \|',
        multiLine: true,
      ).allMatches(routeInventory).map((match) => match.group(1)!).toSet();

      final routesSource = File(
        '${repoRoot.path}/lib/core/router/app_routes.dart',
      ).readAsStringSync();

      final orphanedRoutes = <String>[];
      for (final match in RegExp(
        r"static const (\w+) = '([^']+)';",
      ).allMatches(routesSource)) {
        final name = match.group(1)!;
        final path = match.group(2)!;
        if (!routePaths.contains(path)) {
          orphanedRoutes.add('$name -> $path');
        }
      }

      expect(
        orphanedRoutes,
        isEmpty,
        reason: 'Remove dead route constants or add the missing GoRoute.',
      );
    });

    test('raw Hive API usage stays inside the runtime adapter', () {
      final offenders = <String>[];
      for (final entity in Directory(
        '${repoRoot.path}/lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }

        final relativePath = entity.path.substring(repoRoot.path.length + 1);
        if (relativePath == 'lib/core/services/hive_runtime.dart') {
          continue;
        }

        final source = entity
            .readAsStringSync()
            .replaceAll(RegExp(r'//.*$', multiLine: true), '')
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

        if (RegExp(r'\bHive\.').hasMatch(source)) {
          offenders.add(relativePath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Use OpenHiveBox/InitializeHive adapters instead of raw Hive calls '
            'in application code.',
      );
    });

    test('iOS native bootstrap does not hardcode Firebase client config', () {
      final appDelegate = File(
        '${repoRoot.path}/ios/Runner/AppDelegate.swift',
      ).readAsStringSync();

      expect(appDelegate, isNot(contains('FirebaseOptions(')));
      expect(appDelegate, isNot(contains('options.apiKey')));
      expect(appDelegate, isNot(contains('AIza')));
    });

    test('migrated redesign files use semantic theme tokens', () {
      final offenders = <String>[];
      final genericAppColorsPattern = RegExp(
        r'AppColors\.(?:bg|surface|surface2|surface3|border|border2|text|text2|text3|accent|accent2|accentGlow|blue|blueGlow|orange|purple|yellow|red)\b',
      );

      for (final relativePath in _migratedRedesignFiles) {
        final source = _readSanitizedSource(repoRoot, relativePath);
        if (genericAppColorsPattern.hasMatch(source)) {
          offenders.add(relativePath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Use context.coolPalette or theme extensions instead of generic '
            'AppColors semantic getters in migrated redesign files.',
      );
    });

    test('migrated redesign files keep the stronger typography floor', () {
      final offenders = <String>[];
      final smallFontPattern = RegExp(r'fontSize:\s*(?:8|9|10|11|12|13)\b');
      final weakWeightPattern = RegExp(r'FontWeight\.(?:w400|w500)\b');

      for (final relativePath in _migratedRedesignFiles) {
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
            'Migrated redesign files should preserve the larger, heavier '
            'production typography floor.',
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
