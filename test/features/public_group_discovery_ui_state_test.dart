// Synthetic widget fixtures only; no provider, device, payment or SMS traffic.
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/collections/collection_detail_screen.dart';
import 'package:collect_app/features/collections/collections_screen.dart';
import 'package:collect_app/features/collections/group_empty_state.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _viewer = CollectProfile(
  id: 'synthetic-viewer',
  publicId: '123456',
  whatsappPhone: '+250788123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
);

CollectCollection _privateGroup() => CollectCollection(
  id: 'private-group',
  slug: 'private-group',
  creatorUserId: _viewer.id,
  title: 'Member group',
  description: '',
  isCurrentUserMember: true,
  createdAt: DateTime.utc(2026),
);

CollectCollection _publicGroup({bool member = false}) => CollectCollection(
  id: 'public-group',
  slug: 'public-group',
  creatorUserId: 'platform',
  title: 'Public group',
  description: '',
  receiverMomoNumber: '0788123456',
  receiverNetwork: 'mtn_momo',
  isPublic: true,
  isCurrentUserMember: member,
  createdAt: DateTime.utc(2026),
);

class _Repository extends CollectRepository {
  _Repository({
    required List<CollectCollection> collections,
    bool publicLoading = false,
    bool publicUnavailable = false,
    bool refreshing = false,
    bool stale = false,
    bool financialUncertain = false,
    bool synced = true,
    bool signedIn = true,
  }) : super.fixture(
         initialState: CollectState(
           currentProfile: signedIn ? _viewer : null,
           collections: collections,
           paymentIntents: const [],
           contributions: const [],
           isLoading: refreshing,
           usingStaleCache: stale,
           publicDiscoveryLoading: publicLoading,
           publicDiscoveryUnavailable: publicUnavailable,
           financialObservationUncertain: financialUncertain,
           lastSuccessfulSyncAt: synced ? DateTime.utc(2026) : null,
         ),
       );

  int refreshes = 0;
  int historyReads = 0;

  void discovery({
    required bool loading,
    required bool unavailable,
    bool? refreshing,
  }) {
    state = state.copyWith(
      isLoading: refreshing ?? state.isLoading,
      publicDiscoveryLoading: loading,
      publicDiscoveryUnavailable: unavailable,
    );
  }

  void membership(bool member) {
    state = state.copyWith(collections: [_publicGroup(member: member)]);
  }

  void clearUncertainty() {
    state = state.copyWith(
      usingStaleCache: false,
      financialObservationUncertain: false,
    );
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    refreshes++;
  }

