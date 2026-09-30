import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/activity/activity_screen.dart';
import 'package:collect_app/features/ledger/ledger_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = CollectProfile(
  id: 'scope-user',
  publicId: '123456',
  whatsappPhone: '+250700000001',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: '0700000001',
);

CollectCollection _group({required bool hasMomoRoute}) => CollectCollection(
  id: 'scope-group',
  slug: 'scope-group',
  creatorUserId: _profile.id,
  title: 'Scope group',
  description: 'Synthetic group for a scope test',
  receiverMomoNumber: hasMomoRoute ? '0700000001' : null,
  receiverNetwork: hasMomoRoute ? 'mtn_momo' : 'unknown',
  createdAt: DateTime.utc(2026, 9, 28),
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  CollectCollection? group,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = CollectRepository.fixture(
    initialState: CollectState(
      currentProfile: _profile,
      collections: group == null ? [] : [group],
      paymentIntents: const [],
      contributions: const [],
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repository)],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty member Activity describes confirmed MoMo records', (
    tester,
  ) async {
    await _pump(tester, const ActivityScreen());

    expect(
      find.text('Confirmed MoMo contributions appear here.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bank contributions'), findsNothing);
  });

  testWidgets('Ledger without a MoMo route does not offer contribution', (
    tester,
  ) async {
    await _pump(
      tester,
      const LedgerScreen(collectionId: 'scope-group'),
      group: _group(hasMomoRoute: false),
    );

    expect(
      find.text('This group does not have an active MoMo contribution route.'),
      findsOneWidget,
    );
    expect(find.text('Contribute now'), findsNothing);
    expect(find.textContaining('Bank contributions'), findsNothing);
  });

  testWidgets('Ledger with a MoMo route offers contribution', (tester) async {
    await _pump(
      tester,
      const LedgerScreen(collectionId: 'scope-group'),
      group: _group(hasMomoRoute: true),
    );

    expect(
      find.text('Confirmed MoMo contributions appear here.'),
      findsOneWidget,
    );
    expect(find.text('Contribute now'), findsOneWidget);
  });
}
