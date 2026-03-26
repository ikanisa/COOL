import 'dart:io';

const _goRouterPrefix = 'GoRouter(';
const _goRoutePrefix = 'GoRoute(';
const _shellRoutePrefix = 'StatefulShellRoute.indexedStack(';
const _shellBranchPrefix = 'StatefulShellBranch(';

class GovernanceDocs {
  const GovernanceDocs({
    required this.routeInventory,
    required this.screenBudgets,
  });

  final String routeInventory;
  final String screenBudgets;
}

class RouteEntry {
  const RouteEntry({
    required this.path,
    required this.target,
    required this.shell,
    required this.category,
  });

  final String path;
  final String target;
  final String shell;
  final String category;

  RouteEntry copyWith({
    String? path,
    String? target,
    String? shell,
    String? category,
  }) {
    return RouteEntry(
      path: path ?? this.path,
      target: target ?? this.target,
      shell: shell ?? this.shell,
      category: category ?? this.category,
    );
  }
}

class ScreenBudgetEntry {
  const ScreenBudgetEntry({
    required this.path,
    required this.loc,
    required this.status,
  });

  final String path;
  final int loc;
  final String status;
}

GovernanceDocs buildGovernanceDocs(Directory repoRoot) {
  final routes = _readRouteEntries(repoRoot);
  final budgets = _readScreenBudgets(repoRoot);
  return GovernanceDocs(
    routeInventory: _renderRouteInventory(repoRoot, routes),
    screenBudgets: _renderScreenBudgets(budgets),
  );
}

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current;
  final docs = buildGovernanceDocs(repoRoot);
  final routeInventoryFile = File('${repoRoot.path}/docs/ROUTE_INVENTORY.md');
  final screenBudgetsFile = File('${repoRoot.path}/docs/SCREEN_BUDGETS.md');

  final checkOnly = args.contains('--check');
  if (checkOnly) {
    final mismatches = <String>[];
    if (routeInventoryFile.readAsStringSync() != docs.routeInventory) {
      mismatches.add('docs/ROUTE_INVENTORY.md');
    }
    if (screenBudgetsFile.readAsStringSync() != docs.screenBudgets) {
      mismatches.add('docs/SCREEN_BUDGETS.md');
    }

    if (mismatches.isNotEmpty) {
      stderr.writeln(
        'Governance docs are out of sync: ${mismatches.join(', ')}',
      );
      exitCode = 1;
    }
    return;
  }

  routeInventoryFile.writeAsStringSync(docs.routeInventory);
  screenBudgetsFile.writeAsStringSync(docs.screenBudgets);
}

List<RouteEntry> _readRouteEntries(Directory repoRoot) {
  final routerFile = File('${repoRoot.path}/lib/core/router/app_router.dart');
  final routesFile = File('${repoRoot.path}/lib/core/router/app_routes.dart');
  final source = routerFile.readAsStringSync();
  final routeConstants = _readRouteConstants(
    [
      source,
      if (routesFile.existsSync()) routesFile.readAsStringSync(),
    ].join('\n'),
  );
  final screenPaths = _readScreenClassPaths(repoRoot);
  final shellBranchCount = RegExp(
    r'StatefulShellBranch\(',
  ).allMatches(source).length;

  final routerStart = source.indexOf(_goRouterPrefix);
  if (routerStart == -1) {
    return <RouteEntry>[
      RouteEntry(
        path: '__meta_route_count__',
        target: '0',
        shell: shellBranchCount.toString(),
        category: _countFeatureScreenFiles(repoRoot).toString(),
      ),
    ];
  }

  final routerBlock = _extractInvocation(source, routerStart, _goRouterPrefix);
  final routerContent = _invocationContent(routerBlock, _goRouterPrefix);
  final topLevelRoutes = _findTopLevelPropertyValue(routerContent, 'routes');
  final entries = topLevelRoutes == null
      ? <RouteEntry>[]
      : _parseRouteList(
          topLevelRoutes,
          parentPath: '',
          shell: 'No',
          routeConstants: routeConstants,
          screenPaths: screenPaths,
        );
  entries.addAll(
    _readReturnedGoRouteFile(
      '${repoRoot.path}/lib/core/router/partner_routes.dart',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    ),
  );
  entries.addAll(
    _readReturnedGoRouteFile(
      '${repoRoot.path}/lib/core/router/admin_routes.dart',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    ),
  );
  entries.addAll(
    _readReturnedGoRouteListFile(
      '${repoRoot.path}/lib/core/router/biopay_routes.dart',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    ),
  );

  entries.sort((a, b) => a.path.compareTo(b.path));
  return <RouteEntry>[
    RouteEntry(
      path: '__meta_route_count__',
      target: entries.length.toString(),
      shell: shellBranchCount.toString(),
      category: _countFeatureScreenFiles(repoRoot).toString(),
    ),
    ...entries,
  ];
}

