import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/repo_paths.dart';

void main() {
  test('admin web source has no production placeholder actions', () {
    final Directory adminSource = repoDir('apps/admin/src');
    expect(adminSource.existsSync(), isTrue);

    final List<String> violations = <String>[];
    for (final FileSystemEntity entity in adminSource.listSync(
      recursive: true,
    )) {
      if (entity is! File) continue;
      if (!_isScannedSourceFile(entity.path)) continue;

      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        final String lower = line.toLowerCase();

        if (lower.contains('coming soon') || line.contains('toast.info(')) {
          violations.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Production admin pages must not expose dead or placeholder actions. '
          'Wire the flow to real backend state, hide the action, or explicitly '
          'move it to a non-production surface.\n${violations.join('\n')}',
    );
  });
}

bool _isScannedSourceFile(String path) {
  return path.endsWith('.ts') || path.endsWith('.tsx');
}
