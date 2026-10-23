import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/member_signed_history_test.dart' as fixture;

class _HistoryRepository extends CollectRepository {
  _HistoryRepository(this.page)
    : super.fixture(
        initialState: CollectState(
          currentProfile: const CollectProfile(
            id: 'history-owner',
            publicId: '123456',
            whatsappPhone: '+250788000001',
            countryCode: 'RW',
            currencyCode: 'RWF',
            momoProvider: 'mtn_momo',
            momoNumber: '0788000001',
          ),
          collections: [
            CollectCollection(
              id: fixture.uuid(200),
              slug: 'member-group',
              creatorUserId: 'history-owner',
              title: 'Member group',
              description: '',
              isCurrentUserMember: true,
              receiverMomoNumber: '0788000001',
              receiverNetwork: 'mtn_momo',
              createdAt: DateTime.utc(2026, 10, 1),
            ),
          ],
          paymentIntents: const [],
          contributions: page.items,
          historyPage: page,
          collectionSummaries: {
            fixture.uuid(200): const CollectionSummary(
              amountRaisedRwf: 0,
              supporterCount: 0,
              currentUserBalanceRwf: 0,
            ),
          },
        ),
      );
  final MemberHistoryPage page;
  @override
  bool get isLive => true;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}
  @override
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async => page;
}

void main() {
  for (final route in [
    '/activity',
    '/groups/${fixture.uuid(200)}/ledger',
    '/home',
  ]) {
    testWidgets('$route distinguishes a reversal from its original record', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = fixture.decode(
        fixture.wire([
          fixture.event(2, amount: -1000, kind: 'reversal', reverses: 1),
          fixture.event(1),
        ]),
      );
      final repository = _HistoryRepository(page);
      final router = createAppRouter(initialLocation: route);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const CollectApp(),
        ),
      );
      await tester.pumpAndSettle();
      if (route.contains('ledger')) {
        final rows = tester
            .widgetList<FinancialListRow>(find.byType(FinancialListRow))
            .toList();
        expect(rows.map((row) => row.subtitle), contains('Recorded reversal'));
        expect(rows.map((row) => row.amountRwf), contains(-1000));
      } else {
        final rows = tester
            .widgetList<ActivityFeedItem>(find.byType(ActivityFeedItem))
            .toList();
        expect(
          rows
              .map((row) => row.meta)
              .any((meta) => meta.startsWith('Recorded reversal · ')),
          isTrue,
        );
        expect(rows.map((row) => row.amount), contains(-1000));
      }
      expect(find.text('RWF -1,000'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
