import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/biopay/models/biopay_enrollment_draft.dart';
import 'package:cool_app/features/biopay/providers/biopay_providers.dart';
import 'package:cool_app/features/biopay/screens/biopay_register_screen.dart';
import 'package:cool_app/features/momo/providers/momo_service_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import '../../helpers/test_bootstrap.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _TestRegisterAuthNotifier extends AuthNotifier {
  _TestRegisterAuthNotifier({
    required super.repository,
    required super.crashlytics,
    required super.performance,
    required super.momoService,
    required AuthState initialState,
  }) {
    state = initialState;
  }

  @override
  Future<void> restoreCurrentUser() async {}
}

Session _fakeSession() {
  return Session.fromJson(<String, dynamic>{
    'access_token': 'token-user-1',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-user-1',
    'user': <String, dynamic>{
      'id': 'user-1',
      'user_metadata': const <String, dynamic>{},
      'app_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': DateTime(2026).toIso8601String(),
    },
  })!;
}

void main() {
  testWidgets('continues to face capture without a loaded app profile', (
    tester,
  ) async {
    final repository = _MockAuthRepository();
    final session = _fakeSession();
    when(() => repository.currentSession).thenReturn(session);
    when(() => repository.currentUserId).thenReturn(session.user.id);

    final container = createTestContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authProvider.overrideWith(
          (ref) => _TestRegisterAuthNotifier(
            repository: repository,
            crashlytics: ref.read(crashlyticsServiceProvider),
            performance: ref.read(performanceServiceProvider),
            momoService: ref.read(momoServiceProvider),
            initialState: AuthState(
              session: session,
              profileRestoreState: AuthProfileRestoreState.missing,
            ),
          ),
        ),
        biopayProfileProvider.overrideWith((ref) async => null),
        biopayModelAssetIssueProvider.overrideWith((ref) async => null),
      ],
    );

    final router = GoRouter(
      initialLocation: AppRoutes.biopayRegister,
      routes: [
        GoRoute(
          path: AppRoutes.biopayRegister,
          builder: (context, state) => const BiopayRegisterScreen(),
        ),
        GoRoute(
          path: AppRoutes.biopayScan,
          builder: (context, state) {
            final draft = state.extra! as BiopayEnrollmentDraft;
            return Scaffold(
              body: Text(
                'scan:${draft.displayName}:${draft.routeType.name}:${draft.recipientValue}:${draft.countryCode}',
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: widget!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, '0788123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('scan:BioPay User'), findsOneWidget);
    expect(find.textContaining(':phoneNumber:0788123456:RW'), findsOneWidget);
  });
}
