import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Bound both the response size and the whole operation, including a slow
/// sequence of individually timely chunks. Abort only this request.
Future<http.Response> boundedAdminResponse(
  http.Client client,
  Uri uri, {
  required String method,
  required Map<String, String> headers,
  String? body,
  int maximumBytes = 2097152,
  Duration deadline = const Duration(seconds: 30),
}) {
  if (maximumBytes < 1 || deadline <= Duration.zero) {
    throw ArgumentError('Invalid response bounds.');
  }
  final result = Completer<http.Response>(), abort = Completer<void>();
  StreamSubscription<List<int>>? subscription;
  final bytes = BytesBuilder(copy: false);
  var size = 0;
  void fail(Object error) {
    if (result.isCompleted) return;
    if (!abort.isCompleted) abort.complete();
    unawaited(subscription?.cancel());
    result.completeError(error);
  }

  final timer = Timer(
    deadline,
    () => fail(TimeoutException('The account request timed out.')),
  );
  final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)
    ..followRedirects = false
    ..headers.addAll(headers);
  if (body != null) request.body = body;
  unawaited(() async {
    try {
      final response = await client.send(request);
      if (result.isCompleted) {
        await response.stream.listen((_) {}).cancel();
        return;
      }
      if (response.statusCode >= 300 && response.statusCode < 400 ||
          response.contentLength != null &&
              response.contentLength! > maximumBytes) {
        subscription = response.stream.listen((_) {}, onError: (Object _) {});
        fail(
          http.ClientException('The account response could not be admitted.'),
        );
        return;
      }
      subscription = response.stream.listen(
        (chunk) {
          if (result.isCompleted) return;
          size += chunk.length;
          if (size > maximumBytes) {
            fail(
              http.ClientException(
                'The account response exceeded its size limit.',
              ),
            );
          } else {
            bytes.add(chunk);
          }
        },
        onError: (Object _) => fail(
          http.ClientException('The account response could not be read.'),
        ),
        onDone: () {
          if (!result.isCompleted) {
            result.complete(
              http.Response.bytes(
                bytes.takeBytes(),
                response.statusCode,
                headers: response.headers,
                request: request,
                reasonPhrase: response.reasonPhrase,
              ),
            );
          }
        },
        cancelOnError: true,
      );
      if (result.isCompleted) unawaited(subscription?.cancel());
    } on Object {
      fail(http.ClientException('The account request could not be completed.'));
    }
  }());
  return result.future.whenComplete(timer.cancel);
}
