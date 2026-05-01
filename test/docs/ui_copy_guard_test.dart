import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sdk.dart';
import '../helpers/repo_paths.dart';

void main() {
  final Directory root = repoRoot();

  late String dartBin;

  setUpAll(() {
    dartBin = resolveDartBinary();
  });

  test('ui copy stays concise', () {
    final ProcessResult result = Process.runSync(dartBin, <String>[
      'tool/ui_copy_guard.dart',
    ], workingDirectory: root.path);

    if (result.exitCode != 0) {
      fail(
        'UI copy guard failed.\n'
        '${result.stderr}',
      );
    }
  });
}
