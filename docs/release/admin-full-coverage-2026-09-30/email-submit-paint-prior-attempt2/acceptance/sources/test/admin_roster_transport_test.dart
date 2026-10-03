import 'dart:convert';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/admin_read_fixture.dart';

const _writes = {
  'admin_review_roster_import',
  'admin_commit_roster_import',
  'admin_stage_roster_import_intent',
  'admin_execute_roster_import_intent',
  'admin_save_roster_import_draft',
  'admin_transfer_interrupted_roster_import',
};

Map<String, Object?> _auth() => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': adminReadActor, 'session_id': '99890000-0000-4000-8000-000000000012', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': adminReadActor,
    'aud': 'authenticated',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': adminReadDate,
  },
};

void main() {
  for (final name in _writes) {
    for (final failure in ['network', '503']) {
      test(
        'actual SDK $name $failure sends one POST per explicit caller',
        () async {
          final posts = <http.Request>[];
          final client = SupabaseClient(
            'http://127.0.0.1:9989',
            'sb_publishable_synthetic_only',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((request) async {
              if (request.url.path.startsWith('/auth/v1/')) {
                return http.Response(
                  jsonEncode(_auth()),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              posts.add(request);
              if (failure == 'network') {
                throw http.ClientException('synthetic response loss');
              }
              return http.Response(
                jsonEncode({
                  'code': 'synthetic_unavailable',
                  'message': 'synthetic_unavailable',
                }),
                503,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          await client.auth.verifyOTP(
            phone: '+250788989001',
            token: 'B',
            type: OtpType.sms,
          );
          final gateway = SupabaseAdminRosterGateway(client);
          addTearDown(() async {
            gateway.dispose();
            await client.dispose();
          });
          const payload = {
            'p_request_id': '99890000-0000-4000-8000-000000000013',
          };
          Future<Object?> dispatch() => switch (name) {
            'admin_review_roster_import' => gateway.review(payload),
            'admin_commit_roster_import' => gateway.commit(payload),
            _ => gateway.recoveryRpc(name, payload),
          };
          await expectLater(
            dispatch(),
            throwsA(isA<AdminRosterRequestError>()),
          );
          expect(posts, hasLength(1));
          expect(posts.single.method, 'POST');
          expect(posts.single.url.path, '/rest/v1/rpc/$name');
          expect(posts.single.headers.containsKey('X-Retry-Count'), isFalse);
          expect(jsonDecode(posts.single.body), payload);
          // Only another explicit caller dispatches again, retaining its request.
          await expectLater(
            dispatch(),
            throwsA(isA<AdminRosterRequestError>()),
          );
          expect(posts, hasLength(2));
          expect(jsonDecode(posts.last.body), payload);
        },
      );
    }
  }
}
