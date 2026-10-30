import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_response.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_canonical_reconciliation_support.dart';

class _Client extends http.BaseClient {
  _Client(this.reply);
  final Future<http.StreamedResponse> Function(http.BaseRequest) reply;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      reply(request);
}

void main() {
  test('redirects are denied without following a new destination', () async {
    final client = _Client((request) async {
      expect(request.followRedirects, isFalse);
      return http.StreamedResponse(
        Stream.value(utf8.encode('untrusted body')),
        302,
        headers: {'location': 'https://untrusted.example/'},
      );
    });
    await expectLater(
      boundedAdminResponse(
        client,
        Uri.parse('https://admin.example.test/api/admin/core/users'),
        method: 'GET',
        headers: {},
      ),
      throwsA(isA<http.ClientException>()),
    );
  });
  test(
    'oversized chunked responses cancel their stream before retaining excess bytes',
    () async {
      final listening = Completer<void>();
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onListen: () => listening.complete(),
        onCancel: () => cancelled = true,
      );
      final client = _Client(
        (_) async => http.StreamedResponse(stream.stream, 200),
      );
      final pending = boundedAdminResponse(
        client,
        Uri.parse('https://admin.example.test/api/admin/core/users'),
        method: 'GET',
        headers: {},
        maximumBytes: 5,
      );
      final checked = expectLater(
        pending,
        throwsA(isA<http.ClientException>()),
      );
      await listening.future;
      stream.add([1, 2, 3]);
      stream.add([4, 5, 6]);
      await checked;
      expect(cancelled, isTrue);
      await stream.close();
    },
  );
  test('the whole response deadline cancels an open response body', () async {
    final listening = Completer<void>();
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onListen: () => listening.complete(),
      onCancel: () => cancelled = true,
    );
    final client = _Client(
      (_) async => http.StreamedResponse(stream.stream, 200),
    );
    final pending = boundedAdminResponse(
      client,
      Uri.parse('https://admin.example.test/api/admin/core/users'),
      method: 'GET',
      headers: {},
      deadline: const Duration(milliseconds: 30),
    );
    final checked = expectLater(pending, throwsA(isA<TimeoutException>()));
    await listening.future;
    stream.add([1]);
    await checked;
    expect(cancelled, isTrue);
    await stream.close();
  });
  test(
    'late response headers are cancelled after the request deadline',
    () async {
      final held = Completer<http.StreamedResponse>(),
          cancelled = Completer<void>();
      final client = _Client((_) => held.future);
      await expectLater(
        boundedAdminResponse(
          client,
          Uri.parse('https://admin.example.test/api/admin/core/users'),
          method: 'GET',
          headers: {},
          deadline: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final stream = StreamController<List<int>>(
        onCancel: () => cancelled.complete(),
      );
      held.complete(http.StreamedResponse(stream.stream, 200));
      await cancelled.future;
      await stream.close();
    },
  );
  test(
    'retained plaintext is admitted only with its exact byte count, digest and content type',
    () async {
      const evidence = 'Controlled retained evidence π';
      final bytes = utf8.encode(evidence),
          digest = sha256.convert(bytes).toString();
      final h = await FinancialHarness.create(
        reply: (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {
            'content-type': 'text/plain',
            'x-collect-evidence-sensitivity': 'ordinary',
          },
        ),
      );
      const id = '11111111-1111-4111-8111-111111111111';
      expect(
        await h.session.retainedEvidence(
          id,
          sha256Hex: digest,
          sizeBytes: bytes.length,
          sourceSensitivity: 'ordinary',
        ),
        evidence,
      );
      await expectLater(
        h.session.retainedEvidence(
          id,
          sha256Hex: 'a' * 64,
          sizeBytes: bytes.length,
          sourceSensitivity: 'ordinary',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        h.session.retainedEvidence(
          id,
          sha256Hex: digest,
          sizeBytes: bytes.length - 1,
          sourceSensitivity: 'ordinary',
        ),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );
  test(
    'an account change while evidence waits releases no old plaintext',
    () async {
      const evidence = 'Controlled private retained evidence';
      final bytes = utf8.encode(evidence), held = Completer<http.Response>();
      final h = await FinancialHarness.create(reply: (_) => held.future);
      final pending = h.session.retainedEvidence(
        '11111111-1111-4111-8111-111111111111',
        sha256Hex: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
        sourceSensitivity: 'ordinary',
      );
      final checked = expectLater(
        pending,
        throwsA(isA<AdminAccountException>()),
      );
      h.auth = {
        ...h.auth,
        'user': {
          ...h.auth['user'] as Map,
          'sessionId': 'replacement-cookie-session',
        },
      };
      await h.session.refresh();
      held.complete(
        http.Response.bytes(
          bytes,
          200,
          headers: {
            'content-type': 'text/plain',
            'x-collect-evidence-sensitivity': 'ordinary',
          },
        ),
      );
      await checked;
    },
  );
}
