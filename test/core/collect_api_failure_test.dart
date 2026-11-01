import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'only a 501 or legacy statusless unavailable response allows fallback',
    () {
      for (final status in [403, 404, 429, 500, 503]) {
        final error = collectApiFailure(status, {
          'code': 'operation_unavailable',
          'message': 'synthetic private data',
        });
        expect(error.httpStatusCode, status);
        expect(error.isLegacyOperationUnavailable, isFalse);
        expect(error.message, 'Collect could not complete this request.');
      }
      final unsupported = collectApiFailure(501, {
        'code': 'operation_unavailable',
      });
      expect(unsupported.httpStatusCode, 501);
      expect(unsupported.isLegacyOperationUnavailable, isTrue);
      expect(
        const CollectApiException(
          code: 'operation_unavailable',
        ).isLegacyOperationUnavailable,
        isTrue,
      );
      expect(
        const CollectApiException(
          code: 'permission_denied',
          httpStatusCode: 501,
        ).isLegacyOperationUnavailable,
        isFalse,
      );
    },
  );
}
