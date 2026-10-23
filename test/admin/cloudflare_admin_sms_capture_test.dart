import 'package:collect_app/admin/core/cloudflare_admin_sms_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = '00000000-0000-4000-8000-000000000001';
const _receipt = '00000000-0000-4000-8000-000000000002';

Map<String, dynamic> _capture({
  String? sourceTime = '2026-10-05T08:25:00+02:00',
  int? receivedAt = 1791181500,
  String status = 'received',
}) => {
  'source_kind': 'capture',
  'id': _receipt,
  'user_id': _owner,
  'payee_id': null,
  'source_sha256': 'a' * 64,
  'status': status,
  'version': 1,
  'received_at': receivedAt,
  'received_at_device': sourceTime,
  'created_at': 1791200000,
  'public_id': '938491',
  'display_name': 'Recorded source owner',
  'transaction_id': null,
  'evidence_level': 'client_received',
  'source_fact_id': null,
  'parser_version': null,
  'extraction_status': 'not_extracted',
  'source_body_sha256': null,
  'source_payload_sha256': null,
  'parsed_at': null,
  'payer_name': null,
  'payer_phone': null,
  'payer_masked_phone': null,
  'payer_last3': null,
  'payee_momo_number': null,
  'payee_momo_code': null,
  'momo_transaction_reference': null,
  'momo_timestamp_local': null,
  'momo_timezone_offset': null,
  'amount_rwf': null,
  'wallet_balance_rwf': null,
  'network': null,
  'direction': null,
  'is_payment': null,
  'transaction_reference': null,
  'duplicate_reference_count': 0,
  'conflicting_reference_count': 0,
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
  'timezone_known': false,
  'payer_last3_known': false,
  'source_content_reveal_required': true,
};

void main() {
  test(
    'capture preserves canonical states without asserting payment facts',
    () {
      for (final status in ['received', 'under_review', 'rejected', 'linked']) {
        final source = SmsReceiptSource.parse(_capture(status: status));
        expect(source.kind, 'capture');
        expect(source.identity, 'capture/$_receipt');
        expect(source.values['status'], status);
        expect(source.values['evidence_level'], 'client_received');
        expect(source.values['transaction_id'], isNull);
        expect(source.values['provider_confirmation'], isFalse);
        expect(source.values['settlement_status'], 'not_asserted');
      }
    },
  );

  test(
    'opaque device times remain source text without an invented timezone',
    () {
      for (final value in <String?>[
        null,
        '2026-10-05',
        '2026-10-05T08:25:00',
        '2026-02-31T08:25:00Z',
        '2026-10-05T24:00:00Z',
        '2026-10-05T08:25:60Z',
        '2026-10-05T08:25:00+24:00',
      ]) {
        final source = SmsReceiptSource.parse(
          _capture(sourceTime: value, receivedAt: null),
        );
        expect(source.values['received_at_device'], value);
        expect(source.values['received_at'], isNull);
        expect(
          () => SmsReceiptSource.parse(
            _capture(sourceTime: value, receivedAt: 1791181500),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'explicit source offsets and pre-epoch fractions have exact seconds',
    () {
      for (final vector in <(String, int)>[
        ('2026-10-05T08:25:00+02:00', 1791181500),
        ('2026-10-05T06:25:00Z', 1791181500),
        ('1970-01-01T00:00:00Z', 0),
        ('1969-12-31T23:59:59.999999999Z', -1),
        ('0000-01-01T00:00:00Z', -62167219200),
      ]) {
        final source = SmsReceiptSource.parse(
          _capture(sourceTime: vector.$1, receivedAt: vector.$2),
        );
        expect(source.values['received_at'], vector.$2);
        expect(
          () => SmsReceiptSource.parse(
            _capture(sourceTime: vector.$1, receivedAt: vector.$2 + 1),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'capture refuses invented extraction, raw content and provider finality',
    () {
      for (final change in <Map<String, dynamic>>[
        {'status': 'parsed'},
        {'evidence_level': 'receiver_ingress_unverified'},
        {'user_id': null, 'payee_id': _owner},
        {'transaction_id': _owner},
        {'version': 2},
        {'payer_name': 'Unproven payer'},
        {'extraction_status': 'parsed'},
        {'source_fact_id': _owner},
        {'duplicate_reference_count': 1},
        {'provider_confirmation': true},
        {'settlement_status': 'confirmed'},
        {'raw_body': 'Receipt body must not enter metadata'},
        {'received_at': 1791181500.0},
      ]) {
        expect(
          () => SmsReceiptSource.parse({..._capture(), ...change}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'capture-only fields and states do not loosen legacy source variants',
    () {
      final member = {
        ..._capture(),
        'source_kind': 'member',
        'status': 'needs_review',
        'evidence_level': 'member_submitted',
      };
      expect(() => SmsReceiptSource.parse(member), throwsFormatException);
      member.remove('received_at_device');
      expect(SmsReceiptSource.parse(member).kind, 'member');
      member['status'] = 'received';
      expect(() => SmsReceiptSource.parse(member), throwsFormatException);
    },
  );
}
