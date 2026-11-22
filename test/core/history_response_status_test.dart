import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
}

class _PendingBody {
  _PendingBody() {
    controller = StreamController<List<int>>(
      sync: true,
      onListen: () => listening.complete(),
    );
  }

  late final StreamController<List<int>> controller;
  final listening = Completer<void>();

  http.StreamedResponse attach(http.BaseRequest request, int status) {
    (request as http.Abortable).abortTrigger!.then((_) {
      if (!controller.isClosed) {
        controller.addError(http.RequestAbortedException(request.url));
        unawaited(controller.close());
      }
    });
    return http.StreamedResponse(controller.stream, status);
  }
}

void main() {
  for (final status in [401, 403]) {
    test('malformed history denial preserves status $status', () async {
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((_) async => http.Response('{', status)),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.rpc<dynamic>('list_current_member_history_page'),
        throwsA(
          isA<CollectApiException>()
              .having((error) => error.httpStatusCode, 'status', status)
              .having((error) => error.code, 'code', '$status'),
        ),
      );
    });

    test(
      'stream failure after history denial preserves status $status',
      () async {
        final client = CollectCloudflareClient(
          'https://api.example.com',
          httpClient: _StreamingClient(
            (_) async => http.StreamedResponse(
              Stream<List<int>>.error(StateError('synthetic body failure')),
              status,
            ),
          ),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.rpc<dynamic>('list_current_member_history_page'),
          throwsA(
            isA<CollectApiException>().having(
              (error) => error.httpStatusCode,
              'status',
              status,
            ),
          ),
        );
      },
    );

    test('untriggered stream abort preserves denial $status', () async {
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: _StreamingClient(
          (request) async => http.StreamedResponse(
            Stream<List<int>>.error(http.RequestAbortedException(request.url)),
            status,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.rpc<dynamic>('list_current_member_history_page'),
        throwsA(
          isA<CollectApiException>().having(
            (error) => error.httpStatusCode,
            'status',
            status,
          ),
        ),
      );
    });

    test('local cancellation is not a history denial $status', () async {
      final body = _PendingBody();
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: _StreamingClient(
          (request) async => body.attach(request, status),
        ),
      );
      addTearDown(client.dispose);
      final expected = expectLater(
        client.rpc<dynamic>('list_current_member_history_page'),
        throwsA(isA<http.RequestAbortedException>()),
      );
      await body.listening.future.timeout(const Duration(seconds: 3));
      client.cancelPendingRequests();
      await expected;
    });

    test(
      'history deadline after denial headers preserves status $status',
      () async {
        final body = _PendingBody();
        final client = CollectCloudflareClient(
          'https://api.example.com',
          timeout: const Duration(milliseconds: 40),
          httpClient: _StreamingClient(
            (request) async => body.attach(request, status),
          ),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.rpc<dynamic>('list_current_member_history_page'),
          throwsA(
            isA<CollectApiException>().having(
              (error) => error.httpStatusCode,
              'status',
              status,
            ),
          ),
        );
      },
    );

    test('structured history denial keeps its reason $status', () async {
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'history_scope_unavailable'}),
            status,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.rpc<dynamic>('list_current_member_history_page'),
        throwsA(
          isA<CollectApiException>()
              .having((error) => error.httpStatusCode, 'status', status)
              .having(
                (error) => error.code,
                'code',
                'history_scope_unavailable',
              ),
        ),
      );
    });

    test('malformed write denial keeps its prior outcome $status', () async {
      final client = CollectCloudflareClient(
        'https://api.example.com',
        httpClient: MockClient((_) async => http.Response('{', status)),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.rpc<dynamic>('approve_payment_reconciliation_v2'),
        throwsA(
          isA<CollectApiException>()
              .having((error) => error.httpStatusCode, 'status', isNull)
              .having((error) => error.code, 'code', 'invalid_response'),
        ),
      );
    });
  }
}
