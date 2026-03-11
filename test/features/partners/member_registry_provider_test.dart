import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/member_registry_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';

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
        any(),
        searchQuery: any(named: 'searchQuery'),
        filterTier: any(named: 'filterTier'),
        region: any(named: 'region'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => <RsRegistryMember>[member]);
  });

  test('init loads the first page for the resolved partner', () async {
    final notifier = MemberRegistryNotifier(repository: repository);

    await notifier.init('partner-1');

    expect(notifier.state.members, [member]);
    expect(notifier.state.hasMore, isFalse);
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
  });

  test('search and filter are forwarded to the repository before paging', () async {
    final notifier = MemberRegistryNotifier(repository: repository);
    await notifier.init('partner-1');

    notifier.selectFilter(MemberRegistryFilter.kigali);
    await pumpEventQueue();

    expect(notifier.state.filter, MemberRegistryFilter.kigali);
    verify(
      () => repository.getMembers(
        'partner-1',
        searchQuery: null,
        filterTier: null,
        region: 'kigali',
        limit: 20,
        offset: 0,
      ),
    ).called(1);

    notifier.search('  Alex');
    await pumpEventQueue();

    expect(notifier.state.query, 'Alex');
    verify(
      () => repository.getMembers(
        'partner-1',
        searchQuery: 'Alex',
        filterTier: null,
        region: 'kigali',
        limit: 20,
        offset: 0,
      ),
    ).called(1);
  });
}
