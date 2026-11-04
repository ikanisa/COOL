// Synthetic widget fixtures only; no provider, device, payment or SMS traffic.
import 'dart:async';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/collections/collection_detail_screen.dart';
import 'package:collect_app/features/collections/collections_screen.dart';
import 'package:collect_app/features/collections/group_empty_state.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
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

CollectCollection _publicGroup({
  bool member = false,
  String id = 'public-group',
}) => CollectCollection(
  id: id,
  slug: id,
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
    bool memberScopeUncertain = false,
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
           memberScopeUncertain: memberScopeUncertain,
           lastSuccessfulSyncAt: synced ? DateTime.utc(2026) : null,
         ),
       );

  int refreshes = 0;
  int historyReads = 0;
  int publicJoins = 0;
  int testSessionGeneration = 0;
  bool syntheticLive = false;
  Completer<void>? joinGate;
  final List<Completer<void>> joinSequence = [];
  bool returnLateJoinWithoutApplying = false;

  @override
  int get sessionGeneration => testSessionGeneration;

  @override
  bool get isLive => syntheticLive || super.isLive;

  @override
  Future<CollectCollection> joinPublicGroup(String collectionId) async {
    final index = publicJoins++;
    final gate = index < joinSequence.length ? joinSequence[index] : joinGate;
    await gate?.future;
    if (returnLateJoinWithoutApplying) {
      return _publicGroup(member: true, id: collectionId);
    }
    return super.joinPublicGroup(collectionId);
  }

  void replaceSession() {
    testSessionGeneration++;
    state = state.copyWith(currentProfile: _viewer);
  }

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
        path: '/auth',
        builder: (_, state) => Scaffold(
          body: Text('Auth next: ${state.uri.queryParameters['next']}'),
        ),
      ),
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
            routes: [
              GoRoute(
                path: 'contribute',
                builder: (_, _) =>
                    const Scaffold(body: Text('Contribution route')),
              ),
            ],
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

  testWidgets('public group can be joined without making a contribution', (
    tester,
  ) async {
    final repo = _Repository(collections: [_publicGroup()]);
    expect(repo.state.currentProfile!.isComplete, isFalse);
    await _pumpScreen(tester, repo, '/groups/public-group');
    expect(find.text('Contribute & Join'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pumpAndSettle();
    expect(repo.publicJoins, 1);
    expect(repo.state.collections.single.isCurrentUserMember, isTrue);
    expect(repo.state.paymentIntents, isEmpty);
    expect(find.byKey(const ValueKey('join-public-group')), findsNothing);
    expect(find.text('Contribute'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guest is sent to sign in with the group as the return route', (
    tester,
  ) async {
    final repo = _Repository(collections: [_publicGroup()], signedIn: false);
    await _pumpScreen(tester, repo, '/groups/public-group');
    expect(find.text('Sign in to join'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pumpAndSettle();
    expect(find.text('Auth next: /groups/public-group'), findsOneWidget);
    expect(repo.publicJoins, 0);
    expect(repo.state.paymentIntents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an authenticated viewer with no profile gets a clear message', (
    tester,
  ) async {
    final repo = _Repository(collections: [_publicGroup()], signedIn: false)
      ..syntheticLive = true;
    await _pumpScreen(tester, repo, '/groups/public-group');
    expect(find.text('Profile unavailable'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pump();
    expect(repo.refreshes, 0);
    expect(repo.publicJoins, 0);
    expect(
      find.text('Your profile is unavailable. Refresh and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Auth next:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending public join cannot be submitted twice', (
    tester,
  ) async {
    final repo = _Repository(collections: [_publicGroup()])
      ..joinGate = Completer<void>();
    await _pumpScreen(tester, repo, '/groups/public-group');
    final retainedContribution = tester
        .widget<CollectScreenHero>(find.byType(CollectScreenHero))
        .quickActions
        .singleWhere((a) => a.label == 'Contribute & Join')
        .onTap!;
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pump();
    retainedContribution();
    await tester.pump();
    expect(find.text('Contribution route'), findsNothing);
    expect(find.byType(CollectionDetailScreen), findsOneWidget);
    final join = tester.widget<CollectButton>(
      find.byKey(const ValueKey('join-public-group')),
    );
    expect(join.label, 'Joining group');
    expect(join.onPressed, isNull);
    final hero = tester.widget<CollectScreenHero>(
      find.byType(CollectScreenHero),
    );
    expect(
      hero.quickActions
          .singleWhere((a) => a.label == 'Contribute & Join')
          .onTap,
      isNull,
    );
    expect(repo.publicJoins, 1);
    repo.joinGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.publicJoins, 1);
    expect(repo.state.collections.single.isCurrentUserMember, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late join result does not announce success in a new session', (
    tester,
  ) async {
    final repo = _Repository(collections: [_publicGroup()])
      ..joinGate = Completer<void>()
      ..returnLateJoinWithoutApplying = true;
    await _pumpScreen(tester, repo, '/groups/public-group');
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pump();
    repo.replaceSession();
    repo.joinGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('You joined the group.'), findsNothing);
    expect(repo.state.collections.single.isCurrentUserMember, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an earlier group join cannot clear a later join after A to B to A',
    (tester) async {
      final first = Completer<void>(), second = Completer<void>();
      final repo = _Repository(
        collections: [
          _publicGroup(),
          _publicGroup(id: 'public-group-2'),
        ],
      )..returnLateJoinWithoutApplying = true;
      repo.joinSequence.addAll([first, second]);
      await _pumpScreen(tester, repo, '/groups/public-group');
      await tester.tap(find.byKey(const ValueKey('join-public-group')));
      await tester.pump();
      GoRouter.of(
        tester.element(find.byType(CollectionDetailScreen)),
      ).go('/groups/public-group-2');
      await tester.pumpAndSettle();
      expect(find.text('Join group'), findsOneWidget);
      GoRouter.of(
        tester.element(find.byType(CollectionDetailScreen)),
      ).go('/groups/public-group');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('join-public-group')));
      await tester.pump();
      expect(repo.publicJoins, 2);
      first.complete();
      await tester.pump();
      expect(find.text('You joined the group.'), findsNothing);
      expect(
        tester
            .widget<CollectButton>(
              find.byKey(const ValueKey('join-public-group')),
            )
            .onPressed,
        isNull,
      );
      second.complete();
      await tester.pumpAndSettle();
      expect(find.text('You joined the group.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an earlier session cannot clear a later pending join', (
    tester,
  ) async {
    final first = Completer<void>(), second = Completer<void>();
    final repo = _Repository(collections: [_publicGroup()])
      ..returnLateJoinWithoutApplying = true;
    repo.joinSequence.addAll([first, second]);
    await _pumpScreen(tester, repo, '/groups/public-group');
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pump();
    repo.replaceSession();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pump();
    expect(repo.publicJoins, 2);
    first.complete();
    await tester.pump();
    expect(find.text('You joined the group.'), findsNothing);
    expect(
      tester
          .widget<CollectButton>(
            find.byKey(const ValueKey('join-public-group')),
          )
          .onPressed,
      isNull,
    );
    second.complete();
    await tester.pumpAndSettle();
    expect(find.text('You joined the group.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retained old group callback cannot disturb a newer join', (
    tester,
  ) async {
    final hold = Completer<void>();
    final repo = _Repository(
      collections: [
        _publicGroup(),
        _publicGroup(id: 'public-group-2'),
      ],
    )..returnLateJoinWithoutApplying = true;
    repo.joinSequence.add(hold);
    await _pumpScreen(tester, repo, '/groups/public-group');
    final oldCallback = tester
        .widget<CollectButton>(find.byKey(const ValueKey('join-public-group')))
        .onPressed!;
    GoRouter.of(
      tester.element(find.byType(CollectionDetailScreen)),
    ).go('/groups/public-group-2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('join-public-group')));
    await tester.pump();
    oldCallback();
    await tester.pump();
    expect(repo.publicJoins, 1);
    expect(
      tester
          .widget<CollectButton>(
            find.byKey(const ValueKey('join-public-group')),
          )
          .onPressed,
      isNull,
    );
    GoRouter.of(
      tester.element(find.byType(CollectionDetailScreen)),
    ).go('/groups/public-group');
    await tester.pumpAndSettle();
    oldCallback();
    await tester.pump();
    expect(repo.publicJoins, 1);
    hold.complete();
    await tester.pump();
    expect(find.text('You joined the group.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retained guest callback cannot open the wrong sign-in route', (
    tester,
  ) async {
    final repo = _Repository(
      collections: [
        _publicGroup(),
        _publicGroup(id: 'public-group-2'),
      ],
      signedIn: false,
    );
    await _pumpScreen(tester, repo, '/groups/public-group');
    final oldCallback = tester
        .widget<CollectButton>(find.byKey(const ValueKey('join-public-group')))
        .onPressed!;
    GoRouter.of(
      tester.element(find.byType(CollectionDetailScreen)),
    ).go('/groups/public-group-2');
    await tester.pumpAndSettle();
    oldCallback();
    await tester.pump();
    expect(find.textContaining('Auth next:'), findsNothing);
    expect(find.byType(CollectionDetailScreen), findsOneWidget);
    expect(repo.publicJoins, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified membership does not claim a group is missing', (
    tester,
  ) async {
    final repository = _Repository(
      collections: [_privateGroup()],
      memberScopeUncertain: true,
    );
    await _pumpScreen(
      tester,
      repository,
      '/groups/private-group',
      defaultMissingState: true,
    );
    expect(find.text('Refresh to verify this group.'), findsOneWidget);
    expect(find.text('Group is not available.'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repository.refreshes, 1);
  });
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
