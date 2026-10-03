import 'dart:io';

import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile auth uses renewable persisted sessions', () {
    expect(collectDurableAuthOptions.persistSession, isTrue);
    expect(collectDurableAuthOptions.autoRefreshToken, isTrue);

    final mobileEntrypoint = File('lib/main.dart').readAsStringSync();
    expect(
      mobileEntrypoint,
      contains('await createSupabaseClientFromEnvironment(environment: env)'),
    );
    expect(
      mobileEntrypoint,
      contains('supabaseClientProvider.overrideWithValue(supabase)'),
    );
  });
}
