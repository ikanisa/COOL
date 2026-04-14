import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart'
    as app_auth;
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/models/group_invite_preview.dart';
import 'package:cool_app/features/groups/models/group_join_result.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/groups/repositories/group_repository.dart';
import 'package:cool_app/features/groups/screens/group_create_screen.dart';
import 'package:cool_app/features/groups/screens/groups_screen.dart';
import 'package:cool_app/features/groups/widgets/group_form_widgets.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';



class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _StaticAuthNotifier extends app_auth.AuthNotifier {
  _StaticAuthNotifier(this._initialState);
  final app_auth.AuthState _initialState;

  @override
  app_auth.AuthState build() => _initialState;
}

class _FakeGroupRepository extends GroupRepository {
  _FakeGroupRepository() : super(client: _MockSupabaseClient());

  final List<Map<String, dynamic>> createCalls = <Map<String, dynamic>>[];
  final List<String> joinInviteCodes = <String>[];

  @override
  Future<Group> createGroup({
    required UserProfile creator,
    required String name,
    required String visibility,
    required String type,
    String? description,
    int? targetAmount,
    int? monthlyContribution,
    MomoRecipientType? customMomoRouteType,
    String? customRecipientValue,
    String? frequency,
  }) async {
    createCalls.add(<String, dynamic>{
      'creatorId': creator.id,
      'name': name,
      'visibility': visibility,
      'type': type,
      'description': description,
      'targetAmount': targetAmount,
      'monthlyContribution': monthlyContribution,
      'routeType': customMomoRouteType,
      'recipientValue': customRecipientValue,
      'frequency': frequency,
    });

    return const Group(
      id: 'group-created',
      creatorId: 'user-1',
      name: 'New Circle',
      type: 'saving',
      visibility: 'private',
      amount: 0,
      targetAmount: 300000,
      country: 'RW',
      monthlyContribution: 25000,
      description: 'School fees goal',
      momoNumber: '0788123456',
      momoRouteType: 'phone_number',
      frequency: 'monthly',
    );
  }

  @override
  Future<GroupJoinResult> joinGroupViaInvite(String inviteCode) async {
    joinInviteCodes.add(inviteCode);
    return const GroupJoinResult(status: 'joined', groupId: 'group-invite-1');
  }
}

GoRouter _buildRouter(Widget child, {String path = '/'}) {
  return GoRouter(
    initialLocation: path,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const SizedBox.shrink(),
        routes: <RouteBase>[
          GoRoute(path: 'create', builder: (context, state) => child),
          GoRoute(path: 'groups', builder: (context, state) => child),
          GoRoute(
            path: 'groups/:groupId',
            builder: (context, state) => Text(
              'group-detail:${state.pathParameters['groupId']}:${state.uri.queryParameters['invite_code'] ?? ''}',
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpWithRouter(
  WidgetTester tester, {
  required Widget child,
  required List<Override> overrides,
  required String path,
}) async {
  final router = _buildRouter(child, path: path);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUpAll(() async {
    await CoolCountryCatalog.initialize(
      await File('assets/countries.json').readAsString(),
    );
  });

  testWidgets('verified user creates a savings group', (tester) async {
    _configureTallViewport(tester);
    final repository = _FakeGroupRepository();

    await _pumpWithRouter(
      tester,
      child: const GroupCreateScreen(),
      path: '/create',
      overrides: <Override>[
        app_auth.authProvider.overrideWith(
          () => _StaticAuthNotifier(_verifiedState),
        ),
        groupRepositoryProvider.overrideWithValue(repository),
      ],
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'New Circle');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'School fees goal',
    );
    await tester.enterText(find.byType(TextFormField).at(2), '300000');
    await tester.enterText(find.byType(TextFormField).at(3), '25000');

    await tester.ensureVisible(find.byType(GroupOptionChip).first);
    await tester.tap(find.byType(GroupOptionChip).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GroupOptionChip).at(4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CREATE GROUP'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, hasLength(1));
    expect(repository.createCalls.single['creatorId'], 'user-1');
    expect(repository.createCalls.single['name'], 'New Circle');
    expect(repository.createCalls.single['type'], 'saving');
    expect(repository.createCalls.single['frequency'], 'monthly');
    expect(
      repository.createCalls.single['routeType'],
      MomoRecipientType.phoneNumber,
    );
    expect(repository.createCalls.single['recipientValue'], '0788123456');
  });

  testWidgets('invite banner opens a private-group preview route', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = _FakeGroupRepository();

    await _pumpWithRouter(
      tester,
      child: const GroupsScreen(inviteCode: 'JOIN1234'),
      path: '/groups',
      overrides: <Override>[
        app_auth.authProvider.overrideWith(
          () => _StaticAuthNotifier(_verifiedState),
        ),
        groupRepositoryProvider.overrideWithValue(repository),
        myGroupsProvider.overrideWith((ref) async => const <Group>[]),
        myGroupIdsProvider.overrideWith((ref) => <String>{}),
        groupInvitePreviewProvider('JOIN1234').overrideWith(
          (ref) async =>
              const GroupInvitePreview(group: _inviteGroup, isMember: false),
        ),
      ],
    );

    expect(find.text('Invite Circle'), findsOneWidget);

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.text('group-detail:group-invite-1:JOIN1234'), findsOneWidget);
  });
}

const app_auth.AuthState _verifiedState = app_auth.AuthState(
  user: UserProfile(
    id: 'user-1',
    phone: '+250788123456',
    fullName: 'Verified User',
    momoNumber: '0788123456',
    momoProvider: 'mtn_momo_rw',
    country: 'RW',
  ),
  profileRestoreState: app_auth.AuthProfileRestoreState.available,
);

const Group _inviteGroup = Group(
  id: 'group-invite-1',
  creatorId: 'user-2',
  name: 'Invite Circle',
  type: 'community',
  visibility: 'private',
  amount: 0,
  targetAmount: 0,
  country: 'RW',
  memberCount: 5,
  monthlyContribution: 0,
  description: 'Open community pool',
  momoNumber: '0788111222',
  momoRouteType: 'phone_number',
  inviteCode: 'JOIN1234',
);
