import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/partners/rayon/screens/member_registry_screen.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late RsRegistryMember member;

  setUpAll(() {
    registerFallbackValue(FanTier.blue);
  });

  setUp(() {
    repository = MockRayonSportsRepository();
    member = RsRegistryMember(
      userId: 'user-1',
      displayName: 'Alex Fan',
      membershipNumber: 'RS-2026-AAA111',
      points: 3400,
      tier: FanTier.gold,
      chapter: 'Kigali Central',
      joinedAt: DateTime(2026, 2, 1),
    );

    when(
      () => repository.getMembers(
        'partner-1',
        searchQuery: any(named: 'searchQuery'),
        filterTier: any(named: 'filterTier'),
        region: any(named: 'region'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => <RsRegistryMember>[member]);
  });

  testWidgets(
    'member registry resolves the lightweight partner id path without loading full Rayon data',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rayonSportsRepositoryProvider.overrideWithValue(repository),
            rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
          ],
          child: const MaterialApp(home: MemberRegistryScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Alex Fan'), findsWidgets);
      expect(find.text('Supporter Registry Command'), findsOneWidget);
      verify(
        () => repository.getMembers(
          'partner-1',
          searchQuery: null,
          filterTier: null,
          region: null,
          limit: 20,
          offset: 0,
        ),
      ).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );
}
