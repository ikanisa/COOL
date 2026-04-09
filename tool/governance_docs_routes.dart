part of 'governance_docs.dart';

List<RouteEntry> _readRouteEntries(Directory repoRoot) {
  final routerFile = File('${repoRoot.path}/lib/core/router/app_router.dart');
  final routesFile = File('${repoRoot.path}/lib/core/router/app_routes.dart');
  final shellBranchesFile = File(
    '${repoRoot.path}/lib/core/router/app_shell_branches.dart',
  );
  final source = routerFile.readAsStringSync();
  final routeConstants = _readRouteConstants(
    [
      source,
      if (routesFile.existsSync()) routesFile.readAsStringSync(),
    ].join('\n'),
  );
  final screenPaths = _readScreenClassPaths(repoRoot);
  final shellBranchCount =
      RegExp(r'StatefulShellBranch\(').allMatches(source).length +
      (shellBranchesFile.existsSync()
          ? RegExp(
              r'StatefulShellBranch\(',
            ).allMatches(shellBranchesFile.readAsStringSync()).length
          : 0);

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
    _readReturnedRouteBaseFile(
      '${repoRoot.path}/lib/core/router/partner_routes.dart',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    ),
  );
  entries.addAll(
    _readReturnedRouteBaseFile(
      '${repoRoot.path}/lib/core/router/admin_routes.dart',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    ),
  );
  entries.addAll(
    _readShellBranchEntriesFile(
      '${repoRoot.path}/lib/core/router/app_shell_branches.dart',
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

  final dedupedEntries = _dedupeRouteEntries(entries);
  dedupedEntries.sort((a, b) => a.path.compareTo(b.path));
  return <RouteEntry>[
    RouteEntry(
      path: '__meta_route_count__',
      target: dedupedEntries.length.toString(),
      shell: shellBranchCount.toString(),
      category: _countFeatureScreenFiles(repoRoot).toString(),
    ),
    ...dedupedEntries,
  ];
}

List<RouteEntry> _readReturnedRouteBaseFile(
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
      : _firstPositiveIndex([
          source.indexOf(_goRoutePrefix, returnIndex),
          source.indexOf(_shellRoutePrefix, returnIndex),
          source.indexOf(_plainShellRoutePrefix, returnIndex),
        ]);
  if (routeIndex == -1) {
    return const <RouteEntry>[];
  }

  if (source.startsWith(_goRoutePrefix, routeIndex)) {
    final routeBlock = _extractInvocation(source, routeIndex, _goRoutePrefix);
    return _parseGoRoute(
      routeBlock,
      parentPath: '',
      shell: 'No',
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    );
  }

  if (source.startsWith(_shellRoutePrefix, routeIndex)) {
    final routeBlock = _extractInvocation(
      source,
      routeIndex,
      _shellRoutePrefix,
    );
    return _parseShellRoute(
      routeBlock,
      routeConstants: routeConstants,
      screenPaths: screenPaths,
    );
  }

  final routeBlock = _extractInvocation(
    source,
    routeIndex,
    _plainShellRoutePrefix,
  );
  return _parsePlainShellRoute(
    routeBlock,
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

List<RouteEntry> _readShellBranchEntriesFile(
  String filePath, {
  required Map<String, String> routeConstants,
  required Map<String, String> screenPaths,
}) {
  final file = File(filePath);
  if (!file.existsSync()) {
    return const <RouteEntry>[];
  }

  final source = file.readAsStringSync();
  final entries = <RouteEntry>[];
  var searchStart = 0;
  while (true) {
    final branchIndex = source.indexOf(_shellBranchPrefix, searchStart);
    if (branchIndex == -1) {
      break;
    }

    final branchBlock = _extractInvocation(
      source,
      branchIndex,
      _shellBranchPrefix,
    );
    searchStart = branchIndex + branchBlock.length;

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
