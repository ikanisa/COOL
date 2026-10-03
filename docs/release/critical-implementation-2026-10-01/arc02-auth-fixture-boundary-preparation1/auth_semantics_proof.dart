import 'dart:convert';

import 'package:gotrue/gotrue.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'proposal/test/support/synthetic_jwt.dart' as project;
import 'snapshots/third_party/gotrue/test/synthetic_jwt.dart' as upstream;

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String fixture(Map<String, dynamic> header, Map<String, dynamic> claims) {
  final token = project.syntheticJwt(header, claims);
  require(token == upstream.syntheticJwt(header, claims), 'Fixture drift');
  return token;
}

Future<void> main() async {
  final expired = decodeJwt(fixture(
    {'alg': 'HS256', 'typ': 'JWT'},
    {'sub': '1234567890', 'exp': 1516239022},
  ));
  require(expired.header.alg == 'HS256', 'Expired header drift');
  require(expired.payload.sub == '1234567890', 'Expired subject drift');
  require(expired.payload.exp == 1516239022, 'Expired time drift');
  var expiryRejected = false;
  try {
    validateExp(expired.payload.exp);
  } on AuthException {
    expiryRejected = true;
  }
  require(expiryRejected, 'Expired fixture was not rejected');

  final parser = decodeJwt(fixture(
    {'alg': 'HS256', 'typ': 'JWT', 'kid': 'test-kid'},
    {
      'sub': '1234567890',
      'name': 'John Doe',
      'iat': 1516239022,
      'exp': 9999999999,
    },
  ));
  require(parser.header.kid == 'test-kid', 'Parser key drift');
  require(parser.payload.claims['name'] == 'John Doe', 'Parser claim drift');
  require(parser.payload.iat == 1516239022, 'Parser issued time drift');
  require(parser.payload.exp == 9999999999, 'Parser expiry drift');
  validateExp(parser.payload.exp);

  var jwksRequests = 0;
  final client = GoTrueClient(
    url: 'https://claims-fixture.example.invalid/auth/v1',
    httpClient: MockClient((request) async {
      require(request.url.path == '/auth/v1/.well-known/jwks.json',
          'Unexpected JWKS path');
      jwksRequests += 1;
      return http.Response(jsonEncode({'keys': []}), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  try {
    final token = fixture(
      {'alg': 'RS256', 'typ': 'JWT', 'kid': 'test-key-id'},
      {
        'sub': '1234567890',
        'aud': 'authenticated',
        'exp': 9999999999,
        'iat': 1516239022,
        'email': 'parser@example.invalid',
        'role': 'authenticated',
      },
    );
    var signatureRejected = false;
    try {
      await client.getClaims(token);
    } on AuthException {
      signatureRejected = true;
    }
    require(signatureRejected, 'Dummy signature authenticated');
    require(jwksRequests == 1, 'Unexpected JWKS request count');
    require(client.currentSession == null, 'Fixture created an Auth session');
  } finally {
    client.dispose();
  }
  // stdout is confined to the private proof controller's captured output.
  print(jsonEncode({
    'status': 'pass',
    'checks': 3,
    'upstream_and_project_tokens_identical': true,
    'expired_fixture_rejected': true,
    'parser_claims_preserved': true,
    'asymmetric_dummy_signature_rejected': true,
    'jwks_requests': jwksRequests,
    'authenticated_session_created': false,
  }));
}
