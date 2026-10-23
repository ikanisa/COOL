import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_api.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _actor = '00000000-0000-4000-8000-000000000001';
const _receipt = '00000000-0000-4000-8000-000000000002';
const _prefix = '/functions/v1/admin-api/api/admin';
const _reason = 'Review original captured SMS';
final _hash = 'a' * 64;

// Synthetic metadata and content exercise the real parser, not hosted custody.
Map<String, dynamic> _capture() => {
  'source_kind': 'capture',
  'id': _receipt,
  'user_id': _actor,
  'payee_id': null,
  'source_sha256': _hash,
  'status': 'received',
  'version': 1,
  'received_at': 1791181500,
  'received_at_device': '2026-10-05T08:25:00+02:00',
  'created_at': 1791200000,
  'public_id': '938491',
  'display_name': 'Synthetic source owner',
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

Map<String, dynamic> _content({
  Object? sender = 'MTN',
  Object? body = 'Original captured source',
}) => {
  'source_kind': 'capture',
  'source_id': _receipt,
  'raw_sender': sender,
  'raw_body': body,
  'source_sha256': _hash,
  'evidence_level': 'client_received',
  'provider_confirmation': false,
};

class _Fixture {
  _Fixture({
    this.role = 'admin',
    this.permissions = const ['sms.read', 'sms.reveal'],
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.origin, 'https://backend.collect.ikanisa.com');
        if (request.url.path == '$_prefix/auth/session') {
          return _response({
            'user': {
              'id': _actor,
              'email': 'sms-bounds@example.test',
              'role': role,
              'sessionId': 'synthetic-sms-bounds-session',
              'principalId': _actor,
              'financialModel': 'canonical_evidence_ledger',
              'assuranceLevel': 1,
              'mfaAt': null,
              'permissions': permissions,
            },
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
            'ownerEmail': 'info@ikanisa.com',
            'csrfToken': 'c' * 64,
          });
        }
        requests.add(request);
        expect(
          request.url.path,
          '$_prefix/sms/receipts/capture/$_receipt/content',
        );
        expect(request.url.query, isEmpty);
        expect(request.body, isEmpty);
        expect(request.headers['X-Collect-Review-Reason'], _reason);
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        return _response(content);
      }),
      origin: Uri.parse('https://admin.collect.ikanisa.com/'),
      environment: const AppEnv(
        apiUrl: 'https://backend.collect.ikanisa.com',
        publicUrl: '',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: 'turnstile',
        authCaptchaSiteKey: '',
        backend: 'supabase',
        supabaseUrl: 'https://rrlduytparvsjfmegalh.supabase.co',
        supabaseAdminApiUrl: 'https://backend.collect.ikanisa.com',
        supabasePublishableKey: 'sb_publishable_synthetic_test_key_only',
      ),
    );
    addTearDown(session.dispose);
  }

  final String role;
  final List<String> permissions;
  late final CloudflareAdminSession session;
  final requests = <http.Request>[];
  Map<String, dynamic> content = _content();

  Future<CloudflareAdminSmsApi> open() async {
    await session.refresh();
    expect(session.user, isNotNull);
    return CloudflareAdminSmsApi(session);
  }

  static http.Response _response(Map<String, dynamic> body) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

