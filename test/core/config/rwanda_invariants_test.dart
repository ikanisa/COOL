import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guards to prevent non-Rwanda scope from drifting back into lib/.
///
/// These tests scan Dart source files for banned strings that would indicate
/// off-market or non-RW positioning has been re-introduced.
///
/// Allowlisted paths are explicitly excluded (e.g. country catalog internals,
/// fan club region names, test fixtures).
void main() {
  /// Patterns that must NOT appear in consumer-facing Dart source files.
  /// Each entry is (pattern, reason).
  const bannedPatterns = <(String, String)>[
    ('malta', 'Malta market references are banned (Rwanda-only)'),
    ('SWIFT', 'SWIFT banking references are banned (local MoMo/bank only)'),
    ('USD', 'USD currency references are banned (RWF-only)'),
    ('EUR', 'EUR currency references are banned (RWF-only)'),
  ];

  /// Files or path fragments that are allowed to mention banned strings.
  const allowlistedPaths = <String>[
    // Country catalog definition may reference ISO data
    'core/config/country_catalog.dart',
    // Test files may contain negative-case fixtures
    'test/',
    // Generated localizations
    'l10n/app_localizations',
    // This test itself
    'rwanda_invariants_test.dart',
  ];

  /// Patterns that require case-sensitive matching (avoid false positives).
  const caseSensitivePatterns = {'USD', 'EUR', 'SWIFT'};

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    fail('lib/ directory not found — run from project root');
  }

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  for (final (pattern, reason) in bannedPatterns) {
    test('No "$pattern" in consumer source files ($reason)', () {
      final violations = <String>[];

      for (final file in dartFiles) {
        final relativePath = file.path;

        // Skip allowlisted paths
        if (allowlistedPaths.any((allowed) => relativePath.contains(allowed))) {
          continue;
        }

        final content = file.readAsStringSync();
        final isCaseSensitive = caseSensitivePatterns.contains(pattern);

        final lines = content.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];

          // Skip import/comment lines to reduce noise
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('import ') || trimmed.startsWith('//')) {
            continue;
          }

          final hasMatch = isCaseSensitive
              ? line.contains(pattern)
              : line.toLowerCase().contains(pattern.toLowerCase());

          if (hasMatch) {
            violations.add('  ${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} banned "$pattern" reference(s) in lib/:\n'
          '${violations.join('\n')}\n\n'
          'Reason: $reason\n'
          'Fix: Remove or rewrite the text to be Rwanda-local only.\n'
          'If this is a legitimate exception, add the file to '
          'allowlistedPaths in this test.',
        );
      }
    });
  }

  test('SupportedCountriesRepository has no Supabase dependency', () {
    final file = File(
      'lib/core/repositories/supported_countries_repository.dart',
    );
    if (!file.existsSync()) {
      fail('supported_countries_repository.dart not found');
    }
    final content = file.readAsStringSync();
    expect(
      content.contains('SupabaseClient'),
      isFalse,
      reason:
          'SupportedCountriesRepository must be synchronous with no Supabase '
          'dependency (Rwanda-only hardcoded)',
    );
  });

  test('AdminRepository does not write supported_countries rows', () {
    final file = File('lib/features/admin/repositories/admin_repository.dart');
    if (!file.existsSync()) {
      fail('admin_repository.dart not found');
    }
    final content = file.readAsStringSync();
    expect(
      content.contains("from('supported_countries').update"),
      isFalse,
      reason:
          'supported_countries is now a read-only Rwanda validation reference',
    );
    expect(
      content.contains('Future<void> updateCountry('),
      isFalse,
      reason: 'admin code must not expose supported_countries writes anymore',
    );
  });

  test('AppMarket constants are Rwanda-only', () {
    final file = File('lib/core/config/app_market.dart');
    if (!file.existsSync()) {
      fail('app_market.dart not found');
    }
    final content = file.readAsStringSync();
    expect(content, contains("'RW'"), reason: 'AppMarket must reference RW');
    expect(content, contains("'en'"), reason: 'AppMarket must reference en');
  });

  test('consumer source does not contain Multilingual', () {
    final violations = dartFiles
        .where(
          (file) =>
              !allowlistedPaths.any((allowed) => file.path.contains(allowed)),
        )
        .where((file) => file.readAsStringSync().contains('Multilingual'))
        .map((file) => file.path)
        .toList(growable: false);

    expect(
      violations,
      isEmpty,
      reason:
          'Consumer-facing source must remain English-only. '
          'Found unexpected Multilingual references in: ${violations.join(', ')}',
    );
  });

  test('verify-otp stamps auth metadata to Rwanda English defaults', () {
    // The market defaults are stamped by the auth-user provisioning helper,
    // not by the HTTP handler entrypoint itself.
    final file = File('supabase/functions/verify-otp/verify_otp_helpers.ts');
    if (!file.existsSync()) {
      fail('verify-otp/verify_otp_helpers.ts not found');
    }
    final content = file.readAsStringSync();
    expect(
      content,
      contains('country: "RW"'),
      reason: 'OTP verification must force Rwanda market metadata',
    );
    expect(
      content,
      contains('language_code: "en"'),
      reason: 'OTP verification must force English UI metadata',
    );
    expect(
      content,
      contains('market: "RW"'),
      reason: 'OTP verification must stamp market=RW',
    );
    expect(
      content,
      contains('ui_language: "en"'),
      reason: 'OTP verification must stamp ui_language=en',
    );
  });

  test('Rwanda-only runtime scope migration locks core tables', () {
    final file = File(
      'supabase/migrations/20260313223000_rwanda_only_runtime_scope_contract.sql',
    );
    if (!file.existsSync()) {
      fail('20260313223000_rwanda_only_runtime_scope_contract.sql not found');
    }
    final content = file.readAsStringSync();
    const expectedSnippets = <String>[
      "check (country = 'RW')",
      "check (language_code = 'en')",
      "new.country := 'RW';",
      "alter column language_code set default 'en';",
      'partner_payment_routes_country_rwanda_only_check',
      'groups_country_rwanda_only_check',
      'users_language_code_english_only_check',
      'get_partner_payment_route(',
    ];

    for (final snippet in expectedSnippets) {
      expect(
        content,
        contains(snippet),
        reason:
            'Runtime scope migration must preserve the Rwanda-only contract: '
            '$snippet',
      );
    }
  });

  test('supported_countries write access is removed by migration', () {
    final file = File(
      'supabase/migrations/20260313233000_supported_countries_readonly.sql',
    );
    if (!file.existsSync()) {
      fail('20260313233000_supported_countries_readonly.sql not found');
    }
    final content = file.readAsStringSync();
    const expectedSnippets = <String>[
      'drop policy if exists "supported_countries_insert_admin"',
      'drop policy if exists "supported_countries_update_admin"',
      'drop policy if exists "supported_countries_delete_admin"',
      'comment on table public.supported_countries is',
      'read-only Rwanda validation reference',
    ];

    for (final snippet in expectedSnippets) {
      expect(
        content,
        contains(snippet),
        reason:
            'supported_countries must remain read-only after the Rwanda lock: '
            '$snippet',
      );
    }
  });
}
