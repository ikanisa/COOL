import 'dart:io';
import 'governance_docs.dart';

void main() {
  final repoRoot = Directory.current;
  final docs = buildGovernanceDocs(repoRoot);

  File('docs/ROUTE_INVENTORY.md').writeAsStringSync(docs.routeInventory);
  File('docs/SCREEN_BUDGETS.md').writeAsStringSync(docs.screenBudgets);

  print('Governance docs updated.');
}
