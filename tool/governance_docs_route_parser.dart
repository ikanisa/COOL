part of 'governance_docs.dart';

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
    _plainShellRoutePrefix,
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
      continue;
    }

    if (block.startsWith(_plainShellRoutePrefix)) {
      entries.addAll(
        _parsePlainShellRoute(
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

List<RouteEntry> _parsePlainShellRoute(
  String block, {
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final content = _invocationContent(block, _plainShellRoutePrefix);
  final routesSource = _findTopLevelPropertyValue(content, 'routes');
  if (routesSource == null) {
    return const <RouteEntry>[];
  }

  return _parseRouteList(
    routesSource,
    parentPath: '',
    shell: 'No',
    routeConstants: routeConstants,
    screenPaths: screenPaths,
  );
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
  if (path == '/momo/biopay' || path.startsWith('/momo/biopay/')) {
    return 'BioPay';
  }
  if (path == '/profile' || path.startsWith('/profile/')) {
    return 'Settings';
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
      path == '/momo/biopay' ||
      path.startsWith('/momo/biopay/') ||
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
      'Generated from [`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart) and related router helpers.',
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

List<RouteEntry> _dedupeRouteEntries(List<RouteEntry> entries) {
  final deduped = <String, RouteEntry>{};
  for (final entry in entries) {
    deduped.update(entry.path, (existing) {
      if (existing.target == 'Redirect' && entry.target != 'Redirect') {
        return entry;
      }
      return existing;
    }, ifAbsent: () => entry);
  }
  return deduped.values.toList(growable: false);
}
