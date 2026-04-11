import 'package:cool_app/features/groups/screens/group_create_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/core_detail_scaffold.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders create flow inside the shared detail scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: GroupCreateScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CoreDetailScaffold), findsOneWidget);
    expect(find.byType(CoolCard), findsWidgets);
    expect(find.text('Create a New Group'), findsOneWidget);
    expect(find.text('CREATE GROUP'), findsOneWidget);
  });
}
