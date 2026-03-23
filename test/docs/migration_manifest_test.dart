import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Ensures every .sql migration file in `supabase/migrations/` is listed
/// in `migration_manifest.yaml` and has at least one valid category tag.
void main() {
  const manifestPath = 'supabase/migrations/migration_manifest.yaml';
  const migrationsDir = 'supabase/migrations';

  final validCategories = <String>{
    'schema',
    'seed',
    'mock',
    'repair',
    'fix',
    'security',
    'cleanup',
    'observability',
  };

  group('Migration manifest completeness', () {
    late YamlMap manifest;
    late Set<String> manifestKeys;
    late List<String> sqlFiles;

    setUpAll(() {
      final raw = File(manifestPath).readAsStringSync();
      final yaml = loadYaml(raw) as YamlMap;
      manifest = yaml['migrations'] as YamlMap;
      manifestKeys = manifest.keys.cast<String>().toSet();

      sqlFiles = Directory(migrationsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
    });

    test('every .sql file appears in the manifest', () {
      final missing = sqlFiles.where((f) => !manifestKeys.contains(f)).toList();
      expect(
        missing,
        isEmpty,
        reason:
            'Migrations not listed in manifest:\n  ${missing.join('\n  ')}',
      );
    });

    test('manifest has no stale entries (files that no longer exist)', () {
      final sqlFileSet = sqlFiles.toSet();
      final stale =
          manifestKeys.where((key) => !sqlFileSet.contains(key)).toList();
      expect(
        stale,
        isEmpty,
        reason:
            'Manifest lists files that do not exist:\n  ${stale.join('\n  ')}',
      );
    });

    test('every manifest entry has at least one valid category', () {
      final invalid = <String>[];
      for (final entry in manifest.entries) {
        final key = entry.key as String;
        final categories = (entry.value as YamlList).cast<String>().toSet();
        if (categories.isEmpty) {
          invalid.add('$key: no categories');
          continue;
        }
        final unknowns = categories.difference(validCategories);
        if (unknowns.isNotEmpty) {
          invalid.add('$key: unknown categories $unknowns');
        }
      }
      expect(
        invalid,
        isEmpty,
        reason: 'Invalid manifest entries:\n  ${invalid.join('\n  ')}',
      );
    });

    test('no duplicate entries in the manifest', () {
      final raw = File(manifestPath).readAsStringSync();
      final occurrences = <String, int>{};
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith('#') ||
            trimmed.startsWith('migrations')) {
          continue;
        }
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx <= 0) continue;
        final key = trimmed.substring(0, colonIdx).trim();
        if (key.endsWith('.sql')) {
          occurrences[key] = (occurrences[key] ?? 0) + 1;
        }
      }
      final duplicates = occurrences.entries
          .where((e) => e.value > 1)
          .map((e) => '${e.key} (${e.value}x)')
          .toList();
      expect(
        duplicates,
        isEmpty,
        reason: 'Duplicate entries:\n  ${duplicates.join('\n  ')}',
      );
    });

    test('category distribution is reasonable', () {
      final counts = <String, int>{};
      for (final entry in manifest.values) {
        for (final cat in (entry as YamlList).cast<String>()) {
          counts[cat] = (counts[cat] ?? 0) + 1;
        }
      }

      // Sanity: schema should be the dominant category
      expect(counts['schema'] ?? 0, greaterThan(50));
      // Sanity: mock data should be a small fraction
      expect(counts['mock'] ?? 0, lessThan(15));
    });
  });
}
