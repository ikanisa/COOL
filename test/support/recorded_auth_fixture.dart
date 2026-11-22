import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _transports = Expando<({MockClient transport, String path})>();

/// Registers a synthetic HTTP fixture for non-auth repository/UI tests.
/// Actual OTP tests keep the real challenge and six-digit verification flow.
CollectCloudflareClient recordedFixtureClient(
  String apiUrl, {
  required http.Client httpClient,
  CollectAuthSessionStorage? sessionStorage,
  Future<String> Function()? captchaProvider,
  void Function()? cancelCaptcha,
  String surface = 'member',
  Duration timeout = const Duration(seconds: 20),
  String recordedAuthPath = '/v1/auth/verify',
}) {
  if (httpClient is! MockClient) {
    throw ArgumentError(
      'Recorded auth fixtures require an in-memory MockClient.',
    );
  }
  final client = CollectCloudflareClient(
    apiUrl,
    httpClient: httpClient,
    sessionStorage: sessionStorage,
    captchaProvider: captchaProvider,
    cancelCaptcha: cancelCaptcha,
    surface: surface,
    timeout: timeout,
  );
  _transports[client] = (transport: httpClient, path: recordedAuthPath);
  return client;
}

/// Reads only the registered in-memory fixture, then installs its exact session
/// using the current client's subject/role/expiry checks. This never invokes a
/// provider, supplies a fake production OTP, or authenticates against a server.
Future<CollectAuthResponse> installRecordedAuthFixture(
  CollectCloudflareClient client, {
  required String token,
  String? phone,
  String? email,
  CollectOtpType? type,
}) async {
  final fixture = _transports[client];
  if (fixture == null) throw StateError('No recorded auth fixture registered.');
  final response = await fixture.transport.post(
    Uri.parse('https://recorded-fixture.example.invalid${fixture.path}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'token': token, 'phone': ?phone, 'email': ?email}),
  );
  if (response.statusCode != 200) {
    throw StateError('The recorded auth fixture did not return a session.');
  }
  return client.auth.recoverSession(response.body);
}
