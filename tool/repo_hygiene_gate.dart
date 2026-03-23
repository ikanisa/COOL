import 'dart:io';

/// Repo hygiene gate — enforces file-size limits and reports violations.
///
/// Usage:
///   dart tool/repo_hygiene_gate.dart [--max-lines=500] [--check]
///
/// Exit code 1 if any non-exempt file exceeds the threshold.
/// Use `--check` in CI to fail the build on violations.

const int _defaultMaxLines = 500;

/// Files that are generated or intentionally large — exempt from the gate.
const Set<String> _exemptFiles = <String>{
  // Generated l10n output — size is proportional to translation count.
  'lib/l10n/app_localizations.dart',
  'lib/l10n/app_localizations_en.dart',
  'lib/l10n/app_localizations_rw.dart',
  'lib/l10n/app_localizations_fr.dart',
  // Firebase generated config.
  'lib/firebase_options.dart',
  // Generated route definitions (if auto-generated).
  'lib/core/router/app_router.g.dart',
};

/// Directories to skip entirely (vendor, build output, generated, third-party).
const Set<String> _exemptDirs = <String>{
  '.dart_tool',
  'build',
  'ios/Pods',
  'ios/.symlinks',
  'ios/Runner',
  'android/.gradle',
  'android/app',
  'node_modules',
  '.symlinks',
  'third_party',
  '.flutter-plugins',
  'macos',
  'windows',
  'linux',
  'web',
};

/// File extensions to scan.
const Set<String> _scanExtensions = <String>{
  '.dart',
  '.ts',
  '.tsx',
  '.js',
  '.jsx',
};

final class HygieneViolation {
  const HygieneViolation({
    required this.path,
    required this.lines,
    required this.maxLines,
  });

  final String path;
  final int lines;
  final int maxLines;

  @override
  String toString() => '$path: $lines lines (limit: $maxLines)';
}

void main(List<String> arguments) {
  final int maxLines = _parseMaxLines(arguments);
  final bool checkMode = arguments.contains('--check');
  final Directory repoRoot = Directory.current;

  final List<HygieneViolation> violations = scanForViolations(
    repoRoot,
    maxLines: maxLines,
  );

  if (violations.isEmpty) {
    stdout.writeln(
      'Repo hygiene gate passed. '
      'No source files exceed $maxLines lines.',
    );
    return;
  }

  stdout.writeln(
    'Repo hygiene gate: ${violations.length} file(s) exceed $maxLines lines.\n',
  );

  // Group by directory for readability.
  final Map<String, List<HygieneViolation>> grouped =
      <String, List<HygieneViolation>>{};
  for (final HygieneViolation v in violations) {
    final String dir = v.path.contains('/')
        ? v.path.substring(0, v.path.lastIndexOf('/'))
        : '.';
    (grouped[dir] ??= <HygieneViolation>[]).add(v);
  }

  for (final MapEntry<String, List<HygieneViolation>> entry
      in grouped.entries) {
    stdout.writeln('  ${entry.key}/');
    for (final HygieneViolation v in entry.value) {
      final String basename = v.path.split('/').last;
      stdout.writeln('    $basename: ${v.lines} lines');
    }
  }

  stdout.writeln(
    '\nTo fix: refactor/split large files, or add to _exemptFiles in '
    'tool/repo_hygiene_gate.dart if the file is generated.',
  );

  if (checkMode) {
    exitCode = 1;
  }
}

List<HygieneViolation> scanForViolations(
  Directory repoRoot, {
  int maxLines = _defaultMaxLines,
}) {
  final List<HygieneViolation> violations = <HygieneViolation>[];
  final String rootPath = repoRoot.path.endsWith(Platform.pathSeparator)
      ? repoRoot.path
      : '${repoRoot.path}${Platform.pathSeparator}';

  for (final FileSystemEntity entity in repoRoot.listSync(recursive: true)) {
    if (entity is! File) continue;

    final String relativePath = entity.path.replaceFirst(rootPath, '');

    // Skip exempt directories.
    if (_exemptDirs.any(
      (dir) =>
          relativePath.startsWith('$dir/') || relativePath.startsWith('$dir\\'),
    )) {
      continue;
    }

    // Only scan known source extensions.
    final String ext = _extension(relativePath);
    if (!_scanExtensions.contains(ext)) continue;

    // Skip exempt files.
    if (_exemptFiles.contains(relativePath)) continue;

    // Count lines.
    final int lineCount = _countLines(entity);
    if (lineCount > maxLines) {
      violations.add(
        HygieneViolation(
          path: relativePath,
          lines: lineCount,
          maxLines: maxLines,
        ),
      );
    }
  }

  violations.sort((HygieneViolation a, HygieneViolation b) {
    return b.lines.compareTo(a.lines); // Largest first.
  });

  return violations;
}

int _countLines(File file) {
  try {
    return file.readAsLinesSync().length;
  } catch (_) {
    return 0;
  }
}

String _extension(String path) {
  final int dot = path.lastIndexOf('.');
  return dot >= 0 ? path.substring(dot) : '';
}

int _parseMaxLines(List<String> arguments) {
  for (final String arg in arguments) {
    if (arg.startsWith('--max-lines=')) {
      final int? value = int.tryParse(arg.substring('--max-lines='.length));
      if (value != null && value > 0) return value;
    }
  }
  return _defaultMaxLines;
}
