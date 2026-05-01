import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BioPay lint repair migration qualifies ambiguous PL/pgSQL columns', () {
    final sql = File(
      'supabase/migrations/20260501103000_biopay_function_lint_hardening.sql',
    ).readAsStringSync();

    expect(sql, contains('from public.biopay_profiles bp'));
    expect(sql, contains('where bp.user_id = v_user_id'));
    expect(sql, contains('update public.biopay_embeddings be'));
    expect(sql, contains('where be.profile_id = v_profile.id'));

    expect(
      sql,
      isNot(
        contains(RegExp(r'^\s*where user_id = v_user_id', multiLine: true)),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(r'^\s*where profile_id = v_profile\.id', multiLine: true),
        ),
      ),
    );
  });
}