List<RouteEntry> _readReturnedGoRouteFile(
  String filePath, {
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final file = File(filePath);
  if (!file.existsSync()) {
    return const <RouteEntry>[];
  }

  final source = file.readAsStringSync();
  final returnIndex = source.indexOf('return');
  final routeIndex = returnIndex == -1
      ? -1
      : source.indexOf(_goRoutePrefix, returnIndex);
  if (routeIndex == -1) {
    return const <RouteEntry>[];
  }

  final routeBlock = _extractInvocation(source, routeIndex, _goRoutePrefix);
  return _parseGoRoute(
    routeBlock,
    parentPath: '',
    shell: 'No',
    routeConstants: routeConstants,
    screenPaths: screenPaths,
  );
}

List<RouteEntry> _readReturnedGoRouteListFile(
  String filePath, {
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final file = File(filePath);
  if (!file.existsSync()) {
    return const <RouteEntry>[];
  }

  final source = file.readAsStringSync();
  final returnIndex = source.indexOf('return');
  if (returnIndex == -1) {
    return const <RouteEntry>[];
  }

  final listStart = source.indexOf('[', returnIndex);
  if (listStart == -1) {
    return const <RouteEntry>[];
  }

  final routeList = _extractDelimitedBlock(source, listStart, '[', ']');
  return _parseRouteList(
    routeList,
    parentPath: '',
    shell: 'No',
    routeConstants: routeConstants,
    screenPaths: screenPaths,
  );
}

List<RouteEntry> _parseRouteList(
  String listSource, {
  required String parentPath,
  required String shell,
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final entries = <RouteEntry>[];
  for (final block in _extractTopLevelInvocations(listSource, <String>[
    _goRoutePrefix,
    _shellRoutePrefix,
  ])) {
    if (block.startsWith(_goRoutePrefix)) {
      entries.addAll(
        _parseGoRoute(
          block,
          parentPath: parentPath,
          shell: shell,
          routeConstants: routeConstants,
          screenPaths: screenPaths,
        ),
      );
      continue;
    }

    if (block.startsWith(_shellRoutePrefix)) {
      entries.addAll(
        _parseShellRoute(
          block,
          routeConstants: routeConstants,
          screenPaths: screenPaths,
        ),
      );
    }
  }
  return entries;
}

List<RouteEntry> _parseShellRoute(
  String block, {
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final content = _invocationContent(block, _shellRoutePrefix);
  final branchesSource = _findTopLevelPropertyValue(content, 'branches');
  if (branchesSource == null) {
    return const <RouteEntry>[];
  }

  final entries = <RouteEntry>[];
  for (final branchBlock in _extractTopLevelInvocations(
    branchesSource,
    <String>[_shellBranchPrefix],
  )) {
    final branchContent = _invocationContent(branchBlock, _shellBranchPrefix);
    final routesSource = _findTopLevelPropertyValue(branchContent, 'routes');
    if (routesSource == null) {
      continue;
    }

    final branchEntries = _parseRouteList(
      routesSource,
      parentPath: '',
      shell: 'No',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    );
    if (branchEntries.isEmpty) {
      continue;
    }

    final branchShell = _shellForPath(branchEntries.first.path);
    entries.addAll(
      branchEntries.map(
        (entry) => entry.copyWith(
          shell: branchShell,
          category: _categoryForPath(entry.path),
        ),
      ),
    );
  }

  return entries;
}

List<RouteEntry> _parseGoRoute(
  String block, {
  required String parentPath,
  required String shell,
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final content = _invocationContent(block, _goRoutePrefix);
  final rawPath = _findTopLevelPropertyValue(content, 'path');
  if (rawPath == null) {
    return const <RouteEntry>[];
  }

  final path = _joinPaths(parentPath, _resolvePath(rawPath, routeConstants));
  final builder = _findTopLevelPropertyValue(content, 'builder');
  final pageBuilder = _findTopLevelPropertyValue(content, 'pageBuilder');
  final builderSources = <String?>[builder, pageBuilder];

  final screenNames = <String>{};
  for (final builderSource in builderSources.whereType<String>()) {
    screenNames.addAll(_extractScreenNames(builderSource));
  }

  final redirectSource = _findTopLevelPropertyValue(content, 'redirect');
  final target = screenNames.isNotEmpty
      ? (screenNames.toList()..sort())
            .map((name) => _linkedScreenName(name, screenPaths[name]))
            .join(', ')
      : redirectSource != null
      ? 'Redirect'
      : 'Unknown';

  final children = <RouteEntry>[];
  final childRoutes = _findTopLevelPropertyValue(content, 'routes');
  if (childRoutes != null) {
    children.addAll(
      _parseRouteList(
        childRoutes,
        parentPath: path,
        shell: shell,
        routeConstants: routeConstants,
        screenPaths: screenPaths,
      ),
    );
  }

  return <RouteEntry>[
    RouteEntry(
      path: path,
      target: target,
      shell: shell,
      category: _categoryForPath(path),
    ),
    ...children,
  ];
}

List<String> _extractTopLevelInvocations(String source, List<String> prefixes) {
  final body = _stripOuterBrackets(source);
  final invocations = <String>[];

  var index = 0;
  while (index < body.length) {
    final state = _scanStateAt(body, index);
    if (!state.isTopLevel) {
      index += 1;
      continue;
    }

    String? matchedPrefix;
    for (final prefix in prefixes) {
      if (body.startsWith(prefix, index)) {
        matchedPrefix = prefix;
        break;
      }
    }

    if (matchedPrefix == null) {
      index += 1;
      continue;
    }

    final block = _extractInvocation(body, index, matchedPrefix);
    invocations.add(block);
    index += block.length;
  }

  return invocations;
}

Map<String, String> _readRouteConstants(String source) {
  final constants = <String, String>{};
  for (final match in RegExp(
    r"static const (\w+)\s*=\s*'([^']+)';",
  ).allMatches(source)) {
    constants[match.group(1)!] = match.group(2)!;
  }
  return constants;
}

Map<String, String> _readScreenClassPaths(Directory repoRoot) {
  final mapping = <String, String>{};
  final libRoot = Directory('${repoRoot.path}/lib');
  for (final entity in libRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final relativePath = entity.path.replaceFirst('${repoRoot.path}/', '');
    final content = entity.readAsStringSync();
    for (final match in RegExp(
      r'class\s+([A-Za-z_][A-Za-z0-9_]*Screen)\b',
    ).allMatches(content)) {
      mapping.putIfAbsent(match.group(1)!, () => relativePath);
    }
  }
  return mapping;
}

Iterable<String> _extractScreenNames(String source) sync* {
  final matches = RegExp(
    r'\b([A-Za-z_][A-Za-z0-9_]*Screen)\(',
  ).allMatches(source);
  final seen = <String>{};
  for (final match in matches) {
    final name = match.group(1)!;
    if (seen.add(name)) {
      yield name;
    }
  }
}

String _resolvePath(String rawPath, Map<String, String> constants) {
  final trimmed = rawPath.trim();
  if (trimmed.startsWith('AppRoutes.')) {
    final name = trimmed.substring('AppRoutes.'.length);
    return constants[name] ?? trimmed;
  }
  if (trimmed.startsWith("'") && trimmed.endsWith("'")) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String _joinPaths(String parentPath, String childPath) {
  final trimmedChild = childPath.trim();
  if (trimmedChild.startsWith('/')) {
    return trimmedChild;
  }
  if (parentPath.isEmpty) {
    return trimmedChild.startsWith('/') ? trimmedChild : '/$trimmedChild';
  }

  final normalizedParent = parentPath.endsWith('/')
      ? parentPath.substring(0, parentPath.length - 1)
      : parentPath;
  final normalizedChild = trimmedChild.startsWith('/')
      ? trimmedChild.substring(1)
      : trimmedChild;
  return '$normalizedParent/$normalizedChild';
}

String _linkedScreenName(String className, String? relativePath) {
  if (relativePath == null) {
    return className;
  }
  return '[`$className`](../$relativePath)';
}

String _shellForPath(String path) {
  if (path == '/home') {
    return 'Home';
  }
  if (path == '/groups' || path.startsWith('/groups/')) {
    return 'Groups';
  }
  if (path == '/profile' || path.startsWith('/profile/')) {
    return 'Profile';
  }
  return 'No';
}

String _categoryForPath(String path) {
  if (path == '/' ||
      path == '/onboarding' ||
      path == '/language' ||
      path == '/otp' ||
      path == '/otp-verify' ||
      path == '/register' ||
      path.startsWith('/invite/') ||
      path == '/scanner') {
    return 'Auth And Entry';
  }
  if (path.startsWith('/admin/rayon')) {
    return 'Rayon Admin Routes';
  }
  if (path.startsWith('/admin')) {
    return 'Admin Routes';
  }
  if (path == '/home' ||
      path == '/groups' ||
      path.startsWith('/groups/') ||
      path == '/profile' ||
      path.startsWith('/profile/')) {
    return 'Shell Branches';
  }
  if (path.startsWith('/partners')) {
    return 'Partner And Rayon Consumer Routes';
  }
  return 'Standalone Core Routes';
}

int _countFeatureScreenFiles(Directory repoRoot) {
  final screensDir = Directory('${repoRoot.path}/lib/features');
  return screensDir
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.contains('/screens/') && file.path.endsWith('.dart'),
      )
      .length;
}

String _renderRouteInventory(Directory repoRoot, List<RouteEntry> entries) {
  final meta = entries.first;
  final routes = entries.skip(1).toList(growable: false);
  final grouped = <String, List<RouteEntry>>{};
  for (final route in routes) {
    grouped.putIfAbsent(route.category, () => <RouteEntry>[]).add(route);
  }

  final buffer = StringBuffer()
    ..writeln('# Route Inventory')
    ..writeln()
    ..writeln(
      'Generated from [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).',
    )
    ..writeln()
    ..writeln('Current router shape:')
    ..writeln()
    ..writeln('- `${meta.target}` `GoRoute` declarations')
    ..writeln('- `${meta.shell}` shell branches')
    ..writeln(
      '- `${meta.category}` screen files under `lib/features/**/screens/*.dart`',
    )
    ..writeln()
    ..writeln('Change policy:')
    ..writeln()
    ..writeln('- Route changes must regenerate this document from code.')
    ..writeln(
      '- New user-facing routes must ship with smoke or routing coverage.',
    )
    ..writeln(
      '- Route changes that grow screen scope must also refresh [`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).',
    )
    ..writeln();

  for (final category in <String>[
    'Auth And Entry',
    'Shell Branches',
    'Standalone Core Routes',
    'Partner And Rayon Consumer Routes',
    'Admin Routes',
    'Rayon Admin Routes',
  ]) {
    final categoryRoutes = grouped[category];
    if (categoryRoutes == null || categoryRoutes.isEmpty) {
      continue;
    }
    buffer
      ..writeln('## $category')
      ..writeln()
      ..writeln('| Path | Target | Shell |')
      ..writeln('|---|---|---|');
    for (final route in categoryRoutes) {
      buffer.writeln('| `${route.path}` | ${route.target} | ${route.shell} |');
    }
    buffer.writeln();
  }

  return buffer.toString();
}

List<ScreenBudgetEntry> _readScreenBudgets(Directory repoRoot) {
  final entries = <ScreenBudgetEntry>[];
  final featuresDir = Directory('${repoRoot.path}/lib/features');
  for (final entity in featuresDir.listSync(recursive: true)) {
    if (entity is! File ||
        !entity.path.endsWith('.dart') ||
        !entity.path.contains('/screens/')) {
      continue;
    }
    final relativePath = entity.path.replaceFirst('${repoRoot.path}/', '');
    final content = entity.readAsStringSync();
    final loc = content.isEmpty ? 0 : content.split('\n').length;
    entries.add(
      ScreenBudgetEntry(
        path: relativePath,
        loc: loc,
        status: _budgetStatus(loc),
      ),
    );
  }
  entries.sort((a, b) => b.loc.compareTo(a.loc));
  return entries;
}

String _budgetStatus(int loc) {
  if (loc <= 400) {
    return 'Target';
  }
  if (loc <= 700) {
    return 'Review';
  }
  if (loc <= 1000) {
    return 'Debt';
  }
  return 'Hotspot';
}

String _renderScreenBudgets(List<ScreenBudgetEntry> entries) {
  final hotspotCount = entries
      .where((entry) => entry.status == 'Hotspot')
      .length;
  final debtCount = entries.where((entry) => entry.status == 'Debt').length;
  final reviewCount = entries.where((entry) => entry.status == 'Review').length;

  final buffer = StringBuffer()
    ..writeln('# Screen Budgets')
    ..writeln()
    ..writeln('Generated from `lib/features/**/screens/*.dart`.')
    ..writeln()
    ..writeln('Why this exists:')
    ..writeln()
    ..writeln(
      '- Route scope should be visible from code, not remembered in reviews.',
    )
    ..writeln(
      '- Hotspots and debt screens must be obvious before new UI work lands.',
    )
    ..writeln(
      '- Regenerating this file keeps the current budget state auditable.',
    )
    ..writeln()
    ..writeln('## Budget Rules')
    ..writeln()
    ..writeln('### New Screens')
    ..writeln()
    ..writeln('| Budget | Threshold | Requirement |')
    ..writeln('|---|---|---|')
    ..writeln(
      '| Target | `<= 400` LOC | Normal case for new user-facing routes |',
    )
    ..writeln(
      '| Review | `401-700` LOC | Allowed only with extracted widgets/services and a justification in PR notes |',
    )
    ..writeln(
      '| Block | `> 700` LOC | Do not merge as a new route without splitting the flow |',
    )
    ..writeln()
    ..writeln('### Existing Screens')
    ..writeln()
    ..writeln('| Budget | Threshold | Requirement |')
    ..writeln('|---|---|---|')
    ..writeln('| Stable | `<= 700` LOC | Can evolve normally |')
    ..writeln(
      '| Debt | `701-1000` LOC | New work should reduce or at least not grow route responsibility |',
    )
    ..writeln(
      '| Hotspot | `> 1000` LOC | Do not grow the file unless the work is explicitly simplifying it |',
    )
    ..writeln()
    ..writeln('## Current Snapshot')
    ..writeln()
    ..writeln('- `${entries.length}` screen files measured')
    ..writeln('- `$reviewCount` review-range screens')
    ..writeln('- `$debtCount` debt screens')
    ..writeln('- `$hotspotCount` hotspot screens')
    ..writeln()
    ..writeln('## Measured Screens')
    ..writeln()
    ..writeln('| Screen | LOC | Status |')
    ..writeln('|---|---|---|');

  for (final entry in entries) {
    final fileName = entry.path.split('/').last;
    buffer.writeln(
      '| [`$fileName`](../${entry.path}) | `${entry.loc}` | ${entry.status} |',
    );
  }

  return buffer.toString();
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
