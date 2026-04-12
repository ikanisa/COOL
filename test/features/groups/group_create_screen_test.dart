import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/groups/screens/group_create_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/core_detail_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await CoolCountryCatalog.initialize(
      await File('assets/countries.json').readAsString(),
    );
  });

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
    expect(find.text('Create a New Group'), findsOneWidget);
    expect(find.text('CREATE GROUP'), findsOneWidget);
    expect(find.text('MoMo number required'), findsNothing);
    expect(find.text('USE DIFFERENT MOMO FOR THIS GROUP'), findsNothing);
    expect(find.text('FREQUENCY'), findsNothing);

    await tester.tap(find.text('COMMUNITY'));
    await tester.pumpAndSettle();

    expect(find.text('USE DIFFERENT MOMO FOR THIS GROUP'), findsNothing);
    expect(find.text('FREQUENCY'), findsNothing);

    expect(find.text('RECEIVE PAYMENTS VIA'), findsOneWidget);
    expect(find.text('NUMBER'), findsOneWidget);
    expect(find.text('MOMO NUMBER'), findsNothing);

    await tester.ensureVisible(find.text('SAVING'));
    await tester.tap(find.text('SAVING'));
    await tester.pumpAndSettle();

    expect(find.text('USE DIFFERENT MOMO FOR THIS GROUP'), findsNothing);
    expect(find.text('FREQUENCY'), findsOneWidget);
    expect(find.text('RECEIVE PAYMENTS VIA'), findsNothing);
  });
}
