// PRIVATE CANDIDATE: authored, not executed or adopted.
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/widgets/collect_shell.dart';
import 'package:collect_app/features/collections/collection_detail_screen.dart';
import 'package:collect_app/features/collections/group_profile_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';

class _Repository extends FixtureCollectRepository {
  _Repository({
    bool hasRoute = false,
    bool foreignProfile = false,
    String? imageUrl,
  }) : super(
         profileOverride: CollectProfile(
           id: 'owner',
           publicId: '123456',
           whatsappPhone: '',
           countryCode: foreignProfile ? 'DE' : 'RW',
           currencyCode: foreignProfile ? 'EUR' : 'RWF',
         ),
       ) {
    state = state.copyWith(
      collections: [
        CollectCollection(
          id: 'qa-private-group',
          slug: 'qa-private-group',
          creatorUserId: 'owner',
          title: 'Metadata group',
          description: '',
          imageUrl: imageUrl,
          receiverMomoNumber: hasRoute ? '0788123456' : null,
          receiverDisplayLabel: hasRoute ? 'Synthetic destination' : '',
          receiverNetwork: hasRoute ? 'mtn_momo' : 'unknown',
          primaryPaymentRail: hasRoute ? 'rwanda_momo' : 'unavailable',
          settlementCurrency: 'RWF',
          isCurrentUserMember: true,
          createdAt: DateTime.utc(2026, 10, 20),
        ),
      ],
    );
  }
}

Future<void> _pumpGroup(
  WidgetTester tester,
  _Repository repo,
  double scale, {
  Widget? screen,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/group',
    routes: [
      GoRoute(
        path: '/groups/:collectionId/manage',
        builder: (_, _) => const Scaffold(body: Text('Saved group profile')),
      ),
      GoRoute(
        path: '/group',
        builder: (_, _) => CollectShell(
          currentPath: screen is GroupProfileScreen
              ? '/groups/qa-private-group/profile'
              : '/groups/qa-private-group',
          child:
              screen ??
              const CollectionDetailScreen(collectionId: 'qa-private-group'),
        ),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void expectUnavailableMemberActions(WidgetTester tester) {
  final disabled = tester.widget<CollectButton>(
    find.byKey(const ValueKey('group-payment-unavailable')),
  );
  expect(disabled.onPressed, isNull);
  expect(disabled.label, 'Payments unavailable');
  expect(find.text('Contribute'), findsNothing);
  expect(find.text('Share'), findsOneWidget);
  expect(find.text('Members'), findsOneWidget);
  expect(find.text('Manage'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'route-less group keeps invitations and disables payment at ${scale}x',
      (tester) async {
        await _pumpGroup(tester, _Repository(), scale);
        expectUnavailableMemberActions(tester);
        await tester.scrollUntilVisible(
          find.textContaining('no in-app payment destination'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('no in-app payment destination'),
          findsOneWidget,
        );
        expect(
          find.textContaining('not supported for your profile'),
          findsNothing,
        );
      },
    );
    testWidgets(
      'routed group distinguishes viewer ineligibility at ${scale}x',
      (tester) async {
        final repo = _Repository(hasRoute: true, foreignProfile: true);
        expect(repo.state.collections.single.supportsRwandaMomo, isTrue);
        await _pumpGroup(tester, repo, scale);
        expectUnavailableMemberActions(tester);
        await tester.scrollUntilVisible(
          find.textContaining('not supported for your profile'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('no in-app payment destination'),
          findsNothing,
        );
        expect(
          find.textContaining('not supported for your profile'),
          findsOneWidget,
        );
      },
    );
  }

  for (final hasRoute in [false, true]) {
    testWidgets(
      'profile shows a destination section only when present: $hasRoute',
      (tester) async {
        await _pumpGroup(
          tester,
          _Repository(hasRoute: hasRoute),
          1.0,
          screen: const GroupProfileScreen(collectionId: 'qa-private-group'),
        );
        expect(find.text('Group profile'), findsOneWidget);
        if (hasRoute) {
          await tester.scrollUntilVisible(
            find.text('Paying to'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.text('Paying to'),
          hasRoute ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Synthetic destination'),
          hasRoute ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('0788123456'),
          hasRoute ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Remove image then Save clears the stored group cover', (
    tester,
  ) async {
    const cover = 'collect-cover:rw-01-neighbourhood-ikimina:v1';
    final repo = _Repository(imageUrl: cover);
    await _pumpGroup(
      tester,
      repo,
      1.0,
      screen: const GroupProfileScreen(collectionId: 'qa-private-group'),
    );
    expect(repo.state.collections.single.imageUrl, cover);
    final save = find.widgetWithText(CollectButton, 'Save');
    expect(tester.widget<CollectButton>(save).onPressed, isNull);
    await tester.tap(find.byTooltip('Remove image'));
    await tester.pumpAndSettle();
    expect(tester.widget<CollectButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.state.collections.single.imageUrl, isNull);
    expect(find.text('Saved group profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
