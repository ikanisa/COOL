import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/features/auth/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  group('AuthRepository.deleteAccount', () {
    late MockSupabaseClient client;
    late MockFunctionsClient functionsClient;
    late MockGoTrueClient authClient;
    late AuthRepository repository;

    setUp(() {
      client = MockSupabaseClient();
      functionsClient = MockFunctionsClient();
      authClient = MockGoTrueClient();
      repository = AuthRepository(client: client);

      when(() => client.functions).thenReturn(functionsClient);
      when(() => client.auth).thenReturn(authClient);
      when(
        () => functionsClient.invoke(any(), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: <String, dynamic>{'success': true},
          status: 200,
        ),
      );
      when(() => authClient.signOut()).thenAnswer((_) async {});
    });

    test(
      'sends explicit confirmation to the delete-account edge function',
      () async {
        await repository.deleteAccount();

        final captured =
            verify(
                  () => functionsClient.invoke(
                    'delete-account',
                    body: captureAny(named: 'body'),
                  ),
                ).captured.single
                as Map<dynamic, dynamic>;

        expect(captured, <String, dynamic>{'confirm': true});
        verify(() => authClient.signOut()).called(1);
      },
    );

    test(
      'swallows local sign-out failures after a successful deletion',
      () async {
        when(
          () => authClient.signOut(),
        ).thenThrow(StateError('session already cleared'));

        await expectLater(repository.deleteAccount(), completes);
      },
    );
  });

  test(
    'delete-account edge function rejects requests without explicit confirmation',
    () {
      final source = File(
        'supabase/functions/delete-account/index.ts',
      ).readAsStringSync();

      expect(source, contains('body.confirm !== true'));
      expect(source, contains('Account deletion was not confirmed'));
    },
  );
}
