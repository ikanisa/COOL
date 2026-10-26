import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

Map<String, dynamic> evidenceFixture(String name) => Map<String, dynamic>.from(
  (jsonDecode(File('test/admin/admin-dto-examples.json').readAsStringSync())
          as Map<String, dynamic>)[name]
      as Map,
);

Map<String, dynamic> evidenceTestSession({List<String>? permissions}) => {
  'user': {
    'id': '11111111-1111-4111-8111-111111111111',
    'email': 'operator@example.test',
    'role': 'admin',
    'sessionId': 'evidence-view-session',
    'permissions':
        permissions ??
        [
          'overview.read',
          'account.manage',
          'ledger.manage',
          ...CloudflareCoreArea.values.map((area) => area.permission).toSet(),
        ],
  },
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
};

http.Response evidenceResponse(Map<String, dynamic> data, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Future<CloudflareAdminRepository> evidenceRepository(
  Future<http.Response> Function(http.Request) respond, {
  List<String>? permissions,
}) async {
  final session = CloudflareAdminSession(
    MockClient(
      (request) async => request.url.path.endsWith('/auth/session')
          ? evidenceResponse(evidenceTestSession(permissions: permissions))
          : respond(request),
    ),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  addTearDown(session.dispose);
  await session.refresh();
  return CloudflareAdminRepository(session);
}
