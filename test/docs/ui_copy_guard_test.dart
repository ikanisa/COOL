import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory repoRoot = Directory.current;

  test('ui copy stays concise', () {
    final ProcessResult result = Process.runSync('dart', <String>[
      'tool/ui_copy_guard.dart',
    ], workingDirectory: repoRoot.path);

    if (result.exitCode != 0) {
      fail(
        'UI copy guard failed.\n'
        '${result.stderr}',
      );
    }
  });
}
