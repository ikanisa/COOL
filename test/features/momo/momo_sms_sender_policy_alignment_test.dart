import 'dart:io';

import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M-Money SMS sender policy alignment', () {
    test('mobile app and sms-ingest edge function share the same tokens', () {
      final appTokens = MomoSmsIngestionRepository.approvedInboxSenderIds
          .map(_normalizeSender)
          .toSet();
      final edgeTokens = _extractQuotedValues(
        File('supabase/functions/sms-ingest/rules.ts').readAsStringSync(),
        declarationPattern: RegExp(
          r'approvedSenderTokens\s*=\s*new Set\(\[(.*?)\]\);',
          dotAll: true,
        ),
      );

      expect(edgeTokens, equals(appTokens));
    });

    test('sender drift summary advertises the right approved sender count', () {
      final migration = File(
        'supabase/migrations/20260322174000_reconcile_momo_sms_closed_review_health.sql',
      ).readAsStringSync();
      final expectedSendersMatch = RegExp(
        r"'Expected Senders'::text as tertiary_label,\s*([0-9]+)::integer as tertiary_value",
      ).firstMatch(migration);

      expect(expectedSendersMatch, isNotNull);
      expect(
        int.parse(expectedSendersMatch!.group(1)!),
        equals(MomoSmsIngestionRepository.approvedInboxSenderIds.length),
      );
    });

    test('sender inventory audit shares the approved sender token allowlist', () {
      final appTokens = MomoSmsIngestionRepository.approvedInboxSenderIds
          .map(_normalizeSender)
          .toSet();
      final migration = File(
        'supabase/migrations/20260322178000_momo_sms_sender_inventory_acknowledgements.sql',
      ).readAsStringSync();
      final sqlTokens = _extractQuotedValues(
        migration,
        declarationPattern: RegExp(
          r'v_approved_sender_tokens\s+constant\s+text\[\]\s*:=\s*array\[(.*?)\];',
          dotAll: true,
        ),
      );

      expect(sqlTokens, equals(appTokens));
    });
  });
}

Set<String> _extractQuotedValues(
  String source, {
  required RegExp declarationPattern,
}) {
  final blockMatch = declarationPattern.firstMatch(source);
  if (blockMatch == null) {
    return const <String>{};
  }

  return RegExp(r'''['"]([^'"]+)['"]''')
      .allMatches(blockMatch.group(1)!)
      .map((match) => match.group(1) ?? '')
      .where((value) => value.isNotEmpty)
      .toSet();
}

String _normalizeSender(String value) {
  return value.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
