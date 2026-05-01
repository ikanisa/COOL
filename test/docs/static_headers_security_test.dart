import 'package:flutter_test/flutter_test.dart';

import '../helpers/repo_paths.dart';

void main() {
  group('static hosting security headers', () {
    test(
      'admin Cloudflare Pages headers include CSP for Supabase admin app',
      () {
        final headers = repoFile(
          'apps/admin/public/_headers',
        ).readAsStringSync();

        expect(headers, contains('Content-Security-Policy:'));
        expect(headers, contains("default-src 'self'"));
        expect(headers, contains("frame-ancestors 'none'"));
        expect(headers, contains("object-src 'none'"));
        expect(headers, contains('https://*.supabase.co'));
        expect(headers, contains('wss://*.supabase.co'));
      },
    );

    test('public website headers include a restrictive CSP', () {
      final headers = repoFile(
        'apps/website/public/_headers',
      ).readAsStringSync();

      expect(headers, contains('Content-Security-Policy:'));
      expect(headers, contains("default-src 'self'"));
      expect(headers, contains("frame-ancestors 'none'"));
      expect(headers, contains("connect-src 'self'"));
      expect(headers, isNot(contains('https://*.supabase.co')));
    });
  });
}
