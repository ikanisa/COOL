import 'support/recorded_auth_fixture.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

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
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': adminReadActor, 'session_id': '99890000-0000-4000-8000-000000000012', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
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
  test(
    'animated image rejection survives the actual function transport',
    () async {
      final posts = <http.Request>[];
      final client = recordedFixtureClient(
        'http://127.0.0.1:9989',
        recordedAuthPath: '/auth/v1/verify',
        httpClient: MockClient((request) async {
          if (request.url.path.startsWith('/auth/v1/')) {
            return http.Response(
              jsonEncode(_auth()),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          posts.add(request);
          return http.Response(
            jsonEncode({
              'code': 'roster_animated_image_unsupported',
              'message':
                  'Animated images are not supported. Please upload a static image.',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await installRecordedAuthFixture(
        client,
        phone: '+250788989001',
        token: 'B',
        type: CollectOtpType.sms,
      );
      final gateway = CollectAdminRosterGateway(client);
      final draft = AdminRosterDraft(gateway);
      addTearDown(() async {
        draft.dispose();
        gateway.dispose();
        await client.dispose();
      });
      Future<AdminRosterUpload> image() async => AdminRosterUpload.fromBytes(
        'roster.png',
        'png',
        Uint8List.fromList([1, 2, 3]),
        aiConsent: true,
      );
      await draft.prepare(image);
      expect(draft.errorCode, 'roster_animated_image_unsupported');
      expect(
        draft.error,
        contains('Animated or multi-frame images are not supported'),
      );
      expect(draft.error, contains('Discard this draft'));
      expect(draft.terminalUploadFailure, isTrue);
      await draft.prepare(image);
      expect(posts, hasLength(1));
    },
  );

  for (final name in _writes) {
    for (final failure in ['network', '503']) {
      test(
        'actual SDK $name $failure sends one POST per explicit caller',
        () async {
          final posts = <http.Request>[];
          final client = recordedFixtureClient(
            'http://127.0.0.1:9989',
            recordedAuthPath: '/auth/v1/verify',
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
          await installRecordedAuthFixture(
            client,
            phone: '+250788989001',
            token: 'B',
            type: CollectOtpType.sms,
          );
          final gateway = CollectAdminRosterGateway(client);
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
          expect(posts.single.url.path, '/v1/rpc/$name');
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
