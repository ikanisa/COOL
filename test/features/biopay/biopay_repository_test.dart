import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/biopay/models/biopay_enrollment_draft.dart';
import 'package:cool_app/features/biopay/repositories/biopay_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  group('BiopayRepository', () {
    late MockSupabaseClient client;
    late MockFunctionsClient functionsClient;
    late BiopayRepository repository;

    setUp(() {
      client = MockSupabaseClient();
      functionsClient = MockFunctionsClient();
      repository = BiopayRepository(
        client: client,
        appCheckTokenProvider: () async => 'limited-use-token',
      );

      when(() => client.functions).thenReturn(functionsClient);
      when(
        () => functionsClient.invoke(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: <String, dynamic>{
            'success': true,
            'data': <String, dynamic>{
              'id': 'profile-1',
              'user_id': 'user-1',
              'display_name': 'Marie',
              'route_type': 'phone_number',
              'recipient_value': '0781234567',
              'country_code': 'RW',
              'consent_version': 'biopay-v1',
              'active': true,
              'created_at': '2026-03-23T12:00:00.000Z',
              'updated_at': '2026-03-23T12:00:00.000Z',
            },
          },
          status: 200,
        ),
      );
    });

    test(
      'attaches an App Check header and explicit route payload to enrollment requests',
      () async {
        const draft = BiopayEnrollmentDraft(
          displayName: 'Marie',
          routeType: MomoRecipientType.phoneNumber,
          recipientValue: '0781234567',
          countryCode: 'RW',
          consentVersion: 'biopay-v1',
        );

        await repository.enroll(
          draft: draft,
          embedding: List<double>.filled(128, 0.01),
        );

        final captured = verify(
          () => functionsClient.invoke(
            'biopay-enroll',
            headers: captureAny(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        final capturedHeaders = captured[0] as Map<dynamic, dynamic>;
        final capturedBody = captured[1] as Map<dynamic, dynamic>;

        expect(capturedHeaders, <String, String>{
          'X-Firebase-AppCheck': 'limited-use-token',
        });
        expect(capturedBody['route_type'], 'phone_number');
        expect(capturedBody['recipient_value'], '0781234567');
        expect(capturedBody['country_code'], 'RW');
      },
    );
  });
}
