import 'package:flutter_test/flutter_test.dart';

import 'fixtures/collect_repository_fixture.dart';

void main() {
  test(
    'uncertain member scope hides prior records without changing SMS state',
    () {
      final repository = FixtureCollectRepository();
      addTearDown(repository.dispose);
      final known = repository.state.copyWith(
        smsAccessEnabled: true,
        smsSyncNeedsAttention: true,
        pendingIntentCount: 1,
      );
      final uncertain = known.copyWith(memberScopeUncertain: true);

      expect(uncertain.currentProfile, same(known.currentProfile));
      expect(uncertain.smsAccessEnabled, isTrue);
      expect(uncertain.smsSyncNeedsAttention, isTrue);
      expect(uncertain.collections, isEmpty);
      expect(uncertain.paymentIntents, isEmpty);
      expect(uncertain.contributions, isEmpty);
      expect(uncertain.collectionSummaries, isEmpty);
      expect(uncertain.historyPage, isNull);
      expect(uncertain.pendingIntentCount, isNull);
      expect(uncertain.financialObservationUncertain, isTrue);
      expect(uncertain.hasInitialLoadFailure, isTrue);

      // A late publisher cannot expose an earlier snapshot by copying state.
      final late = uncertain.copyWith(
        collections: known.collections,
        paymentIntents: known.paymentIntents,
        contributions: known.contributions,
        collectionSummaries: known.collectionSummaries,
        historyPage: known.historyPage,
        pendingIntentCount: known.pendingIntentCount,
        financialObservationUncertain: false,
      );
      expect(late.collections, isEmpty);
      expect(late.paymentIntents, isEmpty);
      expect(late.contributions, isEmpty);
      expect(late.collectionSummaries, isEmpty);
      expect(late.historyPage, isNull);
      expect(late.pendingIntentCount, isNull);
      expect(late.financialObservationUncertain, isTrue);

      // Unrelated state changes cannot make the old snapshot visible if a
      // caller clears only the scope flag without a complete replacement.
      final partial = uncertain
          .copyWith(smsSyncNeedsAttention: false)
          .copyWith(memberScopeUncertain: false);
      expect(partial.collections, isEmpty);
      expect(partial.paymentIntents, isEmpty);
      expect(partial.contributions, isEmpty);
      expect(partial.collectionSummaries, isEmpty);
      expect(partial.historyPage, isNull);
      expect(partial.pendingIntentCount, isNull);
      expect(partial.financialObservationUncertain, isTrue);
      expect(partial.smsAccessEnabled, isTrue);

      final refreshed = late.copyWith(
        memberScopeUncertain: false,
        financialObservationUncertain: false,
        collections: known.collections,
        paymentIntents: known.paymentIntents,
        contributions: known.contributions,
        collectionSummaries: known.collectionSummaries,
        historyPage: known.historyPage,
        pendingIntentCount: known.pendingIntentCount,
      );
      expect(refreshed.collections, known.collections);
      expect(refreshed.historyPage, same(known.historyPage));
      expect(refreshed.pendingIntentCount, 1);
      expect(refreshed.financialObservationUncertain, isFalse);
    },
  );
}
