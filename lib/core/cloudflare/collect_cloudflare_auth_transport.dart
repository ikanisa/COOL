part of 'collect_cloudflare_client.dart';

final class _CollectOtpUnconfirmedReply extends CollectAuthException {
  _CollectOtpUnconfirmedReply(this.payload)
    : super(
        'Delivery could not be confirmed.',
        statusCode: '503',
        code: 'otp_delivery_unknown',
      );
  final Map<String, dynamic> payload;
}

final class _CollectAuthTransport {
  const _CollectAuthTransport(this.client);

  final CollectCloudflareClient client;

  Future<String?> captchaToken(String? provided) async {
    final provider = client.captchaProvider;
    try {
      // A shipping client always acquires a fresh challenge. A caller token
      // never replaces the configured browser challenge acquisition.
      final token = provider == null ? provided : await provider();
      if ((provider != null && token == null) ||
          (token != null && (token.isEmpty || token.length > 2048))) {
        throw const FormatException();
      }
      return token;
    } on CollectAuthException {
      rethrow;
    } catch (_) {
      throw const CollectAuthException(
        'Security verification could not finish.',
        code: 'captcha_unavailable',
      );
    }
  }

  Future<Map<String, dynamic>> request(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    try {
      final (status, data) = await client.request(
        'POST',
        'v1/auth/$path',
        body: body,
        bearer: bearer,
        responseLimit: 131072,
      );
      if (status < 200 || status >= 300) {
        final error = collectApiFailure(status, data);
        if ((path == 'otp' || path == 'upgrade/otp') &&
            status == 503 &&
            error.code == 'otp_delivery_unknown') {
          final id = data is Map<String, dynamic> ? data['challenge_id'] : null;
          final retry = data is Map<String, dynamic>
              ? data['retry_after']
              : null;
          if (data is Map<String, dynamic> &&
              id is String &&
              RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              ).hasMatch(id) &&
              data['request_id'] == id &&
              retry is int &&
              retry >= 60 &&
              retry <= 3600) {
            throw _CollectOtpUnconfirmedReply(data);
          }
          throw const CollectAuthException(
            'Verification is unavailable.',
            statusCode: '503',
            code: 'invalid_response',
          );
        }
        throw CollectAuthException(
          error.message,
          statusCode: '$status',
          code: error.code,
        );
      }
      if (data is! Map<String, dynamic>) {
        throw const CollectAuthException(
          'Verification is unavailable.',
          code: 'invalid_response',
        );
      }
      return data;
    } on CollectAuthException {
      rethrow;
    } catch (_) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'auth_transport_unavailable',
      );
    }
  }
}
