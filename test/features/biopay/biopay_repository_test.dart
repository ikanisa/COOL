import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/services/operational_health_service.dart';
import 'package:cool_app/features/biopay/models/biopay_enrollment_draft.dart';
import 'package:cool_app/features/biopay/repositories/biopay_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class RecordingOperationalHealthService implements OperationalHealthService {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  @override
  Future<void> recordEvent({
    required String service,
    required String component,
    required String message,
    OperationalHealthStatus status = OperationalHealthStatus.ok,
    OperationalHealthSeverity? severity,
    String? issueCode,
    String? functionName,
    String? userId,
    String? subjectType,
    String? subjectId,
    Map<String, dynamic> metadata = const <String, dynamic>{},
    DateTime? occurredAt,
  }) async {
    events.add(<String, Object?>{
      'service': service,
      'component': component,
      'message': message,
      'status': status.name,
      'severity': severity?.name,
      'issueCode': issueCode,
      'functionName': functionName,
      'userId': userId,
      'subjectType': subjectType,
      'subjectId': subjectId,
      'metadata': metadata,
      'occurredAt': occurredAt,
    });
  }
}

void main() {
  group('BiopayRepository', () {
    late MockSupabaseClient client;
    late MockFunctionsClient functionsClient;
    late RecordingOperationalHealthService operationalHealthService;
    late BiopayRepository repository;

    setUp(() {
      client = MockSupabaseClient();
      functionsClient = MockFunctionsClient();
      operationalHealthService = RecordingOperationalHealthService();
      repository = BiopayRepository(
        client: client,
        operationalHealthService: operationalHealthService,
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

    test(
      'attaches an App Check header and explicit payload to payment intent requests',
      () async {
        when(
          () => functionsClient.invoke(
            'biopay-create-payment-intent',
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'intent_id': 'intent-1',
                'nonce': 'nonce-1',
                'ussd_code': '*182*1*1*0781234567#',
                'expires_at': '2026-04-10T12:05:00.000Z',
                'display_name': 'Marie',
              },
            },
            status: 200,
          ),
        );

        final intent = await repository.createPaymentIntent(
          profilePublicId: 'public-1',
          matchScore: 0.91,
        );

        final captured = verify(
          () => functionsClient.invoke(
            'biopay-create-payment-intent',
            headers: captureAny(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        final capturedHeaders = captured[0] as Map<dynamic, dynamic>;
        final capturedBody = captured[1] as Map<dynamic, dynamic>;

        expect(capturedHeaders, <String, String>{
          'X-Firebase-AppCheck': 'limited-use-token',
        });
        expect(capturedBody['profile_public_id'], 'public-1');
        expect(capturedBody['match_score'], 0.91);
        expect(intent.intentId, 'intent-1');
        expect(intent.displayName, 'Marie');
      },
    );

    test(
      'records operational telemetry when payment intent creation fails',
      () async {
        when(
          () => functionsClient.invoke(
            'biopay-create-payment-intent',
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenThrow(Exception('create intent failed'));

        await expectLater(
          repository.createPaymentIntent(
            profilePublicId: 'public-1',
            matchScore: 0.91,
          ),
          throwsException,
        );

        expect(operationalHealthService.events, hasLength(1));
        expect(operationalHealthService.events.single['service'], 'biopay');
        expect(
          operationalHealthService.events.single['component'],
          'payment_intent',
        );
        expect(
          operationalHealthService.events.single['issueCode'],
          'biopay_create_intent_failed',
        );
        final metadata =
            operationalHealthService.events.single['metadata']
                as Map<String, dynamic>;
        expect(metadata['error'], contains('create intent failed'));
      },
    );
  });
}
