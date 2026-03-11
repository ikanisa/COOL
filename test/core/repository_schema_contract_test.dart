import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _fromPattern = RegExp(r"\.from\(\s*'([^']+)'\s*\)");
final _rpcPattern = RegExp(r"\.rpc\(\s*'([^']+)'\s*");
final _createTablePattern = RegExp(
  r'create\s+table(?:\s+if\s+not\s+exists)?\s+public\.([a-zA-Z0-9_]+)',
  caseSensitive: false,
);
final _alterTablePattern = RegExp(
  r'alter\s+table\s+public\.([a-zA-Z0-9_]+)',
  caseSensitive: false,
);
final _createFunctionPattern = RegExp(
  r'create\s+(?:or\s+replace\s+)?function\s+public\.([a-zA-Z0-9_]+)\s*\(',
  caseSensitive: false,
);
final _createViewPattern = RegExp(
  r'create\s+(?:or\s+replace\s+)?view\s+public\.([a-zA-Z0-9_]+)',
  caseSensitive: false,
);

void main() {
  test(
    'repository table and rpc references stay aligned with checked-in migrations',
    () {
      final repositoryFiles =
          Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('_repository.dart'))
              .toList(growable: false)
            ..sort((a, b) => a.path.compareTo(b.path));

      final migrationFiles =
          Directory('supabase/migrations')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.sql'))
              .toList(growable: false)
            ..sort((a, b) => a.path.compareTo(b.path));

      expect(repositoryFiles, isNotEmpty);
      expect(migrationFiles, isNotEmpty);

      final knownTables = <String>{};
      final knownFunctions = <String>{};

      for (final file in migrationFiles) {
        final source = file.readAsStringSync();
        knownTables.addAll(_extractMatches(source, _createTablePattern));
        knownTables.addAll(_extractMatches(source, _alterTablePattern));
        knownTables.addAll(_extractMatches(source, _createViewPattern));
        knownFunctions.addAll(_extractMatches(source, _createFunctionPattern));
      }

      expect(knownTables, isNotEmpty);
      expect(knownFunctions, isNotEmpty);

      final failures = <String>[];

      for (final file in repositoryFiles) {
        final source = file.readAsStringSync();
        final missingTables = _extractMatches(
          source,
          _fromPattern,
        ).difference(knownTables);
        final missingFunctions = _extractMatches(
          source,
          _rpcPattern,
        ).difference(knownFunctions);

        if (missingTables.isNotEmpty) {
          failures.add(
            '${file.path}: missing tables ${missingTables.toList()..sort()}',
          );
        }
        if (missingFunctions.isNotEmpty) {
          failures.add(
            '${file.path}: missing rpc functions ${missingFunctions.toList()..sort()}',
          );
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    },
  );

  test(
    'mobility repositories do not reference removed driver profile columns',
    () {
      final mobilityRepositorySource = File(
        'lib/features/mobility/repositories/mobility_repository.dart',
      ).readAsStringSync();
      final subscriptionRepositorySource = File(
        'lib/features/mobility/repositories/subscription_repository.dart',
      ).readAsStringSync();

      expect(mobilityRepositorySource, isNot(contains("'is_regular_driver'")));
      expect(mobilityRepositorySource, isNot(contains("'last_location_lat'")));
      expect(mobilityRepositorySource, isNot(contains("'last_location_lng'")));
      expect(
        mobilityRepositorySource,
        isNot(contains("'location_updated_at'")),
      );
      expect(
        mobilityRepositorySource,
        isNot(contains("'vehicle_description'")),
      );
      expect(
        subscriptionRepositorySource,
        isNot(contains(".select('credits')")),
      );
    },
  );
}

Set<String> _extractMatches(String source, RegExp pattern) {
  return pattern
      .allMatches(source)
      .map((match) => match.group(1))
      .whereType<String>()
      .toSet();
}
