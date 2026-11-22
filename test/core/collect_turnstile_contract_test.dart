import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_types.dart';
import 'package:collect_app/core/cloudflare/collect_turnstile.dart';
import 'package:collect_app/core/cloudflare/collect_turnstile_contract.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _attempt = '12345678-1234-4234-8234-123456789012';
const _other = '12345678-1234-4234-8234-123456789013';
const _candidate = 'SYNTHETIC_CANDIDATE_PROVIDER_TOKEN';
Map<String, String> _envelope(String id) => {
  'type': collectChallengeEnvelope,
  'attempt_id': id,
  'token': _candidate,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'challenge routing is fixed and takes no caller-supplied API origin',
    () {
      final uri = collectChallengeUri(
        _attempt,
        'https://admin.collect.ikanisa.com',
      );
      expect(uri.origin, collectChallengeOrigin);
      expect(uri.path, '/v1/security/challenge');
      expect(uri.queryParameters, {
        'attempt_id': _attempt,
        'parent_origin': 'https://admin.collect.ikanisa.com',
        'theme': 'auto',
      });
    },
  );
  for (final parent in [
    'http://malicious.invalid',
    'https://user:pass@example.invalid',
    'https://example.invalid/path',
    'https://example.invalid?token=secret',
    'https://example.invalid#fragment',
    '//example.invalid',
  ]) {
    test('invalid parent origin is refused: $parent', () {
      expect(
        () => collectChallengeUri(_attempt, parent),
        throwsA(isA<CollectAuthException>()),
      );
    });
  }
  test(
    'matching envelope is only an untrusted candidate for server verification',
    () {
      expect(collectChallengeToken(_envelope(_attempt), _attempt), _candidate);
      expect(
        collectChallengeToken(jsonEncode(_envelope(_attempt)), _attempt),
        _candidate,
      );
    },
  );
  for (final invalid in [
    null,
    [],
    true,
    '{provider-secret',
    _envelope(_other),
    {..._envelope(_attempt), 'type': 'other'},
    {..._envelope(_attempt), 'token': ''},
    {..._envelope(_attempt), 'token': 'contains whitespace'},
    {..._envelope(_attempt), 'token': List.filled(2049, 'a').join()},
    {..._envelope(_attempt), 'error': 'expired'},
    {
      'type': collectChallengeEnvelope,
      'attempt_id': _attempt,
      'error': 'unavailable',
    },
  ]) {
    test('malformed, foreign or failed envelope never returns a token', () {
      expect(
        () => collectChallengeToken(invalid, _attempt),
        throwsA(
          isA<CollectAuthException>().having(
            (e) => e.toString(),
            'redacted failure',
            isNot(contains('provider-secret')),
          ),
        ),
      );
    });
  }
  const channel = MethodChannel('collect/turnstile');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'native acquisition asks for two fresh attempts with no credential or URL',
    () async {
      final attempts = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final arguments = call.arguments as Map;
        expect(arguments.keys, ['attempt_id']);
        if (call.method == 'cancel') return null;
        expect(call.method, 'acquire');
        final attempt = arguments['attempt_id'] as String;
        attempts.add(attempt);
        return jsonEncode(_envelope(attempt));
      });
      final challenge = CollectTurnstileChallenge();
      expect(await challenge.acquire(), _candidate);
      expect(await challenge.acquire(), _candidate);
      expect(attempts, hasLength(2));
      expect(attempts[0], isNot(attempts[1]));
    },
  );
  test('foreign native response cannot finish the live attempt', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'cancel' ? null : jsonEncode(_envelope(_other)),
    );
    await expectLater(
      CollectTurnstileChallenge().acquire(),
      throwsA(isA<CollectAuthException>()),
    );
  });
}
