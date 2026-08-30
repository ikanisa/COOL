import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new-user profile bootstrap keeps phone and country as separate inputs',
    () {
      final liveReader = File(
        'lib/shared/repositories/collect_repository_live_reader.dart',
      ).readAsStringSync();
      final profileRpc = File(
        'supabase/migrations/20260828100000_profile_country_session_independence.sql',
      ).readAsStringSync();
      final readiness = File(
        'scripts/supabase_production_readiness.sh',
      ).readAsStringSync();

      expect(
        profileRpc,
        contains(
          'create or replace function public.ensure_current_profile('
          '\n  p_whatsapp_phone text default null,\n'
          '  p_country_code text default null',
        ),
      );
      expect(liveReader, contains("'p_whatsapp_phone': normalizedPhone"));
      expect(liveReader, contains("'p_country_code': countryCode"));
      expect(profileRpc, contains('update_current_profile'));
      expect(profileRpc, contains('country_code = country_rule.country_code'));
      expect(profileRpc, contains('from auth.users auth_user'));
      expect(
        profileRpc,
        contains('clean_phone := coalesce(verified_phone, requested_phone)'),
      );
      expect(
        profileRpc,
        contains('when verified_phone is not null then verified_phone'),
      );
      expect(
        profileRpc,
        contains("coalesce(trim(profile.whatsapp_phone), '') = ''"),
      );
      expect(
        profileRpc,
        isNot(contains('set whatsapp_phone = p_whatsapp_phone')),
      );
      expect(readiness, contains("('profiles', 'country_code')"));
      expect(readiness, contains("('profiles', 'currency_code')"));
      expect(readiness, contains("('profiles', 'revolut_name')"));
      expect(
        readiness,
        contains("('authenticated', 'update_current_profile', 'EXECUTE')"),
      );
      expect(
        readiness,
        contains("('authenticated', 'profile_country_rules', 'SELECT')"),
      );
    },
  );
}
