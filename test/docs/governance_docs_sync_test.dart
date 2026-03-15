import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/governance_docs.dart';

void main() {
  final repoRoot = Directory.current;

  test('governance docs match generated code inventory', () {
    final result = Process.runSync(
      'dart',
      ['tool/governance_docs.dart', '--check'],
      workingDirectory: repoRoot.path,
    );

    if (result.exitCode != 0) {
      fail('Governance docs are out of sync. Run "dart tool/governance_docs.dart" to fix.\n${result.stderr}');
    }
  });

  test('route inventory keeps nested routes visible', () {
    final routeInventory = buildGovernanceDocs(repoRoot).routeInventory;

    expect(routeInventory, contains('`/groups/create`'));
    expect(routeInventory, contains('`/mobility/driver`'));
    expect(
      routeInventory,
      contains('`/partners/rayon-sports/tickets/:ticketId/confirm`'),
    );
    expect(routeInventory, isNot(contains('`/partners/:id/fans`')));
  });
}
