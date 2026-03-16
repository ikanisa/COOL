import 'dart:convert';
import 'dart:io';

const int _maxUiWords = 4;

const String _wordToken = r"[A-Za-z0-9]+(?:['/-][A-Za-z0-9]+)*";

final RegExp _wordPattern = RegExp(r'\$\{[^}]+\}|\{[^}]+\}|' + _wordToken);
final RegExp _arbUiTokenPattern = RegExp(
  r'\$\{[^}]+\}|\{[^}]+\}|' + _wordToken,
);
final List<RegExp> _uiLiteralPatterns = <RegExp>[
  RegExp(
    "\\b(?:Text|SelectableText)\\s*\\((?:\\s|\\n){0,80}('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    "\\bTextSpan\\s*\\((?:\\s|\\n){0,80}text\\s*:(?:\\s|\\n){0,80}('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\b(?:title|subtitle|label|description|message|tooltip|semanticsLabel|'
    'hintText|helperText|errorText|emptyTitle|emptyMessage|buttonText|cta|'
    'ctaLabel|sheetTitle|sheetSubtitle|body|caption|prompt|headline|'
    'subheadline|supportingText|labelText|hint|value|text)'
    '\\s*:(?:\\s|\\n){0,80}'
    "('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\b(?:_?show[A-Za-z0-9_]*SnackBar|_?show[A-Za-z0-9_]*Toast)\\s*\\('
    '(?:\\s|\\n){0,80}(?:message\\s*:(?:\\s|\\n){0,80})?'
    "('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\bTab\\s*\\((?:[^\\)]*?)(?:text\\s*:(?:\\s|\\n){0,80}'
    "('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\"))",
    dotAll: true,
  ),
  RegExp(
    '\\bInputDecoration\\s*\\((?:[^\\)]*?)(?:labelText|helperText|errorText|hintText)'
    "\\s*:(?:\\s|\\n){0,80}('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\bTextEditingController\\s*\\((?:[^\\)]*?)text\\s*:(?:\\s|\\n){0,80}'
    "('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\bShareParams\\s*\\((?:[^\\)]*?)text\\s*:(?:\\s|\\n){0,80}'
    "('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\bClipboardData\\s*\\((?:[^\\)]*?)text\\s*:(?:\\s|\\n){0,80}'
    "('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
  RegExp(
    '\\b(?:PrismaStatTile|VehicleFilter|_Stat|_StatTile|_SummaryRow|_InfoPill|'
    '_LedgerPill|_TicketChip|_VehicleInfoTile|_MomoStepRow)\\s*\\('
    '(?:[^\\)]*?)(?:label|title|subtitle|text|hint|value)\\s*:'
    "(?:\\s|\\n){0,80}('(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\")",
    dotAll: true,
  ),
];

const Set<String> _excludedDartFiles = <String>{
  'lib/firebase_options.dart',
  'lib/l10n/app_localizations.dart',
  'lib/l10n/app_localizations_en.dart',
};

final class UiCopyViolation {
  const UiCopyViolation({
    required this.path,
    required this.line,
    required this.words,
    required this.value,
  });

  final String path;
  final int line;
  final int words;
  final String value;

  @override
  String toString() {
    return '$path:$line [$words words] $value';
  }
}

void main(List<String> arguments) {
  final Directory repoRoot = Directory.current;
  final List<UiCopyViolation> violations = collectUiCopyViolations(repoRoot);

  if (violations.isEmpty) {
    stdout.writeln('UI copy guard passed.');
    return;
  }

  stderr.writeln(
    'UI copy guard found ${violations.length} violation(s). '
    'Visible UI text must stay at $_maxUiWords words or fewer.',
  );
  for (final UiCopyViolation violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}

List<UiCopyViolation> collectUiCopyViolations(Directory repoRoot) {
  return <UiCopyViolation>[..._scanArb(repoRoot), ..._scanDartFiles(repoRoot)];
}

List<UiCopyViolation> _scanArb(Directory repoRoot) {
  final File arbFile = File('${repoRoot.path}/lib/l10n/app_en.arb');
  final Map<String, dynamic> arb =
      jsonDecode(arbFile.readAsStringSync()) as Map<String, dynamic>;
  final List<String> lines = arbFile.readAsLinesSync();
  final List<UiCopyViolation> violations = <UiCopyViolation>[];

  for (final MapEntry<String, dynamic> entry in arb.entries) {
    if (entry.key.startsWith('@') || entry.value is! String) {
      continue;
    }

    final String value = entry.value as String;
    final int words = _countWords(value, arbContext: true);
    if (words <= _maxUiWords) {
      continue;
    }

    violations.add(
      UiCopyViolation(
        path: 'lib/l10n/app_en.arb',
        line: _findLine(lines, '"${entry.key}"'),
        words: words,
        value: value,
      ),
    );
  }

  return violations;
}

List<UiCopyViolation> _scanDartFiles(Directory repoRoot) {
  final Directory libDir = Directory('${repoRoot.path}/lib');
  final List<UiCopyViolation> violations = <UiCopyViolation>[];
  final Set<String> seen = <String>{};

  for (final FileSystemEntity entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final String relativePath = _relativePath(repoRoot, entity);
    if (_excludedDartFiles.contains(relativePath)) {
      continue;
    }

    final String source = entity.readAsStringSync();
    final List<String> lines = source.split('\n');
    for (int index = 0; index < lines.length; index += 1) {
      final int end = index + 4 < lines.length ? index + 4 : lines.length;
      final String window = lines.sublist(index, end).join('\n');

      for (final RegExp pattern in _uiLiteralPatterns) {
        for (final RegExpMatch match in pattern.allMatches(window)) {
          final String literal = match.group(1)!;
          final String value = _decodeLiteral(literal);
          final int words = _countWords(value);
          if (words <= _maxUiWords) {
            continue;
          }

          final int line = index + _lineNumber(window, match.start);
          final String key = '$relativePath:$line:$value';
          if (!seen.add(key)) {
            continue;
          }

          violations.add(
            UiCopyViolation(
              path: relativePath,
              line: line,
              words: words,
              value: value,
            ),
          );
        }
      }
    }
  }

  violations.sort((UiCopyViolation a, UiCopyViolation b) {
    final int pathCompare = a.path.compareTo(b.path);
    if (pathCompare != 0) {
      return pathCompare;
    }
    return a.line.compareTo(b.line);
  });
  return violations;
}

int _countWords(String value, {bool arbContext = false}) {
  final RegExp tokenPattern = arbContext ? _arbUiTokenPattern : _wordPattern;
  return tokenPattern.allMatches(value).length;
}

String _decodeLiteral(String literal) {
  return _unescapeDartLiteral(literal.substring(1, literal.length - 1));
}

String _unescapeDartLiteral(String value) {
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < value.length; index += 1) {
    final String char = value[index];
    if (char != r'\' || index == value.length - 1) {
      buffer.write(char);
      continue;
    }

    index += 1;
    final String next = value[index];
    switch (next) {
      case 'n':
        buffer.write('\n');
        break;
      case 'r':
        buffer.write('\r');
        break;
      case 't':
        buffer.write('\t');
        break;
      case '\\':
        buffer.write(r'\');
        break;
      case '\'':
        buffer.write('\'');
        break;
      case '"':
        buffer.write('"');
        break;
      default:
        buffer
          ..write(r'\')
          ..write(next);
        break;
    }
  }
  return buffer.toString();
}

int _lineNumber(String source, int offset) {
  return '\n'.allMatches(source.substring(0, offset)).length + 1;
}

int _findLine(List<String> lines, String needle) {
  for (int index = 0; index < lines.length; index += 1) {
    if (lines[index].contains(needle)) {
      return index + 1;
    }
  }
  return 1;
}

String _relativePath(Directory repoRoot, File file) {
  final String rootPath = repoRoot.path.endsWith(Platform.pathSeparator)
      ? repoRoot.path
      : '${repoRoot.path}${Platform.pathSeparator}';
  return file.path.replaceFirst(rootPath, '');
}
