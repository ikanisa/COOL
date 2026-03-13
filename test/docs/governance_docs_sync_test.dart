import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/governance_docs.dart';

void main() {
  final repoRoot = Directory.current;

  test('governance docs match generated code inventory', () {
    final docs = buildGovernanceDocs(repoRoot);

    expect(
      File('${repoRoot.path}/docs/ROUTE_INVENTORY.md').readAsStringSync(),
      docs.routeInventory,
    );
    expect(
      File('${repoRoot.path}/docs/SCREEN_BUDGETS.md').readAsStringSync(),
      docs.screenBudgets,
    );
  });

  test('route inventory keeps nested routes visible', () {
    final routeInventory = buildGovernanceDocs(repoRoot).routeInventory;

    expect(routeInventory, contains('`/groups/create`'));
    expect(routeInventory, contains('`/mobility/driver`'));
    expect(
      routeInventory,
      contains('`/partners/rayon-sports/tickets/:ticketId/confirm`'),
    );
    expect(routeInventory, contains('`/partners/:id/fans`'));
  });
}
