import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/shared/widgets/admin_detail_scaffold.dart';
import 'package:cool_app/shared/widgets/core_detail_scaffold.dart';
import 'package:cool_app/shared/widgets/core_tab_root_scaffold.dart';
import 'package:cool_app/shared/widgets/dense_admin_workspace_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Core scaffolds', () {
    testWidgets('CoreTabRootScaffold renders header content', (tester) async {
      await _pumpScaffold(
        tester,
        child: const CoreTabRootScaffold(
          title: Text('Home'),
          subtitle: Text('Trusted money tools'),
          child: SizedBox.expand(child: Text('Body')),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Trusted money tools'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('CoreDetailScaffold wires back and home actions', (
      tester,
    ) async {
      var backTapped = false;
      var homeTapped = false;

      await _pumpScaffold(
        tester,
        child: CoreDetailScaffold(
          onBack: () => backTapped = true,
          onHome: () => homeTapped = true,
          showHomeButton: true,
          homeTooltip: 'Go home',
          title: const Text('Details'),
          subtitle: const Text('Secondary copy'),
          child: const SizedBox.expand(child: Text('Body')),
        ),
      );

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Secondary copy'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      await tester.tap(find.byTooltip('Go home'));
      await tester.pump();

      expect(backTapped, isTrue);
      expect(homeTapped, isTrue);
    });

    testWidgets('DenseAdminWorkspaceScaffold renders search and filters', (
      tester,
    ) async {
      await _pumpScaffold(
        tester,
        child: const DenseAdminWorkspaceScaffold(
          searchBar: Text('Search bar'),
          filterActions: <Widget>[
            Chip(label: Text('Pending')),
            Chip(label: Text('Reviewed')),
          ],
          child: SizedBox.expand(child: Text('Workspace body')),
        ),
      );

      expect(find.text('Search bar'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Reviewed'), findsOneWidget);
      expect(find.text('Workspace body'), findsOneWidget);
    });

    testWidgets('AdminDetailScaffold keeps back affordance by default', (
      tester,
    ) async {
      await _pumpScaffold(
        tester,
        child: const AdminDetailScaffold(child: Text('Admin body')),
      );

      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('Admin body'), findsOneWidget);
    });
  });
}

Future<void> _pumpScaffold(WidgetTester tester, {required Widget child}) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: child));
  await tester.pump();
}