void main() {
  test(
    'reveal accepts 96 ASCII sender units and refuses 97 without truncation',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      final sender = 'S' * 96;
      fixture.content = _content(sender: sender);
      expect((await api.reveal(source, _reason)).sender, sender);
      fixture.content = _content(sender: '$sender!');
      await expectLater(api.reveal(source, _reason), throwsFormatException);
      expect(fixture.requests.length, 2);
    },
  );

  test(
    'reveal sender limit counts UTF-16 units rather than emoji code points',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      final sender = '😀' * 48;
      expect(sender.length, 96);
      fixture.content = _content(sender: sender);
      expect((await api.reveal(source, _reason)).sender, sender);
      for (final overflow in ['$sender!', '😀' * 49]) {
        expect(overflow.length, greaterThan(96));
        fixture.content = _content(sender: overflow);
        await expectLater(api.reveal(source, _reason), throwsFormatException);
      }
      expect(fixture.requests.length, 3);
    },
  );

  test(
    'reveal accepts 16384 ASCII body bytes and refuses one more byte',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      final body = 'A' * 16384;
      expect(utf8.encode(body).length, 16384);
      fixture.content = _content(body: body);
      expect((await api.reveal(source, _reason)).body, body);
      fixture.content = _content(body: '${body}B');
      await expectLater(api.reveal(source, _reason), throwsFormatException);
      expect(fixture.requests.length, 2);
    },
  );

  test(
    'reveal bounds UTF-8 bytes for accented text and supplementary emoji',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      for (final body in ['é' * 8192, '😀' * 4096]) {
        expect(utf8.encode(body).length, 16384);
        fixture.content = _content(body: body);
        expect((await api.reveal(source, _reason)).body, body);
        final overflow = '${body}A';
        expect(utf8.encode(overflow).length, 16385);
        fixture.content = _content(body: overflow);
        await expectLater(api.reveal(source, _reason), throwsFormatException);
      }
      final overflow = '😀' * 4097;
      expect(utf8.encode(overflow).length, 16388);
      fixture.content = _content(body: overflow);
      await expectLater(api.reveal(source, _reason), throwsFormatException);
      expect(fixture.requests.length, 5);
    },
  );

  test(
    'reveal preserves original sender, multiline body and source provenance',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      const sender = '  MTN 😀  ';
      const body = ' First source line\nSecond é line\r\n\t😀 final line\n ';
      fixture.content = _content(sender: sender, body: body);
      expect(fixture.content.length, 7);
      final revealed = await api.reveal(
        SmsReceiptSource.parse(_capture()),
        '  $_reason  ',
      );
      expect(revealed.sender, sender);
      expect(revealed.body, body);
      expect(revealed.sourceKind, 'capture');
      expect(revealed.sourceId, _receipt);
      expect(revealed.sourceHash, _hash);
      expect(revealed.evidenceLevel, 'client_received');
      expect(fixture.content['provider_confirmation'], isFalse);
      expect(fixture.requests.length, 1);
    },
  );

  test('reveal preserves allowed sender TAB, LF, CR and DEL exactly', () async {
    final fixture = _Fixture();
    final api = await fixture.open();
    final source = SmsReceiptSource.parse(_capture());
    final senders = [
      for (final code in [9, 10, 13, 127])
        ' MTN${String.fromCharCode(code)}source ',
      ' \tMTN\nsource\r\u007f ',
    ];
    for (final sender in senders) {
      fixture.content = _content(sender: sender);
      final revealed = await api.reveal(source, _reason);
      expect(revealed.sender, sender);
      expect(revealed.sender.codeUnits, sender.codeUnits);
    }
    expect(fixture.requests.length, senders.length);
  });

  test(
    'reveal refuses every forbidden sender control and trim-empty sender',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      final forbidden = [
        for (var code = 0; code < 32; code++)
          if (code != 9 && code != 10 && code != 13) code,
      ];
      expect(forbidden.length, 29);
      for (final code in forbidden) {
        fixture.content = _content(
          sender: 'MTN${String.fromCharCode(code)}source',
        );
        await expectLater(api.reveal(source, _reason), throwsFormatException);
      }
      const empty = ['', '   ', '\t\r\n', ' \t\r\n '];
      for (final sender in empty) {
        expect(sender.trim(), isEmpty);
        fixture.content = _content(sender: sender);
        await expectLater(api.reveal(source, _reason), throwsFormatException);
      }
      expect(fixture.requests.length, forbidden.length + empty.length);
    },
  );

  test(
    'reveal refuses body NUL without changing the UTF-8 body boundary',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      final bodies = ['\u0000', 'Original\u0000source', '${'A' * 16383}\u0000'];
      expect(utf8.encode(bodies.last).length, 16384);
      for (final body in bodies) {
        fixture.content = _content(body: body);
        await expectLater(api.reveal(source, _reason), throwsFormatException);
      }
      expect(fixture.requests.length, bodies.length);
    },
  );

  test(
    'reveal still refuses malformed content and altered exact DTO provenance',
    () async {
      final fixture = _Fixture();
      final api = await fixture.open();
      final source = SmsReceiptSource.parse(_capture());
      final invalid = <Map<String, dynamic>>[
        _content(sender: null),
        _content(sender: 123),
        _content(sender: ''),
        _content(sender: '   '),
        _content(body: null),
        _content(body: 123),
        _content(body: false),
        _content(body: <String>[]),
        _content(body: ''),
        {..._content(), 'source_kind': 'member'},
        {..._content(), 'source_id': '00000000-0000-4000-8000-000000000003'},
        {..._content(), 'source_sha256': 'b' * 64},
        {..._content(), 'evidence_level': 'member_submitted'},
        {..._content(), 'provider_confirmation': true},
        {..._content(), 'provider_confirmation': null},
        {..._content(), 'extra': 'Unqualified field'},
        for (final key in _content().keys) ({..._content()}..remove(key)),
      ];
      for (final content in invalid) {
        fixture.content = content;
        await expectLater(api.reveal(source, _reason), throwsFormatException);
      }
      expect(fixture.requests.length, invalid.length);
    },
  );

  test(
    'reason and current reveal authority still stop requests before transport',
    () async {
      final source = SmsReceiptSource.parse(_capture());
      final fixture = _Fixture();
      final api = await fixture.open();
      for (final reason in ['short', 'R' * 1001, 'Review\nsource']) {
        await expectLater(api.reveal(source, reason), throwsFormatException);
      }
      expect(fixture.requests, isEmpty);
      fixture.session.clear();
      await expectLater(
        api.reveal(source, _reason),
        throwsA(isA<AdminAccountException>()),
      );
      expect(fixture.requests, isEmpty);
      for (final denied in [
        _Fixture(role: 'staff'),
        _Fixture(permissions: const ['sms.read']),
      ]) {
        final deniedApi = await denied.open();
        expect(deniedApi.canReveal, isFalse);
        await expectLater(
          deniedApi.reveal(source, _reason),
          throwsA(isA<AdminAccountException>()),
        );
        expect(denied.requests, isEmpty);
      }
    },
  );
}
