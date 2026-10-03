import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new member bootstrap accepts only Rwanda and exposes MoMo fields', () {
    final liveReader = File(
      'lib/shared/repositories/collect_repository_live_reader.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260925190000_rwanda_momo_only.sql',
    ).readAsStringSync();
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();

    expect(liveReader, contains("'p_whatsapp_phone': normalizedPhone"));
    expect(liveReader, contains("'p_country_code': countryCode"));
    expect(migration, contains('Collect supports Rwanda profiles only'));
    expect(
      migration,
      contains("public.ensure_current_profile(p_whatsapp_phone, 'RW')"),
    );
    expect(migration, contains('profiles_rwanda_momo_only'));
    expect(migration, contains("'momo_provider', profile_row.momo_provider"));
    expect(migration, contains("'momo_number', profile_row.momo_number"));
    expect(readiness, contains('profiles_rwanda_momo_only'));
  });
}
