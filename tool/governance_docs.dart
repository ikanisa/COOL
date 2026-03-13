import 'dart:io';

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
  final source = routerFile.readAsStringSync();
  final routeConstants = _readRouteConstants(source);
  final screenPaths = _readScreenClassPaths(repoRoot);
  final shellBranchCount = RegExp(
    r'StatefulShellBranch\(',
  ).allMatches(source).length;
  final blocks = _extractGoRouteBlocks(source);
  final entries = <RouteEntry>[];

  for (final block in blocks) {
    final pathMatch = RegExp(r'path:\s*([^,\n]+)').firstMatch(block);
    if (pathMatch == null) {
      continue;
    }
    final rawPath = pathMatch.group(1)!.trim();
    final path = _resolvePath(rawPath, routeConstants);
    final screenNames =
        RegExp(
            r'\b([A-Za-z_][A-Za-z0-9_]*Screen)\(',
          ).allMatches(block).map((match) => match.group(1)!).toSet().toList()
          ..sort();
    final target = block.contains('redirect:')
        ? 'Redirect'
        : screenNames.isEmpty
        ? 'Unknown'
        : screenNames
              .map((name) => _linkedScreenName(name, screenPaths[name]))
              .join(', ');
    entries.add(
      RouteEntry(
        path: path,
        target: target,
        shell: _shellForPath(path),
        category: _categoryForPath(path),
      ),
    );
  }

  entries.sort((a, b) => a.path.compareTo(b.path));
  return <RouteEntry>[
    RouteEntry(
      path: '__meta_route_count__',
      target: blocks.length.toString(),
      shell: shellBranchCount.toString(),
      category: _countFeatureScreenFiles(repoRoot).toString(),
    ),
    ...entries,
  ];
}

List<String> _extractGoRouteBlocks(String source) {
  final blocks = <String>[];
  var index = 0;
  while (true) {
    final start = source.indexOf('GoRoute(', index);
    if (start == -1) {
      break;
    }
    var depth = 0;
    var end = start;
    for (var cursor = start; cursor < source.length; cursor++) {
      final char = source[cursor];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0) {
          end = cursor;
          break;
        }
      }
    }
    blocks.add(source.substring(start, end + 1));
    index = end + 1;
  }
  return blocks;
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
  if (path == '/mobility' || path.startsWith('/mobility/')) {
    return 'Mobility';
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
      path == '/mobility' ||
      path.startsWith('/mobility/') ||
      path == '/profile') {
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
    ..writeln('Generated from code in ')
    ..writeln(
      '[`lib/core/router/app_router.dart`](../lib/core/router/app_router.dart).',
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
    ..writeln('- Route changes that grow screen scope must also refresh ')
    ..writeln('[`SCREEN_BUDGETS.md`](./SCREEN_BUDGETS.md).')
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
    final loc = entity.readAsLinesSync().length;
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
