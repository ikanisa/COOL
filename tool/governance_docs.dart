import 'dart:io';

part 'governance_docs_routes.dart';
part 'governance_docs_route_parser.dart';
part 'governance_docs_route_scanner.dart';

const _goRouterPrefix = 'GoRouter(';
const _goRoutePrefix = 'GoRoute(';
const _shellRoutePrefix = 'StatefulShellRoute.indexedStack(';
const _plainShellRoutePrefix = 'ShellRoute(';
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
  entries.sort((a, b) {
    final locCompare = b.loc.compareTo(a.loc);
    if (locCompare != 0) {
      return locCompare;
    }
    return a.path.compareTo(b.path);
  });
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
