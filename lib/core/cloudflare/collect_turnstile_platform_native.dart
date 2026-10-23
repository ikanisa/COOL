import 'package:flutter/services.dart';

const _channel = MethodChannel('collect/turnstile');

Future<Object?> acquireChallenge(String attemptId, {Uri? endpoint}) =>
    _channel.invokeMethod<String>('acquire', {
      'attempt_id': attemptId,
      if (endpoint != null) 'backend_origin': endpoint.origin,
      if (endpoint != null) 'backend_path': endpoint.path,
    });

Future<void> cancelChallenge(String attemptId) async {
  await _channel
      .invokeMethod<void>('cancel', {'attempt_id': attemptId})
      .timeout(const Duration(seconds: 2));
}
