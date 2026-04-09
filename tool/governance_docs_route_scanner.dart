part of 'governance_docs.dart';

int _firstPositiveIndex(List<int> indexes) {
  var first = -1;
  for (final index in indexes) {
    if (index == -1) {
      continue;
    }
    if (first == -1 || index < first) {
      first = index;
    }
  }
  return first;
}

String? _findTopLevelPropertyValue(String source, String property) {
  for (var index = 0; index < source.length; index++) {
    final state = _scanStateAt(source, index);
    if (!state.isTopLevel) {
      continue;
    }
    if (!_matchesProperty(source, index, property)) {
      continue;
    }

    var cursor = index + property.length;
    while (cursor < source.length && _isWhitespace(source.codeUnitAt(cursor))) {
      cursor += 1;
    }
    if (cursor >= source.length || source[cursor] != ':') {
      continue;
    }
    cursor += 1;
    while (cursor < source.length && _isWhitespace(source.codeUnitAt(cursor))) {
      cursor += 1;
    }

    final start = cursor;
    for (; cursor < source.length; cursor++) {
      final valueState = _scanStateAt(source, cursor);
      if (!valueState.isTopLevel) {
        continue;
      }
      if (source[cursor] == ',') {
        return source.substring(start, cursor).trim();
      }
    }
    return source.substring(start).trim();
  }
  return null;
}

bool _matchesProperty(String source, int index, String property) {
  if (!source.startsWith(property, index)) {
    return false;
  }
  if (index > 0) {
    final previous = source.codeUnitAt(index - 1);
    if (_isIdentifier(previous)) {
      return false;
    }
  }
  final nextIndex = index + property.length;
  if (nextIndex < source.length) {
    final next = source.codeUnitAt(nextIndex);
    if (_isIdentifier(next)) {
      return false;
    }
  }
  return true;
}

String _extractInvocation(String source, int start, String prefix) {
  final openParenIndex = start + prefix.length - 1;
  return _extractDelimitedBlock(source, openParenIndex, '(', ')', start: start);
}

String _extractDelimitedBlock(
  String source,
  int openIndex,
  String openChar,
  String closeChar, {
  int? start,
}) {
  var depth = 0;
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var escaped = false;

  for (var cursor = openIndex; cursor < source.length; cursor++) {
    final char = source[cursor];

    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }
    if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }
    if (inSingleQuote || inDoubleQuote) {
      continue;
    }

    if (char == openChar) {
      depth += 1;
    } else if (char == closeChar) {
      depth -= 1;
      if (depth == 0) {
        return source.substring(start ?? openIndex, cursor + 1);
      }
    }
  }

  throw StateError('Unbalanced block starting with $openChar');
}

String _invocationContent(String block, String prefix) {
  return block.substring(prefix.length, block.length - 1);
}

String _stripOuterBrackets(String source) {
  final trimmed = source.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

_ScanState _scanStateAt(String source, int endIndex) {
  var parenDepth = 0;
  var bracketDepth = 0;
  var braceDepth = 0;
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var escaped = false;

  for (var index = 0; index < endIndex; index++) {
    final char = source[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }
    if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }
    if (inSingleQuote || inDoubleQuote) {
      continue;
    }

    if (char == '(') {
      parenDepth += 1;
    } else if (char == ')') {
      parenDepth -= 1;
    } else if (char == '[') {
      bracketDepth += 1;
    } else if (char == ']') {
      bracketDepth -= 1;
    } else if (char == '{') {
      braceDepth += 1;
    } else if (char == '}') {
      braceDepth -= 1;
    }
  }

  return _ScanState(
    parenDepth: parenDepth,
    bracketDepth: bracketDepth,
    braceDepth: braceDepth,
    inSingleQuote: inSingleQuote,
    inDoubleQuote: inDoubleQuote,
  );
}

bool _isWhitespace(int codeUnit) =>
    codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13;

bool _isIdentifier(int codeUnit) =>
    (codeUnit >= 48 && codeUnit <= 57) ||
    (codeUnit >= 65 && codeUnit <= 90) ||
    (codeUnit >= 97 && codeUnit <= 122) ||
    codeUnit == 95;

class _ScanState {
  const _ScanState({
    required this.parenDepth,
    required this.bracketDepth,
    required this.braceDepth,
    required this.inSingleQuote,
    required this.inDoubleQuote,
  });

  final int parenDepth;
  final int bracketDepth;
  final int braceDepth;
  final bool inSingleQuote;
  final bool inDoubleQuote;

  bool get isTopLevel =>
      !inSingleQuote &&
      !inDoubleQuote &&
      parenDepth == 0 &&
      bracketDepth == 0 &&
      braceDepth == 0;
}
