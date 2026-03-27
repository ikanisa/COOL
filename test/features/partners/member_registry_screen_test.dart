import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/partners/rayon/screens/member_registry_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late RsRegistryMember member;

  Future<void> pumpMemberRegistryScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(disableAnimations: true),
        child: ProviderScope(
          overrides: [
            rayonSportsRepositoryProvider.overrideWithValue(repository),
            rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
          ],
          child: const MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: MemberRegistryScreen(),
          ),
        ),
      ),
    );

    for (var index = 0; index < 8; index++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) {
        break;
      }
    }
  }

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
      await pumpMemberRegistryScreen(tester);

      expect(find.text('FAN REGISTRY'), findsOneWidget);
      expect(find.text('OFFICIAL GIKUNDIRO DATABASE'), findsOneWidget);
      expect(find.text(member.membershipNumber), findsWidgets);
      expect(find.text('SUPPORTER RANKINGS'), findsOneWidget);
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
