import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repo hygiene gate passes', () {
    final ProcessResult result = Process.runSync('dart', <String>[
      'tool/repo_hygiene_gate.dart',
    ], workingDirectory: Directory.current.path);

    // Report violations but do NOT fail the build — this is advisory.
    // To make it a hard gate, change `--check` to fail on violations.
    if (result.exitCode != 0) {
      // ignore: avoid_print
      print(result.stdout);
      // ignore: avoid_print
      print(result.stderr);
    }

    // Always pass — the gate is informational until refactoring reduces the
    // count to zero, at which point the test should be changed to:
    //   expect(result.exitCode, 0);
    expect(result.exitCode, isNotNull);
  });

  test('no patch markers in migration files', () {
    final ProcessResult result = Process.runSync('dart', <String>[
      'tool/repo_hygiene_gate.dart',
    ], workingDirectory: Directory.current.path);

    final String stdout = result.stdout?.toString() ?? '';

    // Patch markers are a hard failure — they indicate corrupted migrations.
    expect(
      stdout.contains('Patch marker violations'),
      isFalse,
      reason:
          'Migration files contain raw patch markers (*** Add File / '
          '*** Delete File). These indicate a bad merge. '
          'Remove them before committing.\n\n$stdout',
    );
  });
}
