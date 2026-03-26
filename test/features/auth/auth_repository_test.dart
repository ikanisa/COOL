import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _normalizeSessionPayload(Map<String, dynamic> session) {
  final normalized = Map<String, dynamic>.from(session);
  final user = normalized['user'];
  if (user is Map) {
    final normalizedUser = Map<String, dynamic>.from(user);
    normalizedUser.remove('identities');
    normalized['user'] = normalizedUser;
  }
  return normalized;
}

void main() {
  test('removes malformed nested identity data before session parsing', () {
    final rawSession = <String, dynamic>{
      'access_token': 'header.payload.signature',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'token_type': 'bearer',
      'user': <String, dynamic>{
        'id': 'user-123',
        'app_metadata': <String, dynamic>{'provider': 'email'},
        'user_metadata': <String, dynamic>{'phone': '+250788123456'},
        'aud': 'authenticated',
        'email': 'otp-user@example.com',
        'phone': '+250788123456',
        'created_at': '2026-03-11T00:00:00.000Z',
        'identities': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'identity-1',
            'user_id': 'user-123',
            'identity_id': null,
            'provider': null,
          },
        ],
      },
    };

    expect(() => Session.fromJson(rawSession), throwsA(isA<TypeError>()));

    final session = Session.fromJson(_normalizeSessionPayload(rawSession));

    expect(session, isNotNull);
    expect(session!.user.id, 'user-123');
    expect(session.user.userMetadata?['phone'], '+250788123456');
    expect(session.user.identities, isNull);
  });
}
