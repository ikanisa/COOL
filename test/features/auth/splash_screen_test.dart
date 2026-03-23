import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/auth/screens/splash_screen.dart';
import 'package:cool_app/features/momo/providers/momo_service_provider.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import '../../helpers/test_bootstrap.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _TestSplashAuthNotifier extends AuthNotifier {
  _TestSplashAuthNotifier({
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
      'phone': '+250788123456',
      'user_metadata': const <String, dynamic>{'phone': '+250788123456'},
      'app_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': DateTime(2026).toIso8601String(),
    },
  })!;
}

void main() {
  testWidgets('shows restore failure card when profile recovery fails', (
    tester,
  ) async {
    final repository = _MockAuthRepository();
    final session = _fakeSession();
    when(() => repository.currentSession).thenReturn(session);

    final container = createTestContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authProvider.overrideWith(
          (ref) => _TestSplashAuthNotifier(
            repository: repository,
            crashlytics: ref.read(crashlyticsServiceProvider),
            performance: ref.read(performanceServiceProvider),
            momoService: ref.read(momoServiceProvider),
            initialState: AuthState(
              session: session,
              profileRestoreState: AuthProfileRestoreState.failed,
              error: 'Unable to restore your profile right now.',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: SplashScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Cool'), findsOneWidget);
    expect(find.text('We could not restore'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
