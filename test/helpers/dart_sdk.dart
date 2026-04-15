import 'dart:io';

/// Resolves the `dart` binary from FVM or Flutter SDK discovery.
///
/// Mirrors the candidate chain in `scripts/flutterw` so that tests which
/// spawned `Process.runSync('dart', ...)` work when `dart` is not on
/// the global shell PATH.
String resolveDartBinary() {
  // Fast path: dart already on PATH.
  final whichResult = Process.runSync('which', <String>['dart']);
  if (whichResult.exitCode == 0) {
    final path = (whichResult.stdout as String).trim();
    if (path.isNotEmpty) {
      return path;
    }
  }

  final repoRoot = _findRepoRoot();

  final candidates = <String>[
    // FLUTTER_BIN / FLUTTER_ROOT env vars
    ..._fromEnvFlutterBin(),
    // FVM local SDK
    '$repoRoot/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
    // Sibling SDK directories
    '$repoRoot/../Apps/SDKs/flutter/bin/cache/dart-sdk/bin/dart',
    '$repoRoot/../SDKs/flutter/bin/cache/dart-sdk/bin/dart',
    // FVM global default
    '${Platform.environment['HOME']}/fvm/default/bin/cache/dart-sdk/bin/dart',
    '${Platform.environment['HOME']}/.fvm/default/bin/cache/dart-sdk/bin/dart',
  ];

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  // Last resort: assume `dart` will somehow resolve at invocation time.
  return 'dart';
}

/// Returns the `dart` binary path derived from FLUTTER_BIN or FLUTTER_ROOT.
List<String> _fromEnvFlutterBin() {
  final paths = <String>[];
  final flutterBin = Platform.environment['FLUTTER_BIN'];
  if (flutterBin != null && flutterBin.isNotEmpty) {
    // FLUTTER_BIN points at the flutter binary; dart lives alongside it.
    final dir = File(flutterBin).parent.path;
    paths.add('$dir/cache/dart-sdk/bin/dart');
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    paths.add('$flutterRoot/bin/cache/dart-sdk/bin/dart');
  }
  return paths;
}

/// Walk up from `Directory.current` until we find `pubspec.yaml`.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      // Reached filesystem root; fall back to cwd.
      return Directory.current.path;
    }
    dir = parent;
  }
}
