import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import 'package:cool_app/core/config/env_config.dart';

void main() {
  group('EnvConfig.describeCriticalConfigurationError', () {
    test('accepts a valid Supabase URL and anon key', () {
      expect(
        EnvConfig.describeCriticalConfigurationError(
          supabaseUrl: 'https://project-ref.supabase.co',
          supabaseAnonKey: 'anon-key-value',
        ),
        isNull,
      );
    });

    test('rejects placeholder Supabase URLs', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        supabaseUrl: 'url',
        supabaseAnonKey: 'anon-key-value',
      );

      expect(error, isNotNull);
      expect(error, contains('SUPABASE_URL'));
      expect(error, contains('--dart-define-from-file=.env.json'));
    });

    test('rejects non-absolute Supabase URLs', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        supabaseUrl: '/functions/v1',
        supabaseAnonKey: 'anon-key-value',
      );

      expect(error, isNotNull);
      expect(error, contains('absolute URL'));
    });

    test('rejects missing anon keys', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        supabaseUrl: 'https://project-ref.supabase.co',
        supabaseAnonKey: '',
      );

      expect(error, isNotNull);
      expect(error, contains('SUPABASE_ANON_KEY'));
    });
  });

  group('EnvConfig.hasGoogleMapsApiKeyForPlatform', () {
    test('accepts a real Android Maps key', () {
      expect(
        EnvConfig.hasGoogleMapsApiKeyForPlatform(
          TargetPlatform.android,
          androidApiKey: 'AIzaSyRealMapsKey123',
        ),
        isTrue,
      );
    });

    test('rejects placeholder Android Maps keys', () {
      expect(
        EnvConfig.hasGoogleMapsApiKeyForPlatform(
          TargetPlatform.android,
          androidApiKey: 'your_google_maps_android_api_key',
        ),
        isFalse,
      );
    });

    test('reports embedded maps unavailable without a platform key', () {
      expect(
        EnvConfig.embeddedGoogleMapsUnavailableReason(TargetPlatform.android),
        isNotNull,
      );
    });
  });
}
