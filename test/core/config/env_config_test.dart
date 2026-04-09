import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/config/env_config.dart';

void main() {
  group('EnvConfig.describeCriticalConfigurationError', () {
    test('accepts a valid Supabase URL and anon key', () {
      expect(
        EnvConfig.describeCriticalConfigurationError(
          flavor: 'production',
          supabaseUrl: 'https://project-ref.supabase.co',
          supabaseAnonKey: 'anon-key-value',
          supabaseProjectRef: 'project-ref',
          backendEnvironment: 'production',
        ),
        isNull,
      );
    });

    test('rejects placeholder Supabase URLs', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        flavor: 'production',
        supabaseUrl: 'url',
        supabaseAnonKey: 'anon-key-value',
        backendEnvironment: 'production',
      );

      expect(error, isNotNull);
      expect(error, contains('SUPABASE_URL'));
      expect(error, contains('--dart-define-from-file=.env.json'));
    });

    test('rejects non-absolute Supabase URLs', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        flavor: 'production',
        supabaseUrl: '/functions/v1',
        supabaseAnonKey: 'anon-key-value',
        backendEnvironment: 'production',
      );

      expect(error, isNotNull);
      expect(error, contains('absolute URL'));
    });

    test('rejects missing anon keys', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        flavor: 'production',
        supabaseUrl: 'https://project-ref.supabase.co',
        supabaseAnonKey: '',
        backendEnvironment: 'production',
      );

      expect(error, isNotNull);
      expect(error, contains('SUPABASE_ANON_KEY'));
    });

    test('rejects mismatched project refs', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        flavor: 'production',
        supabaseUrl: 'https://project-ref.supabase.co',
        supabaseAnonKey: 'anon-key-value',
        supabaseProjectRef: 'other-project',
        backendEnvironment: 'production',
      );

      expect(error, isNotNull);
      expect(error, contains('SUPABASE_PROJECT_REF'));
    });

    test('rejects flavor and backend environment mismatches', () {
      final error = EnvConfig.describeCriticalConfigurationError(
        flavor: 'staging',
        supabaseUrl: 'https://project-ref.supabase.co',
        supabaseAnonKey: 'anon-key-value',
        supabaseProjectRef: 'project-ref',
        backendEnvironment: 'production',
      );

      expect(error, isNotNull);
      expect(error, contains('BACKEND_ENVIRONMENT'));
    });
  });
}
