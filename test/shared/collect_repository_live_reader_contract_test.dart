import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new-user profile bootstrap uses the deployed RPC argument name', () {
    final liveReader = File(
      'lib/shared/repositories/collect_repository_live_reader.dart',
    ).readAsStringSync();
    final hardenedRpc = File(
      'supabase/migrations/20260611111500_harden_mobile_profile_rpcs.sql',
    ).readAsStringSync();

    expect(
      hardenedRpc,
      contains(
        'create or replace function ensure_current_profile('
        'p_whatsapp_phone text default null)',
      ),
    );
    expect(
      liveReader,
      contains("params: {'p_whatsapp_phone': normalizedPhone}"),
    );
    expect(
      liveReader,
      isNot(contains("params: {'whatsapp_phone': normalizedPhone}")),
    );
  });
}
