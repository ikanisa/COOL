import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HomeActivityRepository extends CollectRepository {
  _HomeActivityRepository() : super.fixture() {
    state = state.copyWith(
      contributions: List.generate(
        7,
        (index) => Contribution(
          id: 'momo:$index',
          collectionId: 'col-church',
          amountRwf: (index + 1) * 1000,
          supporterLabel: '038491',
          isCurrentUserContribution: true,
          createdAt: DateTime.utc(2026, 9, 2, index),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Home takes the five newest receipts without mutating state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _HomeActivityRepository();
    final router = createAppRouter(initialLocation: '/home');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ActivityFeedItem>(find.byType(ActivityFeedItem))
          .map((item) => item.amount),
      [7000, 6000, 5000, 4000, 3000],
    );
    expect(repository.state.contributions.first.id, 'momo:0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
