import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/features/biopay/models/biopay_enrollment_draft.dart';
import 'package:cool_app/features/biopay/models/biopay_match_result.dart';
import 'package:cool_app/features/biopay/models/biopay_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiopayEnrollmentDraft', () {
    test(
      'builds a minimal enrollment payload for server-side route derivation',
      () {
        const draft = BiopayEnrollmentDraft(
          displayName: 'Uwimana Marie',
          routeType: MomoRecipientType.phoneNumber,
          recipientValue: '0781234567',
          countryCode: 'RW',
          consentVersion: 'biopay-v1',
        );

        final payload = draft.toPayload(const <double>[0.1, 0.2, 0.3]);

        expect(payload['display_name'], 'Uwimana Marie');
        expect(payload['consent_version'], 'biopay-v1');
        expect(payload['embedding'], const <double>[0.1, 0.2, 0.3]);
        expect(payload.containsKey('route_type'), isFalse);
        expect(payload.containsKey('recipient_value'), isFalse);
        expect(payload.containsKey('country_code'), isFalse);
      },
    );

    test('adds liveness metadata when the scanner has passed a challenge', () {
      const draft = BiopayEnrollmentDraft(
        displayName: 'Uwimana Marie',
        routeType: MomoRecipientType.phoneNumber,
        recipientValue: '0781234567',
        countryCode: 'RW',
        consentVersion: 'biopay-v1',
      );

      final payload = draft.toPayload(
        const <double>[0.1, 0.2, 0.3],
        liveness: const <String, Object?>{
          'version': 'challenge_pad_v1',
          'result': 'passed',
        },
      );

      expect(payload['liveness'], const <String, Object?>{
        'version': 'challenge_pad_v1',
        'result': 'passed',
      });
    });
  });

  group('BiopayProfile', () {
    test('parses route type and masks recipient value', () {
      final profile = BiopayProfile.fromJson(const <String, dynamic>{
        'id': 'profile-1',
        'public_id': '654321',
        'user_id': 'user-1',
        'display_name': 'Uwimana Marie',
        'route_type': 'phone_number',
        'recipient_value': '0781234567',
        'country_code': 'RW',
        'active': true,
        'consent_version': 'biopay-v1',
      });

      expect(profile.routeType, MomoRecipientType.phoneNumber);
      expect(profile.maskedRecipientValue, '078•••567');
    });
  });

  group('BiopayMatchResult', () {
    test('parses successful API responses into a profile', () {
      final result = BiopayMatchResult.fromApiResponse(const <String, dynamic>{
        'match': true,
        'score': 0.87,
        'profile_id': 'profile-1',
        'public_id': '654321',
        'user_id': 'user-1',
        'display_name': 'Uwimana Marie',
        'route_type': 'code',
        'recipient_value': '123456',
        'country_code': 'RW',
      });

      expect(result.match, isTrue);
      expect(result.score, 0.87);
      expect(result.profile?.routeType, MomoRecipientType.code);
      expect(result.profile?.recipientValue, '123456');
    });

    test('parses cached payloads with nested profile data', () {
      final result = BiopayMatchResult.fromCacheJson(const <String, dynamic>{
        'match': true,
        'score': 0.91,
        'cached': true,
        'profile': <String, dynamic>{
          'id': 'profile-1',
          'public_id': '654321',
          'user_id': 'user-1',
          'display_name': 'Uwimana Marie',
          'route_type': 'phone_number',
          'recipient_value': '0781234567',
          'country_code': 'RW',
          'active': true,
          'consent_version': 'biopay-v1',
        },
      });

      expect(result.cached, isTrue);
      expect(result.profile?.displayName, 'Uwimana Marie');
      expect(result.profile?.routeType, MomoRecipientType.phoneNumber);
      expect(result.profile?.recipientValue, '0781234567');
    });
  });
}