  @override
  MemberHistoryPage localHistoryPage(MemberHistoryQuery query) {
    historyReads++;
    return super.localHistoryPage(query);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _Repository repository,
  String location, {
  double textScale = 1,
  bool defaultMissingState = false,
}) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/groups',
        builder: (_, _) => const CollectionsScreen(),
        routes: [
          GoRoute(
            path: ':collectionId',
            builder: (_, state) => defaultMissingState
                ? const MissingGroupStateScreen()
                : CollectionDetailScreen(
                    collectionId: state.pathParameters['collectionId']!,
                  ),
          ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((_) => repository)],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('featured groups wait for public discovery', (tester) async {
    final repo = _Repository(
      collections: [_privateGroup()],
      publicLoading: true,
    );
    await _pumpScreen(tester, repo, '/groups?filter=featured');
    expect(find.text('Loading public groups'), findsOneWidget);
    expect(find.text('No featured groups loaded'), findsNothing);

    repo.discovery(loading: false, unavailable: false);
    await tester.pump();
    expect(find.text('Loading public groups'), findsNothing);
    expect(find.text('No featured groups loaded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured groups stay pending through both refresh phases', (
    tester,
  ) async {
    final repo = _Repository(collections: [_privateGroup()], refreshing: true);
    await _pumpScreen(tester, repo, '/groups?filter=featured');
    expect(find.text('Loading public groups'), findsOneWidget);
    expect(find.text('No featured groups loaded'), findsNothing);

    repo.discovery(loading: true, unavailable: false, refreshing: false);
    await tester.pump();
    expect(find.text('Loading public groups'), findsOneWidget);
    expect(find.text('No featured groups loaded'), findsNothing);

    repo.discovery(loading: false, unavailable: false);
    await tester.pump();
    expect(find.text('No featured groups loaded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search distinguishes loading and failure from no matches', (
    tester,
  ) async {
    final repo = _Repository(
      collections: [_privateGroup()],
      publicLoading: true,
    );
    await _pumpScreen(tester, repo, '/groups');
    expect(find.text('Member group'), findsOneWidget);
    await tester.tap(find.byTooltip('Search groups'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('Loading public groups'), findsOneWidget);
    expect(find.text('No matches in loaded groups'), findsNothing);

    repo.discovery(loading: false, unavailable: true);
    await tester.pump();
    expect(find.text('Could not load data'), findsOneWidget);
    expect(find.text('No matches in loaded groups'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repo.refreshes, 1);

    repo.discovery(loading: false, unavailable: false);
    await tester.pump();
    expect(find.text('Could not load data'), findsNothing);
    expect(find.text('No matches in loaded groups'), findsOneWidget);
    expect(find.text('Only loaded groups were searched.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member filter remains usable while public discovery fails', (
    tester,
  ) async {
    final repo = _Repository(
      collections: [_privateGroup()],
      publicLoading: true,
    );
    await _pumpScreen(tester, repo, '/groups?filter=member');
    expect(find.text('Member group'), findsOneWidget);
    expect(find.text('Loading public groups'), findsNothing);

    repo.discovery(loading: false, unavailable: true);
    await tester.pump();
    expect(find.text('Member group'), findsOneWidget);
    expect(find.text('Could not load data'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default unsynced state does not claim an empty public list', (
    tester,
  ) async {
    final repo = _Repository(collections: [], synced: false, signedIn: false);
    await _pumpScreen(tester, repo, '/groups');
    expect(find.text('Public groups not yet confirmed'), findsOneWidget);
    expect(find.text('No groups loaded'), findsNothing);
    expect(find.text('Could not load data'), findsNothing);
    expect(find.text('Refresh groups'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsynced public view retains known cards', (tester) async {
    final repo = _Repository(collections: [_privateGroup()], synced: false);
    await _pumpScreen(tester, repo, '/groups');
    expect(find.text('Member group'), findsOneWidget);
    expect(find.text('Public groups not yet confirmed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default unsynced detail does not claim the group is missing', (
    tester,
  ) async {
    final repo = _Repository(collections: [], synced: false, signedIn: false);
    await _pumpScreen(tester, repo, '/groups/public-group');
    expect(find.text('Group not yet confirmed'), findsOneWidget);
    expect(find.text('Group not in loaded groups'), findsNothing);
    expect(find.text('Group is not available.'), findsNothing);
    expect(find.text('Could not load data'), findsNothing);
    expect(find.text('Open groups'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared missing group defaults retain recovery copy', (
    tester,
  ) async {
    final repo = _Repository(collections: []);
    await _pumpScreen(
      tester,
      repo,
      '/groups/public-group',
      defaultMissingState: true,
    );
    expect(find.text('Group is not available.'), findsOneWidget);
    expect(
      find.text(
        'The group may not be joined on this device, the link may have expired, or the group may have been removed.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open groups'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty supported view reports unknown history', (tester) async {
    final repo = _Repository(collections: []);
    await _pumpScreen(tester, repo, '/groups?filter=contributed');
    expect(find.text('Supported groups unavailable'), findsOneWidget);
    expect(find.text('No groups loaded'), findsNothing);
    expect(find.text('Public groups not yet confirmed'), findsNothing);
    expect(find.text('Public groups may be incomplete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored member cards remain visible when discovery fails', (
    tester,
  ) async {
    final repo = _Repository(
      collections: [_privateGroup()],
      stale: true,
      publicUnavailable: true,
    );
    await _pumpScreen(tester, repo, '/groups');
    expect(find.text('Member group'), findsOneWidget);
    expect(find.text('Public groups may be incomplete'), findsOneWidget);
    expect(find.text('Loaded groups may be out of date.'), findsOneWidget);
    expect(find.text('Could not load data'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repo.refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  for (final stale in [true, false]) {
    final reason = stale ? 'stale data' : 'an uncertain refresh';
    testWidgets('public search remains uncertain after $reason', (
      tester,
    ) async {
      final repo = _Repository(
        collections: [_privateGroup()],
        stale: stale,
        financialUncertain: !stale,
      );
      await _pumpScreen(tester, repo, '/groups');
      expect(find.text('Member group'), findsOneWidget);
      expect(find.text('Public groups may be incomplete'), findsOneWidget);
      await tester.tap(find.byTooltip('Search groups'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump();
      expect(find.text('Public groups may be incomplete'), findsOneWidget);
      expect(find.text('No matches in loaded groups'), findsNothing);
      await tester.tap(find.text('Refresh groups'));
      await tester.pump();
      expect(repo.refreshes, 1);

      repo.clearUncertainty();
      await tester.pump();
      expect(find.text('Public groups may be incomplete'), findsNothing);
      expect(find.text('No matches in loaded groups'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing group detail stays unknown after $reason', (
      tester,
    ) async {
      final repo = _Repository(
        collections: [_privateGroup()],
        stale: stale,
        financialUncertain: !stale,
      );
      await _pumpScreen(tester, repo, '/groups/public-group');
      expect(find.text('Could not load data'), findsOneWidget);
      expect(find.text('Group not in loaded groups'), findsNothing);

      repo.clearUncertainty();
      await tester.pump();
      expect(find.text('Group not in loaded groups'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'missing detail waits for discovery and offers retry on failure',
    (tester) async {
      final repo = _Repository(
        collections: [_privateGroup()],
        publicLoading: true,
      );
      await _pumpScreen(tester, repo, '/groups/public-group');
      expect(find.text('Loading group'), findsOneWidget);
      expect(find.text('Group not in loaded groups'), findsNothing);

      repo.discovery(loading: false, unavailable: true);
      await tester.pump();
      expect(find.text('Could not load data'), findsOneWidget);
      expect(find.text('Group not in loaded groups'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(repo.refreshes, 1);

      repo.discovery(loading: false, unavailable: false);
      await tester.pump();
      expect(find.text('Group not in loaded groups'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('activity follows membership at ${scale}x', (tester) async {
      final repo = _Repository(collections: [_publicGroup()]);
      await _pumpScreen(tester, repo, '/groups/public-group', textScale: scale);
      await tester.scrollUntilVisible(
        find.text('Activity for members'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(repo.historyReads, 0);
      expect(find.text('No contributions yet'), findsNothing);

      repo.membership(true);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('No contributions yet'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(repo.historyReads, 1);
      expect(find.text('Activity for members'), findsNothing);

      repo.membership(false);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Activity for members'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(repo.historyReads, 1);
      expect(find.text('No contributions yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
